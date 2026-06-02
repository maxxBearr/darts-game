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
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION


## Called with the player's wedge choice. Mutates the effective values array.
func get_config_fingerprint() -> String:
	return "%s|%d" % [super.get_config_fingerprint(), bonus_value]


func apply_to_board(wedge_values: Array[int], _wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	var target_index: int = config["wedge_index"]
	original_value = wedge_values[target_index]
	wedge_values[target_index] += bonus_value
	applied_wedge_index = target_index
	description = "+%d to wedge %d (now %d)" % [bonus_value, original_value, wedge_values[target_index]]


func get_pick_wedge_header() -> String:
	return "Add +%d to a wedge" % bonus_value


func get_pick_wedge_prompt(current_value: int) -> String:
	return "Make %d into %d? Click to confirm, Escape to cancel" % [current_value, current_value + bonus_value]


static func get_pool_weight() -> int:
	return 25


static func get_rarity_weights() -> Array[int]:
	return [65, 25, 10]


static func generate(rarity_tier: ScoringEnums.Rarity) -> WedgeValueModifier:
	var mod: WedgeValueModifier = WedgeValueModifier.new()
	mod.rarity_tier = rarity_tier

	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.bonus_value = randi_range(1, 2)
		ScoringEnums.Rarity.UNCOMMON:
			mod.bonus_value = randi_range(3, 4)
		ScoringEnums.Rarity.RARE:
			mod.bonus_value = randi_range(5, 7)

	mod.modifier_name = "Wedge Boost +%d" % mod.bonus_value
	mod.description = "+%d to a chosen wedge value" % mod.bonus_value

	return mod
