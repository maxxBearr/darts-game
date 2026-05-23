# DartComponent System & Unlock Conditions — Implementation Spec

> **Status:** Spec — implementation pending.
> When the implementation lands, strip this status line and treat the rest of the file as the living developer guide.

## Overview

A `DartComponent` is a single dart part (barrel / shaft / flight) the player equips on the assembly screen. Each component carries stat bonuses, a weight contribution, an optional `ThrowModifier` ability, and — new in this spec — an optional `UnlockCondition` describing how the player earns it. Locked components do not appear in the assembly screen part-picker until their condition is satisfied; satisfaction is detected at runtime by a central `UnlockManager` listening to game events.

This spec covers three coupled changes:

1. **A stable identity system** for `DartComponent` (the `id: StringName` field and naming/validation rules), so save data referencing components survives file moves and renames.
2. **A `PlayerProgress` autoload** that owns the player's unlock state, separated cleanly from the resource definitions themselves.
3. **An `UnlockCondition` resource hierarchy** (mirroring `ThrowModifier`) plus the `UnlockManager` autoload that evaluates conditions and grants unlocks.

The throw modifier system (`ThrowModifierGuide.txt`) is the pattern this mirrors. If you've read that, this should feel familiar.

---

## Implementation Scope & Acceptance

### In scope for this implementation pass

