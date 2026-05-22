# Dart Roguelike — Design Notes

*Canonical design doc. Last refreshed 2026-05-22 after the Checkout Helper + Locked/Unlocked modifier status passes shipped.*

*This document supersedes `ProjectOverview.txt`. When major design decisions happen, refresh this doc — either by hand or by asking Claude.ai for an updated writeup of its project memory.*

---

## Status snapshot

**Shipped 2026-05-22 (on `checkout-helper` branch):**

- **Checkout Helper** (`specs/2026-05-22-checkout-helper.md`). Solver-based helper in a right-side text panel that surfaces valid checkout paths (annotated for streak interactions and deliberate streak-breaks) and falls back to a single-dart setup recommendation when no checkout exists this turn. Accounts for all active modifiers including live streak state. Toggleable visibility, with a soft "try toggling a modifier" hint when any unlocked modifier is active.
- **Locked/Unlocked modifier status** (no separate spec — shipped contemporaneous follow-on). Every modifier instance rolls toggleable at generation time; 35% become unlocked (clickable on/off), 65% lock as always-on. Locked carries no compensating buff — rarity is the power axis, and swap-anytime via shop/post-leg picks keeps commits real but not permanent.

**Shipped 2026-05-21 (all merged to main):**

- **Streak slot restriction system + Color Streak + Parity Streak modifiers** (`specs/2026-05-21-streak-slots-and-modifiers.md`). One-per-category slot rule for three streak categories (WEDGE, COLOR, PARITY).
- **HUD / Assembly Polish Pass** (`specs/2026-05-21-hud-assembly-polish.md`). Balance bar gradient with new transition sub-zones, score-gold checkout indicator, target tooltip relocation above the crosshair with perk-up hover state, Even/Odd parity streak differentiation.
- **Shop System** (`specs/2026-05-21-shop-system.md`). Every third leg, the post-leg upgrade pick is replaced by a shop where the player throws their accumulated spare darts at lit-up board spots to earn rarity-tiered upgrades.

Phase 5 (Dart Parts & Assembly Screen) is also shipped — `dart_build.gd`, `assembly_screen.gd`, and the balance system exist in the codebase. The phase outline further down has been updated to match.

---

## Game Concept

A Balatro-style roguelike built around darts. The player customizes a dart from three components — barrel, shaft, and flight — with each part affecting throw stats. Runs scale through an x01 format (101 → 201 → 301 → etc.), with escalating score targets requiring increasingly powerful builds to keep pace. An Armored Core-inspired balance system prevents pure stat stacking and forces meaningful tradeoffs. Scoring modifiers (acquired during the run) change how the player sees and values the dartboard, creating different strategic board reads every run.

### Core Design Pillars

- **Throw Mechanic:** A four-stage input system (aim → vertical window → vertical release → horizontal release) that blends deliberate positioning with timing-based skill. Build stats directly affect each stage's difficulty and precision.
- **Build System:** Mario Kart-style stat spreads across dart components. An Armored Core-inspired balance threshold prevents pure stat stacking and forces meaningful tradeoffs.
- **Scoring Modifiers:** Roguelike items that change how the player sees and values the dartboard — e.g., triples worth more but doubles worth 0, odd numbers doubled, red zones give bonus points, wedge value boosts, color-based multiplier bonuses, streak rewards. The board is always the same, but the build makes you play it differently every run.
- **Form (Deck Equivalent):** The player's throwing style, chosen at the start of a run. Changes the fundamental feel of the throw mechanic — e.g., different meter behavior, snap-to-wedge aiming, bonus streaks. Analogous to Balatro's deck choice. NOT YET IMPLEMENTED — future feature.

### Win Condition / Progression

