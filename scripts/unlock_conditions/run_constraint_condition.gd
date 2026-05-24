class_name RunConstraintCondition
extends UnlockCondition
## Triggered on leg_won. Checks how many legs have been won this run while
## a run-scoped constraint flag remained satisfied.

## Minimum legs won this run.
@export var legs_won_this_run_threshold: int = 1

## If non-empty, the named flag on UnlockManager must be true.
@export var required_run_flag: StringName = &""


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
	if event_name != &"leg_won":
		return false

	var legs_this_run: int = context.get("legs_won_this_run", 0)
	if legs_this_run < legs_won_this_run_threshold:
		return false

	if required_run_flag != &"":
		if not UnlockManager.get_run_flag(required_run_flag):
			return false

	return true