- All system code: the `id` field migration on existing `DartComponent` resources, the `PlayerProgress` autoload, the `UnlockManager` autoload, the `UnlockCondition` base + all six subclasses, registry validation, the integration calls in `main.gd` / `scoring_modifier_manager.gd` / shop scripts, the assembly-screen locked-state rendering, and the unlock notification queue.
- Empty "shell" `.tres` files for new locked components — three per slot (barrel / shaft / flight) — placed in their respective folders so Max can fill in design values later. See [section 14](#14-shell-files-for-new-locked-components-content-deferred-to-max) for the exact recipe.

### Out of scope (Max handles separately)

- Stat values, weights, names, descriptions, textures, rarity tiers, throw_modifier links, and unlock_condition links for the new locked components. These get filled in by Max via the Godot inspector after the system lands, following the section 10 checklist.
- Adding the new components to the `DartComponentRegistry` arrays. Max drags them in once each one is filled out — registration is the "ready" signal.
- New `UnlockCondition` `.tres` instances tuned to specific components. Max creates these alongside the component design work.

### Acceptance criteria

The implementation is done when all of the following are true:

1. The game starts cleanly with no `DartComponentRegistry` validation errors against existing components.
2. Every existing dart component has a unique non-empty `id` matching the migration table in section 2; the field formerly known as `unlocked` is now `default_unlocked` and remains `true` on every existing component.
3. The `PlayerProgress` autoload persists to `user://progress.tres` across game restarts (`unlocked_ids` and `career_stats` both survive). Verifiable by manually calling `PlayerProgress.unlock(component)` from a debug shortcut and confirming the unlock survives a restart.
4. The `UnlockManager` autoload is registered, receives `bind_registry()` from `main.gd`, and fires all five event entry methods at the integration points listed in section 8.
5. Locked components (any shell that has been filled in by Max and added to the registry with `default_unlocked = false`) render greyed-out with a lock icon and the `unlock_condition.description` shown in muted grey on the assembly screen part-picker.
6. When `PlayerProgress.component_unlocked` fires, the notification queue displays a toast with the component thumbnail and name, and queues additional unlocks behind it if multiple fire at once.
7. The shell `.tres` files exist at the paths specified in section 14, are NOT added to the registry arrays, and the game continues to run cleanly with them present.

End-to-end test path Claude Code should execute before declaring done: temporarily fill in one shell with a stat block, a `LegWinHitCondition` requiring a double bullseye, and drag it into the registry. Start a new game, win a leg on a double bullseye, observe (a) the notification fires, (b) the component is selectable on the next assembly screen visit, (c) `user://progress.tres` contains the new ID. Then revert the test shell back to empty.

---

## 1. The ID System — Critical Rules

Every `DartComponent` gets a stable `id: StringName` field that uniquely identifies it for save data, statistics, and unlock tracking. **Read this section carefully before adding any new component.**

### Rules

- **Every component MUST have a non-empty `id`.** No exceptions. The registry will assert this on load and refuse to start the game if any component has an empty ID.
- **IDs MUST be unique across all three slots** (barrels, shafts, flights). Use the slot prefix convention below and you will not collide.
- **IDs MUST NEVER be changed after release.** Once a build has shipped, that ID is in players' save files forever. Changing it orphans their unlocks. Display names and descriptions are free to change; the ID is not.
- **IDs are NOT the filename or the display name.** They are their own field, stored inside the `.tres`.

### Naming convention

Slot-prefixed snake_case lowercase `StringName`:

```
&"barrel_torpedo"
&"barrel_ole_reliable"
&"shaft_long_carbon"
&"shaft_medium_aluminum"
&"flight_blue_whisp"
&"flight_wide_sail"
```

Prefix is the slot name (`barrel_`, `shaft_`, `flight_`). The rest is a short, descriptive slug derived from the component's intent — not its current display name (display names drift; IDs do not).

### Filename convention (strongly recommended)

The `.tres` filename SHOULD match the ID slug. So a component with `id = &"barrel_torpedo"` lives at `res://resources/dart_components/barrels/barrel_torpedo.tres`. This is not enforced by code — the ID inside the file is the source of truth — but it makes grepping, navigating, and code review dramatically easier.

If you ever rename a file, the ID inside stays the same; saves keep working.

### Validation (enforced at runtime)

`DartComponentRegistry._ready()` calls `_validate_components()` which:

1. Iterates every component across all three arrays.
2. `push_error()` if any component has an empty `id`.
3. `push_error()` if any two components share an `id`.
4. `push_error()` if any component has `default_unlocked = false` AND `unlock_condition = null` (would be permanently unobtainable).

Errors print loudly in red in the Godot debugger. Fix them before committing.

---

## 2. `DartComponent` — Updated Fields

Modify `res://scripts/dart_components/dart_component.gd`:

### Field changes

- **ADD** `@export var id: StringName = &""` near the top of the file. Description: stable identity for save data and unlock tracking. Read the ID Rules section before assigning.
- **RENAME** the existing `@export var unlocked: bool = true` to `@export var default_unlocked: bool = true`. Description: whether this component is unlocked from the start (true) or must be earned through its `unlock_condition` (false). Most existing components stay `true`.
- **ADD** `@export var unlock_condition: UnlockCondition` (defaults to null). Description: if `default_unlocked` is false, this resource describes how the player earns the component. Leave null for default-unlocked components.

### Full field list after changes

```gdscript
class_name DartComponent
extends Resource

## Stable identity for save data and unlock tracking. Slot-prefixed snake_case.
## Examples: &"barrel_torpedo", &"shaft_long_carbon", &"flight_blue_whisp".
## MUST be non-empty and unique across all components. NEVER change after release.
@export var id: StringName = &""

## Display name shown in the assembly screen and tooltips.
@export var component_name: String = ""

## Player-facing description shown in the assembly screen detail panel.
@export var description: String = ""

## Which slot this part fits in.
@export var component_type: ScoringEnums.ComponentSlot = ScoringEnums.ComponentSlot.BARREL

## Directional balance contribution. Negative = front-heavy, Positive = back-heavy.
@export_range(-1.0, 1.0, 0.01) var weight: float = 0.0

@export var rarity_tier: ScoringEnums.Rarity = ScoringEnums.Rarity.COMMON

## Whether this component is unlocked from the start of a new save file.
## Set to false for progression-locked components — pair with an unlock_condition.
@export var default_unlocked: bool = true

## How the player earns this component if default_unlocked is false.
## Leave null for default-unlocked components. Setting default_unlocked = false
## with a null unlock_condition makes the component permanently unobtainable —
## the registry will push_error() on load.
@export var unlock_condition: UnlockCondition

@export var texture: Texture2D

## --- Stat Modifiers (all default 0.0, only non-zero values appear in tooltips) ---
@export var h_range_bonus: float = 0.0
@export var v_range_bonus: float = 0.0
@export var h_speed_bonus: float = 0.0
@export var v_speed_bonus: float = 0.0
@export var h_accuracy_bonus: float = 0.0
@export var v_accuracy_bonus: float = 0.0

## Optional throw modifier ability. See ThrowModifierGuide.txt.
@export var throw_modifier: ThrowModifier

## Dart marker outer/inner colors used by flights to theme the on-board dart.
@export var dart_outer_color: Color = Color(0.9, 0.85, 0.0)
@export var dart_inner_color: Color = Color(0.2, 0.2, 0.2)
```

Keep the existing `get_tooltip_lines()`, `get_bbcode_tooltip()`, and the `rarity_name` / `rarity_color` properties.

### Migration of existing `.tres` files

Every existing dart component `.tres` needs an `id` field added. Suggested mapping (use the existing filename as the seed):

```
resources/dart_components/barrels/ole_reliable.tres   → id = &"barrel_ole_reliable"
resources/dart_components/barrels/torpedo.tres        → id = &"barrel_torpedo"
resources/dart_components/barrels/laid_back.tres      → id = &"barrel_laid_back"
resources/dart_components/barrels/barrel-medium.tres  → id = &"barrel_medium"
resources/dart_components/barrels/barrel-short.tres   → id = &"barrel_short"
resources/dart_components/barrels/barrel-long.tres    → id = &"barrel_long"
resources/dart_components/shafts/long_carbon.tres     → id = &"shaft_long_carbon"
resources/dart_components/shafts/medium_aluminum.tres → id = &"shaft_medium_aluminum"
resources/dart_components/shafts/shaft_3.tres         → id = &"shaft_3"   (rename to a real slug when you have one)
resources/dart_components/shafts/shaft_4.tres         → id = &"shaft_4"
resources/dart_components/shafts/shaft_5.tres         → id = &"shaft_5"
resources/dart_components/flights/blue_whisp.tres     → id = &"flight_blue_whisp"
resources/dart_components/flights/wide_sail.tres      → id = &"flight_wide_sail"
resources/dart_components/flights/flight_2.tres       → id = &"flight_2"   (rename to a real slug)
resources/dart_components/flights/flight_3.tres       → id = &"flight_3"
```

All existing files keep `default_unlocked = true` (the renamed-from `unlocked` field). The newly-added components Max mentioned go in with `default_unlocked = false` and an `unlock_condition` set.

---

## 3. `PlayerProgress` Autoload

A persistent singleton that owns the player's unlock state. Lives at `res://scripts/player_progress.gd` and is registered as an autoload named `PlayerProgress`.

```gdscript
extends Node
## Persistent player progression state. Tracks unlocked component IDs and
## career statistics used by unlock conditions. Saved to user://progress.tres.

## Path to the save file on disk.
const SAVE_PATH: String = "user://progress.tres"

## Set of component IDs the player has unlocked.
## Stored as a Dictionary for O(1) lookup. Keys are StringNames, values are true.
var unlocked_ids: Dictionary = {}

## Career counters used by CareerCountCondition.
## Examples: "legs_won", "runs_completed", "max_checkout_ever".
## Increment via increment_stat() and read via get_stat().
var career_stats: Dictionary = {}

## Emitted when a component transitions from locked to unlocked.
## The UI uses this to queue the unlock notification.
signal component_unlocked(component: DartComponent)


func _ready() -> void:
    _load()


## Check whether the player has access to a component.
## Combines the resource's default_unlocked flag with earned unlocks.
func is_unlocked(component: DartComponent) -> bool:
    if component.default_unlocked:
        return true
    return unlocked_ids.has(component.id)


## Grant an unlock. No-op if already unlocked. Saves immediately and emits signal.
func unlock(component: DartComponent) -> void:
    if is_unlocked(component):
        return
    unlocked_ids[component.id] = true
    _save()
    component_unlocked.emit(component)


## Read a career stat. Returns 0 if never set.
func get_stat(stat_name: StringName) -> int:
    return career_stats.get(stat_name, 0)


## Increment a career stat by `amount` (default 1). Saves immediately.
func increment_stat(stat_name: StringName, amount: int = 1) -> void:
    career_stats[stat_name] = career_stats.get(stat_name, 0) + amount
    _save()


## Set a career stat to a specific value if it exceeds the current value.
## Used for "highest checkout ever" style stats. Saves if updated.
func set_stat_max(stat_name: StringName, value: int) -> void:
    var current: int = career_stats.get(stat_name, 0)
    if value > current:
        career_stats[stat_name] = value
        _save()


## Save state to user://progress.tres.
func _save() -> void:
    var data: Dictionary = {
        "unlocked_ids": unlocked_ids,
        "career_stats": career_stats,
    }
    var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if save_file == null:
        push_error("PlayerProgress: failed to open %s for writing" % SAVE_PATH)
        return
    save_file.store_var(data)
    save_file.close()


## Load state from user://progress.tres. Creates an empty state if file is missing.
func _load() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
    if save_file == null:
        return
    var data: Variant = save_file.get_var()
    save_file.close()
    if data is Dictionary:
        unlocked_ids = data.get("unlocked_ids", {})
        career_stats = data.get("career_stats", {})
```

### Register in `project.godot`

Add under the `[autoload]` section, after `AuidoManager`:

```
PlayerProgress="*res://scripts/player_progress.gd"
```

---

## 4. `DartComponentRegistry` Updates

Modify `res://scripts/dart_component_registry.gd`:

### Validation in `_ready()`

```gdscript
func _ready() -> void:
    _validate_components()


## Assert that every component has a non-empty unique ID, and that no component
## is permanently unobtainable. Errors are printed via push_error() so they show
## up loudly in the debugger.
func _validate_components() -> void:
    var seen_ids: Dictionary = {}
    var all_parts: Array[DartComponent] = []
    all_parts.append_array(barrels)
    all_parts.append_array(shafts)
    all_parts.append_array(flights)

    for part: DartComponent in all_parts:
        if part == null:
            continue

        # Empty ID check
        if part.id == &"" or part.id == &" ":
            push_error("DartComponentRegistry: component '%s' has empty id"
                % part.component_name)
            continue

        # Duplicate ID check
        if seen_ids.has(part.id):
            push_error("DartComponentRegistry: duplicate id '%s' on '%s' and '%s'"
                % [part.id, seen_ids[part.id], part.component_name])
        else:
            seen_ids[part.id] = part.component_name

        # Permanently unobtainable check
        if not part.default_unlocked and part.unlock_condition == null:
            push_error("DartComponentRegistry: '%s' is locked but has no unlock_condition — permanently unobtainable"
                % part.component_name)
```

### Filter methods consult `PlayerProgress`

Replace the existing `get_unlocked_X()` methods:

```gdscript
func get_unlocked_barrels() -> Array[DartComponent]:
    return _filter_unlocked(barrels)


func get_unlocked_shafts() -> Array[DartComponent]:
    return _filter_unlocked(shafts)


func get_unlocked_flights() -> Array[DartComponent]:
    return _filter_unlocked(flights)


## Internal: return only the components the player has access to.
## A component is accessible if default_unlocked OR PlayerProgress has its id.
func _filter_unlocked(parts: Array[DartComponent]) -> Array[DartComponent]:
    var result: Array[DartComponent] = []
    for part: DartComponent in parts:
        if part == null:
            continue
        if PlayerProgress.is_unlocked(part):
            result.append(part)
    return result
```

### Helper: get all locked components

For the `UnlockManager` to know which conditions to evaluate, add:

```gdscript
## Return all components the player has NOT yet unlocked. Used by UnlockManager
## to know which unlock_conditions to test against game events.
func get_locked_components() -> Array[DartComponent]:
    var result: Array[DartComponent] = []
    var all_parts: Array[DartComponent] = []
    all_parts.append_array(barrels)
    all_parts.append_array(shafts)
    all_parts.append_array(flights)
    for part: DartComponent in all_parts:
        if part == null:
            continue
        if not PlayerProgress.is_unlocked(part) and part.unlock_condition != null:
            result.append(part)
    return result
```

---

## 5. `UnlockCondition` Base Resource

New file: `res://scripts/unlock_conditions/unlock_condition.gd`.

```gdscript
class_name UnlockCondition
extends Resource
## Base class for dart component unlock conditions. Subclass this and override
## is_satisfied() to define a new unlock trigger.
##
## Conditions are evaluated by UnlockManager when relevant game events fire.
## They receive an event name and a context dictionary populated by the
## event source (leg_won → x01_game; item_acquired → scoring_modifier_manager; etc.).
##
## The base implementation returns false so any forgotten subclass is silently
## inert rather than spuriously unlocking.

## Player-facing hint shown on locked components in the assembly screen.
## Keep it short and directive, written in second person.
## Examples:
##   "Win a leg on a double bullseye."
##   "Checkout from over 100."
##   "Win 5 legs total."
@export_multiline var description: String = ""


## Override in subclasses. Return true if the condition is met.
##
## event_name is a StringName naming the event that fired. Subclasses should
## early-return false for events they don't care about.
##
## context is a Dictionary populated by the event source. Each event has its
## own set of keys — see UnlockManager event documentation in section 7.
func is_satisfied(_event_name: StringName, _context: Dictionary) -> bool:
    return false
```

---

## 6. `UnlockCondition` Subclasses

Six subclasses cover every condition in the design list. Each goes in `res://scripts/unlock_conditions/`. The `.tres` instances go in `res://resources/unlock_conditions/{slot}/` so unlock data sits next to the dart components it concerns.

### 6a. `LegWinHitCondition`

Predicates on the winning dart itself.

`res://scripts/unlock_conditions/leg_win_hit_condition.gd`:

```gdscript
class_name LegWinHitCondition
extends UnlockCondition
## Triggered on leg_won. Checks properties of the winning dart.
## All filters are independent; set the ones you want, leave the rest at
## their "any" defaults.

## Required ring of the winning dart. Empty string = any double counts.
## Valid values: "Double", "Double Bull".
@export var required_ring: String = ""

## Required wedge face value of the winning dart.
## 0 = any, 25 = bullseye, 1-20 = a specific wedge number.
@export_range(0, 25, 1) var required_wedge_value: int = 0

## Minimum score of the winning dart (after modifiers). 0 = no minimum.
## Use 51 for "double scoring higher than 50", 101 for "higher than 100".
@export var min_winning_dart_score: int = 0

## Filter on whether the winning dart was the last possible dart of the leg
## (final turn, third dart). 0 = any, 1 = must be final, 2 = must NOT be final.
@export_enum("Any", "Must be final", "Must not be final") var final_dart_mode: int = 0

## Filter on whether a scoring modifier of a certain category was active on
## the winning hit. Empty = any. Use "streak" to require a streak modifier
## active on the winning dart.
@export var required_modifier_category: String = ""

## Filter on whether the winning dart hit a wedge the player was NOT aiming at.
## 0 = any, 1 = must be off-target, 2 = must be on-target.
@export_enum("Any", "Must be off-target", "Must be on-target") var target_mode: int = 0


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
    if event_name != &"leg_won":
        return false

    var winning_ring: String = context.get("winning_ring", "")
    var winning_value: int = context.get("winning_wedge_value", 0)
    var winning_score: int = context.get("winning_score", 0)
    var was_final: bool = context.get("was_final_possible_dart", false)
    var modifier_cats: Array = context.get("winning_modifier_categories", [])
    var was_on_target: bool = context.get("was_winning_dart_on_target", true)

    if required_ring != "" and winning_ring != required_ring:
        return false
    if required_wedge_value > 0 and winning_value != required_wedge_value:
        return false
    if min_winning_dart_score > 0 and winning_score < min_winning_dart_score:
        return false
    if final_dart_mode == 1 and not was_final:
        return false
    if final_dart_mode == 2 and was_final:
        return false
    if required_modifier_category != "" and not modifier_cats.has(required_modifier_category):
        return false
    if target_mode == 1 and was_on_target:
        return false
    if target_mode == 2 and not was_on_target:
        return false

    return true
```

Covers from the design list: "double bullseye", "win on final dart", "win on streak-modified double", "win on double > 50 / > 100", "win on non-target double".

### 6b. `LegStatCondition`

Predicates on the leg as a whole (target value, checkout sum, three-dart-scoring).

`res://scripts/unlock_conditions/leg_stat_condition.gd`:

```gdscript
class_name LegStatCondition
extends UnlockCondition
## Triggered on leg_won. Checks aggregate properties of the leg.

## Required target score for the leg. 0 = any. Use 501 for "win 501".
@export var required_target_score: int = 0

## Minimum sum of the winning turn (the "checkout total").
## 0 = no minimum. Use 101 for "checkout from over 100".
@export var min_checkout_total: int = 0

## If true, all three darts of the winning turn must have scored (none missed
## the board, none busted). Used for "3-dart checkout, all darts must score".
@export var require_three_scoring_darts: bool = false


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
    if event_name != &"leg_won":
        return false

    var target: int = context.get("target_score", 0)
    var checkout_total: int = context.get("checkout_total", 0)
    var three_scored: bool = context.get("winning_turn_all_darts_scored", false)

    if required_target_score > 0 and target != required_target_score:
        return false
    if min_checkout_total > 0 and checkout_total < min_checkout_total:
        return false
    if require_three_scoring_darts and not three_scored:
        return false

    return true
```

Covers: "Win 501", "Checkout from over 100", "3-dart checkout, all darts must score".

### 6c. `CareerCountCondition`

Threshold on a `PlayerProgress.career_stats` counter.

`res://scripts/unlock_conditions/career_count_condition.gd`:

```gdscript
class_name CareerCountCondition
extends UnlockCondition
## Triggered on any event. Checks a PlayerProgress career stat against a
## threshold. Useful for lifetime counters like "win 5 legs total."

## Stat name to read from PlayerProgress.career_stats.
## Common values: &"legs_won", &"runs_completed", &"max_checkout_ever".
@export var stat_name: StringName = &""

## Threshold the stat must reach. Inclusive (>=).
@export var threshold: int = 1


func is_satisfied(_event_name: StringName, _context: Dictionary) -> bool:
    if stat_name == &"":
        return false
    return PlayerProgress.get_stat(stat_name) >= threshold
```

Covers: "Win 5 legs", "Win 10 legs", and any future "Xn lifetime" conditions.

### 6d. `RunConstraintCondition`

Multi-leg constraint within a single run (legs won so far + a constraint flag).

`res://scripts/unlock_conditions/run_constraint_condition.gd`:

```gdscript
class_name RunConstraintCondition
extends UnlockCondition
## Triggered on leg_won. Checks how many legs have been won this RUN, while
## a run-scoped constraint flag remained satisfied.
##
## Run-scoped flags are tracked by UnlockManager and reset on run_started.

## Minimum legs won this run.
@export var legs_won_this_run_threshold: int = 1

## If non-empty, the named flag on UnlockManager must be true for this
## condition to count. Examples:
##   &"only_commons_acquired_this_run" — no uncommon/rare items acquired.
@export var required_run_flag: StringName = &""


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
    if event_name != &"leg_won":
        return false

    var legs_this_run: int = context.get("legs_won_this_run", 0)
    if legs_this_run < legs_won_this_run_threshold:
        return false

    if required_run_flag != &"":
        if not UnlockManager.get_run_flag(required_run_flag):
            return false

    return true
```

Covers: "Win 5 legs with only common items."

### 6e. `ShopAcquisitionCondition`

Counter scoped to a single shop visit.

`res://scripts/unlock_conditions/shop_acquisition_condition.gd`:

```gdscript
class_name ShopAcquisitionCondition
extends UnlockCondition
## Triggered on shop_closed. Checks how many items the player acquired during
## the just-closed shop visit.

@export var min_items_acquired: int = 1


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
    if event_name != &"shop_closed":
        return false
    var count: int = context.get("items_acquired_this_shop", 0)
    return count >= min_items_acquired
```

Covers: "Acquire 10 items during a single shop."

### 6f. `SlotsFilledCondition`

Snapshot check on current slot state.

`res://scripts/unlock_conditions/slots_filled_condition.gd`:

```gdscript
class_name SlotsFilledCondition
extends UnlockCondition
## Triggered on slots_state_changed. Checks whether a specific slot category
## is fully populated.

## Which slot grouping to test. See UnlockManager for what each value checks.
@export_enum("All streak categories", "All modifier slots") var target_slots: int = 0


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
    if event_name != &"slots_state_changed":
        return false

    match target_slots:
        0:  # All streak categories
            return context.get("all_streak_categories_filled", false)
        1:  # All modifier slots
            return context.get("all_modifier_slots_filled", false)
    return false
```

Covers: "Fill all modifier slots", "Fill all streak slots".

> **OPEN QUESTION FOR MAX:** the codebase has 3 streak categories (`WEDGE`, `COLOR`, `PARITY`) — those are unambiguously "all streak slots." But "modifier slots" doesn't have a current fixed count — `active_modifiers` grows freely. Before this subclass is built, decide: is "all modifier slots" referring to a future slot cap system, or is it shorthand for "all streak categories" (in which case the second enum value is unused)? Spec assumes the former and leaves a flag for it; the event source can leave `all_modifier_slots_filled` permanently false until the slot cap exists.

---

## 7. `UnlockManager` Autoload

Central coordinator. Listens to game events, builds the right context dictionary, walks locked components, and grants unlocks.

New file: `res://scripts/unlock_manager.gd`. Register as autoload `UnlockManager` after `PlayerProgress`.

```gdscript
extends Node
## Central unlock coordinator. Listens for game events, evaluates each locked
## component's UnlockCondition, and grants unlocks via PlayerProgress.
##
## Owns run-scoped and shop-scoped state that conditions need to evaluate:
## items_acquired_this_shop counter, only_commons_this_run flag, etc.

## --- Run-scoped state (reset on run_started) ---

var _legs_won_this_run: int = 0
var _run_flags: Dictionary = {}  # StringName -> bool

## --- Shop-scoped state (reset on shop_opened) ---

var _items_acquired_this_shop: int = 0

## --- Dependency: the component registry. Assigned by main.gd at startup. ---
var registry: DartComponentRegistry


## Bootstrap from main.gd: pass in the registry instance so we can walk it.
func bind_registry(r: DartComponentRegistry) -> void:
    registry = r


## --- Event entry points ---
## Each public on_X method below corresponds to one game event. They build the
## context dictionary, update internal state, then call _evaluate(event_name).

## Called by x01_game (via main.gd) when is_leg_won = true.
## leg_context is the dictionary returned by x01_game.process_throw(),
## enriched with winning-dart metadata by main.gd before this call.
func on_leg_won(leg_context: Dictionary) -> void:
    _legs_won_this_run += 1
    PlayerProgress.increment_stat(&"legs_won", 1)

    var checkout_total: int = leg_context.get("checkout_total", 0)
    if checkout_total > 0:
        PlayerProgress.set_stat_max(&"max_checkout_ever", checkout_total)

    var context: Dictionary = leg_context.duplicate()
    context["legs_won_this_run"] = _legs_won_this_run

    _evaluate(&"leg_won", context)


## Called when the player acquires any item (modifier or component).
## item_context: { "rarity": ScoringEnums.Rarity }
func on_item_acquired(item_context: Dictionary) -> void:
    _items_acquired_this_shop += 1

    var rarity: int = item_context.get("rarity", ScoringEnums.Rarity.COMMON)
    if rarity != ScoringEnums.Rarity.COMMON:
        _run_flags[&"only_commons_acquired_this_run"] = false

    _evaluate(&"item_acquired", item_context)


## Called when the shop opens.
func on_shop_opened() -> void:
    _items_acquired_this_shop = 0


## Called when the shop closes.
func on_shop_closed() -> void:
    var context: Dictionary = {
        "items_acquired_this_shop": _items_acquired_this_shop,
    }
    _evaluate(&"shop_closed", context)


## Called when streak slot state or modifier slot state changes.
## slot_context provides the snapshot keys SlotsFilledCondition reads.
func on_slots_state_changed(slot_context: Dictionary) -> void:
    _evaluate(&"slots_state_changed", slot_context)


## Called by main.gd at the start of every run. Resets run-scoped state.
func on_run_started() -> void:
    _legs_won_this_run = 0
    _run_flags.clear()
    # Optimistic-by-default: assume the constraint holds until violated.
    _run_flags[&"only_commons_acquired_this_run"] = true


## Read a run-scoped flag. Returns false if never set.
func get_run_flag(flag_name: StringName) -> bool:
    return _run_flags.get(flag_name, false)


## --- Internal evaluation ---

## Walk every locked component and grant any whose condition is satisfied.
func _evaluate(event_name: StringName, context: Dictionary) -> void:
    if registry == null:
        return

    var locked: Array[DartComponent] = registry.get_locked_components()
    for component: DartComponent in locked:
        if component.unlock_condition == null:
            continue
        if component.unlock_condition.is_satisfied(event_name, context):
            PlayerProgress.unlock(component)
```

### Event context reference

The full set of keys each event provides. Event sources are responsible for populating these; conditions read them.

**`leg_won`** (built by `main.gd` from `x01_game.process_throw()` result):

| Key | Type | Source |
|-----|------|--------|
| `target_score` | int | `x01_game.target_score` |
| `winning_ring` | String | last dart's `ring_name` |
| `winning_wedge_value` | int | last dart's `face_value` |
| `winning_score` | int | last dart's `total_score` (post-modifiers) |
| `was_final_possible_dart` | bool | `current_turn == max_turns and darts_this_turn == 3` |
| `winning_modifier_categories` | Array[String] | categories of modifiers that fired on the winning dart (e.g., `["streak"]`) |
| `was_winning_dart_on_target` | bool | did the dart hit the wedge the player was aiming at |
| `checkout_total` | int | sum of points scored in the winning turn |
| `winning_turn_all_darts_scored` | bool | every dart this turn produced `total_score > 0` |
| `legs_won_this_run` | int | populated by UnlockManager itself |

**`item_acquired`**:

| Key | Type |
|-----|------|
| `rarity` | ScoringEnums.Rarity |

**`shop_closed`**:

| Key | Type |
|-----|------|
| `items_acquired_this_shop` | int |

**`slots_state_changed`**:

| Key | Type | Meaning |
|-----|------|---------|
| `all_streak_categories_filled` | bool | one streak modifier per `StreakCategory.WEDGE`, `COLOR`, and `PARITY` is active |
| `all_modifier_slots_filled` | bool | reserved for future slot-cap system; leave false for now |

---

## 8. Integration points in existing files

### `main.gd`

- On run start, call `UnlockManager.bind_registry(<the registry instance>)` once.
- On run start, call `UnlockManager.on_run_started()`.
- After processing each throw, if the result has `is_leg_won == true`, build the `leg_context` dictionary (using the keys above) and call `UnlockManager.on_leg_won(leg_context)`. The winning dart's ring/value/score/modifier-categories come from the dartboard result + modifier pipeline; `was_final_possible_dart` is computed inline; `was_winning_dart_on_target` reads from the throw mechanic's last-aim-point vs. last-hit-wedge comparison; `checkout_total` and `winning_turn_all_darts_scored` are tracked by main.gd across the three darts of the turn.

### `scoring_modifier_manager.gd`

- After `add_modifier()` succeeds, call `UnlockManager.on_item_acquired({"rarity": modifier.rarity_tier})`.
- After `add_modifier()` finishes, if it changed streak slot occupancy, call `UnlockManager.on_slots_state_changed(_build_slots_context())` where `_build_slots_context()` returns:
  ```gdscript
  func _build_slots_context() -> Dictionary:
      var categories: Dictionary = {}
      for m: Resource in active_modifiers:
          if m is ScoringModifier and m.streak_category != ScoringEnums.StreakCategory.NONE:
              categories[m.streak_category] = true
      var all_streak: bool = (
          categories.has(ScoringEnums.StreakCategory.WEDGE)
          and categories.has(ScoringEnums.StreakCategory.COLOR)
          and categories.has(ScoringEnums.StreakCategory.PARITY)
      )
      return {
          "all_streak_categories_filled": all_streak,
          "all_modifier_slots_filled": false,  # placeholder until slot cap exists
      }
  ```

### Shop scripts

- Whatever controller manages the shop scene: call `UnlockManager.on_shop_opened()` when opening, `UnlockManager.on_shop_closed()` when closing. If the shop also issues dart components in the future, call `on_item_acquired` for those acquisitions too.

---

## 9. UI — Locked state & unlock notification

### Assembly screen — locked component display

When the assembly screen part-picker renders a locked component (anything in the full `barrels` / `shafts` / `flights` arrays but NOT in `get_unlocked_X()`):

- Show the slot in a greyed/silhouetted state — texture tinted dark, no stat readouts.
- Show a small lock icon overlay on the slot.
- In the detail panel area (where the description normally lives), display the `unlock_condition.description` string in a muted grey color. Prefix with "Locked — " or similar.
- The slot is not selectable; clicking it does nothing or plays a soft "no" SFX.

Per Max's note, this is on hold for the *shop* (components aren't in the shop yet) but applies to the assembly screen now.

