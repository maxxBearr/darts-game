class_name TwoDartsBoss
extends Boss
## Boss that reduces the player's darts per turn for the entire leg.
## Tuning key: "dart_count" (int, default 2).

var dart_count: int = 2
var _original_darts_per_turn: int = 3


func configure(tuning: Dictionary) -> void:
	dart_count = tuning.get("dart_count", 2)


func on_leg_start(game_state: Dictionary) -> void:
	var x01: Node = game_state["x01_game"]
	_original_darts_per_turn = x01.darts_per_turn
	x01.darts_per_turn = dart_count


func get_status_text() -> String:
	return "%d dart%s per turn" % [dart_count, "" if dart_count == 1 else "s"]


func on_leg_end(game_state: Dictionary) -> void:
	var x01: Node = game_state["x01_game"]
	x01.darts_per_turn = _original_darts_per_turn
