class_name StreakBonusModifier
extends ScoringModifier
## Awards cumulative multiplier bonus per consecutive hit on the same wedge.
## Any ring on the same numbered wedge counts (whole-wedge matching).
## First qualifying hit scores normally. Second gets +bonus_per_hit x. Etc.

## Multiplier added per consecutive same-wedge hit. Default 2 because grouping
## (consecutive same-wedge throws) is significantly harder than streaking
## color or parity.
@export var bonus_per_hit: int = 2

var _streak_wedge_index: int = -1
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Wedge Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.WEDGE


func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.WEDGE_SECTOR


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var wedge_index: int = result.get("wedge_index", -1)

	if wedge_index < 0 or result.get("is_bull", false):
		if not is_preview:
			_reset_streak()
		return result

	var ring_name: String = result.get("ring_name", "")
	if ring_name == "Off Board":
		if not is_preview:
			_reset_streak()
		return result

	# Calculate what the streak would be without mutating state during preview
	var effective_count: int = _streak_count
	if _streak_wedge_index < 0 or wedge_index == _streak_wedge_index:
		effective_count += 1
	else:
		effective_count = 1

	if not is_preview:
		_streak_count = effective_count
		_streak_wedge_index = wedge_index

	var bonus: int = effective_count - 1
	if bonus > 0:
		for i: int in range(bonus * bonus_per_hit):
			var old_mult: int = result["multiplier"]
			result["multiplier"] += 1
			result["total_score"] = result["face_value"] * result["multiplier"]
			_track_modification(result, "multiplier", old_mult, result["multiplier"])
		result["streak_triggered"] = true
		result["streak_name"] = modifier_name
		result["streak_count"] = effective_count

	return result


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
	mod.description = "+%dx per consecutive same-wedge hit (per %s)" % [mod.bonus_per_hit, scope_name]

	mod.roll_toggleable()
	return mod
