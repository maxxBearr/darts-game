class_name RecessionBoss
extends Boss
## A randomly-selected color has its scoring values reduced for the entire leg.
## Locked at leg start — does not reroll per turn.
## Tuning key: "reduction_percent" (float, default 0.25 = -25%).

var reduction_percent: float = 0.25
var _affected_color: int = -1
var _original_wedge_values: Array[int] = []
var _affected_wedge_indices: Array[int] = []


func configure(tuning: Dictionary) -> void:
	reduction_percent = tuning.get("reduction_percent", 0.25)


func on_leg_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]
	_original_wedge_values = smm.effective_wedge_values.duplicate()

	var colors: Array[int] = [
		ScoringEnums.SegmentColor.RED,
		ScoringEnums.SegmentColor.GREEN,
		ScoringEnums.SegmentColor.BLACK,
		ScoringEnums.SegmentColor.WHITE,
	]
	_affected_color = colors[randi_range(0, 3)]

	_affected_wedge_indices.clear()
	for idx: int in range(20):
		if idx < smm.effective_wedge_colors.size():
			var wedge_color: Dictionary = smm.effective_wedge_colors[idx]
			if wedge_color.get("single", -1) == _affected_color:
				_affected_wedge_indices.append(idx)
				var original_val: int = smm.effective_wedge_values[idx]
				var reduced: int = int(original_val * (1.0 - reduction_percent))
				smm.effective_wedge_values[idx] = maxi(reduced, 0)

	dartboard.effective_wedge_values = smm.effective_wedge_values
	dartboard.boss_reduced_wedges = _affected_wedge_indices.duplicate()
	dartboard.set_boss_recession_wedges(_affected_wedge_indices)
	dartboard.queue_redraw()


func on_leg_end(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	for idx: int in _affected_wedge_indices:
		if idx < _original_wedge_values.size():
			smm.effective_wedge_values[idx] = _original_wedge_values[idx]

	dartboard.effective_wedge_values = smm.effective_wedge_values
	dartboard.boss_reduced_wedges.clear()
	dartboard.set_boss_recession_wedges([] as Array[int])
	dartboard.queue_redraw()
	_affected_wedge_indices.clear()


func get_status_text() -> String:
	var color_names: Array[String] = ["Red", "Green", "Black", "White"]
	var name: String = color_names[_affected_color] if _affected_color >= 0 and _affected_color < 4 else "?"
	return "%s wedges -%d%% for the leg" % [name, int(reduction_percent * 100)]


func get_visual_overlay() -> Array:
	return [{"type": "recession", "affected_color": _affected_color, "wedge_indices": _affected_wedge_indices}]
