module Main where

--------------------------------------------------------------------------------

import Control.Concurrent (forkIO)
import Data.Functor.Identity (runIdentity)
import Data.Machine.FRP.Core (MooreT (..), fixMoore, hoistMooreT, loop)
import Data.Machine.FRP.Driver (annihilateWithClock)
import MUD.Agent.Player (playerAgent)
import MUD.Network (acceptLoop, newRegistry)
import MUD.World.Chat (chatMachine, initialChatState)

--------------------------------------------------------------------------------

main :: IO ()
main = do
  let port = 4000
  putStrLn $ "moore-mud starting on port " <> show port
  reg <- newRegistry
  _ <- forkIO $ acceptLoop reg port
  let world = ignoreDTime . hoistMooreT (pure . runIdentity) $ fixMoore chatMachine initialChatState
  loop $ annihilateWithClock world (playerAgent reg)

-- | Adapt a Moore machine to ignore elapsed time in its input.
ignoreDTime :: (Functor m) => MooreT m i o -> MooreT m (Double, i) o
ignoreDTime (MooreT m) = MooreT $ fmap (\(o, t) -> (o, ignoreDTime . t . snd)) m