### Unlock notification

When `PlayerProgress.component_unlocked` fires, queue a notification toast. Important: multiple unlocks can fire from a single event (e.g., a clutch leg-win that ticks several conditions). The notification system needs a queue, not a single popup.

Suggested behavior:

- A small toast slides in from the side of the screen.
- Shows a thumbnail of the component's `texture`, the `component_name` ("Torpedo Barrel"), and a "NEW COMPONENT UNLOCKED" label.
- Displays for ~2 seconds, then slides out. The next queued notification waits for the previous one to finish.
- Plays a small unlock SFX (route through `AuidoManager`).
- Exposed via a `UnlockNotificationQueue` node in the main scene that connects to `PlayerProgress.component_unlocked` on `_ready()`.

Exported tuning fields on the notification node:

```gdscript
## Duration (seconds) each notification stays on screen before sliding out.
@export var display_duration: float = 2.0

## Slide-in / slide-out animation duration in seconds.
@export var slide_duration: float = 0.3

## Position offset from the screen edge.
@export var screen_margin: Vector2 = Vector2(24, 24)

## Background color of the notification panel.
@export var background_color: Color = Color(0.1, 0.1, 0.12, 0.95)

## Accent color for the "NEW COMPONENT UNLOCKED" header text.
@export var accent_color: Color = Color(1.0, 0.85, 0.2)
```

