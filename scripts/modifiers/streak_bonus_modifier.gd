class_name StreakBonusModifier
extends ScoringModifier
## Awards bonus points when the player lands a streak of consecutive hits
## on segments of the same color. Checks the hit history based on streak_scope
## to count how many consecutive same-color hits precede this one.
## Example: "3 consecutive same-color hits: +15 bonus points"

## How many consecutive same-color hits (including the current one) are required.
@export var required_streak: int = 3

## Flat bonus points added to total_score when the streak triggers.
@export var bonus_points: int = 15


func _init() -> void:
	modifier_name = "Color Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	streak_scope = ScoringEnums.StreakScope.WITHIN_LEG
	config_type = ScoringEnums.ConfigType.NONE


## Checks the appropriate history (based on streak_scope) for consecutive same-color hits.
## If the current dart extends the streak to required_streak, adds bonus_points.
func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	# Select the right history array based on streak_scope
	var history: Array = []
	match streak_scope:
		ScoringEnums.StreakScope.WITHIN_TURN:
			history = context["history_turn"]
		ScoringEnums.StreakScope.WITHIN_LEG:
			history = context["history_leg"]
		ScoringEnums.StreakScope.WITHIN_RUN:
			history = context["history_run"]

	# Need at least (required_streak - 1) previous hits to check
	if history.size() < required_streak - 1:
		return result

	# Check if the last (required_streak - 1) hits share the same color as current
	var current_color: int = result.get("segment_color", -1)
	if current_color == -1:
		return result

	var streak_valid: bool = true
	for i: int in range(1, required_streak):
		var past_idx: int = history.size() - i
		if past_idx < 0:
			streak_valid = false
			break
		var past_color: int = history[past_idx].get("segment_color", -2)
		if past_color != current_color:
			streak_valid = false
			break

	if streak_valid:
		var old_total: int = result["total_score"]
		result["total_score"] += bonus_points
		_track_modification(result, "total_score", old_total, result["total_score"])
		# Tag the result so HUD can show streak feedback
		result["streak_triggered"] = true
		result["streak_name"] = modifier_name
		result["streak_bonus"] = bonus_points

	return result
