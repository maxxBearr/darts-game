class_name PrismBoss
extends Boss
## Inverts all wedge colors to their pair at leg start and holds for the entire leg.
## Red ↔ Green, Black ↔ White. Restores original colors at leg end.

const PAIR_MAP: Dictionary = {
	ScoringEnums.SegmentColor.RED: ScoringEnums.SegmentColor.GREEN,
	ScoringEnums.SegmentColor.GREEN: ScoringEnums.SegmentColor.RED,
	ScoringEnums.SegmentColor.BLACK: ScoringEnums.SegmentColor.WHITE,
	ScoringEnums.SegmentColor.WHITE: ScoringEnums.SegmentColor.BLACK,
}

var _original_colors: Array[Dictionary] = []


func configure(_tuning: Dictionary) -> void:
	pass


func on_leg_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	_original_colors.clear()
	for color_dict: Dictionary in smm.effective_wedge_colors:
		_original_colors.append(color_dict.duplicate())

	dartboard.animate_color_transition()

	for i: int in range(20):
		var entry: Dictionary = smm.effective_wedge_colors[i]
		for ring_key: String in ["inner_single", "triple", "outer_single", "double"]:
			entry[ring_key] = PAIR_MAP[entry[ring_key]]
		smm.effective_wedge_colors[i] = entry
	smm._bump_state_version()

	dartboard.effective_wedge_colors = smm.effective_wedge_colors
	dartboard.queue_redraw()


func get_status_text() -> String:
	return "All colors inverted for the leg"


func on_leg_end(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	for i: int in range(20):
		if i < _original_colors.size():
			smm.effective_wedge_colors[i] = _original_colors[i].duplicate()
	smm._bump_state_version()

	dartboard.effective_wedge_colors = smm.effective_wedge_colors
	dartboard.queue_redraw()
