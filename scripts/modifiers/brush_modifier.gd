class_name BrushModifier
extends ScoringModifier
## Paints one specific ring on one wedge to a pre-rolled color.
## Consumable — one ring per item, no panel presence after acquisition.

## The color this brush paints, pre-rolled at generation.
@export var target_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED

const COLOR_NAMES: Dictionary = {
	ScoringEnums.SegmentColor.RED: "Red",
	ScoringEnums.SegmentColor.GREEN: "Green",
	ScoringEnums.SegmentColor.BLACK: "Black",
	ScoringEnums.SegmentColor.WHITE: "White",
}


func _init() -> void:
	modifier_name = "Brush"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.PICK_SEGMENT
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION


func get_config_fingerprint() -> String:
	return "%s|%d" % [super.get_config_fingerprint(), target_color]


func get_brush_color_name() -> String:
	return COLOR_NAMES.get(target_color, "?")


func apply_to_board(_wedge_values: Array[int], wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	var idx: int = config["wedge_index"]
	var ring_key: String = config["ring_name"]
	wedge_colors[idx][ring_key] = target_color


static func get_pool_weight() -> int:
	if ModifierRegistry.available_brush_colors.is_empty():
		return 0
	return 15


static func get_rarity_weights() -> Array[int]:
	return [100, 0, 0]


static func generate(_rarity_tier: ScoringEnums.Rarity) -> BrushModifier:
	var mod: BrushModifier = BrushModifier.new()
	mod.rarity_tier = ScoringEnums.Rarity.COMMON

	var colors: Array[ScoringEnums.SegmentColor] = ModifierRegistry.available_brush_colors
	if colors.is_empty():
		colors = [
			ScoringEnums.SegmentColor.RED,
			ScoringEnums.SegmentColor.GREEN,
			ScoringEnums.SegmentColor.BLACK,
			ScoringEnums.SegmentColor.WHITE,
		]
	mod.target_color = colors[randi_range(0, colors.size() - 1)]

	var color_name: String = COLOR_NAMES[mod.target_color]
	mod.modifier_name = "Brush: %s" % color_name
	mod.description = "Paint any one segment %s" % color_name.to_lower()

	return mod