---

## 10. Adding a New Locked Component — Step-by-Step Checklist

Once the system is in place, here is the canonical recipe for adding a new locked component. Future-Max: this is the section you re-read every time you add a new part.

### Step 1 — Pick an ID and filename

- ID: slot-prefixed snake_case (`&"barrel_quickdraw"`).
- Filename: same slug (`barrel_quickdraw.tres`).
- Confirm uniqueness by grepping the repo: `rg 'id = &"barrel_quickdraw"'` should return zero hits.

### Step 2 — Create the `.tres`

Right-click `res://resources/dart_components/{slot}/`, **New Resource...**, choose `DartComponent`.

### Step 3 — Fill in the fields

- `id`: your slug (`&"barrel_quickdraw"`).
- `component_name`: display name.
- `description`: player-facing description shown when unlocked.
- `component_type`: matching `ComponentSlot` enum.
- `weight`, `rarity_tier`, stat bonuses, `texture`, colors: per your design.
- `default_unlocked`: **false** for locked content.
- `unlock_condition`: leave empty for now — we'll fill it in step 5.
- `throw_modifier`: optional, drag in a ThrowModifier `.tres` if applicable.

### Step 4 — Pick or create an `UnlockCondition`

- Browse `res://resources/unlock_conditions/{slot}/` — if an existing condition fits, use it.
- Otherwise: right-click that folder, **New Resource...**, choose the right subclass:
  - `LegWinHitCondition` — properties of the winning dart.
  - `LegStatCondition` — properties of the leg (target value, checkout total, three-dart-scoring).
  - `CareerCountCondition` — lifetime counters (legs won, runs completed).
  - `RunConstraintCondition` — multi-leg constraints within one run.
  - `ShopAcquisitionCondition` — single shop counters.
  - `SlotsFilledCondition` — current slot occupancy snapshot.
