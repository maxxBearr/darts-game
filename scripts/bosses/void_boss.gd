class_name VoidBoss
extends Boss
## At the start of each turn, N random wedge segments become voids (score zero).
## Void positions reroll each turn. Tuning key: "void_count" (int, default 6).

var void_count: int = 6
var _void_wedge_indices: Array[int] = []
var _original_wedge_values: Array[int] = []


func configure(tuning: Dictionary) -> void:
	void_count = tuning.get("void_count", 6)


func on_leg_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	_original_wedge_values = smm.effective_wedge_values.duplicate()


func on_turn_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	_restore_wedge_values(smm)

	var available: Array[int] = []
	for i: int in range(20):
		available.append(i)
	available.shuffle()
	_void_wedge_indices = available.slice(0, mini(void_count, 20))

	for idx: int in _void_wedge_indices:
		smm.effective_wedge_values[idx] = 0
	smm._bump_state_version()

	dartboard.effective_wedge_values = smm.effective_wedge_values
	dartboard.set_boss_void_wedges(_void_wedge_indices)


func on_leg_end(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]
	_restore_wedge_values(smm)
	dartboard.effective_wedge_values = smm.effective_wedge_values
	dartboard.clear_boss_overlays()
	_void_wedge_indices.clear()


func _restore_wedge_values(smm: Node) -> void:
	for idx: int in _void_wedge_indices:
		if idx < _original_wedge_values.size():
			smm.effective_wedge_values[idx] = _original_wedge_values[idx]
	if _void_wedge_indices.size() > 0:
		smm._bump_state_version()


func get_status_text() -> String:
	return "%d wedges voided — rerolls each turn" % void_count


func get_visual_overlay() -> Array:
	return [{"type": "void_wedges", "wedge_indices": _void_wedge_indices}]
