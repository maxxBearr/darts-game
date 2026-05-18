class_name WedgeValueModifier
extends ScoringModifier
## Adds a flat bonus to a single wedge's face value. The player picks which
## wedge to target after acquiring this modifier. The change is permanent for
## the run and visually updates the number drawn on the board.
## Example: applying +3 to wedge 7 makes it read as 10. Triple on that wedge
## would then score 30 instead of 21.

## How much to add to the chosen wedge's face value.
@export var bonus_value: int = 3

## The wedge index this was applied to (set during apply_to_board, stored for display).
var applied_wedge_index: int = -1

## The original value before modification (stored for display).
var original_value: int = 0


func _init() -> void:
	modifier_name = "Wedge Boost"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.PICK_WEDGE


## Called with the player's wedge choice. Mutates the effective values array.
func apply_to_board(wedge_values: Array[int], _wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	var target_index: int = config["wedge_index"]
	original_value = wedge_values[target_index]
	wedge_values[target_index] += bonus_value
	applied_wedge_index = target_index
	# Update description to reflect the specific choice made
	description = "+%d to wedge %d (now %d)" % [bonus_value, original_value, wedge_values[target_index]]
