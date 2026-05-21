# Dart Roguelike — Design Notes

*Canonical design doc. Last seeded from Claude.ai project memory on 2026-05-21.*

*This document supersedes `ProjectOverview.txt`. When major design decisions happen, refresh this doc — either by hand or by asking Claude.ai for an updated writeup of its project memory.*

---

## Status snapshot (as of 2026-05-21, beyond what this doc describes below)

- The streak slot restriction system + Color Streak + Parity Streak modifiers have been implemented (uncommitted on branch `streak-item-system`). See `specs/` for the archived spec once it lands.
- Phase 5 (Dart Parts & Assembly Screen) is *not* still planned — `dart_build.gd`, `assembly_screen.gd`, and the balance system (green/orange/red zones with accuracy skew) exist in the codebase. The "PLANNED" status below is outdated.
- The "Phase Outline" further down lags reality; the design philosophy and architecture rules are still accurate.

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
- Between legs, the player picks one of three stat upgrades (randomized, rarity-weighted).
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

### `scoring_modifier_manager.gd` — Manages the scoring modifier pipeline.

- Owns `effective_wedge_values: Array[int]` — mutable copy of wedge order, modified by ON_ACQUIRE modifiers.
- Owns `effective_wedge_colors: Array[Dictionary]` — segment colors per wedge (single/multi keys).
- Owns `active_modifiers: Array[Resource]` — all acquired modifiers in acquisition order.
- Owns hit history at three granularities: `hit_history_turn`, `hit_history_leg`, `hit_history_run`.
- `process_score(raw_result, is_preview)` — runs the scoring pipeline. Applies effective wedge values, then loops through active PER_DART modifiers calling `apply()`. If `is_preview` is true (for hover tooltips), skips history recording.
- `add_modifier(modifier, config) -> Resource` — registers a modifier, applies ON_ACQUIRE effects, records to active list. Enforces one-per-category streak slot restriction (returns replaced modifier if applicable).
- History reset methods: `reset_for_turn()`, `reset_for_leg()`, `reset_for_run()`.
- `get_effective_value()` / `get_effective_color()` for display and hover.
- Debug: `debug_modifiers` export array for dragging in test modifiers via inspector.
- Modification tracking: `_track_modification()` records what each modifier changed for tooltip display.

### `scoring_modifier.gd` — Base Resource class for all scoring modifiers.

- `class_name ScoringModifier extends Resource`
- Exports: `modifier_name`, `description`, `timing`, `streak_scope`, `streak_category`, `config_type`, `rarity`, `rarity_color`.
- Virtual method `apply(result, context) -> Dictionary` — override in subclasses.
- Virtual methods `get_streak_count()` and `get_streak_display()` for streak modifier tooltip integration.
- Helper `_track_modification()` for recording changes to the result.

### Modifier Subclasses (in `res://scripts/modifiers/`)

- **`wedge_value_modifier.gd`** (`WedgeValueModifier`) — ON_ACQUIRE, PICK_WEDGE config. Adds `bonus_value` to a selected wedge's effective face value.
- **`color_bonus_modifier.gd`** (`ColorBonusModifier`) — PER_DART. Adds `bonus_multiplier` to darts landing on segments of a specific `target_color`.
- **`streak_bonus_modifier.gd`** (`StreakBonusModifier`) — PER_DART, streak_category WEDGE. Awards cumulative +1x per consecutive qualifying hit on the same wedge. Leniency tiers: SAME_RING, ADJACENT_SECTIONS, WHOLE_WEDGE.
- **`color_streak_modifier.gd`** (`ColorStreakModifier`) — PER_DART, streak_category COLOR. Awards cumulative +1x per consecutive same-color hit.
- **`parity_streak_modifier.gd`** (`ParityStreakModifier`) — PER_DART, streak_category PARITY. Awards cumulative +1x per consecutive same-parity (odd/even) hit.
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
### Phase 4c — Streak Slot Restriction + Color/Parity Streaks — COMPLETE (uncommitted on `streak-item-system` branch as of 2026-05-21)
### Phase 5 — Dart Parts & Assembly Screen — COMPLETE (was marked planned in earlier doc; verify on next pass)
### Phase 6 — Shop & Run Structure — PLANNED
### Phase 7 — More Modifiers & Items — PLANNED
### Phase 8 — Form System — PLANNED
### Phase 9+ — Polish & Beyond — FUTURE

---

## Open Design Questions

1. **Dart count scaling:** Fixed 15 darts per leg forever, or does it change? Could decrease as difficulty climbs. Could be modifier-dependent.
2. **Modifier stacking/conflicts:** Can modifiers conflict (e.g., "doubles worth 0" + must finish on a double)? Intended as a design feature (risk/reward) or something to prevent?
3. **Absolute weight:** A potential second weight axis (total dart mass) affecting throw arc or power. Currently only directional balance is tracked.
4. **Distribution type for variance:** Currently uniform `randf_range`. Gaussian would feel more natural (most darts near center, fewer at edges).
5. **Currency system:** What do you earn? Points scored? Legs cleared? Both? How does shop pricing work?
6. **Meta-progression scope:** What persists across runs? Unlocked parts? Unlocked modifiers? Cosmetics?

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
- **Streak modifiers are one-per-category.** Three slot categories (WEDGE, COLOR, PARITY). Picking a new streak modifier in a category the player already has triggers replacement, shown on the pick card.