- Configure the subclass's exported parameters.
- **Write the `description`** — this is player-facing copy that appears on the locked component in the assembly screen. Examples:
  - "Win a leg on a double bullseye."
  - "Checkout from over 100."
  - "Win 5 legs total."

### Step 5 — Link the condition

Open your component `.tres`, drag the `UnlockCondition` `.tres` into the `unlock_condition` field.

### Step 6 — Register the component

Open the `DartComponentRegistry` node in the inspector, drag your component `.tres` into the appropriate slot array.

### Step 7 — Run the game

Watch the debugger console. If you see any red `DartComponentRegistry:` errors, fix them — likely an empty/duplicate ID or a `default_unlocked = false` with no condition. The game refuses to silently accept these.

### Step 8 — Test the unlock

If your condition is reachable in normal play, play to it and confirm the notification fires. If it's high-effort to reach naturally, use a debug shortcut: temporarily flip `default_unlocked = true` to verify the component itself works, then flip it back.

---

## 11. Mapping: Design List → Condition Configuration

Quick reference connecting Max's design list to the right subclass and configuration. Use this when authoring the initial set of unlock conditions.

| Design intent | Subclass | Configuration |
|---------------|----------|---------------|
| Win a leg on a double bullseye | `LegWinHitCondition` | `required_ring = "Double Bull"` |
| Checkout from over 100 | `LegStatCondition` | `min_checkout_total = 101` |
| Win a leg on your final dart | `LegWinHitCondition` | `final_dart_mode = 1` (Must be final) |
| Win 501 | `LegStatCondition` | `required_target_score = 501` |
| Acquire 10 items during a single shop | `ShopAcquisitionCondition` | `min_items_acquired = 10` |
| Win a leg on a streak-modified double | `LegWinHitCondition` | `required_ring = "Double"`, `required_modifier_category = "streak"` |
| Win a leg on a double scoring > 50 | `LegWinHitCondition` | `required_ring = "Double"`, `min_winning_dart_score = 51` |
| Win a leg on a double scoring > 100 | `LegWinHitCondition` | `required_ring = "Double"`, `min_winning_dart_score = 101` |
| Fill all modifier slots | `SlotsFilledCondition` | `target_slots = 1` *(blocked on slot-cap design — see OPEN QUESTION in 6f)* |
| Fill all streak slots | `SlotsFilledCondition` | `target_slots = 0` |
| Win 5 legs total | `CareerCountCondition` | `stat_name = &"legs_won"`, `threshold = 5` |
| Win 10 legs total | `CareerCountCondition` | `stat_name = &"legs_won"`, `threshold = 10` |
| Win 5 legs with only common items | `RunConstraintCondition` | `legs_won_this_run_threshold = 5`, `required_run_flag = &"only_commons_acquired_this_run"` |
| 3-dart checkout (all darts must score) | `LegStatCondition` | `require_three_scoring_darts = true` |
| Hit a double for the win without it being your target | `LegWinHitCondition` | `required_ring = "Double"`, `target_mode = 1` (Must be off-target) |

