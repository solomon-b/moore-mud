-- | Player agent (Layer 2): a Mealy machine that mediates between
-- the network layer and the world.
--
-- Parameterized by a serializer factory so the agent is agnostic to
-- the world's command/observation types.
module MUD.Agent.Player
  ( playerAgent,
  )
where

--------------------------------------------------------------------------------

import Control.Concurrent.STM (STM, atomically, retry)
import Data.Map.Strict qualified as Map
import Data.Machine.FRP.Core (MealyT (..))
import Data.Serializer (Serializer (..), TextSerializer)
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

--------------------------------------------------------------------------------

-- | A Mealy machine that bridges connected players and the world.
--
-- The serializer factory produces a player-specific serializer (the
-- parser tags commands with the player's ID). The printer half is
-- the same for all players.
playerAgent :: Registry -> (PlayerId -> TextSerializer obs cmd) -> MealyT IO obs cmd
playerAgent reg mkSerializer = MealyT $ \obs -> do
  -- Format and send observation to all connected players
  let formatted = printer (mkSerializer (PlayerId 0)) obs
  conns <- atomically $ connectedPlayers reg
  if Text.null formatted
    then pure ()
    else mapM_ (\conn -> sendToPlayer conn formatted) conns

  -- Block until a player has a command, harvest it
  (pid, txt, conn) <- atomically $ awaitCommand reg

  -- Parse with player-specific serializer
  case parser (mkSerializer pid) txt of
    Just cmd ->
      pure (cmd, playerAgent reg mkSerializer)
    Nothing -> do
      sendToPlayer conn "Unknown command. Try: say <text> | shout <text> | look | move <dir>"
      -- Bad parse — recurse to await another command
      runMealyT (playerAgent reg mkSerializer) obs

--------------------------------------------------------------------------------

-- | Block until at least one connected player has a pending command.
awaitCommand :: Registry -> STM (PlayerId, Text, Connection)
awaitCommand reg = do
  conns <- connectedPlayers reg
  results <- mapM (\(pid, conn) -> fmap (\mc -> (pid, mc, conn)) (harvestCommand conn)) (Map.toList conns)
  case [(pid, txt, conn) | (pid, Just txt, conn) <- results] of
    ((pid, txt, conn) : _) -> pure (pid, txt, conn)
    [] -> retry
