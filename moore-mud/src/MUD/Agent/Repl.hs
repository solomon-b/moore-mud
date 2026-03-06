-- | A REPL agent: reads commands from stdin, prints observations to stdout.
module MUD.Agent.Repl
  ( replAgent,
  )
where

--------------------------------------------------------------------------------

import Control.Monad (forM_)
import Data.Machine.FRP.Core (MealyT (..))
import Data.Text (Text)
import Data.Text qualified as Text
import MUD.Types (PlayerId (..))
import MUD.World.Chat (ChatCmd (..), ChatMsg (..), ChatOutput (..))
import System.IO (hFlush, stdout)
import Text.Read (readMaybe)

--------------------------------------------------------------------------------

-- | A single-player REPL agent. Prints chat messages, reads commands.
replAgent :: PlayerId -> MealyT IO ChatOutput ChatCmd
replAgent pid = MealyT $ \(ChatOutput msgs) -> do
  -- Print new messages
  forM_ (reverse msgs) $ \msg -> do
    putStrLn $ formatMsg msg
  -- Read a command
  putStr "> "
  hFlush stdout
  line <- getLine
  case parseCmd pid (Text.pack line) of
    Nothing -> do
      putStrLn "Usage: say <text> | whisper <id> <text> | shout <text>"
      pure (Say pid (Text.pack line), replAgent pid)
    Just cmd -> pure (cmd, replAgent pid)

--------------------------------------------------------------------------------

formatMsg :: ChatMsg -> String
formatMsg (SayMsg pid txt) = "[say] player " <> show (getPlayerId pid) <> ": " <> Text.unpack txt
formatMsg (WhisperMsg from to txt) = "[whisper] player " <> show (getPlayerId from) <> " -> " <> show (getPlayerId to) <> ": " <> Text.unpack txt
formatMsg (ShoutMsg pid txt) = "[shout] player " <> show (getPlayerId pid) <> ": " <> Text.unpack txt

parseCmd :: PlayerId -> Text -> Maybe ChatCmd
parseCmd pid input =
  case Text.words input of
    ("say" : rest) -> Just $ Say pid (Text.unwords rest)
    ("whisper" : tidTxt : rest)
      | Just tid <- fmap PlayerId (readMaybe (Text.unpack tidTxt)) ->
          Just $ Whisper pid tid (Text.unwords rest)
    ("shout" : rest) -> Just $ Shout pid (Text.unwords rest)
    _ -> Nothing
