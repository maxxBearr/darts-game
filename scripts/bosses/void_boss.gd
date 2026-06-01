class_name VoidBoss
extends Boss
## At the start of each turn, N whole wedges become voids (score zero). Higher tiers
## mutate: some voided rings *drift* outward to adjacent wedges, so the void grows in
## volume and spreads sideways, becoming less uniform as it hardens. Void positions
## reroll each turn.
##
## Environmental boss (imposes a board condition to play around). Counts are capped at
## 14 because drift needs non-void neighbors to migrate into — at near-total void the
## signature mutation can't fire. Hard's difficulty comes from more drift/spread, not
## raw void volume.
##
## Tuning keys:
##   "void_count"   (int, default 6): whole wedges voided per turn (6 / 10 / 14).
##   "drift_min"/"drift_max" (int): per whole-void wedge, the random number of rings
##                  that drift to a non-void neighbor (easy 0/0, medium 1/2, hard 2/3).
##   "max_void_run" (int, default 3): cap on adjacent whole-void wedges (keeps gaps so
##                  drifts have somewhere visible to migrate into).

const RINGS: Array[String] = ["Inner Single", "Triple", "Outer Single", "Double"]

var void_count: int = 6
## Per-wedge drift range: each whole-void wedge with a non-void neighbor sheds a
## random number of its rings (in [drift_min, drift_max]) to adjacent wedges. easy
## 0/0 (no drift), medium 1–2, hard 2–3.
var drift_min: int = 0
var drift_max: int = 0
## Max run of adjacent whole-void wedges allowed when selecting the void set. Keeps
## the voids spread out so the drifted rings have visible non-void gaps to migrate
## into (a wall of 4+ adjacent voids hides the drift). Relaxed only if the count is
## otherwise unsatisfiable.
var max_void_run: int = 3

var _original_wedge_values: Array[int] = []
var _zeroed_wedges: Array[int] = []


func configure(tuning: Dictionary) -> void:
	void_count = tuning.get("void_count", 6)
	drift_min = tuning.get("drift_min", 0)
	drift_max = tuning.get("drift_max", 0)
	max_void_run = tuning.get("max_void_run", 3)


func on_leg_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	_original_wedge_values = smm.effective_wedge_values.duplicate()


func on_turn_start(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]

	_restore_wedge_values(smm)

	# 1. Pick the whole wedges to void this turn, spaced so no run of adjacent voids
	#    exceeds max_void_run (keeps gaps for the drift to migrate into and read).
	var whole_seed: Array[int] = _select_void_wedges(mini(void_count, 20), max_void_run)

	# 2. Seed the per-ring void set with every ring of each whole wedge.
	var ring_void: Dictionary = {}
	for w: int in whole_seed:
		for r: String in RINGS:
			ring_void["%d:%s" % [w, r]] = true

	# 3. Drift: each whole-void wedge with a non-void neighbor sheds a random number of
	#    its rings (drift_min..drift_max) to adjacent non-void wedges' same ring slot.
	#    No overlaps; total voided ring-count is conserved. Each move is recorded so the
	#    dartboard can animate the source → neighbor slide.
	var drift_moves: Array[Dictionary] = []
	if drift_max > 0:
		var sources: Array[int] = whole_seed.duplicate()
		sources.shuffle()
		for w: int in sources:
			# Adjacent wedges that aren't themselves whole voids — the drift targets.
			var neighbors: Array[int] = []
			for nb: int in [(w + 1) % 20, (w + 19) % 20]:
				if not whole_seed.has(nb):
					neighbors.append(nb)
			if neighbors.is_empty():
				continue  # walled in by other voids — nothing to migrate into.

			var want: int = randi_range(drift_min, drift_max)
			# Randomize ring order so it isn't always the inner single — triples,
			# outer singles and doubles drift too.
			var ring_order: Array[String] = RINGS.duplicate()
			ring_order.shuffle()
			var shed: int = 0
			for r: String in ring_order:
				if shed >= want:
					break
				var src_key: String = "%d:%s" % [w, r]
				if not ring_void.has(src_key):
					continue
				for nb: int in neighbors:
					var dst_key: String = "%d:%s" % [nb, r]
					if not ring_void.has(dst_key):
						ring_void.erase(src_key)
						ring_void[dst_key] = true
						drift_moves.append({"from": w, "to": nb, "ring": r})
						shed += 1
						break

	# 4. Derive whole-void wedges (all 4 rings) vs partial (drifted) ring voids.
	var whole_void_wedges: Array[int] = []
	var partial_rings: Array[Dictionary] = []
	for w: int in range(20):
		var present: Array[String] = []
		for r: String in RINGS:
			if ring_void.has("%d:%s" % [w, r]):
				present.append(r)
		if present.size() == RINGS.size():
			whole_void_wedges.append(w)
		elif present.size() > 0:
			for r: String in present:
				partial_rings.append({"wedge": w, "ring": r})

	# 5. Apply: whole-void wedges score 0; partial wedges keep their value (only the
	#    drifted rings score 0, handled in Dartboard.calculate_score).
	for idx: int in whole_void_wedges:
		smm.effective_wedge_values[idx] = 0
	_zeroed_wedges = whole_void_wedges.duplicate()
	smm._bump_state_version()

	dartboard.effective_wedge_values = smm.effective_wedge_values
	# Two-phase reveal: phase 1 fades in all the freshly-chosen whole wedges, then
	# phase 2 slides the drifted rings from their source wedge to the neighbor.
	dartboard.play_void_turn(whole_seed, whole_void_wedges, partial_rings, drift_moves)


