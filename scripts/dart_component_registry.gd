class_name DartComponentRegistry
extends Node
## Central registry of all available dart components.
## The assembly screen reads from these arrays to populate part selection.
## To add a new part: create a DartComponent .tres, then drag it into the
## appropriate array below in the inspector.

@export var barrels: Array[DartComponent] = []
@export var shafts: Array[DartComponent] = []
@export var flights: Array[DartComponent] = []


func _ready() -> void:
	_validate_components()


func _validate_components() -> void:
	var seen_ids: Dictionary = {}
	var all_parts: Array[DartComponent] = []
	all_parts.append_array(barrels)
	all_parts.append_array(shafts)
	all_parts.append_array(flights)

	for part: DartComponent in all_parts:
		if part == null:
			continue

		if part.id == &"" or part.id == &" ":
			push_error("DartComponentRegistry: component '%s' has empty id"
				% part.component_name)
			continue

		if seen_ids.has(part.id):
			push_error("DartComponentRegistry: duplicate id '%s' on '%s' and '%s'"
				% [part.id, seen_ids[part.id], part.component_name])
		else:
			seen_ids[part.id] = part.component_name

		if not part.default_unlocked and part.unlock_condition == null:
			push_error("DartComponentRegistry: '%s' is locked but has no unlock_condition — permanently unobtainable"
				% part.component_name)


func get_unlocked_barrels() -> Array[DartComponent]:
	return _filter_unlocked(barrels)


func get_unlocked_shafts() -> Array[DartComponent]:
	return _filter_unlocked(shafts)


func get_unlocked_flights() -> Array[DartComponent]:
	return _filter_unlocked(flights)


func _filter_unlocked(parts: Array[DartComponent]) -> Array[DartComponent]:
	var result: Array[DartComponent] = []
	for part: DartComponent in parts:
		if part == null:
			continue
		if PlayerProgress.is_unlocked(part):
			result.append(part)
	return result


## Return all components the player has NOT yet unlocked.
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
