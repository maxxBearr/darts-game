class_name DartComponentRegistry
extends Node
## Central registry of all available dart components.
## The assembly screen reads from these arrays to populate part selection.
## To add a new part: create a DartComponent .tres, then drag it into the
## appropriate array below in the inspector.

@export var barrels: Array[DartComponent] = []
@export var shafts: Array[DartComponent] = []
@export var flights: Array[DartComponent] = []


func get_unlocked_barrels() -> Array[DartComponent]:
	var result: Array[DartComponent] = []
	for part: DartComponent in barrels:
		if part.unlocked:
			result.append(part)
	return result


func get_unlocked_shafts() -> Array[DartComponent]:
	var result: Array[DartComponent] = []
	for part: DartComponent in shafts:
		if part.unlocked:
			result.append(part)
	return result


func get_unlocked_flights() -> Array[DartComponent]:
	var result: Array[DartComponent] = []
	for part: DartComponent in flights:
		if part.unlocked:
			result.append(part)
	return result
