module MUD.Serializer.Chat
  ( chatSerializer,
  )
where

--------------------------------------------------------------------------------

import Data.Serializer (Serializer (..), TextSerializer)
import Data.Text (Text)
import Data.Text qualified as Text
import MUD.Types (PlayerId (..))
import MUD.World.Chat (ChatCmd (..), ChatMsg (..), ChatOutput (..))
import Text.Read (readMaybe)

--------------------------------------------------------------------------------

chatSerializer :: PlayerId -> TextSerializer ChatOutput ChatCmd
chatSerializer pid =
  Serializer
    { parser = parseChatCmd pid,
      printer = printChatOutput
    }

parseChatCmd :: PlayerId -> Text -> Maybe ChatCmd
parseChatCmd pid input =
  case Text.words input of
    ("say" : rest) -> Just $ Say pid (Text.unwords rest)
    ("whisper" : tidTxt : rest)
      | Just tid <- fmap PlayerId (readMaybe (Text.unpack tidTxt)) ->
          Just $ Whisper pid tid (Text.unwords rest)
    ("shout" : rest) -> Just $ Shout pid (Text.unwords rest)
    _ -> Nothing

printChatOutput :: ChatOutput -> Text
printChatOutput (ChatOutput msgs) =
  Text.intercalate "\n" (map formatMsg (reverse msgs))

formatMsg :: ChatMsg -> Text
formatMsg (SayMsg pid txt) = "[say] player " <> Text.pack (show (getPlayerId pid)) <> ": " <> txt
formatMsg (WhisperMsg from to txt) = "[whisper] player " <> Text.pack (show (getPlayerId from)) <> " -> " <> Text.pack (show (getPlayerId to)) <> ": " <> txt
formatMsg (ShoutMsg pid txt) = "[shout] player " <> Text.pack (show (getPlayerId pid)) <> ": " <> txt
