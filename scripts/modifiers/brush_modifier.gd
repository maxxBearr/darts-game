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
	family = ScoringEnums.Family.BRUSH


func get_config_fingerprint() -> String:
	return "%s|%d" % [super.get_config_fingerprint(), target_color]


func get_brush_color_name() -> String:
	return COLOR_NAMES.get(target_color, "?")


func get_pick_segment_header() -> String:
	return "Paint a segment %s" % get_brush_color_name()


func get_pick_segment_prompt(ring_display: String, face_value: int, color_name: String) -> String:
	return "Paint %s %d (%s)? Click to confirm, Escape to cancel" % [ring_display, face_value, color_name]


func apply_to_board(_wedge_values: Array[int], wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	var idx: int = config["wedge_index"]
	var ring_key: String = config["ring_name"]
	wedge_colors[idx][ring_key] = target_color


static func get_pool_weight() -> int:
	# Flat. Brush is ungated AND unbiased everywhere (Max's rulings 2026-06-07/08) — owned
	# streak colors no longer gate pool presence or steer the roll.
	return 15


static func get_rarity_weights() -> Array[int]:
	return [100, 0, 0]


## All four paintable colors — the full, unbiased roll pool.
const ALL_COLORS: Array[ScoringEnums.SegmentColor] = [
	ScoringEnums.SegmentColor.RED,
	ScoringEnums.SegmentColor.GREEN,
	ScoringEnums.SegmentColor.BLACK,
	ScoringEnums.SegmentColor.WHITE,
]


## Build a specific color's brush (mirrors ColorTerritoryModifier.make), so pick surfaces can
## offer DISTINCT colors deterministically instead of reroll-and-hope.
static func make(color: ScoringEnums.SegmentColor) -> BrushModifier:
	var mod: BrushModifier = BrushModifier.new()
	mod.rarity_tier = ScoringEnums.Rarity.COMMON
	mod.target_color = color
	var color_name: String = COLOR_NAMES[color]
	mod.modifier_name = "Brush: %s" % color_name
	mod.description = "Paint any one segment %s" % color_name.to_lower()
	return mod


static func generate(_rarity_tier: ScoringEnums.Rarity) -> BrushModifier:
	# UNBIASED roll over the full color pool (Max's ruling 2026-06-08). The old affinity
	# steering (roll only owned streak colors) collapsed every brush option to one color the
	# moment a single color streak was owned — three identical cards is no choice at all.
	return make(ALL_COLORS[randi_range(0, ALL_COLORS.size() - 1)])
