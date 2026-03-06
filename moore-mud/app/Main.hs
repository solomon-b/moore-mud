module Main where

--------------------------------------------------------------------------------

import Data.Functor.Identity (runIdentity)
import Data.Machine.FRP.Core (MooreT (..), fixMoore, hoistMooreT, loop)
import Data.Machine.FRP.Driver (annihilateWithClock)
import MUD.Agent.Repl (replAgent)
import MUD.Types (PlayerId (..))
import MUD.World.Chat (chatMachine, initialChatState)

--------------------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "moore-mud chat repl (say <text> | whisper <id> <text> | shout <text>)"
  putStrLn ""
  let world = ignoreDTime . hoistMooreT (pure . runIdentity) $ fixMoore chatMachine initialChatState
  loop $ annihilateWithClock world (replAgent (PlayerId 0))

-- | Adapt a Moore machine to ignore elapsed time in its input.
ignoreDTime :: (Functor m) => MooreT m i o -> MooreT m (Double, i) o
ignoreDTime (MooreT m) = MooreT $ fmap (\(o, t) -> (o, ignoreDTime . t . snd)) m
