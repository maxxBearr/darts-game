class_name TwoDartsBoss
extends Boss
## DEPRECATED — archived for reuse (2026-06-01, Boss Redesign spec). "Just take away
## X darts per turn" is a flat resource tax that doesn't change how you play — it fails
## the build-counter/environmental design test, so one_dart and two_darts were cut from
## all level pools. The code + .tres stay in place (moving them risks the .tres/uid
## references). The "−1 dart" idea survives only as a possible future reward-tradeoff
## (the Glass Cannon pattern), never again as a boss. Backs both one_dart.tres and
## two_darts.tres via the "dart_count" tuning key.
##
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