---

## 12. Common Pitfalls

- **Empty `id`.** Caught by the registry on `_ready()`. The game will not start clean — push_error prints in red.
- **Duplicate `id`.** Two components share an ID. Caught by the registry. Rename one (but only if neither has been released yet — never change a released ID).
- **Changing an `id` after release.** Orphans player save data — anyone who unlocked the old ID loses it silently. NEVER do this. If you really must, write a migration in `PlayerProgress._load()` that rewrites old IDs to new ones.
- **`default_unlocked = false` with no `unlock_condition`.** Caught by the registry. Means the component is permanently unobtainable. Either set a condition or flip `default_unlocked` back to true.
- **Forgetting to register the component in `DartComponentRegistry`.** The validation only sees what's in the arrays — a `.tres` file that exists but isn't dragged in is silently unused.
- **Setting `was_winning_dart_on_target` incorrectly.** This requires `main.gd` to compare the player's aim wedge against the actual hit wedge. If you skip this, off-target conditions never fire.
- **Conditions that compete.** Two components both unlock on "Win 5 legs" — both unlock simultaneously on the same event. That's fine and intended. The notification queue handles ordering.
- **`required_modifier_category = "streak"` with no streak modifier active.** The condition simply won't fire — that's correct behavior. Make sure the description sets the player's expectation.
- **`description` left empty on an `UnlockCondition`.** The assembly screen will render a locked component with no hint. Not enforced by code; enforced by code review and playtesting.

