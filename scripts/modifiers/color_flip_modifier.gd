class_name ColorFlipModifier
extends ScoringModifier
## Flips the color pair of a chosen wedge.
## BLACK/RED becomes WHITE/GREEN, and vice versa.

const COLOR_PAIR_NAMES: Dictionary = {
	ScoringEnums.SegmentColor.BLACK: "Black/Red",
	ScoringEnums.SegmentColor.WHITE: "White/Green",
}


func _init() -> void:
	modifier_name = "Color Flip"
	description = "Flip a wedge's colors (Black/Red ↔ White/Green)"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.PICK_WEDGE
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION


func apply_to_board(_wedge_values: Array[int], wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	var idx: int = config["wedge_index"]
	var entry: Dictionary = wedge_colors[idx]

	if entry["single"] == ScoringEnums.SegmentColor.BLACK and entry["multi"] == ScoringEnums.SegmentColor.RED:
		entry["single"] = ScoringEnums.SegmentColor.WHITE
		entry["multi"] = ScoringEnums.SegmentColor.GREEN
	elif entry["single"] == ScoringEnums.SegmentColor.WHITE and entry["multi"] == ScoringEnums.SegmentColor.GREEN:
		entry["single"] = ScoringEnums.SegmentColor.BLACK
		entry["multi"] = ScoringEnums.SegmentColor.RED

	wedge_colors[idx] = entry


static func get_color_pair_name(single_color: ScoringEnums.SegmentColor) -> String:
	return COLOR_PAIR_NAMES.get(single_color, "Unknown")


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [100, 0, 0]


static func generate(_rarity_tier: ScoringEnums.Rarity) -> ColorFlipModifier:
	var mod: ColorFlipModifier = ColorFlipModifier.new()
	mod.rarity_tier = ScoringEnums.Rarity.COMMON
	return mod
