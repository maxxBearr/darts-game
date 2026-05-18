class_name NervousSweaterModifier
extends ThrowModifier
## +5 to both accuracy stats while remaining score is above a threshold.
## The player is calm and steady during bulk scoring, but loses the bonus
## once checkout range approaches. "Sweats when it gets real."

## Score must be above this value for the bonus to activate.
## At or below this threshold, the modifier turns off.
@export var score_threshold: int = 50


## Activates when the remaining score is above the threshold.
func should_activate(context: Dictionary) -> bool:
	var remaining: int = context.get("remaining_score", 0) as int
	return remaining > score_threshold
