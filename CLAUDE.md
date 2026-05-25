# Boss Encounters & Level Select System

**Spec date:** 2026-05-25
**Status:** Designed, ready for implementation. Likely warrants phasing — see Implementation Phases.
**Scope:** Add per-leg boss encounters that mutate the play state with debuffs, gate runs behind a level-select screen with progressive unlocks, and introduce a rule-modifier reward pool that bosses drop. Together these convert the game from "endless escalation" into a structured run-arc with a defined goal and a meta-progression hook.

## Summary

The current game is in a good prototype state — components, shop, modifiers, tutorials, cumulative progression all work — but it has no defined run goal and no run-shape variation. Every run is the same monotonic escalation until failure. This spec adds two structural systems that together address both:

- **Level select**: replaces "press start, play forever" with a level menu. Each level has a max score cap (501, 1001, 1501 to start) and a fixed number of boss encounters. Higher levels unlock by clearing lower ones. Each level tracks fewest-darts-to-clear for personal-best speedrun chasing.
- **Boss encounters**: every 5 legs, a boss appears. A boss leg is a normal leg with a mutating debuff layered onto the play state — voids appear on the board, wedge colors shuffle, dart count drops, etc. Beating a boss leg unlocks a free shop and lets the player pick from a 3-of-3 pool of *rule-modifier rewards* — durable run-wide tweaks that don't fit in the existing modifier system (extra dart per turn, +1 streak slot, etc.).

The two systems are designed together because they constrain each other: the level cap determines how many bosses appear, the boss rewards justify pushing for higher levels, and the level-select infrastructure is what makes boss-pool curation (and difficulty tiering) tractable per level.

## Design Context

### Motivation

Bosses solve run-arc repetitiveness, not leg-to-leg repetitiveness. The current game's leg-to-leg loop is solid; what's missing is a *shape* to a run — a buildup, a climax, a resolution. Boss legs become the climaxes; the level cap is the resolution.

Level select solves three otherwise-tangled problems with one structure:

- **Endgame goal**: A run now has a defined ending ("clear 501") and a clear *victory state*, not just "see how far you get before failing."
- **Boss exposure pacing**: The +1-boss-per-level pattern means new players see one boss in their first run, two in 1001, three in 1501, etc. The cadence within a run stays at every-5-legs regardless of level, so muscle memory carries across levels.
- **Replayability with new unlocks**: Component unlocks are horizontal sidegrades, not vertical upgrades. Returning to 501 with new components is a different puzzle, not a trivially-easy one. Fewest-darts tracking gives those replays a target.

### Key design positions

These were debated and resolved during the design conversation; flagging them here so future-Max remembers *why* rather than re-litigating:

- **Horizontal unlocks over vertical**: Unlocks expand the option space; they do not make the player objectively stronger. This is what protects the level-select system from hollowing out — replaying 501 with all unlocks should still be a meaningful run, not a victory lap.
- **Boss debuffs mutate per turn, not per throw, not in real time**: Per-throw mutation breaks the player's ability to plan a 3-dart sequence. Real-time mutation (the original "slowly rotating board" idea) doesn't fit a turn-based game. Per-turn lets the player plan within a turn and adapt across turns.
- **No boss foreknowledge in this spec**: The player does not see the upcoming boss in advance. Reasoning: with the current modifier pool, there isn't much *meaningful* prep the player could do. This is the most likely thing to revisit — see Open Future Hooks for the foreknowledge-as-item path.
- **No special first-run handling**: 501 has a normal boss like every other level. Continuity matters — the player should learn that bosses appear at the end of every level (including the first one they ever play). A "first run is boss-free" carve-out would break that mental model.
- **Cadence stays uniform at every-5-legs across all levels**: Earlier discussion considered accelerating to every-3-legs after 1001. Dropped in favor of "+1 boss per level with consistent cadence," which keeps the player's mental model of when-to-expect-bosses stable. Difficulty ramp comes from boss *pool quality* per level, not boss *frequency*.
- **Losing to a boss ends the run**: No retry, no penalty-and-continue. This makes the boss feel like a real wall and makes the win feel like a real win.
- **Partial credit doesn't count**: Making it to leg 8 of a 10-leg run doesn't unlock anything. Only full clears count. Keeps the goal meaningful.
- **Rethrow-based rewards are excluded from the reward pool**: Per `specs/2026-05-24-flight-modifier-additions.md` and the dropped-rethrow design memory, rethrow verbs create intentional-miss exploits. Until that's solved, "+1 rethrow per leg" is not in the boss reward pool.

## Level Select System

### Level structure

A `Level` is a `Resource` holding the config for one selectable run:

