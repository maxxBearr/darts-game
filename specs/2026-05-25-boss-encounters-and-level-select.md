---
Spec date: 2026-05-25
Status: Shipped 2026-05-26 (all 5 phases + Phase 6 mid-spec expansion)
Implementation: Claude Code passes 2026-05-26/27 + manual integration
Notes: Phase 6 added 2026-05-25 mid-spec (scaling variants, Rotation/Narrow Double Ring bosses, Triple Outs/Glass Cannon rewards). All phases shipped together rather than incrementally. Glass Cannon implementation note in the spec was followed — bust-kills behavior lives on `x01_game.glass_cannon_active`, mirrored on `scoring_modifier_manager`. `ModifierRegistry.current_rarity_shift` handles per-level rarity tuning. The original status line below (Phases 1 & 2) is preserved as historical context — it reflects the spec's state at archival time, not the final implementation.
---

# Boss Encounters & Level Select System

**Spec date:** 2026-05-25
**Status:** Phases 1 & 2 implemented (level select scaffolding + boss system core with Two Darts). Phases 3-5 outstanding. Phase 6 added 2026-05-25 (scaling variants + Rotation/Narrow Double Ring bosses + Triple Outs/Glass Cannon rewards) — see updated sections below.
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
- **Boss families scale across tiers, they don't get replaced**: A boss that exists at easy tier (e.g., Void with 6 voids) also appears in higher tiers as a stronger variant (Void with 12, Void with 18). Player continuity matters — recognizing "scarier Void" carries learning forward instead of forcing relearning from scratch each tier. Mechanically this is one boss script with multiple `.tres` resources differing only in tuning.
- **Trade-style rewards/items are a deliberate design lean**: Most roguelikes drift toward purely-additive items because they're easy to design. This game leans into trades (e.g., Glass Cannon = checkout flexibility for bust-kills-the-run) as a core balance lever. Targets: at least 30-40% of any future reward/item pool expansion should be trades, not pure additives. Trades naturally resist the win-more-spiral problem because every additive picks up an opportunity cost.

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

## Unique stable identifier for this boss variant. Used in save data and for analytics.
## Scaled variants of the same boss family use distinct ids — e.g., "void_easy", "void_medium", "void_hard".
@export var boss_id: StringName

## Display name shown on the boss-start notification.
@export var display_name: String = "The Void"

## One-line description of the debuff, shown on the boss-start notification.
@export var description: String = "5 random wedges become voids."

## The boss behavior script. Subclass of Boss.
@export var boss_script: GDScript

