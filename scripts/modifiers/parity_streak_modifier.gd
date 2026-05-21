class_name ParityStreakModifier
extends ScoringModifier
## Base class for parity streak modifiers. Awards cumulative +1x multiplier per
## consecutive hit on wedges matching the target parity (odd or even face values).
## First qualifying hit scores normally. Second consecutive gets +1x. Third gets +2x. Etc.
## Subclasses (EvenStreakModifier, OddStreakModifier) set target_is_odd to lock the parity.

## Whether this modifier tracks odd (true) or even (false) face values.
## Set by subclass _init() — determines which parity continues the streak.
@export var target_is_odd: bool = true

## Current number of consecutive matching-parity hits.
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Parity Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.PARITY


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var face_value: int = result.get("face_value", 0)

	# No face value (off board) — break the streak
	if face_value <= 0:
		if not is_preview:
			_reset_streak()
		return result

	var is_odd: bool = face_value % 2 == 1

	# Wrong parity — break the streak
	if is_odd != target_is_odd:
		if not is_preview:
			_reset_streak()
		return result

	# Matching parity — extend the streak
	var effective_count: int = _streak_count + 1

	# Update state only for real throws
	if not is_preview:
		_streak_count = effective_count

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
	_streak_count = 0


func reset_streak_state() -> void:
	_reset_streak()


func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	if _streak_count <= 0:
		return ""
	var parity_label: String = "Odd" if target_is_odd else "Even"
	return "%s ×%d" % [parity_label, _streak_count]