```gdscript
class_name LevelDefinition extends Resource

## The maximum score target for this level — the final leg's cap.
## Player wins the run by clearing the leg at this cap.
@export var max_score_target: int = 501

## How many boss encounters appear during this run.
## Bosses are scheduled at every-5-legs intervals.
@export var boss_count: int = 1

## Pool of boss types this level draws from. Curate to control difficulty.
## Earlier levels should use softer bosses; later levels can include the brutal ones.
@export var boss_pool: Array[BossDefinition] = []

## Rarity weight shift applied to all modifier rolls during this run.
## Negative values for early levels reduce rare frequency; positive values for late levels increase it.
## Default 0.0 means no shift. Recommended: -0.02 to -0.03 for 501, +0.02 to +0.03 for 1501+.
@export var rarity_weight_shift: float = 0.0

## Display name shown on the level select screen.
@export var display_name: String = "501"

## Unlock condition for this level. Null means always unlocked (the starter level).
@export var unlock_condition: UnlockCondition
```

### Starter levels

Three levels ship in this spec:

- **501** — 1 boss, soft boss pool, slight rarity shift toward common/uncommon. Always unlocked.
- **1001** — 2 bosses, mid boss pool, neutral rarity. Unlocks after clearing 501.
- **1501** — 3 bosses, full boss pool (including the harder ones), slight rarity shift toward rare. Unlocks after clearing 1001.

Beyond 1501 is a future expansion: 2001, 2501, etc., each adding +1 boss and the corresponding number of legs. Implementation should make adding new `LevelDefinition` resources trivial — no level-count assumed in code.

### Level select UI

The level-select scene replaces (or precedes) the current start screen. Each level renders as a button card with:

- **Display name** (e.g., "501", "1001")
- **Completion state**: grey (locked), white/neutral (unlocked, never cleared), green (cleared at least once). Locked levels show their unlock condition hint.
- **Fewest darts used to clear** (only shown if cleared). Format: "Best: 28 darts" or similar.

Everything visual should be exported for tuning per the GDScript convention notes — colors, button sizes, layout positions, font choices.

After picking a level, flow continues into dart assembly as it does today.

### PlayerProgress additions

`PlayerProgress` (autoload) gains:

- `cleared_levels: Dictionary` — keys are `LevelDefinition.resource_path` (or a stable StringName ID), values are `{cleared: true, fewest_darts: int}`. Updated on full clear only.
- A signal `level_cleared(level_definition, dart_count)` for the UI to react to.

Partial-progress *during* a run does not write to `PlayerProgress` until the run is fully won. Quitting or dying mid-run leaves nothing behind except the cumulative-progression hooks that already exist.

## Boss Encounters

### Boss scheduling

Bosses appear at fixed intervals within a run. With a uniform every-5-legs cadence and a +1-boss-per-level scaling:

- 501 (5 legs): boss at leg 5 (the final leg)
- 1001 (10 legs): bosses at legs 5 and 10
- 1501 (15 legs): bosses at legs 5, 10, and 15
- N01 (5N legs): bosses at every 5th leg

The boss *type* (which debuff) is rolled from the level's `boss_pool` when the boss leg starts. No advance reveal in this spec. The boss is announced when the leg begins via a brief notification UI (existing notification infrastructure should be reusable per the component unlock system).

### Boss definition

A `BossDefinition` is a `Resource` holding boss-specific tuning and a reference to a `Boss` script:

```gdscript
class_name BossDefinition extends Resource

## Unique stable identifier for this boss. Used in save data and for analytics.
@export var boss_id: StringName

## Display name shown on the boss-start notification.
@export var display_name: String = "The Void"

## One-line description of the debuff, shown on the boss-start notification.
@export var description: String = "5 random wedges become voids."

## The boss behavior script. Subclass of Boss.
@export var boss_script: GDScript
```

A `Boss` base class wraps the lifecycle hooks:

```gdscript
class_name Boss extends RefCounted

## Called when the boss leg starts. Use this to set up persistent state.
func on_leg_start(game_state) -> void: pass

## Called at the start of each turn (between throws-of-3).
## Most boss effects mutate state here.
func on_turn_start(game_state) -> void: pass

## Called when the boss leg ends (win or loss). Clean up any mutations.
func on_leg_end(game_state) -> void: pass

## Returns a list of UI overlay nodes/instructions for this boss's visual state.
## Used by the board renderer to draw voids, color-overrides, etc.
func get_visual_overlay() -> Array: return []
```

### Boss designs (initial pool)

Four bosses ship in this spec. Each mutates the game state per turn (not per throw, not continuously). Tuning numbers should be exported for inspector control.

**1. The Void** — At the start of each turn, 5 random wedge segments become voids. Hitting a void scores zero. The void positions reroll each turn. Uses the existing shop shader (blacked out) for visual consistency. *Why this design: spatial debuff that reuses existing visual language, doesn't disable any modifier category, accuracy and rerouting are the natural counterplay.*

