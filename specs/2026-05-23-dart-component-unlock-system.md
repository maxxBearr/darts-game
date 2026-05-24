---
Spec date: 2026-05-23
Status: Shipped 2026-05-23. Living references: `DartComponentGuide.md` (architecture + how-to-add) and `UnlockConditionRecipes.md` (cookbook). Two follow-up fixes applied same-day: strict reading of `winning_turn_all_darts_scored` in `main.gd`, and defensive `_skip_locked()` in `assembly_screen.gd` for initial equip.
Implementation: Claude Code single pass against `DartComponentGuide.md` (which served as the implementation spec before being repositioned as a living developer guide).
Notes: Eight existing placeholder components were deleted before the pass (Max's call — they had only PNG assignments, no design data). Seven surviving components migrated cleanly with new IDs. All 15 unlock condition recipes documented; nine of the 15 work today, one (`SlotsFilledCondition` for all streak categories) works today as well, recipe 9 was reshaped from "Fill all modifier slots" to "Hold 6+ relics at once" via a new `RelicCountCondition` because the original semantic was design-blocked on a slot-cap that doesn't structurally exist. Nine shell `.tres` files staged in `resources/dart_components/{slot}/_unfilled_*.tres`, not registered — Max fills them in with design data when ready.
---

# Dart Component Unlock System — Design Rationale

This archive captures the *why* behind the dart component unlock system. The *what* and *how* live in `DartComponentGuide.md` (architecture, field references, integration points) and `UnlockConditionRecipes.md` (per-condition cookbook). Read those first if you need to use the system; read this if you're wondering why a decision was made a particular way.

## Motivation

The dart customization system shipped in Phase 5 with all components available from the start. That was correct for that pass — the goal was establishing the three-slot assembly and the balance system. With those proven, the next progression hook was clear: lock some components behind earn conditions so the player has reasons to keep playing and reasons to attempt unusual play patterns (clutch finishes, no-rare runs, specific finishing wedges, etc.).

Max's design list of 15 unlock intents covered both event-triggered moments (win on double bullseye, three-dart checkout) and accumulators (win N legs total, hold N items at once). The system had to handle both shapes uniformly enough to be authored in the inspector.

## Core decisions

### Stable component identity: manual `StringName` IDs

The previous `DartComponent` had no stable identifier — components were referenced by file path or by `component_name`. Both are fragile. Renaming a file or polishing display copy would silently break any save-data reference.

Four ID schemes considered:

- **Godot UIDs (`uid://...`)** — auto-generated, survive file moves. Rejected because save files become opaque hashes, undebuggable, and hand-editing progress files (useful during development) becomes impossible.
- **File path** — already shown fragile.
- **Auto-slug from `component_name`** — breaks on display-name tweaks.
- **Manual `@export var id: StringName`** — chosen. Discipline cost (remembering to set it on every new component) is real but neutralized by `DartComponentRegistry._validate_components()` printing loud `push_error()` lines for empty or duplicate IDs on `_ready()`. Saves stay human-readable (`["barrel_torpedo", "shaft_long_carbon"]`).

Naming convention: slot-prefixed snake_case (`&"barrel_torpedo"`, `&"shaft_long_carbon"`, `&"flight_blue_whisp"`). Slot prefix prevents collisions across the three arrays and surfaces what slot something is for when grepping logs or save files.

Strongly recommended (not enforced): `.tres` filename matches the ID slug. Eases navigation; not required because the ID inside the file is canonical.

**The hard rule: IDs MUST NEVER be changed after a build ships.** Anyone with that ID in their save file would lose their unlock silently. The validator only catches authoring mistakes inside the current codebase, not historical ones. If an ID absolutely must change, a migration step in `PlayerProgress._load()` is the right place — none implemented yet because none has been needed yet.

### Separation of progression from resource definition

Earliest sketch put `unlocked: bool` directly on the `DartComponent` resource and called it done. That bool would need to flip at runtime when the player earned the component. Two paths from there:

- **Mutate the `.tres` file on disk.** Bad — mutates project assets, creates git noise, save/load semantics get weird, can't easily reset for a new player.
- **Override in memory.** Then unlocks don't persist across game restarts, defeating the purpose.

Chosen instead: split static (resource declares the condition) from runtime (player profile owns earned unlocks).

- Resource: `default_unlocked: bool` (starting state for new players) + `unlock_condition: UnlockCondition` (how to earn).
- Player state: `PlayerProgress` autoload holding `unlocked_ids: Dictionary` and `career_stats: Dictionary`, persisted to `user://progress.tres`.

`PlayerProgress.is_unlocked(component)` is the single resolver, combining both. The registry's filter methods consult it; the assembly screen consults it; the unlock manager grants via `PlayerProgress.unlock(component)`.

Side benefit: per-profile progression becomes trivial later — `SAVE_PATH` becomes a property a profile manager can swap.

### Condition representation: subclass per family

The original design list had 15 distinct unlock intents across event types (single throw, single leg, single shop, single run, lifetime career) and shapes (predicate on the winning dart, threshold on a counter, snapshot check on slot state).

Three encodings considered:

- **Single enum + parameter bag.** One condition type with `match` on the enum dispatching to different logic. Compact but loses type safety per family, crowds the inspector with parameters that mean different things in different enum branches.
- **Fully generic context-key threshold check.** Even more abstract. Even worse for inspector authoring.
- **Subclass per condition family.** Chosen. Each subclass has its own focused exported parameters and a clear `is_satisfied()` body. The pattern mirrors the existing `ThrowModifier` system (base Resource + virtual method + `.tres` instances), so the inspector workflow is already familiar to the author.

The six initial subclasses (later seven) map cleanly to the original design list:

- `LegWinHitCondition` — predicates on the winning dart (ring, wedge, score, final-dart-of-leg, off-target, modifier-category-active).
- `LegStatCondition` — leg-aggregate properties (target score, checkout total, all-three-darts-scored).
- `CareerCountCondition` — lifetime counters from `PlayerProgress.career_stats`.
- `RunConstraintCondition` — multi-leg with run-scoped flags (e.g., commons-only).
- `ShopAcquisitionCondition` — counter scoped to a single shop visit.
- `SlotsFilledCondition` — snapshot of streak category occupancy.
- `RelicCountCondition` — count of active RELIC modifiers (added late, see below).

### Event model: broadcast + filter

Conditions implement `is_satisfied(event_name: StringName, context: Dictionary) -> bool`. The `UnlockManager` autoload listens for game events, builds the right context dictionary, and walks every locked component's condition. Each subclass early-returns on events it doesn't care about.

Considered the alternative of having each subclass *declare* the events it cares about (a `relevant_events: Array[StringName]` field on the base) and dispatching only to subscribers. Rejected as premature optimization — the locked component pool is small (10–15 at most), and the broadcast model keeps the subclasses simpler. Revisit if perf is ever a real concern.

### Slot semantics resolution: drop "all modifier slots," add `RelicCountCondition`

Recipe 9 in the original design list was "Fill all modifier slots." The codebase has 3 enforced slot categories (streak: WEDGE / COLOR / PARITY) but no fixed cap on other modifier types — `ColorBonus`, `OddEvenBonus`, etc. can stack freely. So "fill all modifier slots" had no concrete meaning.

Initial spec deferred it as an open question: `SlotsFilledCondition` was given an enum (`All streak categories` / `All modifier slots`) with the latter inert (`all_modifier_slots_filled` hardcoded to `false`) pending future slot-cap design.

After review, that complexity didn't earn its keep. Recipe 9 was reshaped to "Hold at least 6 RELIC items at once" via a new `RelicCountCondition` that listens on `item_acquired` and reads `active_relic_count` from the context. `SlotsFilledCondition` simplified to a single-purpose check on streak categories — no enum, no field configuration.

The per-category cap design (a single color-bonus slot, a single parity-bonus slot, etc.) is preserved as a future extension. When it lands, `RelicCountCondition` remains useful for "amass" milestones, and new subclasses can target specific category caps.

### `winning_turn_all_darts_scored`: strict interpretation

Initial implementation computed this as `_turn_darts_scored == x01_game.darts_this_turn`, meaning "every dart you threw this turn scored." That passes for 1-dart and 2-dart finishes (where the dart that scored *was* every dart thrown).

The original design intent ("Complete a 3 dart checkout — all darts must score") wanted the strict reading: 3 darts thrown, all 3 scored. Fixed to `_turn_darts_scored == 3 and x01_game.darts_this_turn == 3` so a 1-dart or 2-dart finish never qualifies.

Worth flagging because the spec was the source of ambiguity — context-key naming should pick a side and be precise.

### UI: silhouettes in assembly, queued toast notifications

The assembly screen renders locked components as silhouettes (texture dimmed via `modulate = Color(0.3, 0.3, 0.3)`), name replaced with "[Locked]", and `unlock_condition.description` shown in muted grey (#888888) where the stat tooltip would otherwise live. Browseable but not equippable.

Considered hiding locked components entirely. Rejected — the player should know progression exists. Considered always-visible "???" silhouettes with no texture. Rejected — the silhouette image teases what the player could earn, which is a stronger pull than a generic placeholder.

Notifications: a `UnlockNotificationQueue` `Control` listens on `PlayerProgress.component_unlocked` and renders a sliding toast. Critical detail: the queue is real. A single leg-win event can satisfy multiple conditions at once (e.g., a clutch double-bullseye win that's also the player's 5th career leg). The queue plays each notification sequentially with slide-in / display / slide-out tweens.

Lock icon overlay deferred — current visual treatment communicates lock state through dim + grey + text. A dedicated lock sprite would add polish without changing the model. Tracked as "nice to have" in the verification report; not a blocker.

### Shell files for new locked content

Max had created several empty `.tres` files for forthcoming new components (just PNG references, no stats yet). Two options:

- **Delete them, system pass is system-only.** Clean separation, but the system pass would land with no locked components to test against. End-to-end verification would require Max creating components afterward.
- **Have Claude Code create empty shell files in the right locations as part of the system pass.** Bundles system + content scaffolding while keeping every design decision (stats, names, balance) with Max.

Went with the second. Nine shell files (`_unfilled_barrel_{1,2,3}.tres`, `_unfilled_shaft_{1,2,3}.tres`, `_unfilled_flight_{1,2,3}.tres`) with `default_unlocked = false`, empty IDs, and correct `component_type` per slot. Critical rule: shells are NOT added to `DartComponentRegistry`'s arrays — the validator would refuse to start the game (empty ID, locked-without-condition). Max drags each into the registry as he fills it in; registration is the "ready" signal.

The `_unfilled_` filename prefix sorts these to the top of their folders for visibility. When Max fills a shell in, he renames it to match the final ID slug.

## Deferred items

- **Per-category caps on non-streak RELIC modifiers** (color slot, parity-bonus slot, etc.). `RelicCountCondition` is the coarse stand-in for "lots of items" milestones until then.
- **Lock icon sprite overlay on the assembly screen.** Current grey/dim treatment communicates state adequately; the icon is polish.
- **Stable IDs on `ScoringModifier` and `ThrowModifier`.** Same `id: StringName` pattern, useful when those need save data, item-history tracking, or their own unlock conditions. Copy the pattern when needed. Don't extract a shared base class until at least two of them need it.
- **Per-profile progression.** Currently global. `PlayerProgress` is structured so swapping `SAVE_PATH` for a per-profile path is a one-line change.
- **Save format migration handling.** `PlayerProgress._load()` currently just reads or returns empty. If the save format ever needs to change, add versioning and migration there.

## Open questions still standing after this pass

These were tagged elsewhere in `DesignNotes.md` and remain unresolved:

- The shop's relationship to dart components — locked components are intentionally NOT acquired through the shop today (Max's call). When/if dart-component-as-shop-item ships, the system already supports it: call `UnlockManager.on_item_acquired({"rarity": ..., "active_relic_count": ...})` after the acquisition.
- Run-end interaction with the shop (broader open question, not unlock-specific).
- Whether the `legs_won` lifetime counter eventually needs companions (`runs_completed`, `runs_lost`, etc.) for richer career milestones. Trivial to add via `PlayerProgress.increment_stat(&"runs_completed", 1)` when that becomes useful.

## Cross-references

- Living developer guide: `DartComponentGuide.md` (architecture, all subclass definitions, integration points, how to add new components).
- Recipe cookbook: `UnlockConditionRecipes.md` (one section per unlock intent from the original design list).
- Throw modifier system (the pattern this mirrors): `ThrowModifierGuide.txt`.
- Design memory entries: `project_dart_game_concept`, `project_component_philosophy`, `project_open_questions` (the meta-progression item now reflects this pass as partial resolution).
