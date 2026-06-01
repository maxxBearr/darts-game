class_name WeakBoardBoss
extends Boss
## The board wears out where you keep hitting it. Each hit on a wedge permanently
## reduces that wedge's scoring value; repeated hits stack the damage deeper. The
## board never heals during the leg, and a floor keeps a wedge from ever reaching 0
## (degraded-but-scorable stays distinct from a Void).
##
## Counters value-stacking builds: the power-through player's money wedge degrades
## fastest, while a spread player slowly wears down the whole board. Value only,
## never color (kept orthogonal to Prism). Reuses Recession's reduction plumbing,
## driven per-hit instead of once at leg start.
##
## Tuning keys:
##   "reduction_percent" (float, default 0.15): value lost per hit, compounding.
##   "floor_fraction"    (float, default 0.25): a wedge never drops below this
##                        fraction of its original value (and never below 1).

var reduction_percent: float = 0.15
var floor_fraction: float = 0.25

var _original_wedge_values: Array[int] = []
var _hit_counts: Dictionary = {}
var _affected_wedge_indices: Array[int] = []


func configure(tuning: Dictionary) -> void:
	reduction_percent = tuning.get("reduction_percent", 0.15)
	floor_fraction = tuning.get("floor_fraction", 0.25)


func on_leg_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	_original_wedge_values = smm.effective_wedge_values.duplicate()
	_hit_counts.clear()
	_affected_wedge_indices.clear()


func on_dart_landed(result: Dictionary, game_state: Dictionary) -> void:
	var wedge_index: int = result.get("wedge_index", -1)
	if wedge_index < 0 or wedge_index >= _original_wedge_values.size():
		return  # bull, off-board, or no wedge — nothing to wear.
	if result.get("is_bull", false):
		return

	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	var count: int = int(_hit_counts.get(wedge_index, 0)) + 1
	_hit_counts[wedge_index] = count

	var original: int = _original_wedge_values[wedge_index]
	var floor_value: int = maxi(ceili(original * floor_fraction), 1)
	var reduced: int = int(round(original * pow(1.0 - reduction_percent, count)))
	smm.effective_wedge_values[wedge_index] = maxi(reduced, floor_value)

	if not _affected_wedge_indices.has(wedge_index):
		_affected_wedge_indices.append(wedge_index)
	smm._bump_state_version()

	dartboard.effective_wedge_values = smm.effective_wedge_values
	dartboard.boss_reduced_wedges = _affected_wedge_indices.duplicate()
	dartboard.set_boss_recession_wedges(_affected_wedge_indices.duplicate())
	dartboard.queue_redraw()


func on_leg_end(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	for idx: int in _affected_wedge_indices:
		if idx < _original_wedge_values.size():
			smm.effective_wedge_values[idx] = _original_wedge_values[idx]
	smm._bump_state_version()

	dartboard.effective_wedge_values = smm.effective_wedge_values
	dartboard.boss_reduced_wedges.clear()
	dartboard.set_boss_recession_wedges([] as Array[int])
	dartboard.queue_redraw()
	_affected_wedge_indices.clear()
	_hit_counts.clear()


func get_status_text() -> String:
	return "The board wears down where you hit it (-%d%% per hit)" % int(reduction_percent * 100)


## Reduction info for a hit wedge, for the floating-score display. Returns the
## current effective reduction relative to the wedge's original value, or empty.
func get_reduction_for_wedge(wedge_index: int) -> Dictionary:
	if not _affected_wedge_indices.has(wedge_index):
		return {}
	if wedge_index < 0 or wedge_index >= _original_wedge_values.size():
		return {}
	var count: int = int(_hit_counts.get(wedge_index, 0))
	var effective_percent: float = 1.0 - pow(1.0 - reduction_percent, count)
	return {
		"percent": effective_percent,
		"original_face_value": _original_wedge_values[wedge_index],
	}


func get_visual_overlay() -> Array:
	return [{"type": "weak_board", "wedge_indices": _affected_wedge_indices}]
