class_name MomentumMarksmanModifier
extends ThrowModifier
## Accuracy bonus that scales with active streak count, but only when aiming
## at a target that would continue those streaks.

## Accuracy bonus per active streak count.
@export var accuracy_per_streak: float = 2.0


func should_activate(context: Dictionary) -> bool:
	return _get_total_streak_count(context) > 0


func get_active_bonuses(context: Dictionary = {}) -> Dictionary:
	var total: int = _get_total_streak_count(context)
	if total <= 0:
		return {}
	var bonus: float = accuracy_per_streak * total
	return {
		"horizontal_accuracy": bonus,
		"vertical_accuracy": bonus,
	}


func _get_total_streak_count(context: Dictionary) -> int:
	var target: Dictionary = context.get("declared_target", {})
	if target.is_empty():
		return 0
	var streak_mods: Array = context.get("active_streak_modifiers", [])
	var total: int = 0
	for mod in streak_mods:
		if mod.would_continue_streak(target):
			total += mod.get_streak_count()
	return total
