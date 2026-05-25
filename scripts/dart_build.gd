class_name DartBuild
extends Node
## Holds the three equipped dart components, computes balance, and applies
## the final stat modifications to throw_mechanic when a run begins.

signal build_changed

@export var equipped_barrel: DartComponent
@export var equipped_shaft: DartComponent
@export var equipped_flight: DartComponent

## Balance at or below this = perfect balance zone (extra bonus to all stats).
@export_range(0.0, 0.5, 0.01) var perfect_threshold: float = 0.08

## Balance at or below this = GREEN zone (flat bonus to all stats).
@export_range(0.0, 1.0, 0.01) var green_threshold: float = 0.25

## Balance at or below this = ORANGE zone (neutral). Above = RED (skew penalty).
@export_range(0.0, 1.5, 0.01) var orange_threshold: float = 0.5

## Flat bonus added to ALL six stats in the perfect balance zone (stacks with green_bonus).
@export var perfect_bonus: float = 3.0

## Flat bonus added to ALL six stats in the green zone.
@export var green_bonus: float = 2.0

## Maximum accuracy skew in pixels at deep red imbalance.
@export var max_red_skew_pixels: float = 30.0

## Fraction of the orange zone (0.0-1.0) that forms the green→orange transition.
## The transition starts at green_threshold and extends this fraction into the orange zone.
@export_range(0.0, 1.0, 0.05) var green_orange_transition_width: float = 0.4

## Flat stat bonus applied in the green→orange transition zone.
## Suggested: 10-20% of green_bonus for a mild reward.
@export var green_orange_transition_bonus: float = 0.5

## Fraction of the orange zone (0.0-1.0) that forms the orange→red transition.
## The transition starts this fraction before orange_threshold inside the orange zone.
@export_range(0.0, 1.0, 0.05) var orange_red_transition_width: float = 0.4

## Accuracy skew in pixels applied in the orange→red transition zone.
## Suggested: 10-20% of max_red_skew_pixels for a mild warning.
@export var orange_red_transition_skew: float = 4.0

## Player-chosen dart marker outer ring color.
var dart_outer_color: Color = Color(0.9, 0.85, 0.0)

## Player-chosen dart marker inner ring color.
var dart_inner_color: Color = Color(0.2, 0.2, 0.2)


func get_balance_value() -> float:
	var total: float = 0.0
	if equipped_barrel:
		total += equipped_barrel.weight
	if equipped_shaft:
		total += equipped_shaft.weight
	if equipped_flight:
		total += equipped_flight.weight
	return total


func get_balance_zone() -> String:
	var abs_balance: float = absf(get_balance_value())
	if abs_balance <= green_threshold:
		return "green"
	elif abs_balance <= orange_threshold:
		return "orange"
	else:
		return "red"


## Get the detailed balance zone including transition sub-zones.
## Returns: "perfect", "green", "green_orange", "orange", "orange_red", or "red".
func get_balance_zone_detailed() -> String:
	var abs_balance: float = absf(get_balance_value())
	if abs_balance <= perfect_threshold:
		return "perfect"
	elif abs_balance <= green_threshold:
		return "green"
	elif abs_balance <= orange_threshold:
		var orange_width: float = orange_threshold - green_threshold
		var into_orange: float = abs_balance - green_threshold
		var go_transition_end: float = orange_width * green_orange_transition_width
		var or_transition_start: float = orange_width * (1.0 - orange_red_transition_width)
		if into_orange <= go_transition_end:
			return "green_orange"
		elif into_orange >= or_transition_start:
			return "orange_red"
		else:
			return "orange"
	else:
		return "red"


## Vertical accuracy skew for the red and orange→red transition zones.
## Front-heavy (negative) -> positive skew (dart drops).
## Back-heavy (positive) -> negative skew (dart floats).
func get_accuracy_skew() -> float:
	var balance: float = get_balance_value()
	var abs_balance: float = absf(balance)

	# Orange→red transition zone applies mild skew
	var detailed: String = get_balance_zone_detailed()
	if detailed == "orange_red":
		return orange_red_transition_skew * signf(balance)

	if abs_balance <= orange_threshold:
		return 0.0
	var red_amount: float = abs_balance - orange_threshold
	var max_red: float = 3.0 - orange_threshold
	var skew_fraction: float = clampf(red_amount / max_red, 0.0, 1.0)
	var skew: float = skew_fraction * max_red_skew_pixels
	return skew * signf(balance)


