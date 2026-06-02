class_name FlipSignModifier
extends ScoringModifier
## Negates the final dart score on a single chosen wedge. The wedge's stored face
## value stays positive (multiplier math needs it); only the emitted total_score is
## flipped to negative, so a hit on this wedge ADDS to the remaining score instead of
## subtracting (remaining - (negative) = remaining + value).
##
## This fires PER_DART as the dead-last step in the scoring pipeline (the manager runs
## flip modifiers in a second pass after every other modifier), so the negate composes
## cleanly with face boosts, ring multipliers, and relic bonuses. The negate is
## idempotent (-abs), so two flips on the same wedge still produce a negative score.
##
## Kind is BOARD_MUTATION (not RELIC) on purpose: to the player this is a one-time board
## change like a wedge boost — the "+" on the wedge is its only indicator, so it has no
## modifier-panel presence and isn't counted as a relic. Only `kind` drives those two
## things; the per-dart pipeline is gated on `timing`, so it still evaluates every dart.

## The board position (0-19) whose darts get negated. Set by the wedge picker after
## acquisition. -1 means unconfigured.
@export var target_wedge_index: int = -1


func _init() -> void:
	modifier_name = "Flipped Wedge"
	description = "Pick a wedge, its scoring now adds to the score"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.PICK_WEDGE
	kind = ScoringEnums.ModifierKind.BOARD_MUTATION


## Negate the dart's total score when it lands on the flipped wedge. Bulls have no
## wedge index, so they're never affected. Uses -abs() so the result is always
## negative regardless of how many flips stack on the same wedge.
func apply(result: Dictionary, _context: Dictionary) -> Dictionary:
	if result.get("is_bull", false):
		return result
	if result.get("wedge_index", -2) != target_wedge_index:
		return result
	var old_total: int = result["total_score"]
	var new_total: int = -abs(old_total)
	if new_total != old_total:
		_track_modification(result, "flip", old_total, new_total)
		result["total_score"] = new_total
	return result


func get_config_fingerprint() -> String:
	return "%s|%d" % [super.get_config_fingerprint(), target_wedge_index]


func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.NONE


func apply_picked_wedge(wedge_index: int) -> void:
	target_wedge_index = wedge_index


## Follow the wedge through a swap — the flip belongs to the wedge, not the slot, so
## when its wedge moves to the other position the flip moves with it (like the colors).
func on_wedges_swapped(idx_a: int, idx_b: int) -> void:
	if target_wedge_index == idx_a:
		target_wedge_index = idx_b
	elif target_wedge_index == idx_b:
		target_wedge_index = idx_a


func get_pick_wedge_header() -> String:
	return "Flip a wedge"


func get_pick_wedge_prompt(current_value: int) -> String:
	return "Flip wedge %d? Its scoring will now add to the score. Click to confirm" % current_value


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [100, 0, 0]


static func generate(_rarity_tier: ScoringEnums.Rarity) -> FlipSignModifier:
	var mod: FlipSignModifier = FlipSignModifier.new()
	mod.rarity_tier = ScoringEnums.Rarity.COMMON
	mod.modifier_name = "Flipped Wedge"
	mod.description = "Pick a wedge, its scoring now adds to the score"
	return mod
