# Coalgebraic MUD Engine

*A Moore Machine Architecture for Multi-User Dungeons*

> Moore world $\otimes$ Mealy agents $\to$ `Fix IO` — via polynomial functor lenses and higher-kinded data.

---

## 1. Overview

This document describes the architecture of a Multi-User Dungeon (MUD) server built in Haskell. The core insight is that a MUD is the annihilation of two dual machines: the *world* is a Moore machine (a poly map $Sy^S \to Oy^I$) and every *agent* — player or NPC — is a Mealy machine (a poly map $Oy^I \to Sy^S$). The game loop is their composition into `Fix m`, an infinite effectful process. This duality is not a design pattern; it is a theorem in $\mathbf{Poly}$: a $By^A$ Mealy machine is the universal thing that interacts with an $Ay^B$ Moore machine.

The architecture draws on four key ideas from the theory of polynomial functors: Moore machines as poly maps $Sy^S \to Oy^I$ (which are exactly lenses), Mealy machines as their categorical duals, parallel composition via the tensor product $\otimes$, and subsystem wiring via wiring diagrams (poly maps between interface polynomials). The implementation leverages higher-kinded data (HKD) to make adding new game subsystems a matter of adding a single record field.


## 2. Theoretical Foundations

### 2.1 Moore Machine Coalgebra

A Moore machine consists of a set of states $S$, an input alphabet $I$, an output alphabet $O$, an observation function $S \to O$, and a transition function $S \times I \to S$. In the language of polynomial functors, a Moore machine is a poly map $Sy^S \to Oy^I$: the base map is observation and the fiber map is transition. The key property is that output depends only on the current state, not on the input that triggered the transition. This is the defining characteristic that distinguishes Moore from Mealy machines.

We encode this as a coalgebra parameterized by an effect monad $m$, following the cofree-coffee/cofree-bot library:

```haskell
newtype MooreTC m s i o = MooreTC
  { runMooreTC :: s -> m (o, i -> s) }
```

Given a state $s$, the coalgebra produces (in the monad $m$) a pair of the current observation $o$ and a pure transition function from input $i$ to the next state. The monadic context $m$ allows effects during observation (logging, randomness, database reads) while keeping the transition function completely pure.

### 2.2 Pure Specialization

For the MUD engine we make a critical simplifying choice: the observation function is pure. If randomness is needed it lives in the state (as an RNG seed). If elapsed time is needed it arrives via the input. This lets us specialize to `Identity`:

```haskell
type MooreC = MooreTC Identity

-- Equivalently:
-- MooreC s i o  ≅  s -> (o, i -> s)
```

A pure Moore machine is a coalgebra for the polynomial $Oy^I$, i.e., it is a poly map $Sy^S \to Oy^I$. This is exactly a lens from $(S, S)$ to $(O, I)$, which connects Moore machines to the category $\mathbf{Poly}$ of polynomial functors and gives us access to the `lens` library for composition.

### 2.3 Moore Machines as Lenses

A poly map from $Sy^S$ to $Oy^I$ consists of two functions: a base map (observation) $S \to O$ and a fiber map (transition) $S \to I \to S$. This is the same data as a non-dependent lens:

```haskell
type Moore s i o = Lens s s o i

observe    :: Moore s i o -> s -> o
observe    = view

transition :: Moore s i o -> s -> i -> s
transition = set
```

Lens composition is poly map composition. Given a Moore machine $Sy^S \to Oy^I$ and a wiring diagram $Oy^I \to By^A$, their composition is a new poly map $Sy^S \to By^A$ — a Moore machine with a rewired external interface. This is ordinary function composition in Haskell.

### 2.4 Continuous Time via Input

A naive Moore machine steps in discrete ticks, but a MUD has events arriving at arbitrary times and continuous processes (poison damage, NPC patrol routes, day/night cycles) that depend on elapsed time. Rather than introducing a new signal function type, we thread elapsed time through the input:

```haskell
type DTime = Double  -- seconds since last step

type MooreSF s i o = MooreC (DTime, s) i o
```

