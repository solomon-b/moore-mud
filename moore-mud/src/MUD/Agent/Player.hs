-- | Player agent (Layer 2): a Mealy machine that mediates between
-- the network layer and the world.
--
-- Each step:
-- 1. Send the world's observation (new messages) to all connected players.
-- 2. Block (STM retry) until at least one player has a pending command.
-- 3. Harvest and parse that command, emit it to the world.
module MUD.Agent.Player
  ( playerAgent,
  )
where

--------------------------------------------------------------------------------

import Control.Concurrent.STM (STM, atomically, retry)
import Data.Map.Strict qualified as Map
import Data.Machine.FRP.Core (MealyT (..))
import Data.Text (Text)
import Data.Text qualified as Text
import MUD.Network
  ( Connection,
    Registry,
    connectedPlayers,
    harvestCommand,
    sendToPlayer,
  )
import MUD.Types (PlayerId (..))
import MUD.World.Chat (ChatCmd (..), ChatMsg (..), ChatOutput (..))
import Text.Read (readMaybe)

--------------------------------------------------------------------------------

-- | A Mealy machine that bridges connected players and the chat world.
playerAgent :: Registry -> MealyT IO ChatOutput ChatCmd
playerAgent reg = MealyT $ \(ChatOutput msgs) -> do
  -- Send new messages to all connected players
  conns <- atomically $ connectedPlayers reg
  mapM_ (\conn -> mapM_ (sendToPlayer conn . formatMsg) (reverse msgs)) conns

  -- Block until a player has a command, harvest it
  (pid, txt, conn) <- atomically $ awaitCommand reg

  -- Parse and emit
  case parseCmd pid txt of
    Just cmd -> do
      pure (cmd, playerAgent reg)
    Nothing -> do
      sendToPlayer conn $ "Usage: say <text> | whisper <id> <text> | shout <text>"
      -- Bad parse — still need to produce a command. Echo as say.
      pure (Say pid txt, playerAgent reg)

--------------------------------------------------------------------------------

-- | Block until at least one connected player has a pending command.
awaitCommand :: Registry -> STM (PlayerId, Text, Connection)
awaitCommand reg = do
  conns <- connectedPlayers reg
  results <- mapM (\(pid, conn) -> fmap (\mc -> (pid, mc, conn)) (harvestCommand conn)) (Map.toList conns)
  case [(pid, txt, conn) | (pid, Just txt, conn) <- results] of
    ((pid, txt, conn) : _) -> pure (pid, txt, conn)
    [] -> retry

formatMsg :: ChatMsg -> Text
formatMsg (SayMsg pid txt) = "[say] player " <> Text.pack (show (getPlayerId pid)) <> ": " <> txt
formatMsg (WhisperMsg from to txt) = "[whisper] player " <> Text.pack (show (getPlayerId from)) <> " -> " <> Text.pack (show (getPlayerId to)) <> ": " <> txt
formatMsg (ShoutMsg pid txt) = "[shout] player " <> Text.pack (show (getPlayerId pid)) <> ": " <> txt

parseCmd :: PlayerId -> Text -> Maybe ChatCmd
parseCmd pid input =
  case Text.words input of
    ("say" : rest) -> Just $ Say pid (Text.unwords rest)
    ("whisper" : tidTxt : rest)
      | Just tid <- fmap PlayerId (readMaybe (Text.unpack tidTxt)) ->
          Just $ Whisper pid tid (Text.unwords rest)
    ("shout" : rest) -> Just $ Shout pid (Text.unwords rest)
    _ -> Nothing
