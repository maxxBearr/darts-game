class_name LegStatCondition
extends UnlockCondition
## Triggered on leg_won. Checks aggregate properties of the leg.

## Required target score for the leg. 0 = any.
@export var required_target_score: int = 0

## Minimum sum of the winning turn (the "checkout total"). 0 = no minimum.
@export var min_checkout_total: int = 0

## If true, all three darts of the winning turn must have scored.
@export var require_three_scoring_darts: bool = false


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
	if event_name != &"leg_won":
		return false

	var target: int = context.get("target_score", 0)
	var checkout_total: int = context.get("checkout_total", 0)
	var three_scored: bool = context.get("winning_turn_all_darts_scored", false)

	if required_target_score > 0 and target != required_target_score:
		return false
	if min_checkout_total > 0 and checkout_total < min_checkout_total:
		return false
	if require_three_scoring_darts and not three_scored:
		return false

	return true