This is not a new type; it is an alias. All existing `MooreTC` instances (`Trifunctor.Semigroupal`, `Profunctor`) apply directly. The driver loop measures wall-clock time and injects it as part of the input on each step. Every subsystem receives the same `DTime`, ensuring globally consistent time progression.

To route `DTime` to all subsystems when commands target only one, we use a distributive law: the reader functor $(DTime,)$ distributes over `Either` and `These`:

```haskell
routeInput
  :: (DTime, These CombatCmd ChatCmd)
  -> These (DTime, CombatCmd) (DTime, ChatCmd)
routeInput (dt, This c)      = This (dt, c)
routeInput (dt, That c)      = That (dt, c)
routeInput (dt, These c1 c2) = These (dt, c1) (dt, c2)
```


## 3. Moore/Mealy Duality and Annihilation

### 3.1 Agents as Mealy Machines

The world is Moore: what you observe about a room depends on the state of the room, not on the command you just issued. But agents — both players and NPCs — are Mealy: what action they take depends on what they *currently* observe. Output depends on input.

```haskell
newtype MealyTC m s i o = MealyTC
  { runMealyTC :: s -> i -> m (o, s) }

-- In cofree-bot:
newtype Bot m s i o = Bot
  { runBot :: s -> i -> ListT m (o, s) }
```

From the world's perspective there is no distinction between a player and an NPC. Both produce commands in response to observations. But they differ in two important ways: where they run and what monad they need.

- **PC agent:** Pure IO mediation. The player's brain is on the other side of a socket. The agent reads their command from a `TVar`. It has no meaningful state of its own — the "state" is in the player's head.
- **NPC agent:** Pure computation. The AI function evaluates directly. It can run in `Identity` — no IO needed.

This means the composite agent is two Mealy machines tensored together, with different monads:

```haskell
pcAgent  :: MealyT IO       (Map PlayerId Obs) (Map PlayerId Cmd)  -- inherently IO
npcAgent :: MealyT Identity (Map NPCId Obs)    (Map NPCId Cmd)     -- pure!

agents :: MealyT IO
  (Map PlayerId Obs, Map NPCId Obs)
  (Map PlayerId Cmd, Map NPCId Cmd)
agents = pcAgent `tensor` hoistMealy (pure . runIdentity) npcAgent
```

The `npcAgent` is lifted into `IO` at the tensor boundary via `hoistMealy`, but its internals are pure. You can test NPC behavior without any IO by running the `Identity` version directly.

### 3.2 Annihilation

The game loop is the *annihilation* of the Moore world against the Mealy agents. This is a standard construction in $\mathbf{Poly}$: given a Moore machine $Ay^B$ and a Mealy machine $By^A$, their annihilation is `Fix m` — an infinite effectful process that unfolds forever.

From the cofree-bot library:

```haskell
annihilate
  :: (Monad m)
  => MooreT m o i
  -> MealyT m i o
  -> Fix m
annihilate (MooreT moore) (MealyT mealy) = Fix $ do
  (i, nextMoore) <- moore       -- 1. World emits observation
  (o, mealy')    <- mealy i     -- 2. Agent sees it, emits command
  let moore' = nextMoore o      -- 3. World transitions on command
  pure $ annihilate moore' mealy'

loop :: (Monad f) => Fix f -> f x
loop (Fix x) = x >>= loop
```

This is the entire game loop. The Moore machine (world) emits an observation, the Mealy machine (agent) consumes it and produces a command, the Moore machine transitions on that command, and the process recurses. `loop` drives it forever.

### 3.3 Dynamic Population

A MUD has a dynamic population: players connect and disconnect, NPCs spawn and die. But `annihilate` assumes a fixed pair of machines. The solution: the agent population is part of the *world state*, and the composite Mealy machine reads the current population from the world's observation on each step.

```haskell
-- The world observation tells agents who exists right now
data WorldObservation = WorldObservation
  { perPlayer  :: Map PlayerId PlayerObservation
  , perNPC     :: Map NPCId NPCObservation
  , connected  :: Set PlayerId
  , aliveNPCs  :: Set NPCId
  }
```

