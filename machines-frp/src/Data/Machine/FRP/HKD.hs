{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Higher-kinded data for composing Moore coalgebras.
--
-- Define a record parameterized by a 'SlotKind' interpretation
-- functor, derive 'Generic', and get automatic sequencing into a
-- single composite Moore coalgebra.
--
-- @
-- data Mud (f :: SlotKind) = Mud
--   { combat :: f CombatState CombatCmd CombatOutput
--   , nav    :: f NavState    NavCmd    NavOutput
--   , chat   :: f ChatState   ChatCmd   ChatOutput
--   , env    :: f EnvState    ()        EnvOutput
--   } deriving Generic
--
-- instance SequenceMoore Mud
--
-- -- Now you have:
-- -- Mud (MooreTC m)  — a record of machines
-- -- Mud StateF       — composite state
-- -- Mud InputF       — composite input (Maybe per subsystem)
-- -- Mud OutputF      — composite output
-- @
--
-- Adding a new subsystem is just adding a field to the record.
module Data.Machine.FRP.HKD
  ( -- * Slot interpretation
    SlotKind,
    StateF (..),
    InputF (..),
    OutputF (..),

    -- * Generic sequencing
    SequenceMoore (..),
  )
where

--------------------------------------------------------------------------------

import Data.Kind (Type)
import Data.Machine.Moore.Coalgebra (MooreTC (..))
import GHC.Generics

--------------------------------------------------------------------------------
-- Slot interpretations

-- | Kind for HKD slot interpretation functors.
--
-- Each slot in the record carries three type parameters: state,
-- input, and output. The interpretation functor selects which one
-- to project.
type SlotKind = Type -> Type -> Type -> Type

-- | Interpret a slot as its state component.
newtype StateF s i o = StateF {getStateF :: s}
  deriving (Show, Eq)

-- | Interpret a slot as an optional input.
--
-- 'Nothing' means the subsystem receives no command this step;
-- its state is preserved unchanged.
newtype InputF s i o = InputF {getInputF :: Maybe i}
  deriving (Show, Eq)

-- | Interpret a slot as its output observation.
newtype OutputF s i o = OutputF {getOutputF :: o}
  deriving (Show, Eq)

--------------------------------------------------------------------------------
-- Generic sequencing

-- | Collapse a record of Moore coalgebras into a single Moore
-- coalgebra over the record of states, inputs, and outputs.
--
-- The generic default walks the product structure of the record.
-- At each leaf, a single 'MooreTC' is lifted into the
-- 'StateF'/'InputF'/'OutputF' wrappers. At each product node,
-- two machines are combined: both are observed, and the transition
-- function dispatches input to the appropriate subsystem based on
-- the 'Maybe' wrapper ('Nothing' preserves state, 'Just' applies
-- the transition).
class SequenceMoore (rec :: SlotKind -> Type) where
  sequenceMoore ::
    (Applicative m) =>
    rec (MooreTC m) ->
    MooreTC m (rec StateF) (rec InputF) (rec OutputF)
  default sequenceMoore ::
    ( Applicative m,
      Generic (rec (MooreTC m)),
      Generic (rec StateF),
      Generic (rec InputF),
      Generic (rec OutputF),
      GSequenceMoore
        m
        (Rep (rec (MooreTC m)))
        (Rep (rec StateF))
        (Rep (rec InputF))
        (Rep (rec OutputF))
    ) =>
    rec (MooreTC m) ->
    MooreTC m (rec StateF) (rec InputF) (rec OutputF)
  sequenceMoore recM = MooreTC $ \recS ->
    fmap
      (\(repO, t) -> (to repO, to . t . from))
      (runMooreTC (gSequenceMoore (from recM)) (from recS))

--------------------------------------------------------------------------------
-- Generic implementation (not exported)

class
  GSequenceMoore
    m
    (machRep :: Type -> Type)
    (stateRep :: Type -> Type)
    (inputRep :: Type -> Type)
    (outputRep :: Type -> Type)
  where
  gSequenceMoore ::
    machRep x ->
    MooreTC m (stateRep x) (inputRep x) (outputRep x)

-- Leaf: a single MooreTC field
instance
  (Functor m) =>
  GSequenceMoore
    m
    (K1 R (MooreTC m s i o))
    (K1 R (StateF s i o))
    (K1 R (InputF s i o))
    (K1 R (OutputF s i o))
  where
  gSequenceMoore (K1 (MooreTC f)) = MooreTC $ \(K1 (StateF s)) ->
    fmap
      ( \(o, t) ->
          ( K1 (OutputF o),
            \(K1 (InputF mi)) -> K1 (StateF (maybe s t mi))
          )
      )
      (f s)

-- Product: combine two sub-trees
instance
  ( Applicative m,
    GSequenceMoore m mf sf fi fo,
    GSequenceMoore m mg sg gi go
  ) =>
  GSequenceMoore m (mf :*: mg) (sf :*: sg) (fi :*: gi) (fo :*: go)
  where
  gSequenceMoore (mf :*: mg) = MooreTC $ \(sf :*: sg) ->
    liftA2
      ( \(fo, tf) (go, tg) ->
          ( fo :*: go,
            \(fi :*: gi) -> tf fi :*: tg gi
          )
      )
      (runMooreTC (gSequenceMoore mf) sf)
      (runMooreTC (gSequenceMoore mg) sg)

-- Metadata wrappers (D1, C1, S1): transparent pass-through
instance
  (Functor m, GSequenceMoore m f sf fi fo) =>
  GSequenceMoore m (M1 i c f) (M1 i c sf) (M1 i c fi) (M1 i c fo)
  where
  gSequenceMoore (M1 f) = MooreTC $ \(M1 sf) ->
    fmap
      (\(fo, t) -> (M1 fo, \(M1 fi) -> M1 (t fi)))
      (runMooreTC (gSequenceMoore f) sf)
