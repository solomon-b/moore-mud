-- | Network layer (Layer 1): TCP accept loop, connection registry,
-- per-player mailboxes.
--
-- This layer runs outside annihilation. It spawns a thread per
-- connection that reads lines from the socket and writes them into a
-- 'TVar' mailbox. The player Mealy machine (Layer 2) harvests
-- commands from these mailboxes each step.
module MUD.Network
  ( -- * Types
    PlayerId,
    Connection,
    Registry,
    RegistryEvent (..),

    -- * Registry operations
    newRegistry,
    drainEvents,
    connectedPlayers,
    harvestCommand,
    sendToPlayer,

    -- * Server
    acceptLoop,
  )
where

--------------------------------------------------------------------------------

import Control.Concurrent (forkFinally)
import Control.Concurrent.STM
  ( STM,
    TVar,
    atomically,
    modifyTVar',
    newTVarIO,
    readTVar,
    writeTVar,
  )
import Control.Exception (bracket)
import Control.Monad (forever, void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Network.Socket
  ( AddrInfo (..),
    Socket,
    SocketOption (..),
    SocketType (..),
    accept,
    bind,
    close,
    defaultHints,
    getAddrInfo,
    gracefulClose,
    listen,
    openSocket,
    setSocketOption,
    withSocketsDo,
  )
import MUD.Types (PlayerId (..))
import Network.Socket.ByteString (recv, sendAll)

--------------------------------------------------------------------------------

-- | A live player connection.
data Connection = Connection
  { connSocket :: Socket,
    connMailbox :: TVar (Maybe Text)
  }

-- | The connection registry: shared mutable state between Layer 1
-- (network) and Layer 2 (player Mealy).
data Registry = Registry
  { regConnections :: TVar (Map PlayerId Connection),
    regNextId :: TVar PlayerId,
    regEvents :: TVar [RegistryEvent]
  }

-- | Events produced by the network layer for the player Mealy to consume.
data RegistryEvent
  = PlayerConnected PlayerId
  | PlayerDisconnected PlayerId
  deriving (Show, Eq)

--------------------------------------------------------------------------------

-- | Create an empty registry.
newRegistry :: IO Registry
newRegistry =
  Registry
    <$> newTVarIO Map.empty
    <*> newTVarIO (PlayerId 0)
    <*> newTVarIO []

-- | Drain all pending registry events.
drainEvents :: Registry -> STM [RegistryEvent]
drainEvents reg = do
  evts <- readTVar (regEvents reg)
  writeTVar (regEvents reg) []
  pure evts

-- | Get the current set of connected player IDs and their connections.
connectedPlayers :: Registry -> STM (Map PlayerId Connection)
connectedPlayers reg = readTVar (regConnections reg)

-- | Harvest a command from a player's mailbox (if any). Clears the mailbox.
harvestCommand :: Connection -> STM (Maybe Text)
harvestCommand conn = do
  cmd <- readTVar (connMailbox conn)
  writeTVar (connMailbox conn) Nothing
  pure cmd

-- | Send a line of text to a player.
sendToPlayer :: Connection -> Text -> IO ()
sendToPlayer conn txt =
  sendAll (connSocket conn) (Text.Encoding.encodeUtf8 txt <> "\r\n")

--------------------------------------------------------------------------------

-- | Start the TCP accept loop on the given port. Spawns a thread per
-- connection. Blocks forever.
acceptLoop :: Registry -> Int -> IO ()
acceptLoop reg port = withSocketsDo $ do
  let hints = defaultHints {addrSocketType = Stream}
  addrs <- getAddrInfo (Just hints) (Just "0.0.0.0") (Just (show port))
  addr <- case addrs of
    (a : _) -> pure a
    [] -> ioError (userError "no address info")
  bracket (openListenSocket addr) close $ \sock ->
    forever $ do
      (clientSock, _peer) <- accept sock
      pid <- atomically $ allocPlayerId reg
      mailbox <- newTVarIO Nothing
      let connection = Connection clientSock mailbox
      atomically $ do
        modifyTVar' (regConnections reg) (Map.insert pid connection)
        modifyTVar' (regEvents reg) (PlayerConnected pid :)
      sendToPlayer connection $ "Welcome! You are player " <> Text.pack (show (getPlayerId pid))
      void $
        forkFinally
          (playerThread clientSock mailbox)
          ( \_ -> do
              gracefulClose clientSock 1000
              atomically $ do
                modifyTVar' (regConnections reg) (Map.delete pid)
                modifyTVar' (regEvents reg) (PlayerDisconnected pid :)
          )

--------------------------------------------------------------------------------

openListenSocket :: AddrInfo -> IO Socket
openListenSocket addr = do
  sock <- openSocket addr
  setSocketOption sock ReuseAddr 1
  bind sock (addrAddress addr)
  listen sock 5
  pure sock

allocPlayerId :: Registry -> STM PlayerId
allocPlayerId reg = do
  pid <- readTVar (regNextId reg)
  writeTVar (regNextId reg) (PlayerId (getPlayerId pid + 1))
  pure pid

-- | Per-player thread: read lines from the socket, write into the mailbox.
-- Overwrites any unread command (latest wins).
playerThread :: Socket -> TVar (Maybe Text) -> IO ()
playerThread sock mailbox = do
  buf <- newIORef BS.empty
  forever $ do
    line <- recvLine sock buf
    let txt = Text.Encoding.decodeUtf8Lenient (stripCR line)
    atomically $ writeTVar mailbox (Just txt)

-- | Read a single line from a socket, buffering partial reads.
recvLine :: Socket -> IORef ByteString -> IO ByteString
recvLine sock bufRef = do
  buf <- readIORef bufRef
  case BS.elemIndex 0x0A buf of
    Just idx -> do
      let (line, rest) = BS.splitAt idx buf
      writeIORef bufRef (BS.drop 1 rest)
      pure line
    Nothing -> do
      chunk <- recv sock 4096
      if BS.null chunk
        then ioError (userError "connection closed")
        else do
          writeIORef bufRef (buf <> chunk)
          recvLine sock bufRef

-- | Strip trailing CR for telnet-style CRLF line endings.
stripCR :: ByteString -> ByteString
stripCR bs
  | BS.null bs = bs
  | BS.last bs == 0x0D = BS.init bs
  | otherwise = bs
