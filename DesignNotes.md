# Dart Roguelike — Design Notes

*Canonical design doc. Last refreshed 2026-05-31 after the Color Brushes + Per-Ring Color pass shipped.*

*This document supersedes `ProjectOverview.txt`. When major design decisions happen, refresh this doc — either by hand or by asking Claude.ai for an updated writeup of its project memory.*

---

## Status snapshot

**Shipped 2026-06-01 (Boss Redesign — Reactive Counters + Mutating Variants):**

- **Boss roster reworked toward reactive, build-countering effects** (`specs/2026-06-01-boss-redesign-reactive-counters.md`). Playtest found most bosses were flat global taxes that didn't respond to the player. Established a design principle — every boss is either a **build-counter** (reactive, targets a dominant strategy) or **environmental** (a board condition to play around) — and prefer the former. Added a new per-hit boss hook `Boss.on_dart_landed()` (forwarded by `BossManager`, called from `main.gd` after a dart scores) that reactive bosses use. **Prism** now does nothing at leg start; each hit recolors the landed segment(s) to a random color (always *different* from the current one) that persists for the leg, with splash escalating by tier — `wedge` (whole hit wedge) / `wedge_neighbors` (hit wedge + the hit ring on both neighbor wedges) / `three_wedges` (hit wedge and both neighbors fully), the recolor radiating outward from the hit ring — and the checkout helper is suppressed while Prism is active. (Splash was hand-tuned *up* from the spec's gentler ring / adjacent-ring / wedge scheme during playtest; `prism_hard` added.) **Weak Board** replaces Recession (new `weak_board_*` ids/`.tres`, `WeakBoardBoss` reusing Recession's reduction plumbing): each hit permanently wears down that wedge's value, stacking, value-only, with a floor that never reaches 0 — counters value-stacking. **Void** keeps whole-wedge voiding (counts now 6/10/14) but medium/hard **drift** rings outward to adjacent non-void wedges — drift is a per-whole-void-wedge random range (`drift_min`/`drift_max`: easy 0/0, medium 1–2, hard 2–3), with a `max_void_run` cap keeping the voids spread so drifted rings have visible non-void gaps to migrate into (new per-ring void infrastructure in `dartboard.gd`: `_boss_void_rings` checked in `calculate_score`, rendered per-ring, migration fades in after the initial void). **The Drunkard** is a new boss attacking the throw mechanic (`throw_mechanic.gd`): a learnable zigzag warp on the release meter path plus an enforced minimum meter length scaled by `(100 − range)`, clawing back hardest from maxed-accuracy builds.
- **one_dart and two_darts cut** — "just take away X darts" is a flat resource tax that fails the design test. Removed from all level pools; **archived in place** (`two_darts_boss.gd` marked `## DEPRECATED — archived for reuse`, backs both `.tres`) rather than deleted to avoid breaking `.tres`/uid refs. The "−1 dart" idea survives only as a possible future reward-tradeoff (Glass Cannon pattern), never again as a boss.
- **Rendering & feel follow-up, same day** (`specs/2026-06-01-boss-redesign-rendering-feel-followup.md`). Playtest follow-up that turned out to be mostly already-done: the spec's premise (missing `dartboard.gd` setters, unapplied `double_ring_width_scale`) didn't hold against the shipped code, so items 1 & 3 needed no work (Narrow Double already tweens + matches hit detection). Two genuine gaps landed: **Void now does a real two-phase migration** — `void_boss.gd` hands drift moves to `dartboard.play_void_turn()`, which sequences phase 1 (whole wedges fade in, `void_fill_duration`) then phase 2 (drifted rings slide source→neighbor, `void_drift_duration`) — replacing the earlier single fade; and **the Drunkard's perpendicular wander is now folded into the landing** (`throw_mechanic.gd::_drunk_landing_perp_y`), so the dart lands on the squiggle the marker rode, not the straight line under it. Prism's different-color recolor (never green→green) was done by hand in the design session.
- **Deferred:** full pool re-curation (tier-consistent pools, distinct names/surfaced tiers, dedup on draw, slotting orphaned hard variants `void_hard`/`rotation_hard`/`narrow_double_hard`/`prism_hard`/`weak_board_hard`/`drunkard_hard`) — waits for the parked **map system** (Slay-the-Spire-style, would raise boss frequency and demote weak effects to node mini-encounters). Objective bosses parked. Polish deferred: Weak Board wear/scuff shader, Prism recolor animation. **Active roster hand-curated post-spec down to four families — Void, Prism, Weak Board, Drunkard.** Rotation and Narrow Double still exist as `.tres` but were pulled from *every* level pool (benched alongside the unused hard variants), pending the map. Final pools (Weak Board tuning `reduction_percent`/`floor_fraction` = .1/.4, .15/.3, .22/.2 by tier): **501** — void/prism/weak_board/drunkard, all easy, 1 boss; **1001** — those four easy plus void/prism/weak_board medium (drunkard medium only), 2 bosses; **1501** — all-medium void/prism/weak_board/drunkard, 3 bosses.

**Shipped 2026-05-31 (Color Brushes + Per-Ring Board Color):**

- **Per-ring board color + paintable board** (`specs/2026-05-30-color-brushes-per-ring-color.md`). The board color model expanded from two colors per wedge (`single`/`multi`) to **four, one per ring** (`inner_single` / `triple` / `outer_single` / `double`) — the engine can now represent e.g. a white triple 20 on an otherwise black/red wedge. Built to rehabilitate the structurally-weak Red/Green color streaks: those colors only live on the multi rings of a standard board, so they're brutal to chain until late game. The fix turns color into a sculptable build resource. New **`BrushModifier`** ("Brush: Red", "Brush: Green", etc.) **replaces `ColorFlipModifier`** — a consumable BOARD_MUTATION that paints one chosen ring one pre-rolled color (color rolled at generation; player only picks the segment). New **`ConfigType.PICK_SEGMENT`** picker (wedge + `ring_name`, mirrors the PICK_WEDGE flow but highlights a single ring). **Affinity-gated pooling** (Stone-Joker model): a `Brush: <Color>` only appears in the shop if the player owns a `ColorStreak`/`ColorBonus` modifier targeting that color — `main.gd::_sync_brush_affinity()` sets `ModifierRegistry.available_brush_colors`, and an empty set suppresses brushes via a `0.0` weight override. Brush is common-tier only; the affinity gate does all the interesting gating (the rarity-palette idea was dropped). **Prism boss reworked** from a per-turn color *shuffle* to a **leg-scoped pair *inverter*** (red↔green, black↔white at leg start, held all leg, restored at leg end) — a sharper, self-restoring counter to a painted board (inversion is its own inverse, so it preserves brush paint). Recession boss unchanged behaviorally; it now keys its color match off `inner_single` as the wedge's representative single color.

**Shipped 2026-05-29 (late-game perf):**

- **Solver cache correctness + recursive prune** (`specs/2026-05-28-cache-key-hotfix-recursive-prune.md`, preceded by `specs/2026-05-28-late-game-perf-fix.md`). Replaced a broken monotonic `_streak_version` counter with a real per-modifier streak-state hash (`get_streak_state_hash()` → `_streak_state_hash()`) so solver cache keys actually hit, and extended the `_max_single_dart_score × darts_left` upper-bound prune into `_solve_recursive`. Killed the multi-minute `+1 dart` leg-transition freezes at high remainders.

**Shipped 2026-05-27 (Tutorial Revamp):**

- **Mechanics tutorial restructured to DISCOVER → DO → UNDERSTAND** (`specs/2026-05-27-tutorial-revamp.md`). Replaces the original DEMO → GUIDED → FREE structure after playtest revealed throw 1 had too much reading before any doing. New shape: throw 1 is the player throwing cold with freeze-and-explain at each stage (input locked during callouts, meters bouncing visibly during reads); throw 2 is a free uninterrupted throw; throw 3 is an opt-out stats walkthrough with three paired slider demos (V Range + V Speed, H Range + H Speed, V Accuracy + H Accuracy) and the accuracy-zone-breathing teach during the H meter sweep. Stat bars are visible-but-unexplained from throw 1 (exposure-first, explanation-last). Throw 3 auto-continues from throw 2 with a persistent **Skip Stats Walkthrough** button surfaced at the transition. New `TutorialMode { FULL, STATS_ONLY }` enum on `tutorial_controller.gd`; Start Screen's Play Tutorial button now opens a sub-menu chooser (Full Tutorial / Stats Walkthrough Only / Back) so returning players can replay just the stats throw without redoing the mechanics. All tutorial copy lives in an `@export var tutorial_strings: Dictionary` for inspector tuning. Three new `throw_mechanic` hooks added: `set_tutorial_visual_boost(bool)`, `set_tutorial_pulse_target(string)`, `recompute_aim_dimensions()` (for live Range slider updates). Slider behavior: player drags, clicks "Set," and the throw proceeds with the adjusted value — restore-to-base happens on `stop_tutorial` (finish or skip), protecting real-run stats. Rules slideshow, doubles drill, and welcome modal unchanged; ellipse references in `rules_slideshow.gd` deferred to a focused later pass.

**Shipped 2026-05-24 (Flight Modifier Additions):**

- **Two new flight components + reusable ability hooks** (`specs/2026-05-24-flight-modifier-additions.md`). Adds **Momentum Marksman** (throw-time accuracy scaling with the active streak count, but only when aiming at a streak-continuing target) and **Color Connoisseur** (shop-time bias toward color-flavored modifier types). Formalizes two reusable extension points: (1) a second `evaluate_throw_modifiers` pass that runs at aim placement so throw modifiers can read `declared_target` and `active_streak_modifiers` from context — `ThrowModifier.get_active_bonuses()` now accepts an optional context dict so subclasses can compute dynamic bonuses; (2) a new sibling `ShopBias` Resource on `DartComponent` (peer of `throw_modifier`) with a `get_weight_overrides() -> Dictionary` interface that `ModifierRegistry.generate_distinct_at_rarity` multiplies into pool weights at shop generation. New `ScoringModifier.would_continue_streak(target)` virtual lets throw-side code ask streak modifiers whether a candidate target would continue their streak. Streak-stacking shipped as **sum** — flag for revisit if playtest shows it scales too aggressively. The pattern is intentionally extensible: a deferred `ScoringHook` sibling will unlock on-score reactive fliers (retrigger-style) without touching the existing hooks.

**Shipped 2026-05-23 (Dart Component Unlock System):**

- **Dart Component Unlock System** (`DartComponentGuide.md` + `UnlockConditionRecipes.md`, design rationale archived to `specs/2026-05-23-dart-component-unlock-system.md`). Adds progression-locked dart components with player-facing earn conditions. New `id: StringName` field on `DartComponent` (manual slot-prefixed slugs, never changed after release), renames `unlocked` → `default_unlocked`, adds optional `unlock_condition: UnlockCondition`. New `PlayerProgress` autoload owns the player's unlock state and career stats, persisted to `user://progress.tres` — strictly separate from the resource definitions. Seven `UnlockCondition` subclasses (LegWinHit, LegStat, CareerCount, RunConstraint, ShopAcquisition, SlotsFilled, RelicCount) cover the original design list of 15 unlock intents. New `UnlockManager` autoload listens to game events (`leg_won`, `item_acquired`, `shop_opened/closed`, `slots_state_changed`) and grants unlocks. Assembly screen renders locked components as silhouettes with the unlock hint in muted grey. `UnlockNotificationQueue` HUD node shows a toast with the component thumbnail when an unlock fires; queues multiple unlocks from a single event. Registry validator enforces non-empty unique IDs and refuses to start the game if a registered component is locked-without-a-condition. Nine shell `.tres` files staged for filling in later.

**Shipped 2026-05-23 (Modifier Visual Language pass):**

- **Modifier Icon Language, Streak Section, & Color Streak Split** (`specs/2026-05-23-modifier-icons-and-streak-section.md`). Replaced the flat rarity-tinted modifier squares with a category-aware shape language (`scripts/modifier_icon.gd`): circles for color, squares for even, triangles for odd, sectors for wedge. New `StreakSection` in the HUD shows owned streak modifiers as `[Icon] [Name] [(per scope)] : xN` lines, dimmed at idle (x0). Introduced explicit `ModifierKind` enum (RELIC / BOARD_MUTATION) — Wedge Value, Wedge Swap, and Color Flip are now BOARD_MUTATION and don't appear in the modifier panel (the board itself is their receipt). Color Streak split into four per-color variants (Red / Green / Black / White Streak) sharing the COLOR slot; uniform 1/4 weighting. Wedge Streak dropped its leniency axis — always WHOLE_WEDGE; rarity drives scope only; streak section displays the dynamic streaked-wedge value (`20 Wedge Streak` → `5 Wedge Streak` when the player switches). Added `bonus_per_hit` exported var on all three streak types (color/parity default 1, wedge default 2 — grouping is harder).

**Shipped 2026-05-22 (Tutorial pass):**

- **Tutorial & Help System** (`specs/2026-05-22-tutorial-and-help-system.md`). First-time-player onboarding plus persistent help references. New Start Screen ahead of Assembly. A 3-throw sandbox **mechanics tutorial** with freeze-and-explain at the three accuracy zones, progressive stat-bar reveals (bars start hidden, fade in stage-by-stage), and three interactive slider demos (H Range / H Speed / H Accuracy) that let the player drag and watch live. Ghost-dart scatter visualization. A **rules-of-darts slideshow** with side-by-side mini dartboard (custom-drawn `Control` modeled after the assembly screen's zone preview) and one interactive doubles-checkout drill. A **first-run welcome modal** with `user://settings.cfg`-backed persistence. Tutorial uses the player's real stats (default exports on first run, equipped build on Assembly replay), with snapshot/restore around demos. Assembly Tutorial and persistent Stats Reference were scoped out — playtest showed in-context teaching makes them lower priority.

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
├── GhostDartLayer (Node2D) — ghost_dart_layer.gd (tutorial scatter previews + optional always-on)
├── X01Game (Node) — x01_game.gd
├── ScoringModifierManager (Node) — scoring_modifier_manager.gd
├── TutorialController (Node) — tutorial_controller.gd
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
    ├── ModifierPanel (HBoxContainer)
    ├── AssemblyScreen (Control) — assembly_screen.gd
    ├── StartScreen (Control) — start_screen.gd
    ├── WelcomeModal (Control) — welcome_modal.gd
    ├── RulesSlideshow (Control) — rules_slideshow.gd
    └── TutorialCalloutLayer (Control) — tutorial_callout.gd (active callout / slider widgets)
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

### `throw_mechanic.gd` — Three-stage ellipse-based throw input system.

- `ThrowState` enum: `IDLE, AIMING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, RESOLVING, DONE`
- **AIMING:** Aim ellipse follows the cursor. Ellipse size is set by the `horizontal_range` and `vertical_range` stats. The player declares a target wedge by clicking — the segment under the click becomes the *declared target*, and its centroid becomes the "ideal aim point" the rest of the throw is trying to hit.
- **VERTICAL_RELEASE:** Vertical marker bounces up/down across the ellipse. Speed set by `vertical_speed`. Click/Space to lock the vertical release Y.
- **HORIZONTAL_RELEASE:** Horizontal marker bounces left/right along the locked Y. Speed set by `horizontal_speed`. Click/Space to lock the horizontal release X. At this stage the H meter renders colored zone bands (green/orange/red) showing where the locked X would land relative to the declared target's centroid — controllable via `show_h_meter_zone_bands`.
- **RESOLVING:** Brief pause (duration `resolve_preview_duration`) showing the final accuracy/scatter zone. The zone's size = base `horizontal_accuracy` × `vertical_accuracy` × an *accuracy multiplier* derived from the normalized distance between the locked release point and the declared target's centroid. Green zone shrinks the multiplier (tighter scatter — bonus); penalty zone bloats it (wider scatter — penalty). Thresholds: `green_zone_threshold`, `penalty_zone_threshold`. Multipliers: `green_zone_multiplier`, `max_edge_penalty_multiplier`.
- **DONE:** Dart resolves — final position sampled from a 2D Gaussian distribution centered on the locked release, scaled by the accuracy zone × multiplier. Spread tuned via `gaussian_spread`.
- Signals: `throw_completed(hit_position)`, `state_changed(new_state)`, `meter_position_changed(state, normalized_t)`.
- Tutorial hooks (used by `tutorial_controller.gd`): `set_paused(bool)`, `set_scripted_mode(bool)`, `set_input_blocked(bool)`, `set_bounce_t(float)`, `set_horizontal_bounce_t(float)`, `force_lock_aim(pos, target)`, `force_lock_vertical(t)`, `force_lock_horizontal(t)`, `get_zone_boundary_h_positions(locked_y)`, `sample_scatter_points(pos, count, rng_seed)`. Also exposes opt-in always-on visualization via `live_scatter_preview` and `live_scatter_sample_count`.

#### Throw Mechanic Stats (6 stats)

| Stat | Export Var | What It Controls | Throw Stage |
|------|-----------|-----------------|-------------|
| H Range | `horizontal_range` | Half-width of the aim ellipse (higher = tighter ellipse = more precise aim) | Stage 1 — Aim |
| V Range | `vertical_range` | Half-height of the aim ellipse (higher = tighter ellipse) | Stage 1 — Aim |
| V Speed | `vertical_speed` | Bounce speed of the vertical marker (higher = slower = easier to time) | Stage 2 — Vertical Release |
| H Speed | `horizontal_speed` | Bounce speed of the horizontal marker (higher = slower = easier) | Stage 3 — Horizontal Release |
| V Accuracy | `vertical_accuracy` | Base half-height of the final scatter zone (higher = tighter) | Stage 4 — Resolve |
| H Accuracy | `horizontal_accuracy` | Base half-width of the final scatter zone (higher = tighter) | Stage 4 — Resolve |

Range and accuracy stats are on a 1–100 scale (lerped between exported min/max pixel sizes). Speed stats are ~1.0–5.0. Base values are set at run start by `DartBuild.apply_to_throw_mechanic(...)`, and per-leg stat upgrades add to them. All stats cap at 100 (or 5.0 for speed).

**Skill axis on top of stats:** the accuracy multiplier (green/orange/red zones) is independent of stats — a player with weak accuracy stats can still get a green-zone bonus if they time the meters well, and a player with great accuracy stats forgives sloppy meter timing. The two systems compose multiplicatively.

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
- Modifier panel (relic bar) — horizontal row of `ModifierIcon` Controls for active RELIC scoring modifiers (BOARD_MUTATION modifiers don't appear here). Each icon is custom-drawn by category shape with rarity outline and optional category outline. Lock/unlock indicator overlaid as a small label (O = toggleable, X = locked). Tooltip on hover.
- Streak section — runtime status display for owned streak modifiers (added 2026-05-23). One line per streak (max 3, gated by one-per-category slot rule): `[Icon] [Name] (per scope) : xN`. Wedge Streak name interpolates the current streaked-wedge face value from `effective_wedge_values`. Lines dim to `streak_idle_opacity` at x0 and to `streak_disabled_opacity` when an unlocked modifier is toggled off. `update_streak_section(streak_modifiers, effective_wedge_values)` is called from `main.gd` after every throw and on modifier acquire/toggle/reset events.
- Legendary panel — gold-diamond icons for `RuleModifierReward` instances earned from boss defeats (added 2026-05-28). Lives right of the modifier panel; hidden until the first reward is earned, then persists for the run. Each icon is a custom-drawn `LegendaryIcon` Control (45°-rotated square) with a monogram letter (first character of `display_name`) and the gold tint color. `add_legendary(reward)` is called from `main.gd::_on_reward_selected`; `clear_legendary_panel()` runs on new-run reset. Hover tooltip shows `display_name — description`. V1 ships monogram placeholders — proper per-reward iconography deferred.

### `dart_marker.gd` — Visual marker for landed darts.

- Simple drawn circle with outer ring and dark inner center.
- Color and size set by `main.gd` when instantiated.

### `scoring_enums.gd` — Shared enums for the scoring system.

- `class_name ScoringEnums` — globally accessible.
- `SegmentColor { RED, GREEN, BLACK, WHITE }` — the four segment colors on a standard dartboard.
- `ModifierTiming { ON_ACQUIRE, PER_DART }` — when a modifier fires in the scoring pipeline.
- `ModifierKind { RELIC, BOARD_MUTATION }` — whether the modifier persists in the inventory (relic panel) or is a one-time board change with no panel presence. Drives `hud.gd::add_modifier_to_panel()` early-return.
- `IconShape { NONE, COLOR_CIRCLE, EVEN_SQUARE, ODD_TRIANGLE, WEDGE_SECTOR }` — visual category for `ModifierIcon` shape dispatch. Only RELIC modifiers override it.
- `StreakScope { NONE, WITHIN_TURN, WITHIN_LEG, WITHIN_RUN }` — how long streak history persists.
- `StreakCategory { NONE, WEDGE, COLOR, PARITY }` — slot category for streak modifiers (one-per-category restriction).
- `ConfigType { NONE, PICK_WEDGE, PICK_TWO_WEDGES }` — whether the player must configure the modifier.
- `Rarity { COMMON, UNCOMMON, RARE }` — rarity tier for upgrades and modifiers.

### `scoring_modifier_manager.gd` — Manages the scoring modifier pipeline + checkout solver.

**Modifier pipeline:**

- Owns `effective_wedge_values: Array[int]` — mutable copy of wedge order, modified by ON_ACQUIRE modifiers.
- Owns `effective_wedge_colors: Array[Dictionary]` — segment colors per wedge, **four keys per entry, one per ring** (`inner_single` / `triple` / `outer_single` / `double`), since the 2026-05-31 per-ring color pass. Brushes paint a single ring key; `_lookup_segment_color` / `get_effective_color` take a `ring_name`.
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
- `get_setup_recommendation(remaining)` — returns a setup recommendation dict (with `mode`, `target`, `result`, `resulting_remainder`) when `solve_checkout` finds no path. Four-mode priority: endgame setup (1-dart finish next turn), score-reduction (too far from checkout range, O(1) short-circuit), mid-zone setup (3-dart-finishable remainder), off-board preservation (every scoring dart busts). Ranked by `[next_turn_fatness, new_remaining]` within concrete-target modes.
- `_one_dart_finishable: Dictionary` — cached map `{remainder → fatness_of_best_finishing_double}`. Computed cheaply by running 22 doubles through the preview pipeline. Source of truth for the Tier 0 check above.
- `_preferred_remainders: Array[int]` — cached set of remainders that have at least one 3-dart checkout under the current modifier state. Computed via 179 iterations of `_solve_first` sharing one cache across all iterations (this shared cache is the key perf optimization — naive approach was 5s pinwheel).
- `invalidate_preferred_remainders()` — marks both caches dirty; called on every modifier-state change.
- `calculate_checkout_segments(remaining)` — legacy single-dart finder, kept for the existing board double-highlight overlay (separate concern from the helper's text display).

### `scoring_modifier.gd` — Base Resource class for all scoring modifiers.

- `class_name ScoringModifier extends Resource`
- Exports: `modifier_name`, `description`, `timing`, `kind` (RELIC by default), `streak_scope`, `streak_category`, `config_type`, `rarity_tier`. Derived getters expose `rarity` (display name) and `rarity_color` from the rarity tier.
- Runtime state: `enabled: bool` (true by default; toggled off when the player clicks an unlocked modifier) and `toggleable: bool` (rolled at generation via `roll_toggleable()`).
- Virtual method `apply(result, context) -> Dictionary` — override in subclasses.
- Virtual method `get_icon_shape() -> ScoringEnums.IconShape` — returns `NONE` by default. RELIC subclasses override to declare their shape; BOARD_MUTATION subclasses don't override (they never render).
- Virtual methods `get_streak_count()` and `get_streak_display()` for streak modifier tooltip integration.
- Virtual methods `save_streak_state()` / `restore_streak_state_from(snapshot)` — overridden by streak subclasses to support speculative simulation by the checkout solver. Non-streak modifiers return empty dicts and are no-ops.
- Helper `_track_modification()` for recording changes to the result.
- Lock/unlock system: `UNLOCK_CHANCE: int = 35` (constant). `roll_toggleable()` rolls a d100 against this — 35% land toggleable, 65% locked. Called from each subclass's `generate()` after rarity is set.

### `modifier_icon.gd` — Custom-drawn icon Control for RELIC modifiers (added 2026-05-23).

- `class_name ModifierIcon extends Control`. Used by the HUD modifier panel (40px relic squares) and the new streak section (20px inline icons). Same renderer, different sizes — exported via `streak_icon_size` on `hud.gd` for the small variant.
- `_draw()` dispatches on `modifier.get_icon_shape()`. Shape helpers: `_draw_circle()`, `_draw_square()`, `_draw_triangle()`, `_draw_sector()`. All draw inside the Control's `size` minus `draw_inset`.
- Color modifiers: filled with the target SegmentColor. Outline = rarity. One outline.
- Parity modifiers: neutral dark fill. Inner outline = category color (red for even, green for odd). Outer outline = rarity. Two outlines.
- Wedge Streak: neutral dark fill. Outline = rarity. One outline.
- BOARD_MUTATION modifiers (Wedge Value, Wedge Swap, Brush) keep the default `IconShape.NONE` and never render — they have no panel presence.
- Exports for inspector tuning: `rarity_outline_width`, `category_outline_width`, `outline_gap`, `draw_inset`, `neutral_fill_color`, plus per-color overrides for the four SegmentColor fills.
- **Deferred:** if visual identity needs to push past this geometric base, the next pass is hand-drawn art per modifier (not exported font glyphs).

### Modifier Subclasses (in `res://scripts/modifiers/`)

All modifiers declare a `kind` (RELIC or BOARD_MUTATION). RELIC modifiers persist in the modifier panel and contribute to scoring per dart. BOARD_MUTATION modifiers fire once at acquisition, mutate the board, and disappear from the inventory — the board is their visible record.

**RELIC modifiers:**

- **`color_bonus_modifier.gd`** (`ColorBonusModifier`) — PER_DART. Adds `bonus_multiplier` to darts landing on segments of a specific `target_color`. Icon: COLOR_CIRCLE.
- **`streak_bonus_modifier.gd`** (`StreakBonusModifier`, "Wedge Streak") — PER_DART, streak_category WEDGE. Awards `bonus_per_hit × (count - 1)` cumulative multiplier per consecutive same-wedge hit. Always WHOLE_WEDGE matching (any ring on the same numbered wedge counts) — leniency axis was removed 2026-05-23. Rarity drives scope (turn/leg/run) only. Default `bonus_per_hit = 2` because grouping is significantly harder than color/parity streaks. Icon: WEDGE_SECTOR.
- **`color_streak_modifier.gd`** (`ColorStreakModifier`) — PER_DART, streak_category COLOR. Single class with `target_color` rolled at generation: instances appear as Red Streak / Green Streak / Black Streak / White Streak. Awards `bonus_per_hit × (count - 1)` per consecutive hit on the target color. Default `bonus_per_hit = 1`. Pool weight `4` per flavor (so the four together approximate the original combined rate); color is rolled uniformly within the color-streak pool. Icon: COLOR_CIRCLE.
- **`parity_streak_modifier.gd`** (`ParityStreakModifier`) — base resource for parity streak behavior. Split into two distinct items (2026-05-21): **`even_streak_modifier.gd`** and **`odd_streak_modifier.gd`**, both declaring `streak_category PARITY` and sharing the single parity slot under the standard one-per-category rule. PER_DART. Awards `bonus_per_hit × (count - 1)` per consecutive same-parity hit. Default `bonus_per_hit = 1`. Icon: EVEN_SQUARE / ODD_TRIANGLE.
- **`odd_even_bonus_modifier.gd`** (`OddEvenBonusModifier`) — PER_DART. Bonus multiplier on odd OR even face values, picked at generation. Icon: ODD_TRIANGLE or EVEN_SQUARE depending on `target_odd`.

**BOARD_MUTATION modifiers** (no panel presence, no icon):

- **`wedge_value_modifier.gd`** (`WedgeValueModifier`) — ON_ACQUIRE, PICK_WEDGE config. Adds `bonus_value` to a selected wedge's effective face value. The board renders the new number.
- **`wedge_swap_modifier.gd`** (`WedgeSwapModifier`) — ON_ACQUIRE, PICK_TWO_WEDGES config. Swaps two wedges' positions on the board.
- **`brush_modifier.gd`** (`BrushModifier`, "Brush: <Color>") — ON_ACQUIRE, PICK_SEGMENT config. Paints one chosen ring (`wedge_colors[wedge_index][ring_name] = target_color`) one pre-rolled color. Replaced `ColorFlipModifier` (whole-wedge pair flip) on 2026-05-31. Affinity-gated into the pool (see below) — only surfaces for colors the player already has a `ColorStreak`/`ColorBonus` for. Common-tier only.

### ThrowModifier system (separate from ScoringModifier)

`ThrowModifier` is a parallel system to `ScoringModifier`. Where ScoringModifiers transform *scores*, ThrowModifiers transform *throw stats* (range, speed, accuracy) on a per-throw conditional basis. They live on dart components — when a component is equipped, its ThrowModifier (if any) is evaluated each throw against a game-state context (remaining score, current turn, current leg, darts this turn, etc.). Examples: "Nervous Sweater" gives +5 accuracy while score is above 50; "Ice Veins" gives +10 accuracy when checkout is possible. See `ThrowModifierGuide.txt` for full implementation spec.

**Two-pass evaluation (added 2026-05-24).** Throw modifiers evaluate twice per throw — once at throw start (game-state-only context) and once at aim placement when `throw_mechanic` transitions to `VERTICAL_RELEASE`. The second pass overlays target-dependent bonuses on top of the first; its context dictionary additionally contains `declared_target: Dictionary` and `active_streak_modifiers: Array`. `ThrowModifier.get_active_bonuses()` accepts an optional `context: Dictionary = {}` so dynamic subclasses (Momentum Marksman) can compute bonuses from the placed target while static subclasses (Ice Veins, Nervous Sweater) ignore it. The aim-placed visual preview reflects second-pass bonuses automatically because the ghost ellipse recomputes each frame from the current `horizontal_accuracy` / `vertical_accuracy`.

### ShopBias system (added 2026-05-24)

`ShopBias` is a sibling Resource to `ThrowModifier`, attached to `DartComponent` via the optional `shop_bias` field. Where ThrowModifiers fire at throw time, ShopBiases fire at shop generation time. Subclasses override `get_weight_overrides() -> Dictionary` to return a `{ScriptType: float_multiplier}` map that `ModifierRegistry.generate_distinct_at_rarity` multiplies into pool weights inside its weighted-roll loop. `ColorShopBias` (used by the Color Connoisseur flight) maps the color-flavored modifier scripts (`ColorBonus`, `ColorStreak`, and `Brush` since 2026-05-31) to an exported `color_weight_multiplier: float = 2.0`. The pattern is intentionally minimal — a future spot-spawning bias could extend the same base with a new override method, and the same sibling-Resource shape can host future hook types (e.g., the deferred `ScoringHook` for on-score reactive effects).

### Ability Hook Extension Points (canonical pattern, formalized 2026-05-24)

Each lifecycle moment a dart component might fire at gets its own sibling Resource on `DartComponent`. Don't bolt new hooks onto an existing base class; add a peer. Current siblings:

- `throw_modifier: ThrowModifier` — throw-time conditional stat bonus.
- `shop_bias: ShopBias` — shop-generation pool weight bias.
- *(deferred)* `ScoringHook` — would fire inside `ScoringModifierManager.process_score` to unlock retrigger-style fliers and other on-score reactive effects.

The rationale is the same as the scoring-vs-stat-upgrade split (see Architecture Rules): each hook has a different shape and a different lifecycle. Bundling them into one mega-class couples concerns that have nothing to do with each other and makes every new hook a shared-file edit. Sibling Resources let each hook evolve independently and let designers attach only the abilities a component needs.

For throw-time effects that need *aim-time* context (e.g., target-aware accuracy bonuses), use the second-evaluation-pass pattern documented above rather than inventing a new hook. The pattern threads through `main.gd._on_aim_placed` and re-runs `evaluate_throw_modifiers` with extended context. Similarly, for "would this target continue any streak?" queries, use `ScoringModifier.would_continue_streak(target)` — each streak subclass implements its own check, non-streak modifiers default to false.

### Tutorial & Help System scripts (shipped 2026-05-22)

- **`start_screen.gd`** (`StartScreen extends Control`) — Pre-game menu shown ahead of Assembly. Three primary buttons: Start Game, Play Tutorial, Rules of Darts. Also emits `stats_reference_pressed` for the deferred Stats Reference panel.
- **`welcome_modal.gd`** (`WelcomeModal extends Control`) — Soft first-run prompt: "Want a walkthrough?" with Yes/No. Yes routes to the mechanics tutorial; No routes straight to Start Screen. Either choice marks the welcome flag in `SettingsStore` so subsequent launches go straight to Start Screen.
- **`settings_store.gd`** (`SettingsStore extends RefCounted`, static singleton) — Persistent settings backed by `ConfigFile` at `user://settings.cfg`. Currently holds the tutorial-seen flag. Designed to host future settings (audio levels, visual toggles, etc.) under additional sections.
- **`tutorial_controller.gd`** (`TutorialController extends Node`) — Orchestrates the mechanics tutorial. Owns the beat sequence as named functions (`_throw1_place_aim`, `_throw1_show_h_freeze`, `_start_throw_2_guided`, `_start_throw_3_free`, etc.). All captions live in the exported `tutorial_strings: Dictionary`. Phase B added progressive stat-bar reveals and three interactive slider demos (H Range, H Speed, H Accuracy) with snapshot/restore wrappers so player stats stay clean after demos.
- **`tutorial_callout.gd`** (`TutorialCallout extends Control`) — Reusable overlay widget: panel with text, optional anchor arrow, Next button, Skip Tutorial button. Tutorial controller pushes/pops callouts onto the active stack.
- **`tutorial_slider.gd`** (`TutorialSlider extends Control`) — Transient slider widget used during the three interactive demos. Label + HSlider + "Got it" button. Drives a `value_changed` signal; the tutorial controller wires it to the relevant throw_mechanic stat and pairs it with a snapshot/restore on dismissal.
- **`ghost_dart_layer.gd`** (`GhostDartLayer extends Node2D`) — Renders semi-transparent ghost dart markers. Used by the tutorial's accuracy-zone freeze beats to visualize scatter clusters and by the H Accuracy slider demo to show shrink/grow. Sampler lives on `throw_mechanic.gd` (`sample_scatter_points(...)`), supports a fixed `rng_seed` for consistent demo visuals.
- **`rules_slideshow.gd`** (`RulesSlideshow extends Control`) — Modal slideshow walking through wedge layout, scoring, the doubles checkout rule. Side-by-side layout: text/nav on the left, custom-drawn mini dartboard on the right. Mini board uses local arc/polygon helpers (copy of the assembly screen's zone-preview pattern); highlights drawn locally on the mini board only — the main dartboard's highlight system is not touched during the slideshow. Includes one interactive drill at the doubles-checkout slide.

---

## Dart Customization System

*Status: implemented (Phase 5 was described as planned in earlier docs but the balance system, `dart_build.gd`, and `assembly_screen.gd` exist).*

### Overview

Three customizable dart components — barrel, shaft, flight — each with stat bonuses and a weight value. The point was dropped from the customization system as it's the least interesting both visually and in real dart customization. Components are assembled Mario Kart-style on a horizontal assembly screen with a gradient balance bar at the bottom.

### DartComponent Resource

A single `DartComponent` Resource class covers all three types (no subclasses needed). The "type" is implicit based on which slot it's equipped in, with an explicit `component_type: ScoringEnums.ComponentSlot` enum field for slot enforcement.

Key properties per component:
- `id: StringName` — stable identity for save data and unlock tracking. Slot-prefixed snake_case (`&"barrel_torpedo"`). Manual assignment, never changed after release. See `DartComponentGuide.md` for the full ID rules.
- `component_name: String`
- `description: String`
- `weight: float` — range -1.0 to 1.0. Negative = front-heavy, positive = back-heavy.
- `rarity_tier: ScoringEnums.Rarity`
- `default_unlocked: bool` — whether available from the start (true) or earned via `unlock_condition` (false). Most components are true.
- `unlock_condition: UnlockCondition` — optional resource describing the earn condition for locked components. Subclass list and recipes live in `DartComponentGuide.md` § 6 and `UnlockConditionRecipes.md`.
- Six stat bonus floats: `h_range_bonus`, `v_range_bonus`, `h_speed_bonus`, `v_speed_bonus`, `h_accuracy_bonus`, `v_accuracy_bonus` (all default 0.0, only non-zero values shown in tooltips).
- Optional `throw_modifier: ThrowModifier` — conditional ability evaluated each throw.
- Optional `shop_bias: ShopBias` — shop-time pool weight bias (added 2026-05-24). Sibling to `throw_modifier`; evaluated by the shop when generating picks. Leave null for components with no shop influence. See the **Ability Hook Extension Points** section below for the broader pattern.

Player-side unlock state lives in the `PlayerProgress` autoload, never in the resource itself — resources stay canonical, progression is per-save-file. `DartComponentRegistry._validate_components()` enforces ID non-emptiness, ID uniqueness across slots, and that no component is `default_unlocked = false` with a null `unlock_condition` (which would make it permanently unobtainable).

**Flight is the run's archetype-defining slot** (formalized 2026-05-24). Barrel and shaft are stat-tuning slots — players combine many over a run. Flight is build-defining: exactly one equipped via `DartBuild.equipped_flight`, no swap mid-run. Each flight should justify itself as a "this run is about X" choice rather than a stat tweak, and new flights should carry tougher unlock conditions than barrels/shafts since they represent commitment. Defensive-only flight verbs need extra punch to feel worth a whole-run commitment.

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

- HBoxContainer with three TextureRect children (barrel, shaft, flight) with separation = -2 to -5 for seamless visual connection. A purely-decorative point sprite (added 2026-05-23) renders to the left of the barrel for visual completeness — it is **not** a customizable component, the customization system remains three slots (barrel/shaft/flight). Position controlled by exported `point_preview_size`, `point_preview_h_offset`, `point_preview_v_offset` vars on `assembly_screen.gd`.
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

When `solve_checkout` returns zero paths, the helper switches to setup mode. Four modes, evaluated in priority order (first match wins). Each mode carried as a `ScoringEnums.SetupMode` value in the recommendation dict:

1. **Endgame setup** (`ENDGAME_SETUP`): a scoring dart lands at a 1-dart-finishable remainder next turn. Ranked by `[next_turn_fatness, new_remaining]` (lower = better). Concrete target displayed.
2. **Score-reduction** (`SCORE_REDUCTION`): no scoring dart can reach `_preferred_remainders` — player is too far from checkout range. Trigger is O(1): `remaining - _max_single_dart_score > _max_preferred_remainder`. Skips the candidate sweep entirely. Display: "Score more points to enter checkout range" (no target named).
3. **Mid-zone setup** (`MID_ZONE_SETUP`): a scoring dart lands in `_preferred_remainders` (3-dart-finishable) but not at a 1-dart finish. Ranked by `[next_turn_fatness, new_remaining]` — lower remainder = closer to checkout = better. Concrete target displayed.
4. **Off-board preservation** (`OFF_BOARD_PRESERVE`): every scoring dart busts or leaves remainder=1. Display: "Aim off-board — any scoring dart busts".

**Important:** the setup logic explicitly does NOT prefer higher remainders generally — higher remainder = harder next-turn checkout, not easier. `_max_single_dart_score` and `_max_preferred_remainder` are cached alongside `_preferred_remainders` / `_one_dart_finishable` and invalidated by the same `invalidate_preferred_remainders()` call.

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
- Helper integration with the rule-modifier reward category. Rule modifiers themselves shipped 2026-05-26 as boss rewards (Triple Outs, Glass Cannon, Extra Dart, Extra Turn, Streak Slot Extension, Pool Widener, Frequent Shopping, Lucky Eye); the helper acknowledges Triple Outs and Glass Cannon via `allow_triple_checkout` / `glass_cannon_active` gates on the solver, but doesn't yet reason about extra-darts (depth) or rethrows (decision points).

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

## Tutorial & Help System (IMPLEMENTED 2026-05-22)

*Spec: `specs/2026-05-22-tutorial-and-help-system.md`. Implementation lives across `main.gd` (Start Screen routing, first-run gate, sandbox flag), `tutorial_controller.gd` (beat orchestration), `tutorial_callout.gd` and `tutorial_slider.gd` (UI widgets), `ghost_dart_layer.gd` (scatter visualization), `rules_slideshow.gd` (rules walkthrough + mini board + doubles drill), `start_screen.gd`, `welcome_modal.gd`, `settings_store.gd`, plus tutorial hooks added to `throw_mechanic.gd` and `dartboard.gd`, and a `set_stat_bar_visibility(...)` method on `hud.gd`.*

### Why it exists

The game's signature interaction (V meter, H meter, accuracy zone, scatter) is unfamiliar — no other dart game does it this way. Combined with x01 rules (which assume the player knows what "checking out on a double" means) and the build/balance/modifier roguelike layer, a first-time player without explanation is lost in the first thirty seconds. The tutorial system makes the game shippable to friends without sitting next to them.

### Three flows, kept separate

1. **Mechanics Tutorial** — 3-throw sandbox teaching the throw loop.
2. **Rules of Darts** — slideshow + interactive doubles drill teaching x01 scoring.
3. **First-Run Welcome** — soft prompt on first launch routing new players into the mechanics tutorial.

These were deliberately not merged into one walkthrough. Darts vets skip the rules. Returning players replay just mechanics. Mixing them is cognitive overload, and tracking them separately means each can be rebuilt independently if playtest reveals one is unclear.

### Mechanics Tutorial structure

Sandbox mode — no `x01_game` involvement, no score pressure, no leg/turn counters, no modifiers. Player can flub throws without consequences. Uses the player's **real stats**: default `throw_mechanic` exports when entered from Start Screen on first run, equipped build values when entered from Assembly as a replay. The replay-from-Assembly case becomes an emergent "feel my current build" tool for returning players.

**Throw 1 — Autopilot demo with freeze-and-explain.** Tutorial places the aim ellipse for the player, auto-locks vertical, then drives the H meter through three pauses at green / orange / red zone positions. Each pause shows a ghost-dart scatter cluster at that locked candidate position (sampled with a fixed RNG seed so the demonstration stays consistent across runs). Captions walk through what each zone means.

**Throw 2 — Guided attempt.** Normal speed. Banner: "Try to lock the H meter in the green zone." No forced click. Post-throw feedback names the zone they hit without judgment.

**Throw 3 — Free throw.** No prompts. Apply what you learned. End buttons: "Play a real game" → Assembly. "Back to start" → Start Screen.

**Progressive stat-bar reveal woven through Throw 1.** Stat bars start hidden. Range bars fade in when the aim ellipse is shown. V Speed bar appears when the V meter starts. H Speed bar appears when the H meter starts. Accuracy bars appear at the green-zone freeze beat (where scatter is tightest, the visual delta most obvious). Each reveal pairs with a caption explaining the stat's effect.

**Three interactive slider demos.** After the relevant stat reveal, a small slider widget lets the player drag and watch the visual update live. One per stat category (H Range, H Speed, H Accuracy), with explicit "V counterpart works the same way" captions. Demos snapshot the stat value before opening and restore it on dismiss — critical so the player's actual values aren't mutated. The H Speed demo blocks click commits without freezing the meter (via `set_input_blocked`) so the marker keeps bouncing and the player can feel the speed change.

### Rules Slideshow structure

Side-by-side modal layout: text + nav buttons on the left column, custom-drawn mini dartboard on the right column. Mini board is a Control with its own `_draw_board_segment` / `_draw_board_ring` helpers — modeled on `assembly_screen.gd::_build_zone_preview()`. The main dartboard's tutorial-highlight system is *not* used during the slideshow (a Phase B refinement — Phase A initially routed highlights to the main board, but the modal scrim obscured them; the mini board fixes that and isolates state).

Slides cover: board orientation, singles, doubles, triples, bullseye, x01 scoring, the doubles checkout rule, then a single interactive drill ("you have 32 remaining, which dart wins?") with three buttons. The drill picks specifically the doubles checkout rule because it's the most counterintuitive part of x01 for newcomers — passive reading isn't reliable retention; doing it once is.

### First-Run Welcome

`SettingsStore` (static singleton over `ConfigFile` at `user://settings.cfg`) tracks the welcome-seen flag. On launch, `main.gd` checks the flag and either shows the welcome modal (first run) or routes directly to Start Screen. The welcome modal is intentionally soft: "Want a walkthrough?" with Yes/No. Either answer sets the flag. `main.gd` has a `debug_reset_tutorial_seen` export for Max to re-test first-run flow from the inspector.

### Ghost-dart scatter visualization

`throw_mechanic.sample_scatter_points(locked_release_pos, sample_count, rng_seed)` samples N positions from the same gaussian/accuracy-zone math the real throw uses. `ghost_dart_layer.gd` renders them as semi-transparent dart markers. Used by the tutorial at freeze beats and by the H Accuracy slider demo (with a fixed seed so the cluster pattern stays consistent and the player sees shrink/grow rather than "shuffle"). Also exposed as an opt-in always-on preview via `live_scatter_preview: bool` and `live_scatter_sample_count: int` exports — players who want to see their spread during real play can turn it on.

### What didn't ship (deferred)

- **Assembly Tutorial.** A guided walkthrough of the assembly screen itself (cycling components, balance bar, zone preview, Begin Run). Scope is now trimmed because the mechanics tutorial teaches stats in-context, so this becomes a lighter "show me the UI" walkthrough. Future spec.
- **Persistent Stats Reference panel.** A look-it-up-later overlay listing all six stats with longer descriptions. `start_screen.stats_reference_pressed` signal exists but isn't yet handled in `main.gd`. The would-be single-source-of-truth file `scripts/stat_descriptions.gd` was also deferred. Promote to in-flight only if playtest shows in-context teaching alone is insufficient.
- **DartboardGeometry refactor.** The mini-board segment/ring drawing math is the third copy in the codebase (after `dartboard.gd::_draw_segment` and `assembly_screen.gd::_draw_board_segment`). Could be extracted into a shared `class_name DartboardGeometry extends RefCounted` static helper. Small cleanup, not blocking anything.
- **In-game "?" menu.** A contextual help button on the active-game HUD surfacing Stats Reference / Rules of Darts mid-run. Currently those are accessible only from Start Screen and (for rules) Assembly. Could be added later.

### Design decisions captured during the pass

- **Three separate flows, not merged.** Different players need different subsets; cognitive load on a "full" tutorial would be too high.
- **3-throw demo→guided→free.** One throw is "look at this," not "you did this." Three is the sweet spot.
- **Sandbox mode, not first-leg-of-real-game.** No score pressure during learning.
- **Ghost-dart scatter over heatmap shader.** Players don't think in probability density; they think "where will my darts land."
- **Freeze-and-explain at zone transitions, not forced-click prompts.** Show-then-do > railroad clicks.
- **Hybrid slideshow + one drill** for rules of darts. Specifically at the doubles checkout rule — the most counterintuitive piece.
- **Real stats throughout the tutorial.** Tutorial throw 3 must feel identical to throw 1 of the first real leg, or the player feels lied to. Demos snapshot/restore around mutations.
- **Stats taught in context during mechanics tutorial, not as a separate Stats Reference flow.** Realized post-Phase-A playtest: a separated reference is less effective than showing the stat next to the thing it controls.
- **Mini dartboard inside the slideshow modal**, not highlights on the main board. Modal scrim obscures the main board; mini board puts the visual next to the text and isolates state.

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
### Phase 6.7 — Tutorial & Help System — COMPLETE (shipped 2026-05-22). Start Screen, 3-throw sandbox mechanics tutorial with in-context stat reveals and three interactive slider demos, rules slideshow + interactive doubles drill, first-run welcome modal with `user://settings.cfg` persistence, ghost-dart scatter visualization (also exposed as opt-in always-on preview). Spec at `specs/2026-05-22-tutorial-and-help-system.md`. Assembly Tutorial and persistent Stats Reference deferred — playtest showed in-context teaching makes them lower priority.
### Phase 6.8 — Modifier Visual Language & Streak Section — COMPLETE (shipped 2026-05-23). Spec at `specs/2026-05-23-modifier-icons-and-streak-section.md`. `ModifierIcon` shape language for the relic bar and streak section, dedicated runtime streak status strip, Color Streak split into four per-color variants, Wedge Streak simplified (leniency dropped), explicit RELIC vs BOARD_MUTATION classification. Pick-card icons, streak entry animations, broken-streak feedback, and the shared geometry helper refactor deferred.
### Phase 6.9 — Dart Component Unlock System — COMPLETE (shipped 2026-05-23). Design rationale at `specs/2026-05-23-dart-component-unlock-system.md`. Living references: `DartComponentGuide.md` (architecture + how-to-add) and `UnlockConditionRecipes.md` (cookbook for the 15 unlock conditions). Manual `StringName` IDs on `DartComponent`, `PlayerProgress` autoload with persistent `user://progress.tres`, seven `UnlockCondition` subclasses, `UnlockManager` event coordinator, assembly-screen silhouette rendering, queued unlock toast notifications. Nine shell `.tres` files staged for filling in. Per-category caps on non-streak RELIC modifiers (color slot, parity slot, etc.) deferred — `RelicCountCondition` is the coarse stand-in for "lots of items" milestones.
### Phase 7 — More Modifiers & Items — PARTLY SHIPPED. The **rule-modifier category** (turn-count buffs, see-extra-options-at-shop, etc.) shipped 2026-05-26 as the boss-reward channel — 8 rewards delivered through the boss-defeat reward picker (see Boss + Level + Reward System in `specs/2026-05-25-boss-encounters-and-level-select.md`). HUD display for earned rewards landed 2026-05-28 (legendary panel). The original Phase 7 vision of broader scoring-modifier expansion (more streak archetypes, more board mutations) is still PLANNED.
### Phase 8 — Form System — PLANNED
### Phase 9+ — Polish & Beyond — FUTURE

---

## Open Design Questions

1. **Dart count scaling:** Fixed 15 darts per leg forever, or does it change? Could decrease as difficulty climbs. Could be modifier-dependent. Now also affects shop yield, since `shop_darts` is derived from leg dart budgets.
2. **Modifier stacking/conflicts (broader, non-streak):** Can modifiers conflict (e.g., "doubles worth 0" + must finish on a double)? Intended as a design feature (risk/reward) or something to prevent? The streak slot system answered this for streak modifiers (one per category). The lock/toggle system gives the player an out on toggleable conflicts. The broader question — what about *locked* non-streak modifiers that lock the player out of checkout altogether — is still open. The checkout helper makes the failure mode visible (no valid paths surfaced) but doesn't prevent the situation.
3. **Absolute weight:** A potential second weight axis (total dart mass) affecting throw arc or power. Currently only directional balance is tracked.
4. **Shop run-end interaction:** What happens if a shop would fire after the final leg of a run? Deferred from the shop spec. Depends partly on whether runs are fixed-length or open-ended, which depends on #5.
5. **Meta-progression scope:** What persists across runs? Unlocked parts? Unlocked modifiers? Cosmetics? **Partly resolved 2026-05-23** — dart components now persist as global (not per-profile) progression via `PlayerProgress` → `user://progress.tres`. Modifiers and cosmetics are still TBD. The `PlayerProgress` autoload is the natural home for any additional persistent state if/when they're added — e.g., `unlocked_modifier_ids: Dictionary` would mirror the component pattern.
6. **Rule-modifier category — partly resolved 2026-05-26.** Shipped as boss-defeat rewards via `RuleModifierReward` (8 in the V1 set), tracked in `main.gd::_active_rewards`. They didn't get their own slot system in the end — instead, they flag run-level booleans/counts on the relevant systems (`x01_game.allow_triple_checkout`, `x01_game.darts_per_turn`, `main.shop_cadence`, etc.). The HUD legendary panel (added 2026-05-28) surfaces what the player has banked. Still open: checkout helper doesn't yet reason about Extra Dart (solver depth) or any future rethrow-style verb. Slot/conflict rules for a future expanded set still TBD.

### Resolved since previous refresh

- **Distribution type for variance.** Resolved 2026-05-22. Gaussian is shipped via the `gaussian_spread` export on `throw_mechanic.gd` (default 0.4), with green/orange/red zones driven by normalized distance from the declared target's centroid. Sample uses 2D gaussian draws scaled by the accuracy zone × zone-driven multiplier.
- **Currency system.** No traditional currency. Spare darts saved across legs are the de facto currency and spend at the shop directly by throwing. See Shop System section.
- **Streak modifier conflicts.** Resolved by the one-per-category slot rule (Phase 4c).
- **Player agency vs. helper paternalism.** Resolved by the soft-hint design call in the checkout helper — passive nudges ("try toggling a modifier") instead of active suggestions ("disable Color Streak to enable T20-T20-Bull"). Will inform all future helper-style features.
- **Modifier commitment texture.** Resolved by the lock/unlock system — 65% locked / 35% toggleable, with rarity as the power axis (not lock status). See the Locked/Unlocked Modifier Status section.
- **Onboarding scope and shape.** Resolved 2026-05-22 via the Tutorial & Help System pass — three flows (mechanics, rules, welcome) kept separate, in-context stat teaching over a persistent reference panel, 3-throw demo→guide→free for the mechanics walkthrough, hybrid slideshow + one interactive moment for the rules. See the Tutorial & Help System section and `feedback_onboarding_ux_patterns` memory.

---

## Key Design Decisions Already Made

- **Single DartComponent class, not subclasses.** Barrel/shaft/flight are structurally identical; type is determined by which slot they're in.
- **Player starts with same base stats every run.** Components and upgrades add/subtract from there. Form (future) would modify starting stats.
- **Scoring modifier system is separate from stat upgrade system.** Stat upgrades mutate throw_mechanic properties directly. Scoring modifiers run a pipeline per dart through ScoringModifierManager. They share UI space (both are "upgrades" the player picks) but backends are completely independent.
- **X01 game logic is pure and encapsulated.** `x01_game.gd` receives already-modified scores and doesn't know about modifiers.
- **Balance affects accuracy specifically.** Thematically clean — a balanced dart flies straighter. Components determine ceiling, balance determines delivery quality.
- **Three balance zones (green/orange/red)** rather than a continuous curve. Simple for players to understand and tune.
- **Board renders effective values.** If a wedge is modified, the number on the board changes. The player should never have to remember invisible modifications.
- **Hover/inspect active between darts.** Not during AIMING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, or RESOLVING — player needs to focus during active throw phases. (The current enum no longer has a POSITIONING state — that was folded into AIMING with the ellipse rework.)
- **Streak modifiers are one-per-category.** Three slot categories (WEDGE, COLOR, PARITY). Picking a new streak modifier in a category the player already has triggers replacement, shown on the pick card. The PARITY category contains two distinct items (Even Streak / Odd Streak) that compete for the single slot.
- **Spare darts are the shop currency.** No coins, no points-to-spend. Saving darts in a leg (finishing efficiently) directly translates to shop throwing power. Skill expressed in regular play = leverage in the shop.
- **Three calculating interactions on every throw.** Board RNG read + skill/confidence + stat-driven hit probability. The shop's geometric placement rules deliberately invoke all three; future reward-delivery systems should preserve this trinity rather than collapse it.
- **The board's checkout-highlight function is the single source of truth for "can win."** The HUD score-gold indicator and the board's gold checkout highlights both read from the same function. They must never disagree.
- **The checkout helper is solver-driven, not lookup-based.** Modifiers (especially streak modifiers that mutate state per dart) break the static x01 checkout chart. The helper runs the actual scoring pipeline in simulation per candidate dart, with speculative streak-state mutation + restore between candidates. Caches sub-problems within each solve.
- **Setup recommendations use a four-mode priority system, not "highest remaining."** Higher new_remaining is the wrong direction (harder next-turn checkout). Mode 1 (endgame): lands at a 1-dart finish. Mode 2 (score-reduction): too far from checkout — generic "score more" line. Mode 3 (mid-zone): lands at any 3-dart-checkoutable remainder. Mode 4 (off-board): every scoring dart busts. Within concrete-target modes, rank by `[next_turn_fatness, new_remaining]`.
- **Soft hints over active suggestions.** "Try toggling a modifier" instead of "disable Color Streak to enable T20-T20-Bull." Active suggestions feel like the helper is playing for the player; passive nudges teach the verb without commandeering the decision. Applies to all future helper-style features.
- **Locked/unlocked is a 65/35 generation roll with no compensating buff for locked.** Rarity is the power axis, not lock status. Locked is a *constraint* (can't toggle off) at the same statline as unlocked. The interesting decision lives at the rarity boundary (locked-rare vs unlocked-uncommon), not within a single rarity.
- **Modifier commits are leg-scale, not run-scale.** Locked items can be swapped at the next shop or post-leg pick. Long enough for commits to feel real; short enough to not feel punishing.
- **Modifiers come in two kinds: RELIC and BOARD_MUTATION.** RELIC modifiers persist in the modifier panel, contribute to scoring per dart, and have icons. BOARD_MUTATION modifiers (Wedge Value, Wedge Swap, Brush) fire once at acquisition, mutate the dartboard, and then disappear from the inventory entirely — the board itself is their visible record. Two different player-mental-model questions: "what's actively scoring for me?" (panel) vs. "what does the board look like?" (the board). The distinction prevents inventory noise from one-time effects.
- **Modifier visual language is shape + color + outline.** Shape encodes category (circle = color, square = even, triangle = odd, sector = wedge). Fill carries the within-category specifics (target color) where applicable; otherwise neutral fill. Outlines layer rarity-color outside category-color (parity modifiers) or rarity-color alone (color and wedge modifiers). Bonus vs Streak within a category is **not** distinguished by icon — they live in different UI surfaces (relic bar vs streak section), and location does the disambiguation. If visual identity needs more weight than geometry can carry, the next step is hand-drawn art per modifier, not exported font glyphs.
- **Color streaks are per-color modifiers, not a single generic streak.** Four flavors (Red / Green / Black / White Streak) share the COLOR slot. Uniform 1/4 roll within the color-streak pool — black/white score less per hit but are easier to streak; red/green score more but require doubles/triples/bullseye. Rarity scope (turn/leg/run), lock/unlock status, and build synergy already provide enough variation axes that flat color weighting is the right v1.
- **Manual `StringName` IDs over Godot UIDs for dart components.** Considered four options: Godot UIDs (`uid://...`), file paths, auto-slug from `component_name`, and manual `StringName`. Went manual because save files stay human-readable (`["barrel_torpedo"]` vs an opaque hash), the ID survives file moves and display-name renames, and refactors can manually migrate IDs if absolutely necessary. The discipline cost (remembering to set the ID on every new component) is neutralized by `DartComponentRegistry._validate_components()` printing loud `push_error()` lines for empty or duplicate IDs on `_ready()`. Same pattern available to `ScoringModifier` and `ThrowModifier` later — don't extract a shared base class until at least two of them need it.
- **`PlayerProgress` autoload owns runtime unlock state; resources stay canonical.** The resource declares the *condition* (`unlock_condition`) and the starting state (`default_unlocked`); the player's earned unlocks live in `user://progress.tres` via `PlayerProgress`. Mixing those would either mutate `.tres` files on disk (git noise, weird save semantics) or hold in-memory overrides that don't persist. Strict separation also makes per-profile progression a trivial extension later (swap `SAVE_PATH` to per-profile path).
- **`UnlockCondition` mirrors the `ThrowModifier` pattern: base Resource + virtual `is_satisfied()` + `.tres` instances.** Subclass per condition family (`LegWinHitCondition`, `LegStatCondition`, `CareerCountCondition`, `RunConstraintCondition`, `ShopAcquisitionCondition`, `SlotsFilledCondition`, `RelicCountCondition`). Considered a single enum-based condition with dispatch and rejected — loses type safety per condition family and crowds the inspector. Considered fully generic context-key threshold check, also rejected — no inspector guidance, no documentation of what a condition can express. Subclass-per-family hits the sweet spot for an inspector-driven workflow.
- **Notifications queue; do not overwrite.** A single event (e.g., a clutch leg-win) can trip multiple unlock conditions at once. The `UnlockNotificationQueue` accepts `component_unlocked` signals into an internal queue and plays them sequentially with slide-in/display/slide-out tweens. Component data is read at display time, not signal time, so the toast can show the texture and component name without coupling the signal payload.
- **Wedge Streak is always WHOLE_WEDGE — leniency dropped.** Any ring on the same numbered wedge counts (D20 → S20 → T20 streaks). Rarity drives scope only, like the other streak modifiers. Default `bonus_per_hit = 2` (vs 1 for color/parity) because consecutive-same-wedge throws are significantly harder than consecutive-color or consecutive-parity throws. All three streak types' `bonus_per_hit` are exported for inspector tuning.
- **Flight is the run's singular archetype slot.** Exactly one equipped per run, no swap mid-run, intended as the build-defining commitment. Barrel and shaft are stat-tuning slots — players combine many; flight is closer to a class pick than a piece of equipment. Implications: flights should have substantial effects (not stat tweaks), should carry tougher unlock conditions than barrels/shafts, can fire at any lifecycle moment via the sibling-Resource ability hooks (throw-time, shop-time, future on-score), and defensive-only verbs need extra punch to feel worth a whole-run commitment. Without a build-defining slot, every run plays the same shape and "build variety" collapses to stat numbers.
- **Ability hooks are sibling Resources on `DartComponent`, one per lifecycle moment.** Each new ability type — throw-time, shop-time, future on-score — gets its own optional `Resource` field on `DartComponent` (currently `throw_modifier` and `shop_bias`). Don't extend an existing base class to do unrelated things; create a peer. Lets each hook evolve independently and keeps the diff surface tight when adding a new ability type. The same rationale as the scoring-vs-stat-upgrade split: different lifecycle moments need different shapes. The second-evaluation-pass pattern (re-evaluating throw modifiers at aim placement so target-aware bonuses can compute from `declared_target` + `active_streak_modifiers`) is the canonical way to inject *aim-time* context into the throw-time hook without inventing a new one.
- **Rethrow-style flight verbs are a design landmine.** Any "free retry on bad outcome" mechanic (rethrow on broken streak, charge-banked rethrows, etc.) creates an intentional-miss exploit: the player deliberately throws badly to bank the bonus, then uses the free retry on the original high-value target. The exploit can't be patched cleanly without hollowing out the verb — gating by intent inference is fragile, gating by charge caps just turns the exploit into a hoarded resource. The Momentum Marksman flight replaced an earlier "streak saver" rethrow design with a proactive scaling accuracy bonus that rewards keeping the streak alive in the first place. When new rethrow-style proposals surface, close the intentional-miss path before sketching anything else.
