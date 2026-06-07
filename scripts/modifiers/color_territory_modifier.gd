class_name ColorTerritoryModifier
extends ScoringModifier
## GEOMETRY family — grows every ring band currently painted a target color, radially, within
## its own wedge; that wedge's non-target bands pay proportionally (per-wedge renormalization,
## zero-sum per wedge column). Board-wide, rarity-less.
##
## DYNAMIC: ScoringModifierManager.recompute_geometry() recomputes this from the LIVE
## effective_wedge_colors on every repaint (brush, Prism recolor-on-hit). A color with no
## presence on the board is inert until painted — a legal build-around purchase. Composes with
## the painter build: paint a wedge's bands a color, then grow them. Self-limiting: paint a
## whole wedge one color → nothing left to shrink → no-op (renormalization).
##
## Bull is exempt — bull radii are not per-wedge state (only the Bigger Bull relic moves them).
##
## Four pool entries share this class, one per target color (Grow Red / Green / White / Black).
## Carries no board mutation of its own; apply_to_board is a no-op (the manager reads it).

const COLOR_NAMES: Dictionary = {
	ScoringEnums.SegmentColor.RED: "Red",
	ScoringEnums.SegmentColor.GREEN: "Green",
	ScoringEnums.SegmentColor.BLACK: "Black",
	ScoringEnums.SegmentColor.WHITE: "White",
}

## Which segment color this item grows. One of the four pool entries.
@export var target_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED

## Per stack, ring bands currently painted the target color widen radially by this fraction
## within their wedge; the wedge's non-target bands pay proportionally so the wedge's total
## radial span is conserved (zero-sum per wedge column).
@export var growth_factor: float = 0.30


func _init() -> void:
	modifier_name = "Color Territory"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.NONE
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION
	family = ScoringEnums.Family.GEOMETRY
	rarity_tier = ScoringEnums.Rarity.COMMON


## Fingerprint keys on the target color so the four colors read as distinct pool entries.
func get_config_fingerprint() -> String:
	return "%s|%d" % [get_script().resource_path, target_color]


func get_color_name() -> String:
	return COLOR_NAMES.get(target_color, "?")


## Geometry is computed by the manager from active_modifiers; nothing to write here.
func apply_to_board(_wedge_values: Array[int], _wedge_colors: Array[Dictionary], _config: Dictionary) -> void:
	pass


static func get_pool_weight() -> int:
	# ~8 per variant × 4 colors.
	return 32


static func get_rarity_weights() -> Array[int]:
	return [100, 0, 0]


## Build a specific color entry.
static func make(color: ScoringEnums.SegmentColor) -> ColorTerritoryModifier:
	var mod: ColorTerritoryModifier = ColorTerritoryModifier.new()
	mod.target_color = color
	var name: String = COLOR_NAMES.get(color, "?")
	mod.modifier_name = "Grow %s" % name
	mod.description = "%s bands grow within each wedge; that wedge's other bands shrink to pay." % name
	return mod


static func generate(_rarity_tier: ScoringEnums.Rarity) -> ColorTerritoryModifier:
	var colors: Array[ScoringEnums.SegmentColor] = [
		ScoringEnums.SegmentColor.RED,
		ScoringEnums.SegmentColor.GREEN,
		ScoringEnums.SegmentColor.WHITE,
		ScoringEnums.SegmentColor.BLACK,
	]
	return make(colors[randi_range(0, colors.size() - 1)])
