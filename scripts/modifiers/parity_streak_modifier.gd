class_name ParityStreakModifier
extends ScoringModifier
## Awards cumulative +1x multiplier per consecutive hit on wedges sharing the same
## parity (all odd or all even face values). First qualifying hit scores normally.
## Second consecutive gets +1x. Third gets +2x. Etc.

## Whether the current streak is tracking odd (true) or even (false).
## Determined by the first hit in a new streak.
var _streak_is_odd: bool = false

## Current number of consecutive same-parity hits.
var _streak_count: int = 0

## Whether a streak is actively being tracked (false at start / after reset).
var _streak_active: bool = false


func _init() -> void:
	modifier_name = "Parity Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.PARITY


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var face_value: int = result.get("face_value", 0)

	# No face value (off board, bull with 25 is odd — that's fine)
	if face_value <= 0:
		if not is_preview:
			_reset_streak()
		return result

	var is_odd: bool = face_value % 2 == 1

	# Calculate what the streak would be
	var effective_count: int = _streak_count
	if not _streak_active:
		# First hit starts a new streak
		effective_count = 1
	elif is_odd == _streak_is_odd:
		# Same parity — continue streak
		effective_count += 1
	else:
		# Different parity — break and restart
		effective_count = 1

	# Update state only for real throws
	if not is_preview:
		_streak_count = effective_count
		_streak_is_odd = is_odd
		_streak_active = true

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
	_streak_is_odd = false
	_streak_count = 0
	_streak_active = false


func reset_streak_state() -> void:
	_reset_streak()


func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	if _streak_count <= 0:
		return ""
	var parity_label: String = "Odd" if _streak_is_odd else "Even"
	return "%s ×%d" % [parity_label, _streak_count]


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> ParityStreakModifier:
	var mod: ParityStreakModifier = ParityStreakModifier.new()
	mod.rarity_tier = rarity_tier

	# Roll streak scope
	var scopes: Array[ScoringEnums.StreakScope] = [
		ScoringEnums.StreakScope.WITHIN_TURN,
		ScoringEnums.StreakScope.WITHIN_LEG,
	]
	mod.streak_scope = scopes[randi_range(0, scopes.size() - 1)]

	var scope_name: String = "turn" if mod.streak_scope == ScoringEnums.StreakScope.WITHIN_TURN else "leg"

	mod.modifier_name = "Parity Streak"
	mod.description = "+1x per consecutive same-parity hit (per %s)" % scope_name

	return mod
