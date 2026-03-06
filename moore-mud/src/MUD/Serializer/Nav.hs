module MUD.Serializer.Nav
  ( navSerializer,
  )
where

--------------------------------------------------------------------------------

import Data.Serializer (Serializer (..), TextSerializer)
import Data.Text (Text)
import Data.Text qualified as Text
import MUD.Types (PlayerId (..))
import MUD.World.Nav
import Text.Read (readMaybe)

--------------------------------------------------------------------------------

navSerializer :: PlayerId -> TextSerializer NavOutput NavCmd
navSerializer pid =
  Serializer
    { parser = parseNavCmd pid,
      printer = printNavOutput
    }

parseNavCmd :: PlayerId -> Text -> Maybe NavCmd
parseNavCmd pid input =
  case Text.words input of
    ["move", dirTxt] -> Move pid <$> parseDirection dirTxt
    ["look"] -> Just (Look pid)
    ["enter", ridTxt]
      | Just rid <- readMaybe (Text.unpack ridTxt) -> Just (Enter pid (RoomId rid))
    ["leave"] -> Just (Leave pid)
    -- Bare direction as shortcut
    [dirTxt] -> Move pid <$> parseDirection dirTxt
    _ -> Nothing

parseDirection :: Text -> Maybe Direction
parseDirection "north" = Just North
parseDirection "south" = Just South
parseDirection "east" = Just East
parseDirection "west" = Just West
parseDirection "up" = Just Up
parseDirection "down" = Just Down
parseDirection "n" = Just North
parseDirection "s" = Just South
parseDirection "e" = Just East
parseDirection "w" = Just West
parseDirection "u" = Just Up
parseDirection "d" = Just Down
parseDirection _ = Nothing

printNavOutput :: NavOutput -> Text
printNavOutput (NavOutput events) =
  Text.intercalate "\n" (map formatNavEvent events)

formatNavEvent :: NavEvent -> Text
formatNavEvent (MovedRoom _pid from to) =
  "You moved from room " <> Text.pack (show (getRoomId from)) <> " to room " <> Text.pack (show (getRoomId to)) <> "."
formatNavEvent (LookResult _pid rv) =
  Text.unlines
    [ "== " <> rvName rv <> " ==",
      rvDesc rv,
      "Exits: " <> Text.unwords (map (Text.pack . show) (rvExits rv)),
      if null (rvPlayers rv)
        then ""
        else "Players here: " <> Text.unwords (map (Text.pack . show . getPlayerId) (rvPlayers rv))
    ]
formatNavEvent (MoveBlocked _pid dir) =
  "You can't go " <> Text.pack (show dir) <> "."
