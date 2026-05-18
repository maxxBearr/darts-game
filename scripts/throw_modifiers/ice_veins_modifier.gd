class_name IceVeinsModifier
extends ThrowModifier
## +10 to both accuracy stats when checkout is possible.
## Checkout = remaining score is <= 40 (max single-dart double-out).
## Dead weight during bulk scoring, clutch at the finish.

## Remaining score must be at or below this for the bonus to activate.
## 40 = highest double (D20). Adjust if board modifiers change this.
@export var checkout_threshold: int = 40


## Activates when remaining score is within checkout range.
func should_activate(context: Dictionary) -> bool:
	var remaining: int = context.get("remaining_score", 0) as int
	return remaining <= checkout_threshold and remaining > 0