func get_total_stat_bonuses() -> Dictionary:
	var bonuses: Dictionary = {
		"horizontal_range": 0.0,
		"vertical_range": 0.0,
		"horizontal_speed": 0.0,
		"vertical_speed": 0.0,
		"horizontal_accuracy": 0.0,
		"vertical_accuracy": 0.0,
	}
	for part: DartComponent in [equipped_barrel, equipped_shaft, equipped_flight]:
		if part == null:
			continue
		bonuses["horizontal_range"] += part.h_range_bonus
		bonuses["vertical_range"] += part.v_range_bonus
		bonuses["horizontal_speed"] += part.h_speed_bonus
		bonuses["vertical_speed"] += part.v_speed_bonus
		bonuses["horizontal_accuracy"] += part.h_accuracy_bonus
		bonuses["vertical_accuracy"] += part.v_accuracy_bonus

	var zone: String = get_balance_zone_detailed()
	if zone == "perfect":
		for key: String in bonuses.keys():
			bonuses[key] += green_bonus + perfect_bonus
	elif zone == "green":
		for key: String in bonuses.keys():
			bonuses[key] += green_bonus
	elif zone == "green_orange":
		for key: String in bonuses.keys():
			bonuses[key] += green_orange_transition_bonus

	return bonuses


## Apply the build's stat bonuses to the throw mechanic.
## base_stats: the player's raw stat values before any component bonuses.
func apply_to_throw_mechanic(throw_mech: Node2D, base_stats: Dictionary) -> void:
	var bonuses: Dictionary = get_total_stat_bonuses()
	throw_mech.horizontal_range = base_stats["horizontal_range"] + bonuses["horizontal_range"]
	throw_mech.vertical_range = base_stats["vertical_range"] + bonuses["vertical_range"]
	throw_mech.horizontal_speed = base_stats["horizontal_speed"] + bonuses["horizontal_speed"] * (4.0 / 40.0)
	throw_mech.vertical_speed = base_stats["vertical_speed"] + bonuses["vertical_speed"] * (4.0 / 40.0)
	throw_mech.horizontal_accuracy = base_stats["horizontal_accuracy"] + bonuses["horizontal_accuracy"]
	throw_mech.vertical_accuracy = base_stats["vertical_accuracy"] + bonuses["vertical_accuracy"]
	throw_mech.accuracy_skew_v = get_accuracy_skew()


## Collect all ThrowModifiers from equipped components.
func _get_active_throw_modifiers() -> Array[ThrowModifier]:
	var modifiers: Array[ThrowModifier] = []
	for part: DartComponent in [equipped_barrel, equipped_shaft, equipped_flight]:
		if part == null:
			continue
		if part.throw_modifier != null:
			modifiers.append(part.throw_modifier)
	return modifiers


## Evaluate all throw modifiers against current game state.
## Returns a dictionary of total temporary stat bonuses to apply.
## Also returns which modifiers activated for HUD display.
func evaluate_throw_modifiers(context: Dictionary) -> Dictionary:
	var total_bonuses: Dictionary = {
		"horizontal_range": 0.0,
		"vertical_range": 0.0,
		"horizontal_speed": 0.0,
		"vertical_speed": 0.0,
		"horizontal_accuracy": 0.0,
		"vertical_accuracy": 0.0,
	}
	var activated_names: Array[String] = []

	for modifier: ThrowModifier in _get_active_throw_modifiers():
		if modifier.should_activate(context):
			var bonuses: Dictionary = modifier.get_active_bonuses(context)
			for key: String in bonuses.keys():
				total_bonuses[key] += bonuses[key]
			activated_names.append(modifier.modifier_name)

	return {
		"bonuses": total_bonuses,
		"activated": activated_names,
	}


func equip_barrel(part: DartComponent) -> void:
	equipped_barrel = part
	build_changed.emit()


func equip_shaft(part: DartComponent) -> void:
	equipped_shaft = part
	build_changed.emit()


func equip_flight(part: DartComponent) -> void:
	equipped_flight = part
	if part != null:
		dart_outer_color = part.dart_outer_color
		dart_inner_color = part.dart_inner_color
	build_changed.emit()
