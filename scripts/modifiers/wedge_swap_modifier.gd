class_name WedgeSwapModifier
extends ScoringModifier
## Swaps the board positions (and associated colors) of two player-chosen wedges.
## Always generates at COMMON rarity — the effect is the same regardless.

func _init() -> void:
	modifier_name = "Wedge Swap"
	description = "Swap the positions of two wedges on the board"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.PICK_TWO_WEDGES


func apply_to_board(wedge_values: Array[int], wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	var idx1: int = config["wedge_index_1"]
	var idx2: int = config["wedge_index_2"]

	var temp_value: int = wedge_values[idx1]
	wedge_values[idx1] = wedge_values[idx2]
	wedge_values[idx2] = temp_value

	var temp_colors: Dictionary = wedge_colors[idx1]
	wedge_colors[idx1] = wedge_colors[idx2]
	wedge_colors[idx2] = temp_colors

	description = "Swapped wedge %d and wedge %d" % [wedge_values[idx1], wedge_values[idx2]]


static func get_pool_weight() -> int:
	return 10


static func get_rarity_weights() -> Array[int]:
	return [100, 0, 0]


static func generate(_rarity_tier: ScoringEnums.Rarity) -> WedgeSwapModifier:
	var mod: WedgeSwapModifier = WedgeSwapModifier.new()
	mod.rarity_tier = ScoringEnums.Rarity.COMMON
	return mod