**2. Prism** — At the start of each turn, all wedge colors are randomly reshuffled. Color identities stay (still green/red/white whatever the palette is), but which wedges are which color changes. *Why this design: tests build flexibility without nuking it — color modifiers still work, the player just has to re-target. Even/odd builds are unaffected.*

**3. Two Darts** — Player throws 2 darts per turn instead of 3 for the duration of the boss leg. *Why this design: resource debuff, pure throw economy. Adaptable through accuracy and high-value targeting. Mechanically clean, no visual state changes needed.*

**4. Recession** — A randomly-selected color has all its scoring values halved for the leg. The affected color is locked in at leg start (not rerolled per turn — this one is an exception because re-rolling would make planning impossible). The color is announced clearly at leg start. *Why this design: forces deck flexibility, but the locked-at-start design makes it playable rather than chaotic.*

Note on Recession's exception to per-turn mutation: the player needs to make build/aim decisions across multiple turns. If the affected color changed every turn, the player would be doing the boss's job for them (random aim). Lock-at-start preserves agency within the debuff.

### Boss UI

When a boss leg starts, a notification appears showing the boss's `display_name` and `description`. Existing notification infrastructure (per the component unlock system) should handle this — no new UI primitives needed.

During the boss leg, visual mutations (voids, color shuffles) are drawn on top of the existing board via the `get_visual_overlay()` hook. The checkout-helper, stat panel, and other UX features remain visible and accurate — bosses mutate the *game state*, not the player's tools for interpreting it. This is an intentional design constraint (see Design Context).

## Boss Rewards

### Reward flow

After clearing a boss leg, the player sees a reward screen showing 3 rule-modifier rewards drawn from a pool. They pick one. After picking, a free shop appears before the next leg starts. The free shop is a normal shop instance — it just doesn't cost anything to enter.

### Rule-modifier reward pool

Rule modifiers are durable, run-wide tweaks that don't fit the existing modifier system because they change *game rules* rather than *scoring rules*. Initial pool:

- **Extra Dart** — +1 dart per turn for the rest of the run.
- **Extra Turn** — +1 total turns per leg for the rest of the run.
- **Streak Slot Extension** — +1 additional streak slot (lets the player hold one more streak modifier active).
- **Lucky Eye** — Permanent +2% rare modifier roll chance for the rest of the run.
- **Pool Widener** — Shops show +1 option per pool for the rest of the run (3 picks instead of 2, etc.).
- **Frequent Shopping** — Shops appear every 2 legs instead of every 3.
- **Relic Slot Extension** — +1 relic slot (only if relic caps exist or are being added).

Each reward should be its own `Resource` subclass implementing an `apply(run_state)` method. Stackability rules: most are exclusive ("you already have this") to prevent +3-dart-per-turn dominant strategies; flag in the resource whether multiple copies are allowed.

The "Frequent Shopping" reward only makes sense if the player hasn't already taken the lower-frequency option. Pool generation should skip rewards that wouldn't do anything.

### Rule modifiers as their own design problem

Rule modifiers as a category are partially designed but the full pool needs more thought. The above is a starter set. This spec includes them because they're the natural fit for boss rewards (durable, run-arc-shaping), but expanding the pool is a follow-up design effort. The implementation should make adding new rule modifiers trivial — same resource pattern as other modifiers.

## Implementation Phases

This spec is large. Phase it so each phase leaves the game runnable and shippable on its own.

### Phase 1: Level select scaffolding

- `LevelDefinition` resource class
- Three `.tres` level definitions (501, 1001, 1501) with placeholder boss pools (empty arrays)
- Level select scene with completion-state display, replacing or preceding current entry point
- `PlayerProgress.cleared_levels` tracking, `level_cleared` signal, fewest-darts tracking
- Apply `LevelDefinition.max_score_target` to run config; runs now end at the configured cap with a victory screen
- Lock state and unlock display

After Phase 1: the game has a working level select with three levels and a real win state, but no bosses yet. Already a significant UX improvement.

### Phase 2: Boss system core + one boss

- `Boss` base class, `BossDefinition` resource
- Boss scheduler in run logic (every 5 legs)
- Boss-start notification UI
- Implement **Two Darts** (simplest — no visual state changes)
- Wire **Two Darts** into the 501 boss pool
- Boss leg loss = run loss (no special handling needed if it already works that way)

After Phase 2: 501 runs have a boss at the end. Boss system works end to end.

### Phase 3: Remaining bosses

- Implement **The Void** (visual overlay via existing shop shader)
- Implement **Prism** (color reshuffle logic)
- Implement **Recession** (color-halving with leg-start lock)
- Curate boss pools per level (501 = softer subset, 1501 = full pool)
- Visual overlay system for boss mutations

### Phase 4: Boss rewards

