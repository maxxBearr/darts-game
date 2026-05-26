class_name RotationBoss
extends Boss
## At the start of each turn, the dartboard rotates by a random angle.
## Tuning keys: "min_rotation_deg" (float), "max_rotation_deg" (float).

var min_rotation_deg: float = 45.0
var max_rotation_deg: float = 90.0
var _cumulative_rotation: float = 0.0


func configure(tuning: Dictionary) -> void:
	min_rotation_deg = tuning.get("min_rotation_deg", 45.0)
	max_rotation_deg = tuning.get("max_rotation_deg", 90.0)


func on_leg_start(_game_state: Dictionary) -> void:
	_cumulative_rotation = 0.0


func on_turn_start(game_state: Dictionary) -> void:
	var dartboard: Node2D = game_state["dartboard"]
	var angle: float = randf_range(min_rotation_deg, max_rotation_deg)
	if randi() % 2 == 0:
		angle = -angle
	_cumulative_rotation += angle
	dartboard.set_board_rotation(_cumulative_rotation)


func get_status_text() -> String:
	return "Board rotates %d-%d each turn" % [int(min_rotation_deg), int(max_rotation_deg)]


func on_leg_end(game_state: Dictionary) -> void:
	var dartboard: Node2D = game_state["dartboard"]
	dartboard.board_rotation_offset = 0.0
	dartboard.queue_redraw()
	_cumulative_rotation = 0.0