- Scaling x01: Leg 1 starts at 101 with 5 turns (15 darts). Each subsequent leg adds 100 to the target (201, 301, 401...).
- The classic 501 becomes a mid-run challenge; later legs (701, 801+) require strong builds.
- Player must finish each leg by reaching exactly 0, with the final dart landing on a double (or double bullseye). Standard darts "double out" rule.
- Bust rules: if a dart would take the score below 0, to exactly 1 (impossible to finish since no double = 1), or to 0 without hitting a double, the entire 3-dart turn busts — score reverts to what it was at the start of that turn, remaining darts forfeited.
- Between legs, the player picks one of three stat upgrades (randomized, rarity-weighted) **on non-shop legs**. On every third leg, the upgrade pick is replaced by a **shop round** — see the Shop System section below.
- Spare darts (the difference between the leg's dart budget and darts actually used) accumulate across legs and spend at the shop.
- Fail a leg (don't reach 0 in 5 turns) → run over.

---

## Tech Stack & Conventions

- **Engine:** Godot 4
- **Language:** GDScript
- **Scripts location:** `res://scripts/`

### GDScript Coding Conventions

These conventions apply to ALL code in the project and should be followed in every spec handed to Claude Code:

1. **Static typing on ALL variables** — no untyped vars anywhere. Every `var`, every function parameter, every return type.
2. **Frequent commenting** — every function, every block of logic, every non-obvious line.
3. **`##` doc comments on all `@export` vars** — describe what the variable does, what different values mean, and how it interacts with gameplay.
4. **`@export` vars liberally** — any tunable value (colors, speeds, thresholds, sizes, durations) should be exported for inspector tweaking. This is critical for the brainstorm → spec → Claude Code → playtest workflow.

### Development Workflow

1. **Brainstorm & plan** in Claude chat/Cowork — discuss concepts, mechanics, tradeoffs, get constructive feedback, arrive at shared understanding.
2. **Write a spec** as a detailed markdown document describing exactly what to build/modify, including file paths, method signatures, scene tree changes, and coding conventions. Spec lives in `CLAUDE.md` at the repo root during active work; gets archived to `specs/YYYY-MM-DD-feature-slug.md` after shipping.
3. **Hand the spec to Claude Code** for implementation in Godot.
4. **Test in engine**, then return to step 1 for the next feature.

The developer values: constructive feedback, probing questions, thorough mutual understanding before building, and pragmatic organizational advice. Back-and-forth design discussion is encouraged. Claude should interrogate design decisions, surface potential concerns, and help think through tradeoffs before committing to a spec.

---

## Scene Tree (Current)

```
Main (Node2D) — main.gd
├── Dartboard (Node2D) — dartboard.gd
├── ThrowMechanic (Node2D) — throw_mechanic.gd
├── DartContainer (Node2D) — holds dart marker instances
├── X01Game (Node) — x01_game.gd
├── ScoringModifierManager (Node) — scoring_modifier_manager.gd
└── HUD (CanvasLayer) — hud.gd
    ├── ScoreLabel (Label)
    ├── TotalScoreLabel (Label)
    ├── ThrowAgainButton (Button)
    ├── ClearButton (Button)
    ├── InstructionLabel (Label)
    ├── UpgradeContainer (HBoxContainer)
    │   ├── UpgradeButton1 (Button)
    │   ├── UpgradeButton2 (Button)
    │   └── UpgradeButton3 (Button)
    ├── HoverTooltip (Label)
    ├── ModifierTooltip (Label)
    └── ModifierPanel (HBoxContainer)
```

---

## File Descriptions

### `dartboard.gd` — Procedurally drawn dartboard with polar-coordinate scoring.

- Draws all segments using `_draw()` with concentric rings and 20 angular wedges.
- All ring radius thresholds are normalized constants (0.0–1.0), multiplied by `board_radius` at draw/score time.
- Standard dartboard number order: `[20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]`
- `calculate_score(global_hit_position)` converts a pixel position to angle + distance, returns a dictionary with `face_value`, `multiplier`, `total_score`, `ring_name`, `wedge_index`, `segment_color`, `is_bull`.
- Draws effective (modified) wedge values on the board — modified numbers rendered in a distinct color.
- Board hover: segment highlighting and hover detection for inspect mode.
- Ring thresholds: Double Bull 0–0.032, Single Bull 0.032–0.08, Inner Single 0.08–0.48, Triple 0.48–0.53, Outer Single 0.53–0.76, Double 0.76–0.83, Off Board 0.83+.
- All colors are exported and tweakable.

### `throw_mechanic.gd` — Four-stage throw input system.

- `ThrowState` enum: `IDLE, AIMING, POSITIONING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, RESOLVING, DONE`
- **AIMING:** Vertical highlight band follows mouse horizontally. Width = `aim_accuracy * 2`. Click/Space to lock.
- **POSITIONING:** Locked band shrinks via tween to a shorter window based on `vertical_accuracy`. Player moves window with W/S or Up/Down arrows. Enter/Space to lock.
- **VERTICAL_RELEASE:** Bounce marker moves up/down within the locked window via sine wave. Speed based on `vertical_speed`. Click/Space to lock vertical position.
- **HORIZONTAL_RELEASE:** Bounce marker moves left/right within the aim band at the locked Y position. Speed based on `horizontal_speed`. Click/Space to lock horizontal position.
- **RESOLVING:** Brief pause showing the final variance rectangle (vertical consistency height × horizontal consistency width) before dart resolves. Duration controlled by `resolve_preview_duration`.
- **DONE:** Dart resolves — vertical offset from `vertical_consistency`, horizontal offset from `horizontal_consistency`, both using `randf_range`.
- Signals: `throw_completed(hit_position)`, `state_changed(new_state)`.

#### Throw Mechanic Stats (6 stats)

| Stat | Export Var | What It Controls | Throw Stage |
|------|-----------|-----------------|-------------|
| Aim Accuracy | `aim_accuracy` | Width of the horizontal aim band (lower = thinner = more accurate) | Stage 1 — Aim |
| Vertical Accuracy | `vertical_accuracy` | How much the vertical window shrinks (higher = more shrinkage = tighter) | Stage 2 — Window |
| Vertical Speed | `vertical_speed` | Bounce speed of the vertical marker (higher = slower = easier) | Stage 3 — Vertical Release |
| Vertical Consistency | `vertical_consistency` | Size of the vertical variance zone after release (higher = tighter) | Stage 3 — Vertical Release |
| Horizontal Speed | `horizontal_speed` | Bounce speed of the horizontal marker (higher = slower = easier) | Stage 4 — Horizontal Release |
| Horizontal Consistency | `horizontal_consistency` | Size of the horizontal variance zone after release (higher = tighter) | Stage 4 — Horizontal Release |

Stats are on a 1–100 scale (except speeds which are ~1.0–5.0). Base values are set at run start, and stat upgrades add to them. All stats cap at 100 (or 5.0 for speed).

### `x01_game.gd` — Pure game-logic controller for x01 mode.

- No rendering, no signals. Main calls into this after each throw and reads back what happened.
- Tracks: `current_target`, `remaining_score`, `current_turn`, `darts_this_turn`, `current_leg`.
- `start_run()` — initializes first leg at `starting_target` (default 101).
- `process_throw(score_result: Dictionary) -> Dictionary` — returns a response dictionary with what happened (score applied, bust, turn over, leg won, run over, etc.).
- `start_next_leg()` — advances target by 100, resets turn/dart counters.
- Exported: `max_turns` (5), `darts_per_turn` (3), `starting_target` (101), `target_increment` (100).

### `main.gd` — Scene controller and game flow orchestrator.

- Centers dartboard on screen.
- Connects signals between throw mechanic, HUD, X01Game, ScoringModifierManager, and scoring.
- `_on_throw_completed()` — the main pipeline: `dartboard.calculate_score()` → `scoring_modifier_manager.process_score()` → `x01_game.process_throw()` → update HUD → place dart.
- Tracks running scores and manages state transitions between legs, turns, upgrades.
- Stat upgrade system: generates 3 randomized stat boosts (rarity-weighted), presents choices via HUD, applies selected upgrade to throw_mechanic.
- Snapshots base stats at run start, restores them on new run.
- Hover state management: feeds mouse position to dartboard for hover feedback during AIMING and between-darts states.

### `hud.gd` — HUD overlay with score display and controls.

- Shows current throw result (ring name, points), remaining score (countdown), dart count, turn count, leg label.
- Instruction text updates per throw stage.
- Bust message display.
- Leg complete message with upgrade choices (3 buttons, rarity-colored).
- Game over / run over display.
- Hover tooltip for board segments (shows effective score, modified indicator).
- Modifier panel (relic bar) — horizontal row of placeholder squares for active scoring modifiers, tinted by rarity, with tooltip on hover.

### `dart_marker.gd` — Visual marker for landed darts.

- Simple drawn circle with outer ring and dark inner center.
- Color and size set by `main.gd` when instantiated.

### `scoring_enums.gd` — Shared enums for the scoring system.

- `class_name ScoringEnums` — globally accessible.
- `SegmentColor { RED, GREEN, BLACK, WHITE }` — the four segment colors on a standard dartboard.
- `ModifierTiming { ON_ACQUIRE, PER_DART }` — when a modifier fires.
- `StreakScope { NONE, WITHIN_TURN, WITHIN_LEG, WITHIN_RUN }` — how long streak history persists.
- `StreakCategory { NONE, WEDGE, COLOR, PARITY }` — slot category for streak modifiers (one-per-category restriction).
- `ConfigType { NONE, PICK_WEDGE, PICK_TWO_WEDGES }` — whether the player must configure the modifier.
- `Rarity { COMMON, UNCOMMON, RARE }` — rarity tier for upgrades and modifiers.

### `scoring_modifier_manager.gd` — Manages the scoring modifier pipeline + checkout solver.

**Modifier pipeline:**

- Owns `effective_wedge_values: Array[int]` — mutable copy of wedge order, modified by ON_ACQUIRE modifiers.
- Owns `effective_wedge_colors: Array[Dictionary]` — segment colors per wedge (single/multi keys).
- Owns `active_modifiers: Array[Resource]` — all acquired modifiers in acquisition order.
- Owns hit history at three granularities: `hit_history_turn`, `hit_history_leg`, `hit_history_run`.
- `process_score(raw_result, is_preview)` — runs the scoring pipeline. Applies effective wedge values, then loops through active PER_DART modifiers calling `apply()`. If `is_preview` is true (for hover tooltips), skips history recording AND skips streak state mutation.
- `speculative_score(raw_result)` — third mode introduced for the checkout solver: mutates streak state (so dart-2's simulation can see dart-1's effects) but does NOT append to hit history.
- `snapshot_all_streak_state()` / `restore_all_streak_state(snapshots)` — save and restore the live streak state on every active modifier. Used by the solver to wrap each candidate dart's speculative simulation.
- `add_modifier(modifier, config) -> Resource` — registers a modifier, applies ON_ACQUIRE effects, records to active list. Enforces one-per-category streak slot restriction (returns replaced modifier if applicable).
- History reset methods: `reset_for_turn()`, `reset_for_leg()`, `reset_for_run()`.
- `get_effective_value()` / `get_effective_color()` for display and hover.
- Debug: `debug_modifiers` export array for dragging in test modifiers via inspector.
- Modification tracking: `_track_modification()` records what each modifier changed for tooltip display.

**Checkout solver (added 2026-05-22):**

- `solve_checkout(remaining, darts_left) -> Array[Array]` — public entry. Returns up to N path candidates (default 5, exported via `max_displayed_paths`), each a list of `{target, result}` steps. Caller is `_update_checkout_helper()` in `main.gd`.
- `_solve_recursive(remaining, darts_left, cache)` — depth-N tree search across the 83 candidate targets. Internal cache keyed by `(remaining, darts_left, streak_state_hash)` dedupes sub-problems within a single call.
- `_solve_first(remaining, darts_left, cache) -> bool` — early-termination existence variant. Used by `compute_preferred_remainders` which only cares whether a checkout exists, not what it looks like.
- `_solver_candidates` cached at modifier-state changes — 83 candidate targets (40 singles, 20 doubles, 20 triples, 2 bulls, 1 deliberate-non-scoring).
- `get_setup_recommendation(remaining)` — returns a single-dart setup target when `solve_checkout` finds no path. Two-tier lexicographic ranking: Tier 0 = lands at a 1-dart-finishable remainder next turn (best); Tier 1 = lands at a 3-dart-checkoutable remainder (fallback). Tiebreak by (next-turn finishing target fatness, this-throw fatness, higher new_remaining). Off-board fallback when nothing reasonable is reachable.
- `_one_dart_finishable: Dictionary` — cached map `{remainder → fatness_of_best_finishing_double}`. Computed cheaply by running 22 doubles through the preview pipeline. Source of truth for the Tier 0 check above.
- `_preferred_remainders: Array[int]` — cached set of remainders that have at least one 3-dart checkout under the current modifier state. Computed via 179 iterations of `_solve_first` sharing one cache across all iterations (this shared cache is the key perf optimization — naive approach was 5s pinwheel).
- `invalidate_preferred_remainders()` — marks both caches dirty; called on every modifier-state change.
- `calculate_checkout_segments(remaining)` — legacy single-dart finder, kept for the existing board double-highlight overlay (separate concern from the helper's text display).

### `scoring_modifier.gd` — Base Resource class for all scoring modifiers.

- `class_name ScoringModifier extends Resource`
- Exports: `modifier_name`, `description`, `timing`, `streak_scope`, `streak_category`, `config_type`, `rarity_tier`. Derived getters expose `rarity` (display name) and `rarity_color` from the rarity tier.
- Runtime state: `enabled: bool` (true by default; toggled off when the player clicks an unlocked modifier) and `toggleable: bool` (rolled at generation via `roll_toggleable()`).
- Virtual method `apply(result, context) -> Dictionary` — override in subclasses.
- Virtual methods `get_streak_count()` and `get_streak_display()` for streak modifier tooltip integration.
- Virtual methods `save_streak_state()` / `restore_streak_state_from(snapshot)` — overridden by streak subclasses to support speculative simulation by the checkout solver. Non-streak modifiers return empty dicts and are no-ops.
- Helper `_track_modification()` for recording changes to the result.
- Lock/unlock system: `UNLOCK_CHANCE: int = 35` (constant). `roll_toggleable()` rolls a d100 against this — 35% land toggleable, 65% locked. Called from each subclass's `generate()` after rarity is set.

### Modifier Subclasses (in `res://scripts/modifiers/`)

- **`wedge_value_modifier.gd`** (`WedgeValueModifier`) — ON_ACQUIRE, PICK_WEDGE config. Adds `bonus_value` to a selected wedge's effective face value.
- **`color_bonus_modifier.gd`** (`ColorBonusModifier`) — PER_DART. Adds `bonus_multiplier` to darts landing on segments of a specific `target_color`.
- **`streak_bonus_modifier.gd`** (`StreakBonusModifier`) — PER_DART, streak_category WEDGE. Awards cumulative +1x per consecutive qualifying hit on the same wedge. Leniency tiers: SAME_RING, ADJACENT_SECTIONS, WHOLE_WEDGE.
- **`color_streak_modifier.gd`** (`ColorStreakModifier`) — PER_DART, streak_category COLOR. Awards cumulative +1x per consecutive same-color hit.
- **`parity_streak_modifier.gd`** (`ParityStreakModifier`) — base resource for parity streak behavior. After the HUD pass (2026-05-21), parity is split into two distinct items: **`even_streak_modifier.gd`** and **`odd_streak_modifier.gd`**, both declaring `streak_category PARITY` and sharing the single parity slot under the standard one-per-category rule. PER_DART. Awards cumulative +1x per consecutive same-parity hit (evens-only or odds-only depending on which item is equipped).
- **`odd_even_bonus_modifier.gd`** (`OddEvenBonusModifier`) — PER_DART. Bonus on odd or even face values.
- **`wedge_swap_modifier.gd`** (`WedgeSwapModifier`) — ON_ACQUIRE, PICK_TWO_WEDGES config. Swaps two wedges' positions on the board.
- **`color_flip_modifier.gd`** (`ColorFlipModifier`) — ON_ACQUIRE. Flips segment colors.

### ThrowModifier system (separate from ScoringModifier)

`ThrowModifier` is a parallel system to `ScoringModifier`. Where ScoringModifiers transform *scores*, ThrowModifiers transform *throw stats* (range, speed, accuracy) on a per-throw conditional basis. They live on dart components — when a component is equipped, its ThrowModifier (if any) is evaluated each throw against a game-state context (remaining score, current turn, current leg, darts this turn, etc.). Examples: "Nervous Sweater" gives +5 accuracy while score is above 50; "Ice Veins" gives +10 accuracy when checkout is possible. See `ThrowModifierGuide.txt` for full implementation spec.

---

## Dart Customization System

*Status: implemented (Phase 5 was described as planned in earlier docs but the balance system, `dart_build.gd`, and `assembly_screen.gd` exist).*

### Overview

Three customizable dart components — barrel, shaft, flight — each with stat bonuses and a weight value. The point was dropped from the customization system as it's the least interesting both visually and in real dart customization. Components are assembled Mario Kart-style on a horizontal assembly screen with a gradient balance bar at the bottom.

### DartComponent Resource

A single `DartComponent` Resource class covers all three types (no subclasses needed). The "type" is implicit based on which slot it's equipped in. Optional `ComponentType` enum (`BARREL, SHAFT, FLIGHT`) can be added for shop/slot enforcement.

Key properties per component:
- `component_name: String`
- `description: String`
- `weight: float` — range -1.0 to 1.0. Negative = front-heavy, positive = back-heavy.
- `rarity: ScoringEnums.Rarity`
- Six stat bonus floats: `h_range_bonus`, `v_range_bonus`, `h_speed_bonus`, `v_speed_bonus`, `h_accuracy_bonus`, `v_accuracy_bonus` (all default 0.0, only non-zero values shown in tooltips).
- Optional `throw_modifier: ThrowModifier` — conditional ability evaluated each throw.

### Balance System

- `balance_value = barrel.weight + shaft.weight + flight.weight`
- Thresholds check `abs(balance_value)`:
  - **Green (0.0 – 0.3):** Bonus to all stats. Balanced dart flies true.
  - **Orange (0.3 – 0.6):** Neutral, no effect.
  - **Red (0.6+):** Penalties start scaling. Accuracy skew introduced.
- **Transition sub-zones (HUD polish, 2026-05-21):** between the three named zones, two soft transition bands apply mild gameplay effects — a slight stat boost just inside the green→orange edge, and a slight accuracy skew just inside the orange→red edge. Magnitudes started at ~10–20% of the corresponding full-zone effect and are tuned via exported vars. The visual bar is rendered as a smooth color gradient even though the three named zones still drive the dominant gameplay states.
- Balance affects accuracy specifically (thematically clean — a balanced dart flies straighter). Components give range/speed/accuracy, balance is a separate accuracy modifier on top.
- Imbalanced builds should sometimes be the right choice — a rare barrel with extreme stats that pushes into orange/red can be worth the penalty if the raw stats are good enough. "Your dart parts determine your ceiling, your balance determines how cleanly you can actually deliver."
- Balance thresholds and bonus values are all exported vars on `DartBuild` for inspector tuning.

### DartBuild Manager

- Node that holds references to three equipped components.
- Computes `balance_value` and determines threshold zone.
- Applies stat modifications + accuracy skew to `throw_mechanic` before a run starts.
- Player starts with the same base stats every run; components add/subtract from there.
- Future: throwing form/stance selection would affect starting stats before components are applied.

### Assembly Screen (Visual Design)

- HBoxContainer with three TextureRect children (barrel, shaft, flight) with separation = -2 to -5 for seamless visual connection.
- Gradient balance bar at the bottom: left = red/warm (front-heavy), center = green (balanced), right = blue/cool (back-heavy). Needle/marker shows current balance value, slides in real time as parts are swapped.
- Part art: each type has consistent canvas height, variable width. Connection edges mate cleanly at fixed Y positions. Barrels are cropped tight to art width so HBox auto-adjusts positioning.

### Art Pipeline (Procreate)

- Fixed canvas height per part type (all barrels same height, all shafts same height, all flights same height), variable width.
- Center axis guide — all parts align to this.
- Consistent connection edges between part types (barrel right edge mates with shaft left edge, shaft right edge mates with flight left edge).
- Export as PNG with transparency, trim left/right whitespace to art bounds, keep full vertical canvas height.

### Starting Component Pool (Design Draft)

**Barrels (primary: range, primary balance driver):**
- Standard Grip — modest range bonuses both axes, mild weight. Safe pick.
- Tungsten Heavy — big h_range bonus, low v_range, very front-heavy (-0.6 to -0.8). High ceiling if balanced.
- Slim Profile — good v_range, modest h_range, slight weight (-0.1 to -0.2). Easy to balance, lower total stats.

**Shafts (primary: speed, secondary balance):**
- Medium Aluminum — neutral speed both axes, small balance offset (+0.2 to +0.3).
- Long Carbon — better v_speed, worse h_speed, larger backward balance offset (+0.4 to +0.6). Pairs well with heavy barrels.

**Flights (primary: accuracy, minor balance):**
- Standard Fin — even accuracy both axes, tiny balance effect (+0.05 to +0.1). ThrowModifier: Nervous Sweater.
- Wide Sail — big v_accuracy, less h_accuracy, slight backward balance offset (+0.1 to +0.15). ThrowModifier: Ice Veins.

### Stat Philosophy: Weight ↔ Stat Correlation

Heavier parts tend to have better horizontal stats (more mass = more resistant to lateral drift). Lighter parts tend to have better vertical stats (dart floats truer, less susceptible to gravity effects). This gives every part natural personality without arbitrary stat blocks.

### Component Acquisition

Parts appear in the shop at a voucher-like rate (less frequent than regular upgrades). Player decides whether to slot them in, considering balance tradeoffs.

---

## Stat Upgrade System (IMPLEMENTED)

Between legs, the player picks one of three randomized stat upgrades. Each upgrade boosts one of the six throw stats.

- Upgrades are rarity-weighted: Common (60%), Uncommon (30%), Rare (10%).
- Common: +5 to +10. Uncommon: +8 to +15. Rare: +12 to +20.
- The specific boost value is rolled per upgrade and shown to the player (e.g., "Uncommon — Aim Accuracy +11").
- Upgrade buttons show rarity name, stat name, and boost value, tinted by rarity color.
- Stats cap at 100 (or 5.0 for speed stats — speed uses a separate internal scaling formula).
- After picking an upgrade, the "Next Leg" button appears.
- Base stats are snapshotted at run start and restored on new run.
- Duplicates within a single set of 3 are allowed.
- Logic lives in `main.gd` currently; will migrate to a dedicated manager when items get complex.
- **On shop legs (every third leg), this pick is replaced by the shop round** — see below. On non-shop legs the 2-of-3 (or 3-of-3 — TODO confirm against current code) pick continues unchanged.

---

## Shop System (IMPLEMENTED 2026-05-21)

*Spec: `specs/2026-05-21-shop-system.md`. Implementation lives across `main.gd` (state machine + lit-spot generation, gated on `_in_shop` and `_leg_phase`), `dartboard.gd` (lit-spot drawing + `check_shop_hit`), `hud.gd` (shop hover tooltip), `modifier_registry.gd` (rarity-weighted item pool draw), and `x01_game.gd` (saved-darts accumulator). The swirly fill effect is `shaders/shop_spot.gdshader`.*

### Cadence

Every third leg, the post-leg upgrade pick is replaced by a shop round. The shop is not itself a leg — it does not consume a leg slot or advance run scaling. It's a screen between leg-end and leg-start. On non-shop legs, the regular per-leg upgrade pick continues unchanged. Tunable via `shop_cadence` (default 3).

### Spare-Dart Math

Each leg has a finite dart budget: `total_darts_in_leg = max_turns * darts_per_turn` (currently 5 × 3 = 15). Each throw increments `used_darts`. On a bust, the remaining darts in the busted turn are counted as used (busting on dart 1 of a turn burns the full 3-dart turn). On leg win, `saved_darts = total_darts_in_leg - used_darts`.

`shop_darts` is the sum of saved darts across the three legs preceding the shop. The accumulator resets to 0 once the shop concludes.

### Board Setup

- `lit_spots = shop_darts + 3` (flat +3 slack via `shop_spot_slack` export). The slack gives the player meaningful choice in *which* targets to prioritize.
- Rarity distribution within lit spots:
  - `rares = max(1, floor(lit_spots / 6))` — at least one rare guaranteed.
  - `uncommons = floor(lit_spots / 3)`.
  - `commons` fill the rest.
- Placement: commons fill the larger single regions of wedges; uncommons and rares fill the smaller double and triple rings. Within those constraints, placement is random.

### Throw Resolution

When a dart hits a lit spot, two items of that rarity tier are rolled and shown to the player. The player picks one; the other is discarded. The spot deactivates for the rest of the shop. Existing slot-conflict rules (streak categories) apply — same logic as the leg-end pick.

The shop draws from the same item pool the per-leg picks use, weighted by rarity tier. Stat upgrades and scoring modifiers can both appear.

Missing a lit spot does nothing. If the player whiffs every dart, they get nothing — no consolation. The spare-dart system already rewards play quality; softening misses would dilute that.

The shop does not score throws. No scoring modifiers apply, no streak counters update.

### Visuals

Lit spots are filled with a Balatro-style swirly animated shader (`shop_spot.gdshader`), tinted by rarity:

- **Common:** white / light grey.
- **Uncommon:** blue.
- **Rare:** purple.

### Zero-Dart Shop

If the player saved zero darts across the three preceding legs (`shop_darts == 0`), the shop screen still appears. The board has no lit spots. A brief "oh dear, you didn't save ANY darts" acknowledgment plays (duration tunable via `shop_zero_dart_duration`), then the shop closes and the next leg begins. The point is to make the consequence of poor play visible.

### Emergent Strategy

Three interacting systems the player calculates on every shop throw: (1) the **board RNG read** — what's lit, where, what shape are the clusters; (2) **skill/confidence** — can I hit that triple under pressure; (3) **stat-driven hit probability** — do my dart parts give me the precision to back the read. Because doubles and triples are physically adjacent to their corresponding singles, missing a hard rare often clips into a related common spot — a natural geometric near-miss reward, not a designed-in consolation mechanic.

This three-interaction trinity is a load-bearing design principle for the project. Future reward-delivery systems should preserve it.

### Open: Run-End Interaction

If a shop would fire after the final leg of a run, behavior is currently undefined. Resolution depends on whether runs are fixed-length or open-ended — which itself depends on meta-progression scope. See Open Design Questions below.

---

## Checkout Helper (IMPLEMENTED 2026-05-22)

*Spec: `specs/2026-05-22-checkout-helper.md`. Solver lives in `scoring_modifier_manager.gd`, UI in `hud.gd` (right-side panel below stats, plus toggle button and soft hint label). Triggered from `_update_checkout_helper()` in `main.gd`, which runs after every throw and on modifier-state changes.*

### Why it exists

At low modifier counts the player can mentally compute checkout paths from the standard x01 chart. Past about 5 stacked modifiers — especially when streak modifiers mutate state per-dart — the math is effectively impossible to do by hand. The helper closes that gap with a solver-driven text panel.

### Solver behavior

- Recursive simulation across 83 candidate targets per dart (20 inner singles + 20 outer singles + 20 doubles + 20 triples + single bull + double bull + one deliberate-non-scoring candidate).
- Uses the existing scoring pipeline's `speculative_score(...)` mode that mutates streak state per simulated dart, then `snapshot_all_streak_state()` / `restore_all_streak_state(...)` to roll back between candidates.
- Returns up to `max_displayed_paths` (default 5) paths, ranked by (1) fewest darts, (2) fattest reliable segment per step (outer single > inner single > double > single bull > triple > double bull > off-board), (3) fewest deliberate-non-scoring darts as final tiebreak.
- Caches sub-problems by `(remaining, darts_left, streak_state_hash)` within a single solve call.

### Setup recommendation

When `solve_checkout` returns zero paths, the helper switches to setup mode. Setup ranking is **two-tier lexicographic**:

- **Tier 0 (best):** resulting remainder is in `_one_dart_finishable` — next turn checks out in a single dart.
- **Tier 1 (fallback):** resulting remainder is in `_preferred_remainders` — next turn has at least one 3-dart checkout.
- **Otherwise:** skip the candidate.

Within tiers, tiebreaks are (a) fattest next-turn finishing target, (b) fattest this-throw target, (c) higher new_remaining as final stable tiebreak.

If no candidate qualifies anywhere, the helper recommends an off-board throw to preserve the current remaining. Display string: `"Aim off-board → preserves remaining (N)"`.

**Important:** the setup logic explicitly does NOT prefer higher remainders generally — higher remainder = harder next-turn checkout, not easier. The original spec wording got this backwards; the shipped implementation flipped it.

### Display

- Right-side panel under the existing stats readout. Text-based, no new board markup. Existing `calculate_checkout_segments` board double-highlight stays as-is.
- Annotated path format: `Dart 1 → Dart 2 → Dart 3`, each step labeled with score and any streak interaction (e.g., `0 (break Odd ×2) → D5 (10)` or `T20 (Wedge ×2: 90)`).
- Progressive narrowing: after each throw, paths that started with the actual hit stay visible and the committed dart's label turns green; others filter out. Off-script throws trigger a full recompute.
- Toggle button has three states: disabled+greyed (no checkout exists), inactive (checkout exists but hidden), active (helper visible). The player's visibility preference persists across throws.

### Soft toggle hint

When the player has at least one **toggleable** (unlocked) scoring modifier active, the helper appends "Try toggling a modifier to recalculate" below the path list. Intentionally passive — does NOT name a specific modifier ("disable Color Streak…"). Active suggestions were rejected because they feel like the helper is playing for the player; passive nudges preserve agency. Hint suppressed when all active modifiers are locked.

### Performance notes

The naive precompute for `_preferred_remainders` ran 179 separate `solve_checkout` calls with fresh per-iteration caches and produced a 3-5 second pinwheel on first invocation. Shipped fix uses (a) a shared cache across all 179 iterations, and (b) a find-first-path variant of the solver (`_solve_first`) since existence is all that's needed. Drops the cost to ~hundreds of ms in vanilla.

### Deferred from spec

- V2 streak-aware preferred remainder list (project carried-over streak state forward when computing the preferred set). Build only if V1 gives bad advice under `WITHIN_LEG` / `WITHIN_RUN` carry-over.
- Active modifier-toggle suggestions ("disable X to enable T20-T20-Bull"). Intentionally avoided per agency-over-hand-holding design call.
- Dart-accuracy-aware EV ranking. Fattest-segment heuristic handles this implicitly for now.
- Multi-turn setup planning. V1 recommends one dart at a time.
- Helper integration with future rule-modifier category (extra turns, rethrows, etc. — see Open Design Questions).

---

## Locked/Unlocked Modifier Status (IMPLEMENTED 2026-05-22)

*No separate spec — shipped as a contemporaneous follow-on Claude Code pass on the `checkout-helper` branch. Implementation lives in `scoring_modifier.gd` (the constant, the field, and the roll method) and in each modifier subclass's `generate()` (the call site).*

### The rule

Every modifier instance, at generation time, rolls toggleable vs. locked. The roll is a flat d100 against `UNLOCK_CHANCE: int = 35`:

- **~35% toggleable (unlocked).** Player can click the modifier card to disable/re-enable it. Disabled modifiers don't fire in the scoring pipeline.
- **~65% locked.** Always active, no click interaction.

### Design rationale

The 65/35 bias makes **unlocked the rare/precious state**, not the default. Most builds end up predominantly locked — toggling is a niche precision tool, not a default verb of play. This was a deliberate choice over flipping to majority-unlocked.

**Locked carries no compensating buff.** A locked-common is strictly worse than an unlocked-common; an unlocked-rare is strictly better than a locked-rare of the same archetype. **Rarity is the power axis**, not lock status. This puts the interesting decision at the rarity boundary: "do I take this locked-rare or hold out for an unlocked-uncommon?"

**Swappable anytime upgrades are offered.** Locked status applies *while you keep the modifier* — you can swap it out at the next shop or post-leg pick. Commits are leg-scale, not run-scale. Long enough to feel like a real choice, short enough to not feel punishing.

### How it interacts with the checkout helper

The "Try toggling a modifier to recalculate" hint in the checkout helper only appears when at least one active modifier is `toggleable=true`. Locked-only builds correctly don't see the hint. The helper recomputes on any toggle event.

### What didn't ship (deferred)

- **Modifier Switchboard shop item.** Earlier design conversation considered making "toggling capability" itself a shop unlock. Currently toggling is universally available (for unlocked modifiers) without needing an unlock item. Could revisit if toggling proves too powerful in playtest.
- **Streak reset on toggle.** Conceptual cost: toggling off a streak modifier forfeits any accumulated streak count. Currently not implemented — toggling is free of streak penalty. Easy to add later by hooking the modifier's `enabled` setter to call `_reset_streak()`.

---

## Phase Outline

*Note: status markers below may lag reality. Cross-check against actual code state.*

### Phase 1 — Dartboard & Basic Throw — COMPLETE
### Phase 2 — Vertical Window Stage — COMPLETE
### Phase 2.5 — Resolve Preview — COMPLETE
### Phase 3 — X01 Game Mode — COMPLETE
### Phase 3.5 — Stat Upgrades — COMPLETE
### Phase 3.75 — Four-Stage Throw Rework — COMPLETE
### Phase 4a — Scoring Modifier Infrastructure — COMPLETE
### Phase 4b — Enum Refactor + Hover/Inspect + Modifier Panel — COMPLETE
### Phase 4c — Streak Slot Restriction + Color/Parity Streaks — COMPLETE (merged 2026-05-21)
### Phase 4d — HUD / Assembly Polish Pass — COMPLETE (merged 2026-05-21). Balance bar gradient + transition sub-zones, score-gold checkout indicator, target tooltip relocated above the crosshair with perk-up hover state, Even/Odd parity streak differentiation.
### Phase 5 — Dart Parts & Assembly Screen — COMPLETE
### Phase 6 — Shop System — COMPLETE (merged 2026-05-21). Run-end interaction with the shop is the remaining open question — see Open Design Questions below.
### Phase 6.5 — Checkout Helper — COMPLETE (shipped 2026-05-22 on `checkout-helper` branch). Solver-driven text panel for valid checkout paths and setup recommendations. Lives in `scoring_modifier_manager.gd` + `hud.gd`.
### Phase 6.6 — Locked/Unlocked Modifier Status — COMPLETE (shipped 2026-05-22 on `checkout-helper` branch). 65/35 lock-rate roll at modifier generation. Toggle interaction in HUD modifier panel.
### Phase 7 — More Modifiers & Items — PLANNED. Includes the **rule-modifier category** (turn-count buffs, rethrows, see-extra-options-at-shop, etc.) as a deferred-but-discussed expansion.
### Phase 8 — Form System — PLANNED
### Phase 9+ — Polish & Beyond — FUTURE

---

## Open Design Questions

1. **Dart count scaling:** Fixed 15 darts per leg forever, or does it change? Could decrease as difficulty climbs. Could be modifier-dependent. Now also affects shop yield, since `shop_darts` is derived from leg dart budgets.
2. **Modifier stacking/conflicts (broader, non-streak):** Can modifiers conflict (e.g., "doubles worth 0" + must finish on a double)? Intended as a design feature (risk/reward) or something to prevent? The streak slot system answered this for streak modifiers (one per category). The lock/toggle system gives the player an out on toggleable conflicts. The broader question — what about *locked* non-streak modifiers that lock the player out of checkout altogether — is still open. The checkout helper makes the failure mode visible (no valid paths surfaced) but doesn't prevent the situation.
3. **Absolute weight:** A potential second weight axis (total dart mass) affecting throw arc or power. Currently only directional balance is tracked.
4. **Distribution type for variance:** Currently uniform `randf_range`. Gaussian would feel more natural (most darts near center, fewer at edges).
5. **Shop run-end interaction:** What happens if a shop would fire after the final leg of a run? Deferred from the shop spec. Depends partly on whether runs are fixed-length or open-ended, which depends on #6.
6. **Meta-progression scope:** What persists across runs? Unlocked parts? Unlocked modifiers? Cosmetics?
7. **Rule-modifier category (new):** Discussed during the checkout helper design pass but explicitly deferred. Items that affect run-structure rather than scoring: +1 turn per leg, get a rethrow each leg, see +1 option at upgrade pick, etc. Likely needs its own slot system distinct from the 6 scoring slots, and the checkout helper will need to learn about these (extra darts affect solver depth, rethrows introduce a new decision point). Pure design space, no implementation yet.

### Resolved since previous refresh

- **Currency system.** No traditional currency. Spare darts saved across legs are the de facto currency and spend at the shop directly by throwing. See Shop System section.
- **Streak modifier conflicts.** Resolved by the one-per-category slot rule (Phase 4c).
- **Player agency vs. helper paternalism.** Resolved by the soft-hint design call in the checkout helper — passive nudges ("try toggling a modifier") instead of active suggestions ("disable Color Streak to enable T20-T20-Bull"). Will inform all future helper-style features.
- **Modifier commitment texture.** Resolved by the lock/unlock system — 65% locked / 35% toggleable, with rarity as the power axis (not lock status). See the Locked/Unlocked Modifier Status section.

---

## Key Design Decisions Already Made

- **Single DartComponent class, not subclasses.** Barrel/shaft/flight are structurally identical; type is determined by which slot they're in.
- **Player starts with same base stats every run.** Components and upgrades add/subtract from there. Form (future) would modify starting stats.
- **Scoring modifier system is separate from stat upgrade system.** Stat upgrades mutate throw_mechanic properties directly. Scoring modifiers run a pipeline per dart through ScoringModifierManager. They share UI space (both are "upgrades" the player picks) but backends are completely independent.
- **X01 game logic is pure and encapsulated.** `x01_game.gd` receives already-modified scores and doesn't know about modifiers.
- **Balance affects accuracy specifically.** Thematically clean — a balanced dart flies straighter. Components determine ceiling, balance determines delivery quality.
- **Three balance zones (green/orange/red)** rather than a continuous curve. Simple for players to understand and tune.
- **Board renders effective values.** If a wedge is modified, the number on the board changes. The player should never have to remember invisible modifications.
- **Hover/inspect active during AIMING and between darts.** Not during POSITIONING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, or RESOLVING — player needs to focus during active throw phases.
- **Streak modifiers are one-per-category.** Three slot categories (WEDGE, COLOR, PARITY). Picking a new streak modifier in a category the player already has triggers replacement, shown on the pick card. The PARITY category contains two distinct items (Even Streak / Odd Streak) that compete for the single slot.
- **Spare darts are the shop currency.** No coins, no points-to-spend. Saving darts in a leg (finishing efficiently) directly translates to shop throwing power. Skill expressed in regular play = leverage in the shop.
- **Three calculating interactions on every throw.** Board RNG read + skill/confidence + stat-driven hit probability. The shop's geometric placement rules deliberately invoke all three; future reward-delivery systems should preserve this trinity rather than collapse it.
- **The board's checkout-highlight function is the single source of truth for "can win."** The HUD score-gold indicator and the board's gold checkout highlights both read from the same function. They must never disagree.
- **The checkout helper is solver-driven, not lookup-based.** Modifiers (especially streak modifiers that mutate state per dart) break the static x01 checkout chart. The helper runs the actual scoring pipeline in simulation per candidate dart, with speculative streak-state mutation + restore between candidates. Caches sub-problems within each solve.
- **Setup recommendations rank by 1-dart-finishable next-turn first, not by "highest remaining."** Higher new_remaining is the wrong direction (harder next-turn checkout). Tier 0: lands at a 1-dart finish. Tier 1: lands at any 3-dart-checkoutable remainder. Within tiers, prefer fattest next-turn finishing target.
- **Soft hints over active suggestions.** "Try toggling a modifier" instead of "disable Color Streak to enable T20-T20-Bull." Active suggestions feel like the helper is playing for the player; passive nudges teach the verb without commandeering the decision. Applies to all future helper-style features.
- **Locked/unlocked is a 65/35 generation roll with no compensating buff for locked.** Rarity is the power axis, not lock status. Locked is a *constraint* (can't toggle off) at the same statline as unlocked. The interesting decision lives at the rarity boundary (locked-rare vs unlocked-uncommon), not within a single rarity.
- **Modifier commits are leg-scale, not run-scale.** Locked items can be swapped at the next shop or post-leg pick. Long enough for commits to feel real; short enough to not feel punishing.
