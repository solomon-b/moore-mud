# Changelog

## 0.1.0.0

- Initial release
- Re-export core types from `machines-coalgebras`: `MooreT`, `MooreTC`, `MealyT`, `MealyTC`, and their pure specializations
- Re-export `Fix` and `loop` for driving infinite effectful processes
- `annihilateWithClock`: annihilate a Moore world against a Mealy agent with wall-clock elapsed time injection, returning `Fix m`
- `MooreSF` type alias for Moore signal functions receiving `(DTime, i)`
- `DTime` type alias for elapsed time threading
- `distributeDTime`, `distributeDTimeEither`, `distributeDTimePair`: distributive laws for routing elapsed time across `These`, `Either`, and `(,)` input coproducts
- `applyWiring`: compose a Moore coalgebra with a wiring diagram (projection + routing) to rewire its external interface
- `observe` and `transition` helpers for pure Moore coalgebras
- Higher-kinded data module (`Data.Machine.FRP.HKD`):
  - `SlotKind`, `StateF`, `InputF`, `OutputF` interpretation functors
  - `SequenceMoore` typeclass with `Generic` default: collapse a record of Moore coalgebras into a single composite coalgebra
  - Adding a new subsystem is just adding a field to the HKD record
- `moore-mud` package:
  - `MUD.World.Chat`: chat subsystem Moore coalgebra (Say, Whisper, Shout) with bounded message log
  - `MUD.Agent.Repl`: single-player REPL Mealy agent for testing
  - `MUD.Agent.Player`: networked player Mealy agent — harvests commands from TVar mailboxes, sends observations to sockets, blocks via STM retry until input arrives
  - `MUD.Network`: TCP accept loop, per-player TVar mailboxes, connection registry with connect/disconnect events
  - `moore-mud-repl` executable: end-to-end chat REPL via `annihilateWithClock`
  - `moore-mud-server` executable: TCP chat server on port 4000
- Nix flake: `nix build`, `nix run`, and dev shell for both packages
