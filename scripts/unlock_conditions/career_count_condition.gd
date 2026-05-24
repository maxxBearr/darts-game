class_name CareerCountCondition
extends UnlockCondition
## Triggered on any event. Checks a PlayerProgress career stat against a threshold.

## Stat name to read from PlayerProgress.career_stats.
@export var stat_name: StringName = &""

## Threshold the stat must reach. Inclusive (>=).
@export var threshold: int = 1


func is_satisfied(_event_name: StringName, _context: Dictionary) -> bool:
	if stat_name == &"":
		return false
	return PlayerProgress.get_stat(stat_name) >= threshold
