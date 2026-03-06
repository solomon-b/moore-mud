-- | Player agent (Layer 2): a Mealy machine that mediates between
-- the network layer and the world.
--
-- Parameterized by a serializer factory and lifecycle callbacks so
-- the agent is agnostic to the world's command/observation types.
module MUD.Agent.Player
  ( playerAgent,
    PlayerAgentConfig (..),
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
    RegistryEvent (..),
    connectedPlayers,
    drainEvents,
    harvestCommand,
    sendToPlayer,
  )
import MUD.Types (PlayerId (..))

--------------------------------------------------------------------------------

-- | Configuration for the player agent.
data PlayerAgentConfig obs cmd = PlayerAgentConfig
  { pacSerializer :: PlayerId -> TextSerializer obs cmd,
    pacOnConnect :: PlayerId -> cmd,
    pacOnDisconnect :: PlayerId -> cmd
  }

-- | A Mealy machine that bridges connected players and the world.
--
-- Each step:
-- 1. Send the world's observation to all connected players.
-- 2. Drain registry events — if a player connected/disconnected,
--    emit the corresponding lifecycle command immediately.
-- 3. Otherwise, block until a player has a pending command,
--    parse it via the serializer, and emit it.
playerAgent :: Registry -> PlayerAgentConfig obs cmd -> MealyT IO obs cmd
playerAgent reg cfg = MealyT $ \obs -> do
  -- Format and send observation to all connected players
  let formatted = printer (pacSerializer cfg (PlayerId 0)) obs
  conns <- atomically $ connectedPlayers reg
  if Text.null formatted
    then pure ()
    else mapM_ (\conn -> sendToPlayer conn formatted) conns

  -- Check for registry events (connect/disconnect)
  events <- atomically $ drainEvents reg
  case events of
    (PlayerConnected pid : _) ->
      pure (pacOnConnect cfg pid, playerAgent reg cfg)
    (PlayerDisconnected pid : _) ->
      pure (pacOnDisconnect cfg pid, playerAgent reg cfg)
    _ -> do
      -- No lifecycle events — wait for a player command
      (pid, txt, conn) <- atomically $ awaitCommand reg

      case parser (pacSerializer cfg pid) txt of
        Just cmd ->
          pure (cmd, playerAgent reg cfg)
        Nothing -> do
          sendToPlayer conn "Unknown command. Try: say <text> | shout <text> | look | move <dir>"
          runMealyT (playerAgent reg cfg) obs

--------------------------------------------------------------------------------

-- | Block until at least one connected player has a pending command.
awaitCommand :: Registry -> STM (PlayerId, Text, Connection)
awaitCommand reg = do
  conns <- connectedPlayers reg
  results <- mapM (\(pid, conn) -> fmap (\mc -> (pid, mc, conn)) (harvestCommand conn)) (Map.toList conns)
  case [(pid, txt, conn) | (pid, Just txt, conn) <- results] of
    ((pid, txt, conn) : _) -> pure (pid, txt, conn)
    [] -> retry
