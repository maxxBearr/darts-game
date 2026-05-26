extends Node
## Persistent player progression state. Tracks unlocked component IDs and
## career statistics used by unlock conditions. Saved to user://progress.tres.

const SAVE_PATH: String = "user://progress.tres"

## Set of component IDs the player has unlocked.
## Keys are StringNames, values are true.
var unlocked_ids: Dictionary = {}

## Career counters used by CareerCountCondition.
var career_stats: Dictionary = {}

## Cleared level records. Keys are level resource paths (String),
## values are {cleared: true, fewest_darts: int}.
var cleared_levels: Dictionary = {}

## Emitted when a component transitions from locked to unlocked.
signal component_unlocked(component: DartComponent)

## Emitted when a level is cleared (first time or new best).
signal level_cleared(level_definition: Resource, dart_count: int)


func _ready() -> void:
	_load()


## Check whether the player has access to a component.
## A component with default_unlocked = true is always unlocked.
## Otherwise, look up its id in the saved progress dict.
## Defensive: components with an empty id are treated as locked regardless of
## save state — empty ids are an authoring mistake the registry validator
## flags, and we never want a single &"" key in unlocked_ids to satisfy
## multiple distinct components.
func is_unlocked(component: DartComponent) -> bool:
	if component.default_unlocked:
		return true
	if component.id == &"":
		return false
	return unlocked_ids.has(component.id)


## Grant an unlock. No-op if already unlocked. Saves immediately and emits signal.
## Defensive: refuses to write an empty id into unlocked_ids — that would cause
## every component with an empty id to appear unlocked from then on.
func unlock(component: DartComponent) -> void:
	if component.id == &"":
		push_error("PlayerProgress.unlock(): refusing to unlock '%s' — component has empty id. Set an id on the resource before registering it."
			% component.component_name)
		return
	if is_unlocked(component):
		return
	unlocked_ids[component.id] = true
	_save()
	component_unlocked.emit(component)


## Read a career stat. Returns 0 if never set.
func get_stat(stat_name: StringName) -> int:
	return career_stats.get(stat_name, 0)


## Increment a career stat by amount (default 1). Saves immediately.
func increment_stat(stat_name: StringName, amount: int = 1) -> void:
	career_stats[stat_name] = career_stats.get(stat_name, 0) + amount
	_save()


## Set a career stat to a specific value if it exceeds the current value.
func set_stat_max(stat_name: StringName, value: int) -> void:
	var current: int = career_stats.get(stat_name, 0)
	if value > current:
		career_stats[stat_name] = value
		_save()


## Check whether a level has been cleared at least once.
func is_level_cleared(level_path: String) -> bool:
	return cleared_levels.has(level_path) and cleared_levels[level_path].get("cleared", false)


## Get the fewest darts used to clear a level. Returns 0 if never cleared.
func get_fewest_darts(level_path: String) -> int:
	if cleared_levels.has(level_path):
		return cleared_levels[level_path].get("fewest_darts", 0)
	return 0


## Record a full level clear. Updates fewest-darts if this is a new best.
func record_level_clear(level_definition: Resource, dart_count: int) -> void:
	var path: String = level_definition.resource_path
	var existing: Dictionary = cleared_levels.get(path, {})
	var prev_best: int = existing.get("fewest_darts", 999999)
	var best: int = mini(dart_count, prev_best) if existing.get("cleared", false) else dart_count
	cleared_levels[path] = {"cleared": true, "fewest_darts": best}
	_save()
	level_cleared.emit(level_definition, dart_count)


## Debug: clear all unlock state and career stats. Used for testing the
## unlock flow from scratch without manually deleting user://progress.tres.
## Resets are also picked up by the registry's locked filter — the assembly
## screen will reflect the new state next time it re-renders a slot.
func debug_reset_all() -> void:
	unlocked_ids.clear()
	career_stats.clear()
	cleared_levels.clear()
	_save()
	print("PlayerProgress: reset all unlock state, career stats, and level clears.")


## Debug: unlock every component in the registry that has a non-empty id.
## Components with empty ids are skipped (the validator should already be
## flagging them). Use for previewing the assembly screen with the full pool.
func debug_unlock_all(registry: DartComponentRegistry) -> void:
	if registry == null:
		push_error("PlayerProgress.debug_unlock_all(): registry is null")
		return
	var count: int = 0
	var all_parts: Array[DartComponent] = []
	all_parts.append_array(registry.barrels)
	all_parts.append_array(registry.shafts)
	all_parts.append_array(registry.flights)
	for part: DartComponent in all_parts:
		if part == null or part.id == &"":
			continue
		if not unlocked_ids.has(part.id):
			unlocked_ids[part.id] = true
			count += 1
	_save()
	print("PlayerProgress: debug_unlock_all() unlocked %d previously-locked components." % count)


func _save() -> void:
	var data: Dictionary = {
		"unlocked_ids": unlocked_ids,
		"career_stats": career_stats,
		"cleared_levels": cleared_levels,
	}
	var save_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file == null:
		push_error("PlayerProgress: failed to open %s for writing" % SAVE_PATH)
		return
	save_file.store_var(data)
	save_file.close()


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
		cleared_levels = data.get("cleared_levels", {})
		# Migration: scrub any empty-id key that may have leaked in from an
		# earlier session where a component was unlocked before being given
		# a proper id. The &"" key is now refused by unlock() itself, but
		# old save files might still carry it.
		if unlocked_ids.has(&""):
			unlocked_ids.erase(&"")
			_save()
