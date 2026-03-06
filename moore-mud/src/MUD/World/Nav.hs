module MUD.World.Nav
  ( -- * Types
    Direction (..),
    RoomId (..),
    Room (..),
    NavState (..),
    NavCmd (..),
    NavOutput (..),
    NavEvent (..),
    RoomView (..),

    -- * Coalgebra
    navMachine,

    -- * Initial state
    initialNavState,
  )
where

--------------------------------------------------------------------------------

import Data.Functor.Identity (Identity (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Machine.FRP.Core (MooreC, MooreTC (..))
import Data.Text (Text)
import MUD.Types (PlayerId (..))

--------------------------------------------------------------------------------

data Direction = North | South | East | West | Up | Down
  deriving (Show, Eq, Ord)

newtype RoomId = RoomId {getRoomId :: Int}
  deriving (Show, Eq, Ord)

data Room = Room
  { roomName :: Text,
    roomDesc :: Text,
    roomExits :: Map Direction RoomId
  }
  deriving (Show, Eq)

data NavState = NavState
  { navRooms :: Map RoomId Room,
    navPlayers :: Map PlayerId RoomId,
    navPending :: [NavEvent]
  }
  deriving (Show, Eq)

--------------------------------------------------------------------------------

data NavCmd
  = Move PlayerId Direction
  | Look PlayerId
  | Enter PlayerId RoomId
  | Leave PlayerId
  deriving (Show, Eq)

data NavOutput = NavOutput
  { navEvents :: [NavEvent]
  }
  deriving (Show, Eq)

data NavEvent
  = MovedRoom PlayerId RoomId RoomId
  | LookResult PlayerId RoomView
  | MoveBlocked PlayerId Direction
  deriving (Show, Eq)

data RoomView = RoomView
  { rvName :: Text,
    rvDesc :: Text,
    rvExits :: [Direction],
    rvPlayers :: [PlayerId]
  }
  deriving (Show, Eq)

--------------------------------------------------------------------------------

-- | A small default world: two rooms connected north/south.
initialNavState :: NavState
initialNavState =
  NavState
    { navRooms =
        Map.fromList
          [ ( RoomId 0,
              Room
                { roomName = "Town Square",
                  roomDesc = "A dusty town square with a fountain in the center.",
                  roomExits = Map.fromList [(North, RoomId 1)]
                }
            ),
            ( RoomId 1,
              Room
                { roomName = "Market Street",
                  roomDesc = "A narrow street lined with market stalls.",
                  roomExits = Map.fromList [(South, RoomId 0)]
                }
            )
          ],
      navPlayers = Map.empty,
      navPending = []
    }

-- | The navigation Moore coalgebra.
--
-- Observation: events from the previous step (stored in navPending).
-- Transition: process the command, store resulting events in navPending.
navMachine :: MooreC NavState NavCmd NavOutput
navMachine = MooreTC $ \s ->
  Identity
    ( NavOutput (navPending s),
      \cmd ->
        let (events, s') = execNav s cmd
         in s' {navPending = events}
    )

--------------------------------------------------------------------------------

execNav :: NavState -> NavCmd -> ([NavEvent], NavState)
execNav s (Move pid dir) =
  case Map.lookup pid (navPlayers s) of
    Nothing -> ([], s)
    Just fromId ->
      case Map.lookup fromId (navRooms s) >>= Map.lookup dir . roomExits of
        Nothing -> ([MoveBlocked pid dir], s)
        Just toId ->
          ( [MovedRoom pid fromId toId],
            s {navPlayers = Map.insert pid toId (navPlayers s)}
          )
execNav s (Look pid) =
  case Map.lookup pid (navPlayers s) of
    Nothing -> ([], s)
    Just rid ->
      case Map.lookup rid (navRooms s) of
        Nothing -> ([], s)
        Just room ->
          let others =
                [ p
                  | (p, r) <- Map.toList (navPlayers s),
                    r == rid,
                    p /= pid
                ]
              rv =
                RoomView
                  { rvName = roomName room,
                    rvDesc = roomDesc room,
                    rvExits = Map.keys (roomExits room),
                    rvPlayers = others
                  }
           in ([LookResult pid rv], s)
execNav s (Enter pid rid) =
  ([], s {navPlayers = Map.insert pid rid (navPlayers s)})
execNav s (Leave pid) =
  ([], s {navPlayers = Map.delete pid (navPlayers s)})
