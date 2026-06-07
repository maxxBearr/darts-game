extends SceneTree
## Headless unit tests for the GEOMETRY family (geometry spec §8). Drives the pure GeometrySolver
## directly (the manager itself can't compile under --script — it references the UnlockManager
## autoload — which is exactly why the reshape math lives in a pure RefCounted), plus a Dartboard
## instance (autoload-free) for hit-detection consistency. Run with:
##   godot --headless --script res://tests/test_geometry.gd
## (Run --import once first so the geometry class_names are registered.) Exits non-zero on failure.

const Dartboard := preload("res://scripts/dartboard.gd")

const EPS: float = 0.0005
const DOUBLE_OUTER: float = 0.830
const SINGLE_BULL: float = 0.080
const DOUBLE_BULL: float = 0.032
const RING_ORDER: Array[String] = ["inner_single", "triple", "outer_single", "double"]
const BASE_WIDTHS: Dictionary = {"inner_single": 0.400, "triple": 0.050, "outer_single": 0.230, "double": 0.070}
const RING_FLOOR: float = 0.45
const ANGLE_FLOOR: float = 0.45

# Mirror of ScoringModifierManager.DEFAULT_WEDGE_ORDER (kept local — the manager won't compile here).
const WEDGE_ORDER: Array[int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_test_conservation()
	_test_floors_hold()
	_test_netting()
	_test_not_inert()
	_test_color_territory_dynamic()
	_test_parity_dynamic()
	_test_hit_detection_consistency()
	_test_fatness()
	_test_event_pool()
	print("\nGeometry test: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# ── helpers ───────────────────────────────────────────────────────────────────

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  FAIL: %s" % label)


func _default_colors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(20):
		var even: bool = i % 2 == 0
		var single: int = ScoringEnums.SegmentColor.BLACK if even else ScoringEnums.SegmentColor.WHITE
		var multi: int = ScoringEnums.SegmentColor.RED if even else ScoringEnums.SegmentColor.GREEN
		out.append({"inner_single": single, "triple": multi, "outer_single": single, "double": multi})
	return out


## Run the solver with explicit rule lists against a default-or-given board.
func _solve(dial: float, color_rules: Array, parity_rules: Array, values: Array = [], colors: Array = [], bull: float = SINGLE_BULL) -> Dictionary:
	var v: Array = values if not values.is_empty() else WEDGE_ORDER.duplicate()
	var c: Array = colors if not colors.is_empty() else _default_colors()
	return GeometrySolver.recompute(dial, color_rules, parity_rules, v, c, bull, RING_FLOOR, ANGLE_FLOOR)


func _bw(bounds: Array, wedge: int, ring: String) -> float:
	var b: Array = bounds[wedge][ring]
	return float(b[1]) - float(b[0])


## (dial, color_rules, parity_rules) for a single geometry pool entry.
func _rules_from(mod: ScoringModifier) -> Array:
	if mod is RingTradeModifier:
		return [(mod as RingTradeModifier).triple_shift, [], []]
	if mod is ColorTerritoryModifier:
		var ct: ColorTerritoryModifier = mod as ColorTerritoryModifier
		return [0.0, [{"color": int(ct.target_color), "growth": ct.growth_factor}], []]
	if mod is ParityShiftModifier:
		var ps: ParityShiftModifier = mod as ParityShiftModifier
		return [0.0, [], [{"even": ps.grow_even, "factor": ps.weight_factor}]]
	return [0.0, [], []]


# ── §8 conservation ────────────────────────────────────────────────────────────

func _test_conservation() -> void:
	print("— Conservation (angles sum 360°, bounds ascending/contiguous in [bull, edge])")
	var r: Dictionary = _solve(0.015, [{"color": int(ScoringEnums.SegmentColor.RED), "growth": 0.30}], [{"even": true, "factor": 1.25}])
	var wsum: float = 0.0
	for w: float in r["weights"]:
		wsum += w
	_check(absf(wsum - 20.0) < EPS, "weights sum to 20 (got %.4f) → 360°" % wsum)
	for wi: int in range(20):
		var prev: float = SINGLE_BULL
		for rk: String in RING_ORDER:
			var b: Array = r["bounds"][wi][rk]
			_check(absf(float(b[0]) - prev) < EPS, "wedge %d %s contiguous" % [wi, rk])
			_check(float(b[1]) > float(b[0]) - EPS, "wedge %d %s ascending" % [wi, rk])
			prev = float(b[1])
		_check(absf(prev - DOUBLE_OUTER) < EPS, "wedge %d outermost == edge (got %.4f)" % [wi, prev])


# ── §8 floors hold ──────────────────────────────────────────────────────────────

func _test_floors_hold() -> void:
	print("— Floors hold (stack ×10 never breaks the brakes)")
	var r: Dictionary = _solve(0.015 * 10.0, [], [])  # fat triple, starves double
	for wi: int in range(20):
		for rk: String in RING_ORDER:
			var floor_w: float = RING_FLOOR * float(BASE_WIDTHS[rk])
			_check(_bw(r["bounds"], wi, rk) >= floor_w - EPS,
				"wedge %d %s %.4f >= floor %.4f" % [wi, rk, _bw(r["bounds"], wi, rk), floor_w])

	var parity_rules: Array = []
	for _i: int in range(10):
		parity_rules.append({"even": true, "factor": 1.25})
	var r2: Dictionary = _solve(0.0, [], parity_rules)
	for w: float in r2["weights"]:
		_check(w >= ANGLE_FLOOR - EPS, "wedge weight %.4f >= angle floor %.4f" % [w, ANGLE_FLOOR])


# ── §8 netting ──────────────────────────────────────────────────────────────────

func _test_netting() -> void:
	print("— Netting (Wide Triple + Wide Double cancel to base)")
	var r: Dictionary = _solve(0.015 + (-0.015), [], [])
	for wi: int in range(20):
		for rk: String in RING_ORDER:
			_check(absf(_bw(r["bounds"], wi, rk) - float(BASE_WIDTHS[rk])) < EPS,
				"wedge %d %s back to base (%.4f vs %.4f)" % [wi, rk, _bw(r["bounds"], wi, rk), BASE_WIDTHS[rk]])


# ── §8 not inert ─────────────────────────────────────────────────────────────────

func _test_not_inert() -> void:
	print("— Not inert (every one of the eight moves the board with default tuning)")
	var base: Dictionary = _solve(0.0, [], [])
	for entry: ScoringModifier in ModifierRegistry.geometry_pool():
		var rules: Array = _rules_from(entry)
		var r: Dictionary = _solve(rules[0], rules[1], rules[2])
		var moved: bool = false
		for wi: int in range(20):
			if absf(float(r["weights"][wi]) - float(base["weights"][wi])) > EPS:
				moved = true
			for rk: String in RING_ORDER:
				if absf(_bw(r["bounds"], wi, rk) - _bw(base["bounds"], wi, rk)) > EPS:
					moved = true
		_check(moved, "%s moves the board (not inert)" % entry.modifier_name)


# ── §8 color territory dynamic ───────────────────────────────────────────────────

func _test_color_territory_dynamic() -> void:
	print("— Color Territory dynamic (grows painted bands; all-target wedge = no-op)")
	var red: Array = [{"color": int(ScoringEnums.SegmentColor.RED), "growth": 0.30}]
	var r: Dictionary = _solve(0.0, red, [])
	# Wedge 0 is even → triple + double are RED.
	_check(_bw(r["bounds"], 0, "triple") > float(BASE_WIDTHS["triple"]) + EPS, "red triple grew on wedge 0")
	_check(_bw(r["bounds"], 0, "double") > float(BASE_WIDTHS["double"]) + EPS, "red double grew on wedge 0")
	_check(_bw(r["bounds"], 0, "inner_single") < float(BASE_WIDTHS["inner_single"]) - EPS, "black inner single paid on wedge 0")

	# Paint every band of wedge 5 RED → Grow Red renormalizes to a no-op.
	var colors: Array = _default_colors()
	for rk: String in RING_ORDER:
		colors[5][rk] = ScoringEnums.SegmentColor.RED
	var r2: Dictionary = _solve(0.0, red, [], [], colors)
	for rk: String in RING_ORDER:
		_check(absf(_bw(r2["bounds"], 5, rk) - float(BASE_WIDTHS[rk])) < EPS,
			"all-red wedge 5 %s is a no-op (%.4f)" % [rk, _bw(r2["bounds"], 5, rk)])


# ── §8 parity dynamic ────────────────────────────────────────────────────────────

func _test_parity_dynamic() -> void:
	print("— Parity Shift dynamic (re-flows on swapped face values)")
	var even_rule: Array = [{"even": true, "factor": 1.25}]
	var r: Dictionary = _solve(0.0, [], even_rule)
	# Wedge 0 value 20 (even) wider than wedge 1 value 1 (odd).
	_check(float(r["weights"][0]) > float(r["weights"][1]) + EPS,
		"even-valued wedge wider than odd (%.3f vs %.3f)" % [r["weights"][0], r["weights"][1]])

	# Swap the values on wedges 0 and 1 → weights follow the values.
	var values: Array = WEDGE_ORDER.duplicate()
	values[0] = 1
	values[1] = 20
	var r2: Dictionary = _solve(0.0, [], even_rule, values)
	_check(float(r2["weights"][0]) < float(r["weights"][0]) - EPS, "wedge 0 narrowed after becoming odd")
	_check(float(r2["weights"][1]) > float(r2["weights"][0]) + EPS, "wedge 1 now the wide (even) one")


# ── §8 hit detection ─────────────────────────────────────────────────────────────

func _test_hit_detection_consistency() -> void:
	print("— Hit detection agrees with the computed bounds")
	var r: Dictionary = _solve(0.015, [], [])  # widen the triple globally
	var db: Object = Dartboard.new()
	db.set_geometry(r["weights"], r["bounds"], {"single_bull": SINGLE_BULL, "double_bull": DOUBLE_BULL}, false)
	db.effective_wedge_values = WEDGE_ORDER.duplicate()
	db.effective_wedge_colors = _default_colors()

	var tri: Array = r["bounds"][0]["triple"]
	var mid: float = (float(tri[0]) + float(tri[1])) * 0.5
	var res: Dictionary = db.calculate_score(_board_point(db, 0, mid))
	_check(res.get("ring_name", "") == "Triple", "widened triple mid scores Triple (got %s)" % res.get("ring_name", ""))

	var widened_outer: float = float(tri[1])
	_check(widened_outer > 0.530 + EPS, "triple widened past base outer (got %.4f)" % widened_outer)
	var probe: float = (0.530 + widened_outer) * 0.5  # was Outer Single on a base board
	var res2: Dictionary = db.calculate_score(_board_point(db, 0, probe))
	_check(res2.get("ring_name", "") == "Triple", "new triple territory scores Triple (got %s)" % res2.get("ring_name", ""))

	# Bull still scores bull (unchanged radii).
	var resb: Dictionary = db.calculate_score(db.global_position)
	_check(resb.get("ring_name", "") == "Double Bull", "center scores Double Bull (got %s)" % resb.get("ring_name", ""))
	db.free()


# ── §8 fattest tiebreak prefers the enlarged segment ────────────────────────────

func _test_fatness() -> void:
	print("— Fattest tiebreak prefers the enlarged target")
	var base: Dictionary = _solve(0.0, [], [])
	var grown: Dictionary = _solve(0.015, [], [])  # wider triple
	var base_area: float = _area(base, 0, "triple")
	var grown_area: float = _area(grown, 0, "triple")
	_check(grown_area > base_area + EPS, "enlarged triple has larger area (%.5f > %.5f)" % [grown_area, base_area])


func _area(r: Dictionary, wedge: int, ring: String) -> float:
	var b: Array = r["bounds"][wedge][ring]
	var weight: float = float(r["weights"][wedge])
	return weight * (float(b[1]) * float(b[1]) - float(b[0]) * float(b[0]))


# ── §8 event pool ────────────────────────────────────────────────────────────────

func _test_event_pool() -> void:
	print("— Event pool: eight distinct rarity-less GEOMETRY entries")
	var pool: Array = ModifierRegistry.geometry_pool()
	_check(pool.size() == 8, "geometry pool has eight entries (got %d)" % pool.size())
	var fps: Dictionary = {}
	for entry: ScoringModifier in pool:
		fps[entry.get_config_fingerprint()] = true
		_check(entry.family == ScoringEnums.Family.GEOMETRY, "%s is GEOMETRY family" % entry.modifier_name)
		_check(entry.rarity_tier == ScoringEnums.Rarity.COMMON, "%s carries no special rarity" % entry.modifier_name)
	_check(fps.size() == 8, "all eight fingerprints distinct (got %d)" % fps.size())


func _board_point(db: Object, w: int, norm: float) -> Vector2:
	var rad: float = deg_to_rad(db._wedge_center_deg(w))
	return db.global_position + Vector2(sin(rad), -cos(rad)) * db.board_radius * norm
