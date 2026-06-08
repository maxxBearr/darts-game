extends Node
## Headless SCENE harness for the brush ↔ Color Territory resize repro (active bug-hunt spec,
## 2026-06-08). Unlike a `--script` test, running a scene boots the project's autoloads, so the real
## ScoringModifierManager (which references UnlockManager) actually loads. Drives BOTH orderings the
## spec calls out and reports which (if either) fails to grow a painted ring. Doubles as the
## manager-level regression once green.
##
## Run: godot --headless --path <project> res://tests/repro_brush.tscn   (exits non-zero on failure)

const SMM := preload("res://scripts/scoring_modifier_manager.gd")
const Dartboard := preload("res://scripts/dartboard.gd")
const ColorTerritory := preload("res://scripts/modifiers/color_territory_modifier.gd")
const Brush := preload("res://scripts/modifiers/brush_modifier.gd")

# Wedge 1 (the "1") is odd → its multi rings are naturally GREEN. Painting its double RED is a real
# colour change, and Grow-RED should then widen it exactly as a naturally-RED (even-wedge) double.
const PAINT_WEDGE := 1
const PAINT_RING := "double"


func _ready() -> void:
	var fails: int = 0
	fails += _run("(a) acquire Grow-RED, THEN paint RED", true)
	fails += _run("(b) paint RED FIRST, then acquire Grow-RED", false)
	fails += _run_dartboard_sync_and_4a()
	print("REPRO brush↔territory: %d check(s) failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Full width path THROUGH the dartboard + §4a live tracking. Replicates main._sync_board_state
## (share colors by ref, push the manager's bounds via set_geometry) and asserts: (1) the
## dartboard's SETTLED bounds (hit detection) grow for the painted ring, (2) after a reflow tick
## the DRAW bounds grow too, and (3) §4a re-derives a hotspot on that ring to the wider band.
func _run_dartboard_sync_and_4a() -> int:
	var f: int = 0
	var m: Node = SMM.new()
	m.debug_geometry_log = false
	add_child(m)
	var db: Node2D = Dartboard.new()
	db.debug_geometry_log = false
	add_child(db)   # _ready seeds default geometry

	# A hotspot on the ring we'll paint, built on the DEFAULT (pre-grow) geometry.
	db.hotspot_rings = {"%d:%s" % [PAINT_WEDGE, PAINT_RING]: 2}
	db.use_hotspot_shader = true
	db._rebuild_hotspot_shader_layer()
	var inner_before: float = _hotspot_inner_radius(db)

	# Paint RED + Grow-RED on the manager (grows the painted ring's bounds, proven above).
	m.add_modifier(Brush.make(ScoringEnums.SegmentColor.RED), {"wedge_index": PAINT_WEDGE, "ring_name": PAINT_RING})
	m.add_modifier(ColorTerritory.make(ScoringEnums.SegmentColor.RED), {})
	var mgr_w: float = _double_width(m)

	# Replicate main._sync_board_state: share colors by ref, push bounds (animated reflow).
	db.effective_wedge_values = m.effective_wedge_values
	db.effective_wedge_colors = m.effective_wedge_colors
	db.set_geometry(m.effective_wedge_weights, m.effective_ring_bounds, m.bull_radii, true)

	# (1) Settled bounds (hit detection) must match the manager immediately.
	var settled_w: float = float(db._geo_bounds[PAINT_WEDGE][PAINT_RING][1]) - float(db._geo_bounds[PAINT_WEDGE][PAINT_RING][0])
	var settled_ok: bool = absf(settled_w - mgr_w) < 0.0001
	# Drive the reflow to completion (headless: no auto-tick), settling the DRAW copy + firing §4a.
	db._apply_reflow(1.0)
	var draw_w: float = float(db._geo_bounds_draw[PAINT_WEDGE][PAINT_RING][1]) - float(db._geo_bounds_draw[PAINT_WEDGE][PAINT_RING][0])
	var draw_ok: bool = draw_w > 0.0700 + 0.0001
	# (3) §4a: the hotspot polygon re-derived to the wider band → inner radius moved inward.
	var inner_after: float = _hotspot_inner_radius(db)
	var hotspot_ok: bool = inner_after < inner_before - 0.5

	print("[REPRO dartboard+§4a] settled=%.4f (mgr %.4f) ok=%s | draw=%.4f ok=%s | hotspot inner %.1f→%.1f ok=%s" % [settled_w, mgr_w, str(settled_ok), draw_w, str(draw_ok), inner_before, inner_after, str(hotspot_ok)])
	if not settled_ok:
		f += 1
	if not draw_ok:
		f += 1
	if not hotspot_ok:
		f += 1
	m.queue_free()
	db.queue_free()
	return f


## Smallest inner band radius across ALL hotspot Polygon2D children. _rebuild_hotspot_shader_layer
## queue_free()s old polys (deferred to frame-end) before appending fresh ones, so headless/mid-frame
## the layer transiently holds both — the FRESH (grown) poly has the smaller inner radius, so the min
## across all current children reflects the latest re-derive (which is what renders next frame anyway).
func _hotspot_inner_radius(db: Node2D) -> float:
	var best: float = 1e9
	for child: Node in db._hotspot_shader_layer.get_children():
		if child is Polygon2D and not child.is_queued_for_deletion():
			for p: Vector2 in (child as Polygon2D).polygon:
				best = minf(best, p.length())
	return best if best < 1e9 else -1.0


## Returns 0 if the painted ring grew, 1 if it didn't. acquire_first picks the ordering.
func _run(label: String, acquire_first: bool) -> int:
	var m: Node = SMM.new()
	m.debug_geometry_log = false   # quiet the per-recompute dump; we print the deltas ourselves
	add_child(m)                   # _ready → _init_default_board_state seeds the canonical board
	var base_w: float = _double_width(m)

	var terr: ColorTerritory = ColorTerritory.make(ScoringEnums.SegmentColor.RED)
	var brush: Brush = Brush.make(ScoringEnums.SegmentColor.RED)
	var paint_cfg: Dictionary = {"wedge_index": PAINT_WEDGE, "ring_name": PAINT_RING}

	if acquire_first:
		m.add_modifier(terr, {})
		m.add_modifier(brush, paint_cfg)
	else:
		m.add_modifier(brush, paint_cfg)
		m.add_modifier(terr, {})

	var grown_w: float = _double_width(m)
	# Confirm the paint actually landed in the manager's colour state recompute reads.
	var col: int = int(m.effective_wedge_colors[PAINT_WEDGE][PAINT_RING])
	var painted_red: bool = col == int(ScoringEnums.SegmentColor.RED)
	var grew: bool = grown_w > base_w + 0.0001
	print("[REPRO %s] wedge %d %s: width %.4f → %.4f  grew=%s  colorRED=%s" % [label, PAINT_WEDGE, PAINT_RING, base_w, grown_w, str(grew), str(painted_red)])
	m.queue_free()
	return 0 if (grew and painted_red) else 1


func _double_width(m: Node) -> float:
	var b: Array = m.effective_ring_bounds[PAINT_WEDGE][PAINT_RING]
	return float(b[1]) - float(b[0])