---

## 13. Shell Files for New Locked Components (Content Deferred to Max)

Claude Code creates these empty `.tres` files as scaffolding. Max fills them in via the Godot inspector after the system lands, following the section 10 checklist.

### What Claude Code creates

Nine empty `DartComponent` `.tres` resources — three per slot:

| File path | `component_type` field |
|-----------|------------------------|
| `res://resources/dart_components/barrels/_unfilled_barrel_1.tres` | `BARREL` |
| `res://resources/dart_components/barrels/_unfilled_barrel_2.tres` | `BARREL` |
| `res://resources/dart_components/barrels/_unfilled_barrel_3.tres` | `BARREL` |
| `res://resources/dart_components/shafts/_unfilled_shaft_1.tres` | `SHAFT` |
| `res://resources/dart_components/shafts/_unfilled_shaft_2.tres` | `SHAFT` |
| `res://resources/dart_components/shafts/_unfilled_shaft_3.tres` | `SHAFT` |
| `res://resources/dart_components/flights/_unfilled_flight_1.tres` | `FLIGHT` |
| `res://resources/dart_components/flights/_unfilled_flight_2.tres` | `FLIGHT` |
| `res://resources/dart_components/flights/_unfilled_flight_3.tres` | `FLIGHT` |

### Field values to write into each shell

