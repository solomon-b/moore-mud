module Main where

--------------------------------------------------------------------------------

import Data.Functor.Identity (runIdentity)
import Data.Machine.FRP.Core (MealyT (..), MooreT (..), fixMoore, hoistMooreT, loop)
import Data.Machine.FRP.Driver (annihilateWithClock)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import MUD.Types (PlayerId (..))
import MUD.World.Nav
import System.IO (hFlush, stdout)
import Text.Read (readMaybe)

--------------------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn "moore-mud nav repl (move <dir> | look | enter <roomid> | leave)"
  putStrLn "Directions: north south east west up down (or n s e w u d)"
  putStrLn ""
  let pid = PlayerId 0
      st = initialNavState {navPlayers = Map.singleton pid (RoomId 0)}
      world = ignoreDTime . hoistMooreT (pure . runIdentity) $ fixMoore navMachine st
  -- Trigger an initial look so the player sees the room
  loop $ annihilateWithClock world (navReplAgent pid)

navReplAgent :: PlayerId -> MealyT IO NavOutput NavCmd
navReplAgent pid = MealyT $ \(NavOutput events) -> do
  mapM_ (putStrLn . formatNavEvent) events
  putStr "> "
  hFlush stdout
  line <- getLine
  case parseNavCmd pid (Text.pack line) of
    Nothing -> do
      putStrLn "Usage: move <dir> | look | enter <roomid> | leave"
      -- Default to look on bad parse
      pure (Look pid, navReplAgent pid)
    Just cmd -> pure (cmd, navReplAgent pid)

formatNavEvent :: NavEvent -> String
formatNavEvent (MovedRoom _pid from to) =
  "You moved from room " <> show (getRoomId from) <> " to room " <> show (getRoomId to) <> "."
formatNavEvent (LookResult _pid rv) =
  unlines
    [ "== " <> Text.unpack (rvName rv) <> " ==",
      Text.unpack (rvDesc rv),
      "Exits: " <> unwords (map show (rvExits rv)),
      if null (rvPlayers rv)
        then ""
        else "Players here: " <> unwords (map (show . getPlayerId) (rvPlayers rv))
    ]
formatNavEvent (MoveBlocked _pid dir) =
  "You can't go " <> show dir <> "."

parseNavCmd :: PlayerId -> Text.Text -> Maybe NavCmd
parseNavCmd pid input =
  case Text.words input of
    ["move", dirTxt] -> Move pid <$> parseDirection dirTxt
    ["look"] -> Just (Look pid)
    ["enter", ridTxt]
      | Just rid <- readMaybe (Text.unpack ridTxt) -> Just (Enter pid (RoomId rid))
    ["leave"] -> Just (Leave pid)
    -- Allow bare direction as shortcut for move
    [dirTxt] -> Move pid <$> parseDirection dirTxt
    _ -> Nothing

parseDirection :: Text.Text -> Maybe Direction
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

-- | Adapt a Moore machine to ignore elapsed time in its input.
ignoreDTime :: (Functor m) => MooreT m i o -> MooreT m (Double, i) o
ignoreDTime (MooreT m) = MooreT $ fmap (\(o, t) -> (o, ignoreDTime . t . snd)) m