## Difficulty tier for this variant. Documentation/sorting field; the active
## pool comes from LevelDefinition.boss_pool, which is manually curated. Values
## by convention: &"easy", &"medium", &"hard".
@export var difficulty_tier: StringName = &"easy"
```

### Boss families and scaled variants

A boss *family* (Void, Recession, Rotation, etc.) is one `Boss` script with tunable parameters. Each *variant* is a separate `BossDefinition.tres` referencing the same script with different exported tuning values plus a different `difficulty_tier`. The family concept is implicit — it lives in the shared script reference — not as a Godot type.

Pool curation per starter level uses the bracketed-tier structure: 501 pulls from easy variants only, 1001 pulls from easy + medium, 1501 pulls from medium only, 2001+ adds hard. The brackets are realized by hand-picking which `.tres` resources go in each `LevelDefinition.boss_pool` array. The `difficulty_tier` field is for documentation, sorting, and any future tag-based filter — *not* for runtime pool derivation in this spec.

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

Six boss families, totaling roughly 12-14 variants when all scaled tiers are populated. Each mutates the game state per turn (not per throw, not continuously, except where noted). Tuning numbers are exported on each variant's `.tres` for inspector control.

**1. The Void** — At the start of each turn, N random wedge segments become voids. Hitting a void scores zero. Void positions reroll each turn. Uses the existing shop shader (blacked out) for visual consistency.
- *Easy* (`void_easy`): 6 voids
- *Medium* (`void_medium`): 12 voids
- *Hard* (`void_hard`): 18 voids

*Why this design: spatial debuff that reuses existing visual language, doesn't disable any modifier category, accuracy and rerouting are the natural counterplay. Scales numerically by void count.*

**2. Prism** — At the start of each turn, all wedge colors are randomly reshuffled. Color identities stay (still green/red/white), but which wedges are which color changes.
- *Easy* (`prism_easy`): reshuffles every 2 turns instead of every turn (gives planning room).
- *Medium* (`prism_medium`): reshuffles every turn.
- *Hard variant*: deferred — Prism's "every turn" is already disruptive; a harder variant might pair it with one Void wedge per turn, but worth playtesting Prism-medium first.

*Why this design: tests build flexibility without nuking it — color modifiers still work, the player just has to re-target. Even/odd builds are unaffected. Scales by reshuffle frequency.*

**3. Two Darts** — Player throws fewer darts per turn for the duration of the boss leg.
- *Easy* (`two_darts`, currently implemented): 2 darts per turn.
- *Hard variant* (`one_dart`): 1 dart per turn. Brutal but valid against a strong endgame build. Reserve for hard tier only.

*Why this design: resource debuff, pure throw economy. Adaptable through accuracy and high-value targeting. Mechanically clean, no visual state changes needed.*

**4. Recession** — A randomly-selected color has its scoring values reduced for the leg. The affected color is locked in at leg start (not rerolled per turn — this is an exception because re-rolling would make planning impossible). The color is announced clearly at leg start.
- *Easy* (`recession_easy`): -25% to affected color.
- *Medium* (`recession_medium`): -50%.
- *Hard* (`recession_hard`): -75%.

*Why this design: forces deck flexibility. Locked-at-start preserves agency. Scales by reduction percentage.*

Note on Recession's exception to per-turn mutation: the player needs to make build/aim decisions across multiple turns. If the affected color changed every turn, the player would be doing the boss's job for them (random aim). Lock-at-start preserves agency within the debuff.

**5. Rotation** — At the start of each turn, the entire dartboard rotates by a random angle (clockwise or counter-clockwise). All wedge positions, colors, and parity shift together. The player's stat-favored aiming zones (top/bottom for V-heavy accuracy, sides for H-heavy accuracy) now contain different wedges than they did last turn, forcing target re-evaluation against the new layout.
- *Medium* (`rotation_medium`): rotation angle in 45-90° range per turn.
- *Hard* (`rotation_hard`): rotation angle in 90-135° range per turn.

*Why this design: a strictly broader debuff than Prism — moves color identities AND wedge values AND parity together. Unique among bosses in that it specifically disrupts stat-based aiming heuristics. Reserve for medium and hard tiers because the disruption is meaningfully larger than Prism's color-only shuffle. Visual: animate the rotation between turns so the player can track which way the board moved.*

**6. Narrow Double Ring** — The double ring (the outer scoring band) is visually and mechanically narrowed for the leg, shrinking the target area for double hits. Counterplay is accuracy investment. Particularly mean late in a leg where checkouts cluster on doubles.
- *Medium* (`narrow_double_medium`): double ring narrowed by 50%.
- *Hard* (`narrow_double_hard`): double ring narrowed by 75%.

*Why this design: geometry debuff rather than state debuff — changes the board's physical layout rather than what's on it. Pairs thematically with Recession because both target checkout strategy. Reserve for medium and hard tiers.*

### Pool composition per starter level

Initial bracketed structure (easy variants in 501, easy + medium in 1001, medium only in 1501):

- **501** (1 boss, easy pool): `void_easy`, `prism_easy`, `two_darts`, `recession_easy`
- **1001** (2 bosses, easy + medium pool): all of 501's pool plus `void_medium`, `prism_medium`, `recession_medium`, `rotation_medium`, `narrow_double_medium`
- **1501** (3 bosses, medium pool only): `void_medium`, `prism_medium`, `recession_medium`, `rotation_medium`, `narrow_double_medium`

Future levels (2001+) add hard variants: `void_hard`, `recession_hard`, `rotation_hard`, `narrow_double_hard`, and `one_dart`.

The "1501 drops easy variants entirely" is intentional — at 1501 the player has graduated past the gentlest versions of these debuffs, and the level having a *distinct identity* (medium-only) beats wider pools that blur 1001 and 1501 together. If playtest shows this feels too narrow, easy variants can be re-added to 1501 with no code change — it's a one-edit to the `.tres`.

### Boss UI

When a boss leg starts, a notification appears showing the boss's `display_name` and `description`. Existing notification infrastructure (per the component unlock system) should handle this — no new UI primitives needed.

During the boss leg, visual mutations (voids, color shuffles) are drawn on top of the existing board via the `get_visual_overlay()` hook. The checkout-helper, stat panel, and other UX features remain visible and accurate — bosses mutate the *game state*, not the player's tools for interpreting it. This is an intentional design constraint (see Design Context).

## Boss Rewards

### Reward flow

After clearing a boss leg, the player sees a reward screen showing 3 rule-modifier rewards drawn from a pool. They pick one. After picking, a free shop appears before the next leg starts. The free shop is a normal shop instance — it just doesn't cost anything to enter.

### Rule-modifier reward pool

Rule modifiers are durable, run-wide tweaks that don't fit the existing modifier system because they change *game rules* rather than *scoring rules*. Initial pool (mix of additives and trades — see the design-position note about trade-item lean):

**Additives:**
- **Extra Dart** — +1 dart per turn for the rest of the run.
- **Extra Turn** — +1 total turns per leg for the rest of the run.
- **Streak Slot Extension** — +1 additional streak slot (lets the player hold one more streak modifier active).
- **Lucky Eye** — Permanent +2% rare modifier roll chance for the rest of the run.
- **Pool Widener** — Shops show +1 option per pool for the rest of the run (3 picks instead of 2, etc.).
- **Frequent Shopping** — Shops appear every 2 legs instead of every 3.
- **Relic Slot Extension** — +1 relic slot (only if relic caps exist or are being added).
- **Triple Outs** — Allows checking out on a triple, in addition to doubles. Widens the checkout option space but does not raise scoring ceilings. Utility smoothing, low risk.

**Trades:**
- **Glass Cannon** — Allows checking out on *any* dart landing exactly on zero (singles, doubles, triples, bull — anything that lands you at 0 wins the leg). In exchange, *any bust* immediately ends the run (rather than the normal "lose the turn, score reverts" behavior). The trade is: massive checkout flexibility for the rest of the run, no bust-and-recover safety net for the rest of the run. Telegraphs as "fragile but versatile" — name choice intentional. This is the canonical trade-item in the starter pool; future expansions should add more in the same spirit.

Each reward should be its own `Resource` subclass implementing an `apply(run_state)` method. Stackability rules: most are exclusive ("you already have this") to prevent +3-dart-per-turn dominant strategies; flag in the resource whether multiple copies are allowed.

The "Frequent Shopping" reward only makes sense if the player hasn't already taken the lower-frequency option. Pool generation should skip rewards that wouldn't do anything. Same logic applies to Triple Outs if Glass Cannon is already taken (Glass Cannon supersedes — any zero-landing checkout works under Glass Cannon, so Triple Outs adds nothing).

Glass Cannon implementation note: the bust-kills behavior must respect the player's existing checkout context. If Glass Cannon is active, the checkout-helper UI should reflect the expanded checkout options *and* clearly indicate the bust-kills rule (color the warning differently, or show a small Glass Cannon indicator near the score). The player should never be surprised by the rule change.

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

### Phase 3: Remaining bosses (now expanded to 6 families with scaled variants)

- Add `difficulty_tier: StringName` field to `BossDefinition` (documentation/sorting; not used for runtime filtering — pools stay manually curated)
- Implement **The Void** family (visual overlay via existing shop shader). Three variants: `void_easy`/`_medium`/`_hard` differing only in `void_count`.
- Implement **Prism** family (color reshuffle logic). Two variants: `prism_easy` (every 2 turns) and `prism_medium` (every turn).
- Implement **Recession** family (color-halving with leg-start lock). Three variants: `recession_easy`/`_medium`/`_hard` differing in reduction percentage.
- Implement **Rotation** family. Two variants: `rotation_medium` (45-90° per turn) and `rotation_hard` (90-135° per turn). Animate the rotation visually so the player can track which direction the board moved.
- Implement **Narrow Double Ring** family. Two variants: `narrow_double_medium` (50% narrowed) and `narrow_double_hard` (75% narrowed). Requires geometry adjustment in the dartboard's hit-detection and visual rendering.
- Add **One Dart** variant of `TwoDartsBoss` (1 dart per turn). Pure tuning change to the existing Two Darts script — no new behavior.
- Curate boss pools per level via the bracketed structure (see Pool Composition section above).
- Visual overlay system for boss mutations (voids, rotation, narrowed ring).

### Phase 4: Boss rewards

- `RuleModifierReward` base class
- Initial reward pool (8 rewards: 7 additives + Glass Cannon trade)
- Reward pick screen (3-of-3)
- Free shop after pick
- Stack/exclusion logic per reward (including Glass Cannon supersedes Triple Outs)
- **Glass Cannon-specific:** bust-handling code path that converts "lose turn, revert score" into "end run" when the rule is active. Update checkout-helper UI to reflect both the expanded checkout options and the bust-kills warning state.

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
- **Tag-based pool filtering instead of manual curation.** If the boss pool grows past ~15 variants, the per-`LevelDefinition.boss_pool` array becomes painful to maintain (every new boss requires editing every level it should appear in). At that point, refactor to a tag-based filter: `LevelDefinition.accepted_tiers: Array[StringName]` and a global boss registry. The `difficulty_tier` field already exists on `BossDefinition` to make this a low-cost refactor when needed. Not worth doing preemptively at 6 families / 12 variants.
- **Harder Prism variant.** A hard-tier Prism wasn't designed in this spec because Prism-medium (every-turn color reshuffle) is already disruptive. If hard-tier Prism is wanted later, candidates include pairing with one floating Void wedge per turn, or shuffling colors *and* parity together (which would also affect even/odd builds).

## Files Affected (likely; will be refined during implementation)

**Already implemented (Phase 1 + 2):**
- `scripts/levels/level_definition.gd`, `scripts/levels/level_select.gd`
- `resources/levels/level_501.tres`, `level_1001.tres`, `level_1501.tres`
- `scripts/bosses/boss.gd`, `boss_definition.gd`, `boss_manager.gd`, `two_darts_boss.gd`
- `resources/bosses/two_darts.tres`
- Modifications to: `scripts/player_progress.gd`, `scripts/main.gd`, `scripts/x01_game.gd`, `scripts/hud.gd`, `scripts/game_over_screen.gd`, `scenes/main.tscn`

**New files for remaining phases:**
- `scripts/bosses/void_boss.gd`, `prism_boss.gd`, `recession_boss.gd`, `rotation_boss.gd`, `narrow_double_ring_boss.gd`
- `resources/bosses/void_easy.tres`, `void_medium.tres`, `void_hard.tres`, `prism_easy.tres`, `prism_medium.tres`, `recession_easy.tres`, `recession_medium.tres`, `recession_hard.tres`, `rotation_medium.tres`, `rotation_hard.tres`, `narrow_double_medium.tres`, `narrow_double_hard.tres`, `one_dart.tres`
- `scripts/rewards/rule_modifier_reward.gd` (base) and one `.gd` per reward (extra_dart, extra_turn, streak_slot_extension, lucky_eye, pool_widener, frequent_shopping, triple_outs, glass_cannon)
- `resources/rewards/*.tres` for each
- `scenes/boss_reward_pick.tscn`

**Modified files for remaining phases:**
- `scripts/bosses/boss_definition.gd` — add `difficulty_tier: StringName` field
- `scripts/main.gd` — handle reward picks, route to free shop after boss
- `scripts/modifier_registry.gd` — apply `rarity_weight_shift` from the current run's level
- `scripts/scoring_modifier_manager.gd` (or wherever streak slots are capped) — make slot count configurable for Streak Slot Extension reward
- Dartboard / checkout-helper code — handle Glass Cannon's expanded checkout rule and bust-kills warning state
- Dartboard hit-detection and rendering — handle Narrow Double Ring's geometry adjustment
