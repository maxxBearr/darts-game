class_name ParityShiftModifier
extends ScoringModifier
## GEOMETRY family — angularly widens every wedge whose CURRENT effective face value matches a
## parity (even or odd); all 20 wedge weights renormalize to 360°, so the matching wedges grow
## at the non-matching wedges' expense (zero-sum, board-wide, rarity-less).
##
## DYNAMIC: ScoringModifierManager.recompute_geometry() recomputes this from the LIVE
## effective_wedge_values on every face-value change. With Wedge Swap sidelined (geometry spec
## §9a), the pool-facing parity contest now rides Wedge Value (a +1 flips a wedge's parity,
## moving it between the grown and shrunk sets). Adjacent same-parity wedges exist (18–4, 6–10,
## 16–8; 17–3–19–7 is a run of four odds) — renormalization is exactly why this works with no
## neighbor edge cases: a wider wedge simply pushes its boundaries into the narrower neighbors.
## Self-limiting: if every wedge matched the parity, renormalization returns them all to base.
##
## Known polarizing item; ships as the experiment. Two pool entries: Grow Even / Grow Odd.
## Carries no board mutation of its own; apply_to_board is a no-op (the manager reads it).

## Which parity this item grows. true = grow even-valued wedges, false = grow odd-valued.
@export var grow_even: bool = true

## Per stack, the angular weight multiplier applied to wedges whose current effective face
## value matches the parity. All 20 weights renormalize to 360° after, so this is zero-sum.
@export var weight_factor: float = 1.25


func _init() -> void:
	modifier_name = "Parity Shift"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.NONE
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION
	family = ScoringEnums.Family.GEOMETRY
	rarity_tier = ScoringEnums.Rarity.COMMON


## Fingerprint keys on the parity so the two directions read as distinct pool entries.
func get_config_fingerprint() -> String:
	return "%s|%s" % [get_script().resource_path, "E" if grow_even else "O"]


## Geometry is computed by the manager from active_modifiers; nothing to write here.
func apply_to_board(_wedge_values: Array[int], _wedge_colors: Array[Dictionary], _config: Dictionary) -> void:
	pass


static func get_pool_weight() -> int:
	# ~8 per variant × 2 parities.
	return 16


static func get_rarity_weights() -> Array[int]:
	return [100, 0, 0]


## Build a specific parity entry.
static func make(even: bool) -> ParityShiftModifier:
	var mod: ParityShiftModifier = ParityShiftModifier.new()
	mod.grow_even = even
	if even:
		mod.modifier_name = "Grow Even"
		mod.description = "Even-valued wedges widen; odd-valued wedges narrow to pay."
	else:
		mod.modifier_name = "Grow Odd"
		mod.description = "Odd-valued wedges widen; even-valued wedges narrow to pay."
	return mod


static func generate(_rarity_tier: ScoringEnums.Rarity) -> ParityShiftModifier:
	return make(randi_range(0, 1) == 0)
