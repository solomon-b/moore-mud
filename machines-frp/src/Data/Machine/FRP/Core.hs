-- | Core FRP types built on coalgebraic Moore and Mealy machines.
--
-- This module re-exports the key types from @machines-coalgebras@ and
-- provides composition primitives for building systems from
-- independent subsystems: tensor products for parallel composition,
-- wiring diagrams for inter-subsystem routing, and elapsed-time
-- distribution for continuous processes.
module Data.Machine.FRP.Core
  ( -- * Moore Machines (fixed-point, state hidden)
    MooreT (..),
    Moore,
    hoistMooreT,
    liftMooreT,
    processMooreT,
    processMoore,

    -- * Moore Coalgebras (state exposed)
    MooreTC (..),
    MooreC,
    hoistMooreTC,
    fixMooreTC,
    fixMoore,
    scanMooreTC,
    scanMoore,
    processMooreTC,
    processMooreC,

    -- * Mealy Machines (fixed-point, state hidden)
    MealyT (..),
    Mealy,
    hoistMealyT,
    liftMealyT,

    -- * Mealy Coalgebras (state exposed)
    MealyTC (..),
    MealyC,
    hoistMealyTC,
    fixMealyTC,
    fixMealy,
    scanMealyTC,
    scanMealy,
    processMealyTC,
    processMealy,

    -- * Running
    Fix (..),
    annihilateWithClock,
    loop,

    -- * Wiring diagrams
    applyWiring,

    -- * Elapsed time
    DTime,
    MooreSF,
    distributeDTime,
    distributeDTimeEither,
    distributeDTimePair,

    -- * Pure Moore helpers
    observe,
    transition,

    -- * Higher-kinded data
    SlotKind,
    StateF (..),
    InputF (..),
    OutputF (..),
    SequenceMoore (..),
  )
where

--------------------------------------------------------------------------------

import Data.Fix (Fix (..))
import Data.Functor.Identity (Identity (..))
import Data.Machine.FRP.Driver (annihilateWithClock, loop)
import Data.Machine.FRP.HKD (InputF (..), OutputF (..), SequenceMoore (..), SlotKind, StateF (..))
import Data.Machine.Mealy (Mealy, MealyT (..), hoistMealyT, liftMealyT)
import Data.Machine.Mealy.Coalgebra (MealyC, MealyTC (..), fixMealy, fixMealyTC, hoistMealyTC, processMealy, processMealyTC, scanMealy, scanMealyTC)
import Data.Machine.Moore (Moore, MooreT (..), hoistMooreT, liftMooreT, processMoore, processMooreT)
import Data.Machine.Moore.Coalgebra (MooreTC (..), fixMoore, fixMooreTC, hoistMooreTC, processMooreC, processMooreTC, scanMoore, scanMooreTC)
import Data.These (These (..))

--------------------------------------------------------------------------------

-- | Pure Moore coalgebra (state exposed, no effects).
type MooreC = MooreTC Identity

--------------------------------------------------------------------------------
-- Wiring diagrams

-- | Apply a wiring diagram to a Moore coalgebra.
--
-- A wiring diagram is a poly map from an inner interface to an outer
-- interface. It consists of a projection (base map) from inner
-- outputs to the external observation, and a routing function (fiber
-- map) that uses the current inner outputs and the external input to
-- compute each subsystem's inner input.
--
-- @
--   applyWiring project route machine
-- @
--
-- This is the composition of two poly maps: the machine
-- @Sy^S → InnerOut y^InnerIn@ and the wiring diagram
-- @InnerOut y^InnerIn → OuterOut y^OuterIn@.
applyWiring ::
  (Functor m) =>
  -- | Projection: merge inner outputs into external observation
  (innerOut -> outerOut) ->
  -- | Routing: distribute external input + cross-wire inner outputs
  (innerOut -> outerIn -> innerIn) ->
  MooreTC m s innerIn innerOut ->
  MooreTC m s outerIn outerOut
applyWiring project route (MooreTC machine) = MooreTC $ \s ->
  fmap
    ( \(innerOut, trans) ->
        ( project innerOut,
          trans . route innerOut
        )
    )
    (machine s)

--------------------------------------------------------------------------------
-- Elapsed time

-- | Elapsed time in seconds since the last step.
type DTime = Double

-- | A Moore signal function: a pure Moore coalgebra that receives
-- elapsed time alongside its state. Continuous subsystems (poison
-- ticks, day\/night cycles, cooldown expiry) use this to compute
-- proportional effects regardless of step rate.
--
-- This is not a new type — all existing 'MooreTC' instances apply
-- directly. The driver loop measures wall-clock time and injects it
-- as part of the input on each step.
type MooreSF s i o = MooreC s (DTime, i) o

-- | Distribute elapsed time over 'These'.
--
-- When a command targets one subsystem, the other, or both, every
-- branch receives the current @DTime@. This is the distributive law
-- of the reader functor @(DTime,)@ over 'These'.
distributeDTime :: (DTime, These a b) -> These (DTime, a) (DTime, b)
distributeDTime (dt, This a) = This (dt, a)
distributeDTime (dt, That b) = That (dt, b)
distributeDTime (dt, These a b) = These (dt, a) (dt, b)

-- | Distribute elapsed time over 'Either'.
distributeDTimeEither :: (DTime, Either a b) -> Either (DTime, a) (DTime, b)
distributeDTimeEither (dt, Left a) = Left (dt, a)
distributeDTimeEither (dt, Right b) = Right (dt, b)

-- | Distribute elapsed time over a pair.
distributeDTimePair :: (DTime, (a, b)) -> ((DTime, a), (DTime, b))
distributeDTimePair (dt, (a, b)) = ((dt, a), (dt, b))

--------------------------------------------------------------------------------
-- Pure Moore helpers

-- | Extract the observation from a pure Moore coalgebra at a given state.
observe :: MooreC s i o -> s -> o
observe (MooreTC moore) s = fst $ runIdentity (moore s)

-- | Apply a pure Moore coalgebra's transition function.
transition :: MooreC s i o -> s -> i -> s
transition (MooreTC moore) s = snd (runIdentity (moore s))
