class_name StreakBonusModifier
extends ScoringModifier
## The WEDGE streak — the multiplicative scaling axis for hitting the same number
## repeatedly (any ring on the same numbered wedge counts). Capacity-gated by the shaft.
## First qualifying hit scores normally (×1). Each further consecutive same-wedge hit
## raises the multiplicative factor: factor = 1 + (count - 1) × streak_growth, applied to
## the whole additive baseline (face × (ring + hotspot)) as the LAST scoring step.
## This is the one sanctioned way past the ~140 streakless baseline — earned, not
## accumulated, and it resets on a miss.

## Streak growth slope (per consecutive hit) for the multiplicative factor. The headline
## tuning dial: 1 = linear-in-count (×streak_count), the spec's recommended sweet spot;
## higher values ramp faster. Kept on the wedge streak because grouping the same number
## is the harder feat, so Max may tune it above the color streak.
@export var streak_growth: int = 1

var _streak_wedge_index: int = -1
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Wedge Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.WEDGE


func get_streak_state_hash() -> int:
	return (_streak_count * 31 + (_streak_wedge_index + 1)) & 0x7FFFFFFF


func get_config_fingerprint() -> String:
	return "%s|%d" % [super.get_config_fingerprint(), streak_scope]


func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.WEDGE_SECTOR


## Report this wedge streak's contribution to the combined streak factor. Runs the
## continue/break logic and updates state (only on real throws), but does NOT mutate the
## score — the manager sums all streaks into one factor and applies it once.
func streak_contribution(result: Dictionary, context: Dictionary) -> int:
	var is_preview: bool = context.get("is_preview", false)
	var wedge_index: int = result.get("wedge_index", -1)

	if wedge_index < 0 or result.get("is_bull", false):
		if not is_preview:
			_reset_streak()
		return 0

	var ring_name: String = result.get("ring_name", "")
	if ring_name == "Off Board":
		if not is_preview:
			_reset_streak()
		return 0

	# Calculate what the streak would be without mutating state during preview
	var effective_count: int = _streak_count
	if _streak_wedge_index < 0 or wedge_index == _streak_wedge_index:
		effective_count += 1
	else:
		effective_count = 1

	if not is_preview:
		_streak_count = effective_count
		_streak_wedge_index = wedge_index

	if effective_count <= 1:
		return 0
	return (effective_count - 1) * streak_growth


func would_continue_streak(target: Dictionary) -> bool:
	if _streak_count <= 0:
		return false
	if target.get("is_bull", false) or target.get("ring_name", "") == "Off Board":
		return false
	var wedge_index: int = target.get("wedge_index", -1)
	return wedge_index >= 0 and wedge_index == _streak_wedge_index


func _reset_streak() -> void:
	_streak_wedge_index = -1
	_streak_count = 0


func reset_streak_state() -> void:
	_reset_streak()


func save_streak_state() -> Dictionary:
	return {"wedge_index": _streak_wedge_index, "count": _streak_count}


func restore_streak_state_from(snapshot: Dictionary) -> void:
	_streak_wedge_index = snapshot.get("wedge_index", -1)
	_streak_count = snapshot.get("count", 0)


func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	return "Wedge ×%d" % _streak_count


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> StreakBonusModifier:
	var mod: StreakBonusModifier = StreakBonusModifier.new()
	mod.rarity_tier = rarity_tier

	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_TURN
		ScoringEnums.Rarity.UNCOMMON:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_LEG
		ScoringEnums.Rarity.RARE:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_RUN

	const SCOPE_NAMES: Dictionary = {
		ScoringEnums.StreakScope.WITHIN_TURN: "turn",
		ScoringEnums.StreakScope.WITHIN_LEG: "leg",
		ScoringEnums.StreakScope.WITHIN_RUN: "run",
	}
	var scope_name: String = SCOPE_NAMES[mod.streak_scope]

	mod.modifier_name = "Wedge Streak"
	mod.description = "×streak multiplier per consecutive same-wedge hit (per %s)" % scope_name

	return mod
