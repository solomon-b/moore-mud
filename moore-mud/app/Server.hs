module Main where

--------------------------------------------------------------------------------

import Control.Concurrent (forkIO)
import Data.Bifunctor.Monoidal ((|*&|))
import Data.Functor.Identity (runIdentity)
import Data.Machine.FRP.Core (MooreT (..), fixMoore, hoistMooreT, loop)
import Data.Machine.FRP.Driver (annihilateWithClock)
import Data.Trifunctor.Monoidal ((|*&*|))
import Data.These (These (..))
import MUD.Agent.Player (PlayerAgentConfig (..), playerAgent)
import MUD.Network (acceptLoop, newRegistry)
import MUD.Serializer.Chat (chatSerializer)
import MUD.Serializer.Nav (navSerializer)
import MUD.World.Chat (chatMachine, initialChatState)
import MUD.World.Nav (NavCmd (..), RoomId (..), initialNavState, navMachine)

--------------------------------------------------------------------------------

main :: IO ()
main = do
  let port = 4000
  putStrLn $ "moore-mud starting on port " <> show port
  reg <- newRegistry
  _ <- forkIO $ acceptLoop reg port

  let worldMachine = chatMachine |*&*| navMachine
      initialState = (initialChatState, initialNavState)
      world = ignoreDTime . hoistMooreT (pure . runIdentity) $ fixMoore worldMachine initialState
      cfg =
        PlayerAgentConfig
          { pacSerializer = \pid -> chatSerializer pid |*&| navSerializer pid,
            pacOnConnect = \pid -> That (Enter pid (RoomId 0)),
            pacOnDisconnect = \pid -> That (Leave pid)
          }
  loop $ annihilateWithClock world (playerAgent reg cfg)

-- | Adapt a Moore machine to ignore elapsed time in its input.
ignoreDTime :: (Functor m) => MooreT m i o -> MooreT m (Double, i) o
ignoreDTime (MooreT m) = MooreT $ fmap (\(o, t) -> (o, ignoreDTime . t . snd)) m
