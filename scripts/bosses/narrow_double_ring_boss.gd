class_name NarrowDoubleRingBoss
extends Boss
## Narrows the double ring for the entire leg/race, making checkout doubles harder.
##
## RELATIVE, not absolute: width_scale is a multiplier the dartboard folds onto each wedge's
## CURRENT double width (RING_DOUBLE_OUTER − (RING_DOUBLE_OUTER − current_inner) × width_scale,
## see dartboard._effective_double_inner_*). So it shrinks whatever double the player currently
## has — a GEOMETRY item that widened the double is preserved proportionally (a wider double
## stays wider after the squeeze), rather than collapsing every player to one destination width.
## Tuning key: "width_scale" (the fraction of the current width that REMAINS — 0.5 = keep half /
## shrink by 50%, 0.25 = keep a quarter / shrink by 75%).

## Fraction of the CURRENT double width that survives the squeeze (1.0 = untouched, 0.5 = half).
## Lower = a harsher checkout. Relative to the live (geometry-inclusive) width, so it scales the
## player's actual double rather than snapping it to a fixed size. Overridable via configure().
@export_range(0.05, 1.0, 0.05) var width_scale: float = 0.5


func configure(tuning: Dictionary) -> void:
	width_scale = tuning.get("width_scale", width_scale)


func get_status_text() -> String:
	return "Double ring at %d%% width" % int(width_scale * 100)


func on_leg_start(game_state: Dictionary) -> void:
	var dartboard: Node2D = game_state["dartboard"]
	dartboard.set_double_ring_scale(width_scale)


func on_leg_end(game_state: Dictionary) -> void:
	var dartboard: Node2D = game_state["dartboard"]
	dartboard.set_double_ring_scale(1.0)
