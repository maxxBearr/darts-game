class_name NarrowDoubleRingBoss
extends Boss
## Narrows the double ring for the entire leg, making checkout doubles harder.
## Tuning key: "width_scale" (float, 0.5 = half width, 0.25 = quarter width).

var width_scale: float = 0.5


func configure(tuning: Dictionary) -> void:
	width_scale = tuning.get("width_scale", 0.5)


func get_status_text() -> String:
	return "Double ring at %d%% width" % int(width_scale * 100)


func on_leg_start(game_state: Dictionary) -> void:
	var dartboard: Node2D = game_state["dartboard"]
	dartboard.set_double_ring_scale(width_scale)


func on_leg_end(game_state: Dictionary) -> void:
	var dartboard: Node2D = game_state["dartboard"]
	dartboard.set_double_ring_scale(1.0)
