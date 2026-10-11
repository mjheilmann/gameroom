# GameRoom Roadmap

GameRoom is a modern real-time tabletop and board game platform built on **Elixir**, **Phoenix v1.8**, **LiveView v1.1**, **Bandit**, **SQLite3**, and **Tailwind CSS v4**.

---

## Quick Resume Guide

If you are picking up this project in a new session:

1. **Verify Environment**:
   ```bash
   mix precommit
   ```
   Ensures compilation with `--warning-as-errors`, formatting, and all tests pass.

2. **Start Dev Server**:
   ```bash
   mix phx.server
   ```
   Accessible at [`http://localhost:4000`](http://localhost:4000).

3. **Current Active Phase**: **Phase 2 (Modern Real-Time Lobby & Multiplayer Tic-Tac-Toe)**
   - **Next Task**: Phase 2.1 – Pure Elixir Tic-Tac-Toe game engine (`Gameroom.Games.TicTacToe`) + unit tests.

4. **Engineering Guidelines**:
   - Project engineering rules and Phoenix 1.8 constraints are codified in [`AGENTS.md`](file:///Users/michael/workspace/gameroom/AGENTS.md).

---

## Phase Checklist

### Phase 1: Clean Baseline & Tooling Upgrade (COMPLETED)
- [x] Upgrade foundation to Phoenix 1.8.1, LiveView 1.1.0, Bandit, and SQLite3 (`ecto_sqlite3`).
- [x] Configure Tailwind CSS v4 assets bundle.
- [x] Clean up `.DS_Store`, orphan directories, and configure [`.gitignore`](file:///Users/michael/workspace/gameroom/.gitignore) for SQLite databases.
- [x] Establish `mix precommit` workflow with clean compilation and passing baseline tests.

---

### Phase 2: Modern Real-Time Lobby & Multiplayer Tic-Tac-Toe (IN PROGRESS)
- [ ] **2.1 Game Logic Engine** (`Gameroom.Games.TicTacToe`)
  - [ ] Implement pure functional game logic: 3×3 grid, turn alternation, legal moves, win & draw checking.
  - [ ] Comprehensive ExUnit test suite covering horizontal, vertical, diagonal wins, draws, and illegal moves.
- [ ] **2.2 Room Process & State Management** (`Gameroom.Games.Room` / `Gameroom.Games.RoomSupervisor`)
  - [ ] Dynamic GenServer per active game room using `DynamicSupervisor` and `Registry`.
  - [ ] Support two players (X and O) + spectator mode.
  - [ ] PubSub broadcast on game state changes, player joins/leaves, and game termination.
  - [ ] Automatic room cleanup on idle/timeout.
- [ ] **2.3 Real-Time Hub / Lobby** (`GameroomWeb.HubLive`)
  - [ ] Player presence tracking using `Phoenix.Presence` (online count, active players).
  - [ ] Fast player nickname selection (stored in session/cookie or guest state).
  - [ ] Active game rooms browser with live status (waiting for player 2, in progress, finished).
  - [ ] "Create New Game" quick-action with customizable room code/slug.
- [ ] **2.4 Modern LiveView Game UI** (`GameroomWeb.GameLive`)
  - [ ] Wraps template with `<Layouts.app flash={@flash} ...>`.
  - [ ] Responsive Tailwind v4 grid with clear player turns, hover micro-interactions, and status banners.
  - [ ] Win line visual highlighting and draw celebration/rematch action.
  - [ ] One-click "Copy Invite Link" for instant 2-player matchmaking.
- [ ] **2.5 Automated Test Coverage**
  - [ ] ExUnit tests for `Room` GenServer lifecycle and edge cases.
  - [ ] `Phoenix.LiveViewTest` tests for Lobby navigation, nickname entry, room creation, and move play.
  - [ ] Run `mix precommit` clean check.

---

### Phase 3: Extensible Multi-Game Platform Engine
- [ ] **3.1 `Gameroom.Games.Engine` Behaviour**
  - [ ] Define standardized callbacks:
    - `@callback new_game(opts :: keyword()) :: game_state()`
    - `@callback valid_move?(game_state(), player(), move()) :: boolean()`
    - `@callback apply_move(game_state(), player(), move()) :: {:ok, game_state()} | {:error, term()}`
    - `@callback game_status(game_state()) :: :in_progress | {:winner, player()} | :draw`
  - [ ] Refactor Tic-Tac-Toe to implement the behaviour.
- [ ] **3.2 Connect Four Game Implementation** (`Gameroom.Games.ConnectFour`)
  - [ ] 7×6 vertical board physics (column dropping, gravity).
  - [ ] 4-in-a-row detection (horizontal, vertical, diagonals).
  - [ ] Full unit test suite.
- [ ] **3.3 Catalog Integration**
  - [ ] Multi-game selector in lobby with game thumbnails and player counts.
  - [ ] Generic room supervisor accommodating any game engine implementation.
  - [ ] Specialized LiveView board components for each game.

---

### Phase 4: Persistent Records, Profiles & Leaderboards (SQLite)
- [ ] **4.1 Ecto Schemas & Migrations**
  - [ ] `players`: guest UUIDs with optional permanent username/email.
  - [ ] `matches`: game type, player 1, player 2, winner, duration, timestamps.
  - [ ] `match_moves`: move sequences for match replay.
- [ ] **4.2 Game Archiving**
  - [ ] Asynchronously record finished games from `Room` GenServer to SQLite.
- [ ] **4.3 Stats & Leaderboard UI**
  - [ ] Player win/loss records and streaks.
  - [ ] Global and per-game leaderboards in `HubLive`.
  - [ ] Match replay viewer LiveView.

---

## Technical Constraints & Conventions (from `AGENTS.md`)

- **Phoenix v1.8**:
  - Always wrap LiveView templates in `<Layouts.app flash={@flash} ...>`.
  - Flash messages live exclusively in `GameroomWeb.Layouts`; do not invoke `<.flash_group>` elsewhere.
  - Use `<.icon>` for heroicons; never call `Heroicons` modules directly.
  - Use `<.input>` and `<.form for={@form}>` driven by `to_form/2`.
- **CSS / Tailwind v4**:
  - CSS resides in `assets/css/app.css` using the `@import "tailwindcss" source(none);` syntax.
  - Do not use `@apply` in raw CSS.
  - Build custom Tailwind components without daisyUI for clean, bespoke UI.
- **Verification**:
  - Always run `mix precommit` before completing any phase.
