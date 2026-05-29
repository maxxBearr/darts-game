class_name PrismBoss
extends Boss
## At the start of each Nth turn, all wedge colors are randomly reshuffled.
## Tuning key: "reshuffle_interval" (int, default 1 = every turn).

var reshuffle_interval: int = 1
var _turns_since_shuffle: int = 0
var _original_colors: Array[Dictionary] = []


func configure(tuning: Dictionary) -> void:
	reshuffle_interval = tuning.get("reshuffle_interval", 1)


func on_leg_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	_original_colors.clear()
	for color_dict: Dictionary in smm.effective_wedge_colors:
		_original_colors.append(color_dict.duplicate())
	_turns_since_shuffle = reshuffle_interval - 1


func on_turn_start(game_state: Dictionary) -> void:
	_turns_since_shuffle += 1
	if _turns_since_shuffle % reshuffle_interval != 0:
		return

	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	dartboard.animate_color_transition()

	var indices: Array[int] = []
	for i: int in range(20):
		indices.append(i)
	indices.shuffle()

	for i: int in range(20):
		smm.effective_wedge_colors[i] = _original_colors[indices[i]].duplicate()
	smm._bump_state_version()

	dartboard.effective_wedge_colors = smm.effective_wedge_colors
	dartboard.queue_redraw()


func get_status_text() -> String:
	if reshuffle_interval <= 1:
		return "Colors shuffle every turn"
	var turns_until: int = reshuffle_interval - (_turns_since_shuffle % reshuffle_interval)
	if turns_until <= 1:
		return "Colors shuffle next turn"
	return "Colors shuffle in %d turns" % turns_until


func on_leg_end(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	for i: int in range(20):
		if i < _original_colors.size():
			smm.effective_wedge_colors[i] = _original_colors[i].duplicate()
	smm._bump_state_version()

	dartboard.effective_wedge_colors = smm.effective_wedge_colors
	dartboard.queue_redraw()
