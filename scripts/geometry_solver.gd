class_name GeometrySolver
extends RefCounted
## Pure, headless-testable geometry math for the GEOMETRY family (geometry spec §0–§2). The
## ScoringModifierManager owns the board-geometry STATE and the modifier list; this owns the
## zero-sum reshape MATH so the rolled result can be unit-tested directly without instantiating
## the manager (which pulls autoloads) — exactly the EventRewards pattern, and the "NOT inert"
## lesson's safeguard (a default tuning value must produce a visible change; test it).
##
## recompute() folds, in order: the ring-trade dial, then per-wedge color scaling, then parity
## weights (weights are multiplicative so order is irrelevant), clamps the floors LAST, and
## renormalizes. It NEVER touches bull radii — only the single-bull radius is read, as the inner
## edge of the radial span (so the Bigger Bull relic composes: a grown bull shrinks the span and
## the inner single re-pays).

# Base normalized ring radii — MUST mirror dartboard.gd's RING_* constants.
const DOUBLE_BULL_OUTER: float = 0.032
const SINGLE_BULL_OUTER: float = 0.080
const INNER_SINGLE_OUTER: float = 0.480
const TRIPLE_OUTER: float = 0.530
const OUTER_SINGLE_OUTER: float = 0.760
const DOUBLE_OUTER: float = 0.830

const TRIPLE_BASE_WIDTH: float = TRIPLE_OUTER - INNER_SINGLE_OUTER          # 0.050
const OUTER_SINGLE_BASE_WIDTH: float = OUTER_SINGLE_OUTER - TRIPLE_OUTER     # 0.230
const DOUBLE_BASE_WIDTH: float = DOUBLE_OUTER - OUTER_SINGLE_OUTER           # 0.070

const RING_ORDER: Array[String] = ["inner_single", "triple", "outer_single", "double"]


## Recompute the board geometry. Inputs:
##   dial          — signed Σ triple_shift across Ring Trade stacks.
##   color_rules   — Array of {color:int, growth:float} (Color Territory stacks).
##   parity_rules  — Array of {even:bool, factor:float} (Parity Shift stacks).
##   wedge_values  — 20 ints (live effective face values; parity reads them).
##   wedge_colors  — 20 dicts of ring_key→SegmentColor (live paint; color territory reads them).
##   single_bull   — current single-bull outer radius (the radial span's inner edge).
##   ring_band_floor / wedge_angle_floor — the brake-preservation clamps.
## Returns { "weights": Array[float] (20, mean 1.0 / sum 20), "bounds": Array[Dictionary] (20,
## each ring_key → [inner_norm, outer_norm]) }.
static func recompute(dial: float, color_rules: Array, parity_rules: Array, wedge_values: Array, wedge_colors: Array, single_bull: float, ring_band_floor: float, wedge_angle_floor: float) -> Dictionary:
	# 1. Angular weights — uniform, parity multipliers, floor-clamp + renormalize to sum 20.
	var weights: Array[float] = []
	for i: int in range(20):
		weights.append(1.0)
	for rule: Dictionary in parity_rules:
		for i: int in range(20):
			var v: int = int(wedge_values[i]) if wedge_values.size() == 20 else 0
			var is_even: bool = (v % 2) == 0
			if is_even == bool(rule["even"]):
				weights[i] *= float(rule["factor"])
	weights = _floor_normalize(weights, wedge_angle_floor, 20.0)

	# 2. Per-wedge ring bounds over the span [single_bull, DOUBLE_OUTER].
	var span_start: float = single_bull
	var span: float = DOUBLE_OUTER - span_start
	var base_inner_single: float = INNER_SINGLE_OUTER - span_start
	var base_widths: Dictionary = {
		"inner_single": base_inner_single,
		"triple": TRIPLE_BASE_WIDTH,
		"outer_single": OUTER_SINGLE_BASE_WIDTH,
		"double": DOUBLE_BASE_WIDTH,
	}

	var bounds_out: Array[Dictionary] = []
	for w: int in range(20):
		# Ring-trade dial: move `dial` of width double→triple; outer single slides; inner single
		# untouched. The dial cancels in the sum, so seeded widths still total `span`.
		var widths: Dictionary = {
			"inner_single": base_inner_single,
			"triple": maxf(TRIPLE_BASE_WIDTH + dial, 0.0),
			"outer_single": OUTER_SINGLE_BASE_WIDTH,
			"double": maxf(DOUBLE_BASE_WIDTH - dial, 0.0),
		}
		# Color Territory (dynamic): widen target-colored bands, renormalize to span (zero-sum).
		if not color_rules.is_empty() and wedge_colors.size() == 20:
			var colors: Dictionary = wedge_colors[w]
			for rule: Dictionary in color_rules:
				for rk: String in RING_ORDER:
					if int(colors.get(rk, -1)) == int(rule["color"]):
						widths[rk] = float(widths[rk]) * (1.0 + float(rule["growth"]))
			_renormalize_widths(widths, span)
		# Floors LAST.
		_apply_band_floors(widths, base_widths, span, ring_band_floor)
		# Cumulative bounds from the bull radius outward.
		var bounds: Dictionary = {}
		var cur: float = span_start
		for rk: String in RING_ORDER:
			var nxt: float = cur + float(widths[rk])
			bounds[rk] = [cur, nxt]
			cur = nxt
		bounds["double"][1] = DOUBLE_OUTER  # pin against float drift.
		bounds_out.append(bounds)

	return {"weights": weights, "bounds": bounds_out}


