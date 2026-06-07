class_name RingTradeModifier
extends ScoringModifier
## GEOMETRY family — a signed global triple↔double width dial. Board-wide, rarity-less,
## zero-sum: width moved out of one band is moved into the other on EVERY wedge, and the
## outer single band SLIDES (same width, shifted) so the singles — the board's brakes —
## stay untouched. This is the clean identity trade.
##
## Two pool entries share this class, distinguished by the SIGN of triple_shift:
##   • Wide Triple / Narrow Double  (scoring-lean, +shift) — fatter triples, thinner doubles.
##   • Wide Double / Narrow Triple  (checkout-lean, −shift) — fatter doubles, thinner triples.
## Opposite stacks net out arithmetically through the manager's shared accumulated dial —
## no special-case code (an event 1-of-3 may legitimately show both directions side by side).
##
## The modifier carries no board mutation of its own: it persists in active_modifiers and
## ScoringModifierManager.recompute_geometry() folds its accumulated shift into the per-wedge
## ring bounds. apply_to_board is therefore a no-op.

## Normalized radial width moved from the double band into the triple band per stack;
## negative moves it the other way. Triple base width 0.050, double base width 0.070.
## A positive value fattens the triple at the double's expense (scoring-lean); the outer
## single band slides outward by the same amount, keeping its width fixed.
@export var triple_shift: float = 0.015


func _init() -> void:
	modifier_name = "Ring Trade"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.NONE
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION
	family = ScoringEnums.Family.GEOMETRY
	rarity_tier = ScoringEnums.Rarity.COMMON


## Fingerprint keys on the SIGN of the shift so the two directions read as distinct pool
## entries to the distinctness logic (an event won't offer the same direction twice).
func get_config_fingerprint() -> String:
	var dir: String = "WT" if triple_shift >= 0.0 else "WD"
	return "%s|%s" % [get_script().resource_path, dir]


## Geometry is computed by the manager from active_modifiers; nothing to write here.
func apply_to_board(_wedge_values: Array[int], _wedge_colors: Array[Dictionary], _config: Dictionary) -> void:
	pass


static func get_pool_weight() -> int:
	# ~8 per variant × 2 directions (the spec's per-entry 8–10 starting weight).
	return 16


static func get_rarity_weights() -> Array[int]:
	# Rarity-less family: conservation eats the rarity axis, so always Common-tier.
	return [100, 0, 0]


## Build a specific direction. positive = Wide Triple / Narrow Double (scoring-lean).
static func make(positive: bool) -> RingTradeModifier:
	var mod: RingTradeModifier = RingTradeModifier.new()
	# Default magnitude lives on the export; flip its sign for the checkout-lean entry.
	if not positive:
		mod.triple_shift = -absf(mod.triple_shift)
	else:
		mod.triple_shift = absf(mod.triple_shift)
	if positive:
		mod.modifier_name = "Wide Triple / Narrow Double"
		mod.description = "Every triple band grows; every double band shrinks by the same amount. Singles unchanged."
	else:
		mod.modifier_name = "Wide Double / Narrow Triple"
		mod.description = "Every double band grows; every triple band shrinks by the same amount. Singles unchanged."
	return mod


static func generate(_rarity_tier: ScoringEnums.Rarity) -> RingTradeModifier:
	return make(randi_range(0, 1) == 0)