Connect, disconnect, spawn, and die are just commands in the input alphabet:

```haskell
data MetaCommand
  = Connect PlayerId
  | Disconnect PlayerId
  | SpawnNPC NPCId RoomId
  | NPCDied NPCId
```

The world's transition function handles them like any other state change. `annihilate` runs once. The Mealy machine adapts each step by reading `connected` and `aliveNPCs` from the observation — it doesn't need to be reconstructed.

### 3.4 Three-Layer Architecture

The system has three layers. Only layers 2 and 3 participate in annihilation:

```
  Layer 1: Network (concurrent IO, outside annihilate)
  ────────────────────────────────────────────────────
  TCP accept loop
    → spawn thread per player
    → thread reads socket, writes to TVar
    → on connect: insert TVar into registry, push Connect cmd
    → on disconnect: remove from registry, push Disconnect cmd

  Layer 2: Composite Agent (Mealy, inside annihilate)
  ────────────────────────────────────────────────────
  Two Mealy machines tensored together:

    pcAgent (IO):
      → read TVar registry (which players exist)
      → harvest commands from connected players' TVars
      → skip disconnected players

    npcAgent (Identity, lifted to IO):
      → run AI functions for living NPCs
      → skip dead NPCs

  Layer 3: World (Moore, inside annihilate)
  ────────────────────────────────────────────────────
  Pure state machine:
    → receive Map AgentId Command
    → transition (rooms, combat, chat, env, population)
    → emit WorldObservation (including who's connected/alive)
```

The boundary between layer 1 and layer 2 is a `TVar (Map PlayerId PlayerMailbox)` — the only shared mutable state in the entire system. Layer 1 mutates it when players connect/disconnect. Layer 2 reads it each step. The world (layer 3) is pure.

```haskell
-- Layer 2: two Mealy machines tensored
pcAgent :: TVar (Map PlayerId PlayerMailbox)
        -> MealyT IO WorldObservation (Map PlayerId Command)
pcAgent registry = MealyT $ \obs -> do
  mailboxes <- readTVarIO registry
  cmds <- atomically $
    for (Map.restrictKeys mailboxes (connected obs)) $ \box -> do
      cmd <- readTVar box
      writeTVar box Nothing
      pure cmd
  pure (Map.mapMaybe id cmds, pcAgent registry)

npcAgent :: Map NPCId (MealyTC Identity NPCState NPCObservation NPCCommand)
         -> MealyT Identity WorldObservation (Map NPCId NPCCommand)

-- Tensor them, annihilate against the world
game :: Fix IO
game = annihilate world (pcAgent registry `tensor` liftNPC npcAgent)
```

### 3.5 Why This Matters

The duality isn't just elegant — it has practical consequences:

- **Testing.** Annihilate the world against a *scripted* Mealy machine that replays a recorded command log. Deterministic replay is just annihilation with a pure agent.
- **AI development.** `npcAgent` runs in `Identity`. Test NPC behavior by feeding mock observations and asserting on commands — no IO, no sockets, no timing.
- **Protocol agnosticism.** `pcAgent` is an interface, not an implementation. Matrix, Discord, IRC, telnet, a CLI REPL — each is just a different `MealyT IO` that translates between the protocol and `Command`/`Observation`. Tensor in whichever ones you need.
- **Extensibility.** Adding a new agent type — a scripted replay agent, a logging observer, an admin console — is tensoring another Mealy machine into the composite. The world doesn't know or care.
- **Dynamic population.** Players connecting and NPCs spawning are just world state transitions. `annihilate` runs once. No reconstruction.


## 4. Composition

### 4.1 Tensor Product

The tensor product (parallel product) in $\mathbf{Poly}$ takes the product of both base and fiber: given $Sy^S$ and $Ty^T$, their tensor is $(S \times T)y^{S \times T}$. For Moore machines encoded as lenses, this composes two machines to run in parallel with independent state, paired inputs, and paired outputs. This corresponds to the `Trifunctor.Semigroupal` instance with `(,)` on all three type parameters:

