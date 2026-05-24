class_name RelicCountCondition
extends UnlockCondition
## Triggered on item_acquired. Checks how many RELIC-kind modifiers are
## currently active simultaneously. Used for "amass N items" milestones.
##
## RELIC modifiers persist in the player's inventory; BOARD_MUTATION modifiers
## (wedge swaps, board mutations) fire once on acquire and do NOT count.

## Minimum number of active RELIC modifiers required.
@export var min_relic_count: int = 6


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
	if event_name != &"item_acquired":
		return false
	var count: int = context.get("active_relic_count", 0)
	return count >= min_relic_count
