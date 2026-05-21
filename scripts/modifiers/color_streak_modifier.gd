class_name ColorStreakModifier
extends ScoringModifier
## Awards cumulative +1x multiplier per consecutive hit on the same segment color.
## First qualifying hit scores normally. Second consecutive gets +1x. Third gets +2x. Etc.
## Tracks which SegmentColor was last hit to maintain the streak.

## The last segment color that was hit (for streak continuity checks).
var _streak_color: int = -1

## Current number of consecutive same-color hits.
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Color Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.COLOR


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var segment_color: int = result.get("segment_color", -1)

	# No color info (off board, etc.) — break the streak
	if segment_color < 0:
		if not is_preview:
			_reset_streak()
		return result

	# Calculate what the streak would be
	var effective_count: int = _streak_count
	if segment_color == _streak_color:
		effective_count += 1
	else:
		effective_count = 1

	# Update state only for real throws
	if not is_preview:
		_streak_count = effective_count
		_streak_color = segment_color

	# Apply bonus: streak count - 1 extra multipliers
	var bonus: int = effective_count - 1
	if bonus > 0:
		for i: int in range(bonus):
			var old_mult: int = result["multiplier"]
			result["multiplier"] += 1
			result["total_score"] = result["face_value"] * result["multiplier"]
			_track_modification(result, "multiplier", old_mult, result["multiplier"])
		result["streak_triggered"] = true
		result["streak_name"] = modifier_name
		result["streak_count"] = effective_count

	return result


func _reset_streak() -> void:
	_streak_color = -1
	_streak_count = 0


func reset_streak_state() -> void:
	_reset_streak()


func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	if _streak_count <= 0:
		return ""
	return "Color ×%d" % _streak_count


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> ColorStreakModifier:
	var mod: ColorStreakModifier = ColorStreakModifier.new()
	mod.rarity_tier = rarity_tier

	# Roll streak scope
	var scopes: Array[ScoringEnums.StreakScope] = [
		ScoringEnums.StreakScope.WITHIN_TURN,
		ScoringEnums.StreakScope.WITHIN_LEG,
	]
	mod.streak_scope = scopes[randi_range(0, scopes.size() - 1)]

	var scope_name: String = "turn" if mod.streak_scope == ScoringEnums.StreakScope.WITHIN_TURN else "leg"

	mod.modifier_name = "Color Streak"
	mod.description = "+1x per consecutive same-color hit (per %s)" % scope_name

	return mod