```haskell
tensor
  :: Moore s i o
  -> Moore t i' o'
  -> Moore (s, t) (i, i') (o, o')
tensor m n = lens observe' transition'
  where
    observe' (s, t)            = (view m s, view n t)
    transition' (s, t) (a, b)  = (set m s a, set n t b)
```

The tensor product is associative and unital (with unit `Moore () () ()`), making Moore machines a monoidal category under parallel composition.

### 4.2 Monoidal Functor Instances

The cofree-bot library provides three `Trifunctor.Semigroupal` instances for `MooreTC`, varying the monoidal structure on the input parameter:

- **(,) on input:** Both subsystems receive input simultaneously. This is the tensor product $\otimes$.
- **Either on input:** Input is routed to one subsystem or the other. The idle subsystem's state is preserved exactly (not stepped with a dummy input). This is honest because the state is explicit.
- **These on input:** Input hits one, the other, or both. This handles commands that cross subsystem boundaries (e.g., an attack that affects both combat and chat).

The `Either` and `These` instances are a key advantage of keeping state explicit in `MooreTC` rather than existentializing it (as in dunai's `MSF`). With existentialized state, an idle subsystem must be stepped with a fabricated input. With explicit state, it is simply unchanged.

### 4.3 Wiring Diagrams

Parallel composition puts subsystems side by side, but a game requires subsystems to communicate: combat needs to know the player's current room (from navigation), chat is spatial (messages go to players in the same room), death in combat triggers respawn in navigation.

Wiring diagrams are poly maps $P \to Q$ that describe how to route the internal outputs and external inputs of a composite system. $P$ is the inner polynomial (the tensored subsystem interfaces) and $Q$ is the outer polynomial (the public interface). They are a separate, inspectable artifact from the subsystem machines themselves.

```
    Q = Observation y^(Δt × Command)
    ┌─────────────────────────────────────────────────────────┐
    │                                                         │
    │            ┌──────────┐  death    ┌──────────┐          │
    │         ┌──┤          ├─────────►─┤          │          │
    │         │  │  Combat  │           │   Nav    ├──room─┐  │
    │         │  │          ├─◄─────────┤          │       │  │
    │         │  └──────────┘    room   └────┬─────┘       │  │
    │         │                              │room         │  │
    │         │                              ▼             │  │
    │         │                         ┌──────────┐       │  │
    │         │                         │          │       │  │
    │         │                         │   Chat   │       │  │
    │         │                         │          │       │  │
    │         │                         └──────────┘       │  │
    │         │                                            │  │
    │         │  ┌──────────┐                              │  │
    │         │  │          │                              │  │
    │    Δt───┼──┤   Env    │                              │  │
    │         │  │          │                              │  │
    │         │  └──────────┘                              │  │
    │         │                                            │  │
  ──┼── Δt ───┘                                            └──┼──► Observation
  ──┼── Cmd ──► (routed to Combat, Nav, Chat via fiber map)   │
    │                                                         │
    │  P = (CombatOut × NavOut × ChatOut × EnvOut)            │
    │       y^(CombatIn × NavIn × ChatIn × EnvIn)            │
    └─────────────────────────────────────────────────────────┘

    fiber map (set):  routes Δt + Cmd + inner outputs → inner inputs
    base map  (view): merges inner outputs → Observation
```

The outer box is $Q$ — the public interface. The inner boxes are the subsystem Moore machines tensored together as $P$. The arrows between inner boxes are the internal wiring: the fiber map routes subsystem outputs into other subsystems' inputs (room → combat targets, death → respawn, room → spatial chat). The fiber map also fans $\Delta t \times \text{Command}$ from the external input to each subsystem. The base map merges all inner outputs into a single `Observation`.

In Haskell, the wiring diagram is a lens:

```haskell
-- Inner poly:  (CombatOut × NavOut × ChatOut × EnvOut)y^(CombatIn × NavIn × ChatIn × EnvIn)
-- Outer poly:  Observation y^(DTime × Command)

mudWiring
  :: Lens
       (CombatOut, NavOut, ChatOut, EnvOut)
       (CombatIn, NavIn, ChatIn, EnvIn)
       Observation
       (DTime, Command)
mudWiring = lens observe route
  where
    observe (combatOut, navOut, chatOut, envOut) =
      Observation { .. }

    route (combatOut, navOut, chatOut, envOut) (dt, cmd) =
      ( CombatIn
          { cmd   = cmd
          , dt    = dt
          , room  = navRoom navOut
          }
      , NavIn
          { cmd     = cmd
          , dt      = dt
          , respawn = combatRespawn combatOut
          }
      , ChatIn
          { cmd  = cmd
          , room = navRoom navOut
          }
      , EnvIn
          { dt = dt }
      )
```

The final composed MUD is just lens composition:

```haskell
mudMachines :: Moore
  (CombatState, NavState, ChatState, EnvState)
  (CombatIn, NavIn, ChatIn, EnvIn)
  (CombatOut, NavOut, ChatOut, EnvOut)
mudMachines =
  combatMachine `tensor` navMachine
    `tensor` chatMachine `tensor` envMachine

mud :: Moore
  (CombatState, NavState, ChatState, EnvState)
  (DTime, Command)
  Observation
mud = mudMachines . mudWiring
```


## 5. Higher-Kinded Data

### 5.1 The Pattern

Rather than manually tensoring subsystems and managing nested tuples, we use higher-kinded data (HKD) to define the MUD as a record parameterized by an interpretation functor. This follows the pattern from cofree-bot's HKD module, adapted from Mealy (`Bot`) to Moore.

The interpretation functor has kind `Type -> Type -> Type -> Type`, representing the triple of state, input, and output for each subsystem slot:

```haskell
type SlotKind = Type -> Type -> Type -> Type

newtype StateF  s i o = StateF  { getStateF  :: s }
newtype InputF  s i o = InputF  { getInputF  :: Maybe i }
newtype OutputF s i o = OutputF { getOutputF :: Maybe o }
```

### 5.2 The MUD Record

```haskell
data Mud (f :: SlotKind) = Mud
  { combat :: f CombatState CombatCmd CombatOutput
  , chat   :: f ChatState   ChatCmd   ChatOutput
  , nav    :: f NavState    NavCmd    NavOutput
  , env    :: f EnvState    ()        EnvOutput
  } deriving Generic
```

This single declaration gives us four types for free:

- `Mud (MooreTC m)` — A record of Moore machines, one per subsystem.
- `Mud StateF` — The composite state of the entire MUD.
- `Mud InputF` — The composite input: a `Maybe` command per subsystem (`Nothing` = idle).
- `Mud OutputF` — The composite output: a `Maybe` observation per subsystem.

### 5.3 Generic Sequencing

A typeclass `SequenceMoore` with a `Generic` default collapses a record of Moore machines into a single Moore machine over the record of states, inputs, and outputs:

```haskell
class SequenceMoore f where
  sequenceMoore
    :: Applicative m
    => f (MooreTC m)
    -> MooreTC m (f StateF) (f InputF) (f OutputF)
```

The generic implementation walks the product structure of the record via `GHC.Generics`. At each leaf (`K1`), a single `MooreTC` is lifted into the `StateF`/`InputF`/`OutputF` wrappers. At each product node (`:*:`), two machines are combined: both are observed, and the transition function dispatches input to the appropriate subsystem based on the `Maybe` wrapper (`Nothing` preserves state, `Just` applies the transition).

Adding a new subsystem (e.g., crafting, economy, weather) requires only adding a field to the `Mud` record. The generic derivation picks it up automatically. No manual tensor products, no tuple plumbing.


## 6. Synchronization and the Driver Loop

### 6.1 The Purity Guarantee

With `MooreC` (Moore over `Identity`), the world engine is a pure function: $S \to (O, I \to S)$. There is one value of type $S$ at any point in time, and one pure function that produces the next. Player synchronization is guaranteed by construction: there is no concurrent mutation, no shared mutable state, no locks. The world state is always consistent because it is always a single immutable value.

### 6.2 Annihilate as the Game Loop

The driver is `annihilate` from section 3.2 composed with `loop`:

```haskell
main :: IO ()
main = do
  registry <- newTVarIO Map.empty
  forkIO $ acceptLoop registry   -- Layer 1: network

  let world  = fixMooreTC mudCoalgebra initialWorldState
      agents = pcAgent registry `tensor` liftNPC npcAgent
      game   = annihilate world agents

  loop game                       -- Layers 2+3: annihilate forever
```

The `atomically` block inside `pcAgent` is the only synchronization primitive. Connection handler threads (layer 1) write commands into `TVar` mailboxes and mutate the registry. The composite Mealy machine (layer 2) reads the registry and harvests commands each step. The world (layer 3) is pure. `annihilate` ties layers 2 and 3 into `Fix IO`, and `loop` drives it.

### 6.3 Event-Driven Stepping

The driver does not run on a fixed tick. The `pcAgent` Mealy machine blocks on STM until at least one player has submitted a command (or a timeout fires for continuous processes). The `DTime` is measured at each step and injected into the world's input. Continuous subsystems (environment, NPC patrol, poison ticks) use this delta to compute proportional effects regardless of step rate.


## 7. Properties and Testing

The architecture yields several properties that are valuable for development and operations:

- **Pure testability.** Every world subsystem is a pure function from state and input to observation and next-state. Property-based testing with QuickCheck is straightforward: generate random command sequences, run them through `scanMoore`, and assert invariants on the output trace. NPC Mealy machines are tested in isolation by feeding mock observations.

- **Serializable state.** The entire world state is a plain Haskell value. Snapshotting to PostgreSQL (or any store) is just serialization. Restoring is deserialization. There is no hidden monadic context to reconstruct.

- **Deterministic replay.** Annihilate the world against a scripted Mealy machine that replays a recorded command log. Same initial state + same inputs = identical output, every time. This enables replay debugging and regression tests from production logs.

- **Subsystem isolation.** Each Moore machine is tested independently. The wiring diagram is tested separately by mocking subsystem outputs and verifying correct routing. Composition preserves subsystem invariants by construction.

- **Hot-swappable wiring.** The wiring diagram is a separate value from the subsystem machines. Changing how subsystems communicate (e.g., making chat non-spatial, adding a new cross-cutting concern) is a change to the wiring lens, not to any subsystem.

- **Protocol agnosticism.** The agent Mealy machine is an interface. Matrix, Discord, IRC, telnet, a CLI REPL — each is just a different `MealyT IO` that wraps the protocol. The world doesn't know or care.


## 8. Subsystem Inventory

The initial MUD engine defines four subsystems. Each is an independent Moore machine with its own state, input, and output types.

### 8.1 Navigation

| | |
|---|---|
| **State** | Room graph, player positions, exits, item placements |
| **Input** | Move direction, Look, Enter/Exit |
| **Output** | Room description, visible exits, present players/items |
| **Continuous** | None (purely event-driven) |

### 8.2 Combat

| | |
|---|---|
| **State** | HP, active effects, cooldowns, combat log |
| **Input** | Attack, Defend, Use item, Flee |
| **Output** | Damage dealt/received, status changes, death events |
| **Continuous** | Poison/regen ticks (proportional to $\Delta t$), cooldown expiry |

### 8.3 Chat

| | |
|---|---|
| **State** | Message history (bounded ring buffer) |
| **Input** | Say, Whisper, Shout |
| **Output** | Messages visible to each player (spatial filtering via wiring) |
| **Continuous** | None |

### 8.4 Environment

| | |
|---|---|
| **State** | Time of day, weather, ambient descriptions |
| **Input** | $()$ — no player input, only $\Delta t$ via wiring |
| **Output** | Current time-of-day description, weather effects |
| **Continuous** | Day/night cycle, weather transitions (proportional to $\Delta t$) |


## 9. Wiring Diagram

The wiring diagram encodes the engine design: how subsystems see each other and how player commands are routed. This is the part of the architecture that is hand-written rather than generically derived, because it embodies structural decisions specific to this engine. The game — rooms, items, NPCs, quests, lore — is data that populates the world state and the specific transition rules within each subsystem.

The wiring is expressed as a single lens (poly map) from the inner polynomial

$$P = (\text{CombatOut} \times \text{NavOut} \times \text{ChatOut} \times \text{EnvOut})\, y^{\text{CombatIn} \times \text{NavIn} \times \text{ChatIn} \times \text{EnvIn}}$$

to the outer polynomial

$$Q = \text{Observation}\, y^{\Delta t \times \text{Command}}$$

The base map wires inner outputs to the external observation. The fiber map wires the external input and inner outputs to inner inputs:

- **Combat → Nav:** Death events from combat trigger respawn logic in navigation.
- **Nav → Combat:** Current room from navigation determines valid combat targets.
- **Nav → Chat:** Current room determines which players receive spatial chat messages.
- **Env → Observation:** Time-of-day and weather are layered into every player's room description.
- **$\Delta t$ → All:** Elapsed time is distributed to every subsystem via the distributive law over the input coproduct.

Adding a new cross-cutting concern (e.g., crafting consumes items from navigation, stealth modifies combat visibility) is a modification to the wiring lens. The subsystem machines remain unchanged.


## 10. Extension Points

The architecture is designed to grow along several axes:

- **New subsystems.** Add a field to the `Mud` record (e.g., crafting, economy, quests). Generic derivation handles composition.

- **NPC behavior.** NPCs are Mealy machines annihilated against the world alongside player agents. Adding an NPC is adding a `MealyTC` to the composite agent, not modifying the world. NPC AI can be tested in isolation by feeding mock observations.

- **Persistence.** The pure state is serializable via Aeson or binary. Periodic snapshots to PostgreSQL, with the $(\Delta t, \text{MudInput})$ log as a write-ahead log for replay.

- **Speculative execution.** Because the machine is pure, the server can speculatively run the game forward to preview consequences (e.g., AI planning for NPCs, client-side prediction).

- **Multiple clock rates.** The driver can step the machine at different rates for different contexts: fast for combat (sub-second), slow for environment (minutes). Rhine-style clock composition is available if needed but not required initially.

- **Monadic upgrade.** If a subsystem genuinely needs effects at observation time (e.g., procedural generation requiring IO-based randomness), it can be lifted from `MooreC` to `MooreTC IO` without changing the composition machinery. The `Trifunctor` instances are parameterized by $m$.


## 11. Key Dependencies

| Package | Role |
|---|---|
| `lens` | Moore machines as lenses, wiring diagram composition |
| `cofree-bot` (machines-coalgebras) | `MooreTC` type, `Trifunctor.Semigroupal` instances |
| `cofree-bot` (chat-bots) | HKD pattern, Generic sequencing (adapted from `Bot` to Moore) |
| `stm` | `TVar` mailboxes for player command collection |
| `aeson` / `postgresql-simple` | State serialization and persistence |
| `QuickCheck` | Property-based testing of subsystem invariants |


## 12. Summary

The MUD is the annihilation of two dual machines. The *world* is a pure Moore machine (a poly map $Sy^S \to Oy^I$) composed from independent subsystems via the tensor product $\otimes$ and connected by a hand-written wiring diagram. The *agents* are two Mealy machines tensored together: `pcAgent` in `IO` (mediating between sockets and the game) and `npcAgent` in `Identity` (pure AI, lifted to `IO` at the boundary). Their annihilation produces `Fix IO`: the running game.

Population is dynamic — players connect and disconnect, NPCs spawn and die — but `annihilate` runs once. Population changes are world state transitions; the Mealy machines read the current population from the world's observation each step.

Higher-kinded data makes subsystem composition extensible and generic. State synchronization is guaranteed by construction: the world is a single pure value, the agents are a single composite Mealy machine, and `annihilate` mediates between them.

```haskell
world  :: MooreT IO WorldObservation (Map AgentId Command)
agents :: MealyT IO WorldObservation (Map AgentId Command)
agents = pcAgent registry `tensor` liftNPC npcAgent
game   :: Fix IO
game   = annihilate world agents
```

That is the whole thing.
