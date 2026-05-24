class_name SlotsFilledCondition
extends UnlockCondition
## Triggered on slots_state_changed. Returns true when one streak modifier
## from each of the three streak categories (WEDGE, COLOR, PARITY) is active
## simultaneously.
##
## For "amass N relic items" style milestones, use RelicCountCondition instead.


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
	if event_name != &"slots_state_changed":
		return false
	return context.get("all_streak_categories_filled", false)