func on_leg_end(game_state: Dictionary) -> void:
	var smm: Node = game_state["scoring_modifier_manager"]
	var dartboard: Node2D = game_state["dartboard"]
	_restore_wedge_values(smm)
	dartboard.effective_wedge_values = smm.effective_wedge_values
	dartboard.clear_boss_overlays()
	_zeroed_wedges.clear()


func _restore_wedge_values(smm: Node) -> void:
	for idx: int in _zeroed_wedges:
		if idx < _original_wedge_values.size():
			smm.effective_wedge_values[idx] = _original_wedge_values[idx]
	if _zeroed_wedges.size() > 0:
		smm._bump_state_version()


## Choose `count` whole-void wedges, rejecting any pick that would extend a run of
## adjacent voids past `max_run` (circular). If the spacing constraint can't reach the
## count, the remainder is filled unconstrained so the void_count is always honored.
func _select_void_wedges(count: int, max_run: int) -> Array[int]:
	var order: Array[int] = []
	for i: int in range(20):
		order.append(i)
	order.shuffle()

	var selected: Dictionary = {}
	for w: int in order:
		if selected.size() >= count:
			break
		if not _would_exceed_run(selected, w, max_run):
			selected[w] = true

	# Relax: if spacing blocked us short of the count, fill from the rest.
	if selected.size() < count:
		for w: int in order:
			if selected.size() >= count:
				break
			selected[w] = true

	var result: Array[int] = []
	for w: int in selected:
		result.append(w)
	return result


## Whether voiding wedge `w` would create a run of more than `max_run` adjacent voids,
## counting selected neighbors on both sides around the 20-wedge circle.
func _would_exceed_run(selected: Dictionary, w: int, max_run: int) -> bool:
	var left: int = 0
	var i: int = (w + 19) % 20
	while selected.has(i) and left < 20:
		left += 1
		i = (i + 19) % 20
	var right: int = 0
	var j: int = (w + 1) % 20
	while selected.has(j) and right < 20:
		right += 1
		j = (j + 1) % 20
	return (left + 1 + right) > max_run


func get_status_text() -> String:
	if drift_max > 0:
		return "%d wedges voided, %d-%d rings drift per wedge — rerolls each turn" % [void_count, drift_min, drift_max]
	return "%d wedges voided — rerolls each turn" % void_count


func get_visual_overlay() -> Array:
	return [{"type": "void_wedges", "wedge_indices": _zeroed_wedges}]
