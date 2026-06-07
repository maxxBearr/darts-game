class_name PrismBoss
extends Boss
## The board fractures color where you touch it. Prism does nothing at leg start;
## instead, each dart that lands recolors the hit segment(s) to a random color, and
## that recolor persists for the rest of the leg. Consequences accumulate from the
## player's own choices — they watch the board mutate as they hit it and start
## routing around the corners they've already poisoned.
##
## Counters color/affinity builds. Color only, never value (orthogonal to Weak Board).
## The checkout helper is suppressed while Prism is active (see main.gd) — color and
## value can't be trusted once the board mutates reactively.
##
## Tuning key "splash" (String) sets the recolor radius per difficulty tier:
##   "wedge"           (easy)   — every ring of the hit wedge.
##   "wedge_neighbors" (medium) — the whole hit wedge + the hit ring on both
##                                physically-adjacent wedges (hit OS20 → all of 20's
##                                rings, plus OS5 and OS1).
##   "three_wedges"    (hard)   — every ring of the hit wedge AND both neighbor wedges
##                                (hit OS20 → wedges 20, 5 and 1 each fully recolored).
## The recolor reveal radiates outward from the hit ring (closest rings first).

const RING_KEYS: Array[String] = ["inner_single", "triple", "outer_single", "double"]

const RANDOM_COLORS: Array[int] = [
	ScoringEnums.SegmentColor.RED,
	ScoringEnums.SegmentColor.GREEN,
	ScoringEnums.SegmentColor.BLACK,
	ScoringEnums.SegmentColor.WHITE,
]

## Maps the ring_name produced by Dartboard.calculate_score to the color dict key.
const RING_NAME_TO_KEY: Dictionary = {
	"Inner Single": "inner_single",
	"Triple": "triple",
	"Outer Single": "outer_single",
	"Double": "double",
}

var splash: String = "wedge"
var _original_colors: Array[Dictionary] = []


func configure(tuning: Dictionary) -> void:
	splash = tuning.get("splash", "wedge")


func on_leg_start(game_state: Dictionary) -> void:
	# Snapshot for restore at leg end only — no mutation at leg start.
	var smm: Node = game_state["scoring_modifier_manager"]
	_original_colors.clear()
	for color_dict: Dictionary in smm.effective_wedge_colors:
		_original_colors.append(color_dict.duplicate())


func on_dart_landed(result: Dictionary, game_state: Dictionary) -> void:
	var wedge_index: int = result.get("wedge_index", -1)
	if wedge_index < 0 or wedge_index >= 20:
		return  # bull or off-board — nothing to recolor.
	if result.get("is_bull", false):
		return
	var ring_key: String = RING_NAME_TO_KEY.get(result.get("ring_name", ""), "")
	if ring_key == "":
		return

	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]
	var hit_ring_idx: int = RING_KEYS.find(ring_key)

	# Build the (wedge, ring) list to recolor for this tier.
	var targets: Array[Dictionary] = []
	match splash:
		"wedge_neighbors":  # medium: whole hit wedge + hit ring on both neighbors
			for key: String in RING_KEYS:
				targets.append({"wedge": wedge_index, "ring": key})
			targets.append({"wedge": (wedge_index + 1) % 20, "ring": ring_key})
			targets.append({"wedge": (wedge_index + 19) % 20, "ring": ring_key})
		"three_wedges":  # hard: every ring of the hit wedge and both neighbors
			for w: int in [wedge_index, (wedge_index + 1) % 20, (wedge_index + 19) % 20]:
				for key: String in RING_KEYS:
					targets.append({"wedge": w, "ring": key})
		_:  # "wedge" (easy) and any unknown tier: every ring of the hit wedge
			for key: String in RING_KEYS:
				targets.append({"wedge": wedge_index, "ring": key})

	# Recolor each target to a different color, capturing the prev color and the
	# distance from the hit ring so the dartboard can radiate the reveal outward.
	var segments: Array[Dictionary] = []
	for t: Dictionary in targets:
		var w: int = t["wedge"]
		var key: String = t["ring"]
		var entry: Dictionary = smm.effective_wedge_colors[w]
		var prev: int = int(entry.get(key, -1))
		entry[key] = _pick_new_color(prev)
		smm.effective_wedge_colors[w] = entry
		var ring_dist: int = absi(RING_KEYS.find(key) - hit_ring_idx)
		var wedge_dist: int = 0 if w == wedge_index else 1
		segments.append({"wedge": w, "ring": key, "prev_color": prev, "dist": ring_dist + wedge_dist})

	smm._bump_state_version()
	dartboard.effective_wedge_colors = smm.effective_wedge_colors
	# Color Territory is DYNAMIC — recompute geometry against the freshly-repainted board so a
	# grown color re-flows as Prism contests it (this fires at score resolution, between darts).
	smm.recompute_geometry()
	dartboard.set_geometry(smm.effective_wedge_weights, smm.effective_ring_bounds, smm.bull_radii)
	dartboard.play_prism_recolor(segments)


## Pick a random color *different from* `current`. Excluding the current color
## guarantees a visible change on every hit — a same-color reroll (green→green) reads
## as "no impact," which is exactly what we don't want from a recolor-on-hit boss.
func _pick_new_color(current: int) -> int:
	var choices: Array[int] = []
	for c: int in RANDOM_COLORS:
		if c != current:
			choices.append(c)
	if choices.is_empty():
		choices = RANDOM_COLORS.duplicate()  # defensive: current wasn't a known color.
	return choices[randi_range(0, choices.size() - 1)]


func get_status_text() -> String:
	return "The board recolors where you hit it"


func on_leg_end(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	for i: int in range(20):
		if i < _original_colors.size():
			smm.effective_wedge_colors[i] = _original_colors[i].duplicate()
	smm._bump_state_version()
	# Restoring colors can revert a Color Territory grow — recompute so the geometry follows.
	smm.recompute_geometry()

	dartboard.effective_wedge_colors = smm.effective_wedge_colors
	dartboard.set_geometry(smm.effective_wedge_weights, smm.effective_ring_bounds, smm.bull_radii)
	dartboard.queue_redraw()