- `id`: `&""` (empty — Max assigns following the slot-prefix convention in section 1)
- `component_name`: `""` (empty)
- `description`: `""` (empty)
- `component_type`: the correct enum for the folder (`BARREL`, `SHAFT`, or `FLIGHT`)
- `weight`: `0.0`
- `rarity_tier`: `COMMON`
- `default_unlocked`: `false`
- `unlock_condition`: `null`
- `texture`: `null`
- All six stat bonuses: `0.0`
- `throw_modifier`: `null`
- `dart_outer_color`: default `Color(0.9, 0.85, 0.0)`
- `dart_inner_color`: default `Color(0.2, 0.2, 0.2)`

### Critical: do NOT register these shells

Claude Code MUST NOT add any of these shells to the `DartComponentRegistry`'s `barrels`, `shafts`, or `flights` arrays. They remain unregistered until Max fills each one in and drags it into the registry manually. This is intentional — the registry validator would refuse to start the game if a registered component has an empty `id` or is `default_unlocked = false` with a null `unlock_condition`, both of which describe an unfilled shell.

The leading `_unfilled_` prefix sorts these to the top of their folder in the FileSystem dock so Max can see at a glance what's pending. When Max fills a shell in, he renames the file to match its final `id` slug (e.g., `_unfilled_barrel_1.tres` → `barrel_quickdraw.tres`) before registering it.

### Why this approach

- Bundles system + content scaffolding in one PR while keeping every design decision (stats, names, balance) Max's.
- Registry validator stays strict — no loosening to accommodate placeholder content.
- Game remains runnable throughout the fill-in process; unregistered shells don't break anything.
- Renaming a shell to its final slug is a single rename operation in the FileSystem dock; no folder moves needed.

---

## 14. Future Extensions

Items deliberately deferred from this spec, listed here so future work has a head start:

- **Component slot cap / "modifier slots" semantics.** Section 6f flags this — needs design pass before the `all_modifier_slots_filled` flag means anything.
- **Stable IDs on `ScoringModifier` and `ThrowModifier`.** Same `id: StringName` pattern, useful for save data and item-history tracking. Not built yet — copy the pattern from `DartComponent` when needed. Resist extracting a shared base class until at least two of them need it.
- **Achievement-style overlays.** The `component_unlocked` signal could feed an achievements panel listing every component and its unlock status. Not in scope here.
- **Migration handling in `PlayerProgress._load()`.** Currently it just loads or returns empty. If the save format ever needs to change, add versioning and a migration step there.
- **Per-profile vs. global progression.** Currently global (single `user://progress.tres`). Per-profile would mean `user://profiles/{name}/progress.tres` and a profile-picker. Forward-compatible: the autoload's `SAVE_PATH` becomes a property a future profile manager swaps.
