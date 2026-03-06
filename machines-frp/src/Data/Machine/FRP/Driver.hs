-- | Driver loop for running Moore/Mealy annihilation with wall-clock
-- elapsed time injection.
module Data.Machine.FRP.Driver
  ( annihilateWithClock,
    loop,
  )
where

--------------------------------------------------------------------------------

import Control.Monad.IO.Class (MonadIO (..))
import Data.Fix (Fix (..))
import Data.Machine.Mealy (MealyT (..))
import Data.Machine.Moore (MooreT (..))
import Data.Time.Clock (diffUTCTime, getCurrentTime)

--------------------------------------------------------------------------------

-- | Like 'annihilate', but measures wall-clock elapsed time between
-- steps and pairs it with the agent's command before feeding it to
-- the world.
--
-- The world receives @(Double, cmd)@ as input — elapsed seconds since
-- the previous step plus the agent's command. The agent sees the
-- world's observation and produces a command. The driver measures
-- time, assembles the pair, and recurses.
--
-- Returns a @'Fix' m@ — an infinite effectful process. Use 'loop' to
-- drive it.
--
-- @
--   let world  = fixMooreTC mudCoalgebra initialState
--       agents = pcAgent registry
--   loop $ annihilateWithClock world agents
-- @
annihilateWithClock ::
  (MonadIO m) =>
  -- | World: input = (elapsed time, command), output = observation
  MooreT m (Double, cmd) obs ->
  -- | Agents: input = observation, output = command
  MealyT m obs cmd ->
  Fix m
annihilateWithClock world0 mealy0 = Fix $ do
  t0 <- liftIO getCurrentTime
  unFix $ go t0 world0 mealy0
  where
    go prevTime (MooreT moore) (MealyT mealy) = Fix $ do
      (obs, nextMoore) <- moore
      (cmd, mealy') <- mealy obs
      now <- liftIO getCurrentTime
      let dt = realToFrac (diffUTCTime now prevTime)
      pure $ go now (nextMoore (dt, cmd)) mealy'

-- | Drive a @'Fix' m@ — unfold the infinite effectful process forever.
loop :: (Monad m) => Fix m -> m x
loop (Fix x) = x >>= loop