- `RuleModifierReward` base class
- Initial reward pool (7 rewards above)
- Reward pick screen (3-of-3)
- Free shop after pick
- Stack/exclusion logic per reward

### Phase 5: Polish + per-level tuning

- Apply `rarity_weight_shift` per level to modifier rolls
- Speedrun display on level-select screen
- Boss preview/announcement polish
- Playtest passes for boss tuning (export all tunable numbers — bonus counts, void counts, etc.)

## Architectural Notes

- All new `@export` vars should have hover descriptions per the GDScript conventions.
- Static-type everything.
- Visual/UI choices (colors, sizes, positions) should be exported wherever cleanly possible per the project conventions, especially on the level-select scene and the boss-start notification.
- Reuse existing notification infrastructure from the component unlock system rather than building new notification primitives.
- The shop shader (used for marking shop spots) is the visual primitive for The Void — reuse it.
- The existing PlayerProgress autoload pattern is the home for new per-level tracking.
- Reward pool generation should follow the same "skip if not applicable" pattern that modifier shop rolls already use.

## Open Future Hooks (intentionally not in this spec)

- **Boss foreknowledge as item/toggle.** The current spec has no boss preview. A future relic, flight, or settings toggle could reveal the upcoming boss one leg in advance, creating meaningful prep decisions at shop time. Most likely to be revisited once the modifier pool grows and there's *more* meaningful prep the player could do.
- **Rule-modifier pool expansion.** The initial 7 are a starter set. Designing more rule modifiers is its own follow-up. Worth pairing with any future rethink of what "items" mean in this game.
- **Rethrow-based rewards (re-enabled).** Currently excluded because the rethrow exploit isn't solved. If/when that's solved, "+1 rethrow per leg" is a natural reward.
- **Mega-final-boss for endgame levels.** Beyond 1501, the final boss could be a stacked-debuff encounter rather than a normal one. Gives the longest level a real climax.
- **Speedrun milestones / achievements.** "Beat 501 in under 30 darts" as concrete sub-goals. Cheap to add once fewest-darts tracking is in.
- **Per-level cosmetic differentiation.** Different background, music, framing per level. Pure polish, but worth thinking about once mechanical content is solid.
- **Boss-specific component unlocks.** Some component unlock conditions could specifically require beating certain bosses. Aspirational gates without level gating.

## Files Affected (likely; will be refined during implementation)

**New files:**
- `scripts/levels/level_definition.gd`
- `scripts/levels/level_select.gd`
- `scenes/level_select.tscn`
- `resources/levels/level_501.tres`, `level_1001.tres`, `level_1501.tres`
- `scripts/bosses/boss.gd` (base)
- `scripts/bosses/boss_definition.gd`
- `scripts/bosses/two_darts_boss.gd`
- `scripts/bosses/void_boss.gd`
- `scripts/bosses/prism_boss.gd`
- `scripts/bosses/recession_boss.gd`
- `resources/bosses/*.tres` for each
- `scripts/rewards/rule_modifier_reward.gd` (base)
- `scripts/rewards/*.gd` for each starter reward
- `resources/rewards/*.tres` for each
- `scenes/boss_reward_pick.tscn`

**Modified files:**
- `scripts/player_progress.gd` — add `cleared_levels`, fewest-darts tracking, signal
- `scripts/main.gd` (or whatever orchestrates a run) — apply LevelDefinition, schedule bosses, handle reward picks, route to free shop
- Whatever current start-screen / entry scene exists — route through level select first
- `scripts/modifier_registry.gd` — apply `rarity_weight_shift` from the current run's level
- Possibly `scripts/scoring_modifier_manager.gd` or wherever streak slots are capped — make slot count configurable for Streak Slot Extension reward

---

## Workflow Notes

`CLAUDE.md` holds the **single active spec** — the feature currently being designed or implemented. It auto-loads into every Claude conversation in this repo, so it should stay lean and focused on one thing at a time.

When a feature ships (or work moves on to a new spec), the previous one gets archived:

1. Move everything above this "Workflow Notes" section into `specs/YYYY-MM-DD-feature-slug.md`.
2. Add a status header at the top of the archived file:
   ```
   ---
   Spec date: YYYY-MM-DD
   Status: Shipped YYYY-MM-DD | Partially shipped | Superseded by specs/X
   Implementation: Where the implementation pass ran (Claude Code, manual, etc.)
   Notes: What shipped vs deferred, links to follow-up specs that revisit anything here.
   ---
   ```
3. Reset the spec section in `CLAUDE.md` to this placeholder (or replace it with the next spec).

The archive is for design context, not implementation reference. Code lives in code; the archived spec exists to remind future-Max (and future-Claude) *why* a system was built a certain way, what alternatives were considered, and what the design assumptions were. When making changes that touch an existing system, scan `specs/` for any prior decision that constrains the new work.
