class_name LegWinHitCondition
extends UnlockCondition
## Triggered on leg_won. Checks properties of the winning dart.

## Required ring of the winning dart. Empty string = any double counts.
@export var required_ring: String = ""

## Required wedge face value of the winning dart. 0 = any.
@export_range(0, 25, 1) var required_wedge_value: int = 0

## Minimum score of the winning dart (after modifiers). 0 = no minimum.
@export var min_winning_dart_score: int = 0

## Filter on whether the winning dart was the last possible dart of the leg.
@export_enum("Any", "Must be final", "Must not be final") var final_dart_mode: int = 0

## Filter on whether a scoring modifier of a certain category was active.
@export var required_modifier_category: String = ""

## Filter on whether the winning dart hit the wedge the player was aiming at.
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