## Normalize to target_sum, clamp each element to floor_val, redistribute the deficit
## proportionally among above-floor elements so the sum stays target_sum. Identity (exact ratios)
## when no floor binds.
static func _floor_normalize(values: Array[float], floor_val: float, target_sum: float) -> Array[float]:
	var n: int = values.size()
	if n == 0:
		return []
	var s: float = 0.0
	for v: float in values:
		s += v
	var norm: Array[float] = []
	for v: float in values:
		norm.append(v * target_sum / s if s > 0.0 else target_sum / float(n))
	var free: float = target_sum - floor_val * float(n)
	if free < 0.0:
		var even: Array[float] = []
		for _i: int in range(n):
			even.append(target_sum / float(n))
		return even
	var above: Array[float] = []
	var above_sum: float = 0.0
	for v: float in norm:
		var a: float = maxf(0.0, v - floor_val)
		above.append(a)
		above_sum += a
	var out: Array[float] = []
	for i: int in range(n):
		if above_sum > 0.0:
			out.append(floor_val + free * above[i] / above_sum)
		else:
			out.append(floor_val + free / float(n))
	return out


## Scale the four ring-band widths in place so they sum to `span`.
static func _renormalize_widths(widths: Dictionary, span: float) -> void:
	var s: float = 0.0
	for rk: String in RING_ORDER:
		s += float(widths[rk])
	if s <= 0.0:
		return
	for rk: String in RING_ORDER:
		widths[rk] = float(widths[rk]) * span / s


## Clamp each band to ring_band_floor × base width, redistribute the remaining span among the
## above-floor bands so the sum stays exactly `span`.
static func _apply_band_floors(widths: Dictionary, base_widths: Dictionary, span: float, ring_band_floor: float) -> void:
	var floors: Dictionary = {}
	var floor_sum: float = 0.0
	for rk: String in RING_ORDER:
		var f: float = ring_band_floor * float(base_widths[rk])
		floors[rk] = f
		floor_sum += f
	var free: float = span - floor_sum
	if free < 0.0:
		for rk: String in RING_ORDER:
			widths[rk] = float(floors[rk]) * span / floor_sum
		return
	var above: Dictionary = {}
	var above_sum: float = 0.0
	for rk: String in RING_ORDER:
		var a: float = maxf(0.0, float(widths[rk]) - float(floors[rk]))
		above[rk] = a
		above_sum += a
	for rk: String in RING_ORDER:
		if above_sum > 0.0:
			widths[rk] = float(floors[rk]) + free * float(above[rk]) / above_sum
		else:
			widths[rk] = float(floors[rk]) + free / float(RING_ORDER.size())
