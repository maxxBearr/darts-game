extends Node
## Manages scoring modifiers that transform dart scores.
## Sits between dartboard.calculate_score() and x01_game.process_throw().
## Owns effective board state (wedge values and colors) and hit history.

# --- Standard dartboard color mapping ---
# Even-index wedges (0, 2, 4...): singles are BLACK, doubles/triples are RED
# Odd-index wedges (1, 3, 5...): singles are WHITE, doubles/triples are GREEN

## The default wedge number order from dartboard.gd, used to reset at run start.
const DEFAULT_WEDGE_ORDER: Array[int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

## The effective wedge values after all ON_ACQUIRE modifiers have been applied.
## Index 0 = top wedge (normally 20), index 1 = next clockwise (normally 1), etc.
## Dartboard reads from this for scoring and number rendering.
var effective_wedge_values: Array[int] = []

## The effective segment colors for each wedge. Index matches wedge position.
## Each entry is a dictionary with four ring keys mapping to SegmentColor:
## "inner_single", "triple", "outer_single", "double".
## Dartboard reads from this for segment color rendering and score enrichment.
var effective_wedge_colors: Array[Dictionary] = []

## All currently active scoring modifiers, in acquisition order.
## ON_ACQUIRE modifiers are stored here too (for display/inspection purposes)
## but only PER_DART modifiers are called during process_score().
var active_modifiers: Array[Resource] = []

# ── GEOMETRY family substrate (see the geometry spec) ─────────────────────────
# Computed board geometry, parallel to voided_rings / hotspot_rings: the manager owns it so
# boss hooks can read and fight it, and it persists across legs like every other board
# mutation. recompute_geometry() rebuilds all three from base constants + the active GEOMETRY
# modifiers (read straight off active_modifiers) + the live values/colors, clamps the floors,
# renormalizes, and emits geometry_changed. The dartboard mirrors these for hit detection +
# rendering (per-wedge bounds + weighted wedge boundaries).

## Emitted whenever recompute_geometry() rebuilds the board geometry. main mirrors the new
## state onto the dartboard (which re-flows) and the board studs.
signal geometry_changed

## Per-wedge angular weights (20, default 1.0). Mean 1.0 (sum 20); a wedge's angular width is
## weight/20 × 360° = weight × 18°. Parity Shift fattens matching wedges here; floors clamp.
var effective_wedge_weights: Array[float] = []

## Per-wedge normalized ring boundaries (20 entries). Each entry is a Dictionary keyed by ring
## ("inner_single"/"triple"/"outer_single"/"double") → [inner_norm, outer_norm]. Seeded from the
## RING_* base widths; Ring Trade + Color Territory reshape them per wedge (zero-sum per column).
var effective_ring_bounds: Array[Dictionary] = []

## Bull radii (normalized): "single_bull" and "double_bull" outer radii. The eight geometry
## trades NEVER touch these — only the Bigger Bull boss-reward relic moves them, after which it
## calls recompute_geometry() so the inner single re-pays the space the bull took.
var bull_radii: Dictionary = {"single_bull": GEOM_SINGLE_BULL_OUTER, "double_bull": GEOM_DOUBLE_BULL_OUTER}

# Base normalized ring radii — MUST mirror dartboard.gd's RING_* constants so the manager's
# computed bounds and the board's hit detection agree.
const GEOM_DOUBLE_BULL_OUTER: float = 0.032
const GEOM_SINGLE_BULL_OUTER: float = 0.080
const GEOM_INNER_SINGLE_OUTER: float = 0.480
const GEOM_TRIPLE_OUTER: float = 0.530
const GEOM_OUTER_SINGLE_OUTER: float = 0.760
const GEOM_DOUBLE_OUTER: float = 0.830

# Base band widths (with the bull at its base radius). inner_single's base is derived per
# recompute from the live single-bull radius so the Bigger Bull relic composes (it eats into
# the inner single). triple 0.050, double 0.070 per the spec; outer single 0.230.
const GEOM_TRIPLE_BASE_WIDTH: float = GEOM_TRIPLE_OUTER - GEOM_INNER_SINGLE_OUTER          # 0.050
const GEOM_OUTER_SINGLE_BASE_WIDTH: float = GEOM_OUTER_SINGLE_OUTER - GEOM_TRIPLE_OUTER     # 0.230
const GEOM_DOUBLE_BASE_WIDTH: float = GEOM_DOUBLE_OUTER - GEOM_OUTER_SINGLE_OUTER           # 0.070

## Ring order inside-out — the order ring bounds are laid down radially.
const RING_ORDER: Array[String] = ["inner_single", "triple", "outer_single", "double"]

## Minimum fraction of a ring band's BASE width it can be squeezed to by geometry items;
## clamped after all rules apply, then the freed space is redistributed so the wedge's radial
## span is conserved. Protects the singles — the board's brakes. Max's call to tune.
@export var ring_band_floor: float = 0.45

## Same, for a wedge's base 18° angular width: a wedge can't be narrowed below this fraction of
## 18° by Parity Shift. Clamped last, then renormalized to 360°. Max's call to tune.
@export var wedge_angle_floor: float = 0.45

## Geometric per-stack decay for STACKED geometry items (§1). The same fingerprint can now be
## acquired more than once; same-fingerprint stacks are aggregated here and the cumulative
## magnitude decays so it asymptotes instead of compounding linearly (stack k contributes
## base × decay^(k-1)). 0.65 ⇒ a Color Territory stack tops out near +86%. See GeometrySolver.
## decayed_cumulative. The band/angle floors above remain the hard backstop. Max's call to tune.
@export var geometry_stack_decay: float = 0.65

## §1 offer-side soft cap. main's geometry pick gates off an entry once one more copy's marginal
## effect falls below this FRACTION of a first copy's effect (decay^owned < epsilon) — i.e. the
## next stack is near-inert, so re-offering it would ship a dead card. Scale-free so it gates the
## three geometry magnitudes (dial / color growth / parity excess) uniformly despite their
## different units. 0.05 ⇒ offered until a new stack is under ~5% as strong as the first (≈7
## stacks at decay 0.65). The decay curve + this epsilon self-limit; no hard stack count needed.
@export var geometry_stack_offer_epsilon: float = 0.05

## Segments voided by a boss this turn, keyed "<wedge_index>:<RingName>" (e.g.
## "3:Double"). A voided segment scores 0 no matter what modifiers would do to it.
## The Void boss sets this each turn; whole-void wedges (value zeroed) are included
## too so the solver, checkout segments, and hover tooltip all agree with live
## scoring. Empty in normal play. Drifted (partial) ring voids live ONLY here — the
## wedge keeps its value — which is why the solver must consult this, not just values.
var voided_rings: Dictionary = {}

## Rings marked as hotspots, keyed "<wedge_index>:<RingName>" (display ring name, e.g.
## "3:Triple") → flat multiplier bonus (an int, 1–3). Parallel to voided_rings so the
## boss hooks, solver, and tooltip can all read/contest it. The per-dart scoring path
## folds this bonus into the additive baseline multiplier (face × (ring + hotspot) ×
## streak). No-stack: one tier per ring (see HotspotModifier + the segment picker guard).
var hotspot_rings: Dictionary = {}

## Per-category streak-slot capacity, keyed by ScoringEnums.StreakCategory → int.
## Sourced from the equipped components on run start (shaft → WEDGE, barrel → COLOR)
## via DartBuild.get_streak_capacity(). Base 1 each so a vanilla build can hold one of
## each. get_streak_conflicts() enforces this per category. Replaces the old global
## max_streak_slots int.
var streak_capacity: Dictionary = {
	ScoringEnums.StreakCategory.WEDGE: 1,
	ScoringEnums.StreakCategory.COLOR: 1,
}

## When true, triples count as valid checkout finishes for the solver.
var allow_triple_checkout: bool = false:
	set(value):
		if allow_triple_checkout != value:
			allow_triple_checkout = value
			_bump_state_version()

## When true, any ring counts as a valid checkout finish for the solver.
var glass_cannon_active: bool = false:
	set(value):
		if glass_cannon_active != value:
			glass_cannon_active = value
			_bump_state_version()

## Parity Out checkout restriction (geometry spec §9b). The out-rule narrows which wedge-based
## finishes count by the wedge's CURRENT effective face value parity:
##   -1 = no restriction (standard double-out), 0 = even-valued wedges only, 1 = odd-valued only.
## The bull is EXEMPT ("the bull always outs" — 25 is odd, but exempting it keeps 50 finishable
## under Even Out, §9b cond 3). DYNAMIC: validity reads effective_wedge_values, so a Wedge Value
## +1 flips a dead double live mid-race. Set per-challenge by ParityOutBoss; -1 between races.
var checkout_parity: int = -1:
	set(value):
		if checkout_parity != value:
			checkout_parity = value
			_bump_state_version()

## Hit history for the current turn (cleared every turn via reset_for_turn).
var hit_history_turn: Array[Dictionary] = []

## Hit history for the current leg (cleared every leg via reset_for_leg).
var hit_history_leg: Array[Dictionary] = []

## Hit history for the entire run (cleared on new run via reset_for_run).
var hit_history_run: Array[Dictionary] = []

## Export test modifiers so developers can drag Resource files in via the inspector
## to test modifier behavior without needing a shop/acquisition flow.
## These are added via add_modifier() during _ready().
@export var debug_modifiers: Array[Resource] = []

@export var debug_perf_log: bool = false

## TEMP bug-hunt instrumentation (brush ↔ Color Territory resize desync, 2026-06-08). When on,
## recompute_geometry() dumps every non-default-colored ring (painted or Prism-recolored), the
## active color_rules, and that ring's CURRENT width — so one in-game paint shows whether the paint
## reached recompute and whether the matching color rule grew it. Localized 2026-06-08 (the resize
## machinery is provably clean — see tests/repro_brush.tscn); kept off, flip on for interactive checks.
@export var debug_geometry_log: bool = false

var _state_version: int = 0
var _last_sync_version: int = -1


func _bump_state_version() -> void:
	_state_version += 1


func _ready() -> void:
	# Initialize board state to defaults
	_init_default_board_state()

	# Add any debug modifiers from the inspector
	for modifier: Resource in debug_modifiers:
		if modifier != null:
			add_modifier(modifier, {})


func _perf_log(msg: String) -> void:
	if not debug_perf_log:
		return
	print("[PERF] %s" % msg)


func _streak_state_hash() -> int:
	var h: int = 0
	for modifier: Resource in active_modifiers:
		if modifier is ScoringModifier:
			h = (h * 31 + modifier.get_streak_state_hash()) & 0x7FFFFFFF
	return h


## Initialize effective wedge values and colors to standard dartboard defaults.
func _init_default_board_state() -> void:
	effective_wedge_values = DEFAULT_WEDGE_ORDER.duplicate()

	effective_wedge_colors.clear()
	for wedge_idx: int in range(20):
		var is_even: bool = wedge_idx % 2 == 0
		var single_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
		var multi_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
		effective_wedge_colors.append({
			"inner_single": single_color,
			"triple": multi_color,
			"outer_single": single_color,
			"double": multi_color,
		})

	# Seed the geometry substrate from the freshly-defaulted values/colors. recompute_geometry
	# reads active_modifiers (empty here at run start) and the base constants, so this lands the
	# canonical board geometry that the dartboard mirrors.
	recompute_geometry()


## Rebuild the board geometry from base constants, fold in the active GEOMETRY modifiers, clamp
## the floors LAST, renormalize, and emit geometry_changed. DYNAMIC — recomputed against the
## live board state (Color Territory tracks current paint, Parity Shift tracks current face
## values), so geometry is contestable and composes with the painter/swap builds.
##
## Triggers (all funnel here): a geometry modifier acquired (add_modifier), brush apply / wedge
## swap (apply_to_board, via add_modifier), Prism recolor-on-hit (prism_boss calls this between
## darts), the Bigger Bull relic, and run/leg init. Order of folds: ring-trade dial, then
## per-wedge color scaling, then parity weights — weights are multiplicative so the order is
## irrelevant; floors are clamped last.
func recompute_geometry() -> void:
	# 1. Accumulate the active geometry rules off active_modifiers, AGGREGATING same-fingerprint
	#    stacks under geometric per-stack decay (§1) so cumulative effect asymptotes instead of
	#    compounding linearly. Group by the pool-facing fingerprint (Ring Trade direction / Color
	#    Territory color / Parity Shift parity); each group folds to ONE decayed magnitude the
	#    solver applies once. (run-scoped, so they persist across legs — the family never lives in
	#    a leg-end reset path.)
	var ring_mags: Dictionary = {}    # "WT"/"WD" -> Array of |triple_shift| per stack
	var color_mags: Dictionary = {}   # color int -> Array of growth_factor per stack
	var parity_mags: Dictionary = {}  # "E"/"O" -> Array of (weight_factor − 1) per stack
	for m: Resource in active_modifiers:
		if m is RingTradeModifier:
			var rt: RingTradeModifier = m as RingTradeModifier
			var rkey: String = "WT" if rt.triple_shift >= 0.0 else "WD"
			if not ring_mags.has(rkey):
				ring_mags[rkey] = []
			ring_mags[rkey].append(absf(rt.triple_shift))
		elif m is ColorTerritoryModifier:
			var ct: ColorTerritoryModifier = m as ColorTerritoryModifier
			var ckey: int = int(ct.target_color)
			if not color_mags.has(ckey):
				color_mags[ckey] = []
			color_mags[ckey].append(ct.growth_factor)
		elif m is ParityShiftModifier:
			var ps: ParityShiftModifier = m as ParityShiftModifier
			var pkey: String = "E" if ps.grow_even else "O"
			if not parity_mags.has(pkey):
				parity_mags[pkey] = []
			parity_mags[pkey].append(ps.weight_factor - 1.0)

	# Fold each group to a single decayed magnitude. Ring Trade: a signed dial (Wide-Triple
	# positive, Wide-Double negative) — opposite directions still net to base, since each side
	# decays independently and then subtracts. Color: one rule per color at the decayed cumulative
	# growth (so N copies asymptote, not (1+g)^N). Parity: decay the EXCESS over 1.0 (a factor
	# asymptotes toward a ceiling, not toward 0), then re-add the 1.0.
	var dial: float = 0.0  # signed triple↔double width shift, decayed-summed across Ring Trade stacks.
	if ring_mags.has("WT"):
		dial += GeometrySolver.decayed_cumulative(ring_mags["WT"], geometry_stack_decay)
	if ring_mags.has("WD"):
		dial -= GeometrySolver.decayed_cumulative(ring_mags["WD"], geometry_stack_decay)
	var color_rules: Array[Dictionary] = []   # {color:int, growth:float}
	for ckey: int in color_mags:
		color_rules.append({"color": ckey, "growth": GeometrySolver.decayed_cumulative(color_mags[ckey], geometry_stack_decay)})
	var parity_rules: Array[Dictionary] = []  # {even:bool, factor:float}
	for pkey: String in parity_mags:
		parity_rules.append({"even": pkey == "E", "factor": 1.0 + GeometrySolver.decayed_cumulative(parity_mags[pkey], geometry_stack_decay)})

	# 2–3. Delegate the zero-sum reshape MATH to the pure GeometrySolver (headless-testable; no
	#       autoload deps). It folds the dial, per-wedge color scaling, and parity weights, clamps
	#       the floors last, and renormalizes — returning the angular weights + per-wedge bounds.
	var single_bull: float = float(bull_radii.get("single_bull", GEOM_SINGLE_BULL_OUTER))
	var result: Dictionary = GeometrySolver.recompute(
		dial, color_rules, parity_rules,
		effective_wedge_values, effective_wedge_colors,
		single_bull, ring_band_floor, wedge_angle_floor
	)
	effective_wedge_weights = result["weights"]
	effective_ring_bounds = result["bounds"]

	# Rebuild the O(1) fatness table from the freshly-computed geometry (see _fatness_cache).
	_rebuild_fatness_cache()

	if debug_geometry_log:
		_dump_geometry_debug(color_rules)

	geometry_changed.emit()


## TEMP bug-hunt dump (see debug_geometry_log). For every ring whose color differs from the default
## board scheme (i.e. painted or Prism-recolored), print its color + CURRENT band width, alongside
## the active Color Territory rules. If a painted GREEN double under Grow-Green shows ~0.0885 the
## resize landed; if it shows ~0.0700 the rule didn't grow it; if the painted wedge is ABSENT the
## paint never reached the array recompute reads (a desync/revert upstream).
func _dump_geometry_debug(color_rules: Array) -> void:
	var lines: Array[String] = []
	for wi: int in range(20):
		if wi >= effective_wedge_colors.size() or wi >= effective_ring_bounds.size():
			continue
		var even: bool = wi % 2 == 0
		var c: Dictionary = effective_wedge_colors[wi]
		var diffs: Array[String] = []
		for rk: String in RING_ORDER:
			var is_single: bool = rk == "inner_single" or rk == "outer_single"
			var defc: int = int(ScoringEnums.SegmentColor.BLACK if even else ScoringEnums.SegmentColor.WHITE) if is_single else int(ScoringEnums.SegmentColor.RED if even else ScoringEnums.SegmentColor.GREEN)
			if int(c.get(rk, defc)) != defc:
				var b: Array = effective_ring_bounds[wi].get(rk, [0.0, 0.0])
				diffs.append("%s=col%d w=%.4f" % [rk, int(c[rk]), float(b[1]) - float(b[0])])
		if not diffs.is_empty():
			lines.append("w%d(val%d): %s" % [wi, effective_wedge_values[wi], ", ".join(diffs)])
	print("[GEO] recompute color_rules=%s | non-default rings: %s" % [str(color_rules), (", ".join(lines) if not lines.is_empty() else "(none)")])


## Recompute the per-(wedge, ring) fatness table = −(angular weight × annular area) from the
## current geometry, so path ranking is a table lookup instead of per-comparison math.
func _rebuild_fatness_cache() -> void:
	_fatness_cache.clear()
	for wi: int in range(20):
		var weight: float = effective_wedge_weights[wi] if wi < effective_wedge_weights.size() else 1.0
		var bounds: Dictionary = effective_ring_bounds[wi] if wi < effective_ring_bounds.size() else {}
		var entry: Dictionary = {}
		for rk: String in RING_ORDER:
			if bounds.has(rk):
				var inner: float = float(bounds[rk][0])
				var outer: float = float(bounds[rk][1])
				entry[rk] = -weight * maxf(outer * outer - inner * inner, 0.0)
			else:
				entry[rk] = 0.0
		_fatness_cache.append(entry)


## Active geometry rules for the board studs. Returns {name, summary, modifier, count} entries in
## first-acquisition order; summary is a live one-line effect description. §1: stacked copies of
## the same fingerprint collapse to ONE stud carrying a ×N count and the live CUMULATIVE (decayed)
## effect — not N separate studs (geometry spec §5).
func get_active_geometry_rules() -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	var index_by_fp: Dictionary = {}   # fingerprint -> index into rules (first-seen order)
	var counts: Dictionary = {}        # fingerprint -> stack count
	for m: Resource in active_modifiers:
		if not (m is RingTradeModifier or m is ColorTerritoryModifier or m is ParityShiftModifier):
			continue
		var fp: String = (m as ScoringModifier).get_config_fingerprint()
		if index_by_fp.has(fp):
			counts[fp] = int(counts[fp]) + 1
			continue
		index_by_fp[fp] = rules.size()
		counts[fp] = 1
		rules.append({
			"name": (m as ScoringModifier).modifier_name,
			"summary": "",          # filled below once the stack count is known
			"modifier": m,
			"fingerprint": fp,
		})
	# Second pass: live cumulative summary + a ×N suffix on the name once the counts are known.
	for entry: Dictionary in rules:
		var fp: String = entry["fingerprint"]
		var n: int = int(counts[fp])
		entry["count"] = n
		entry["summary"] = _geometry_rule_summary(entry["modifier"], n)
		if n > 1:
			entry["name"] = "%s ×%d" % [entry["name"], n]
	return rules


## All active board-rule stud entries: the geometry rules PLUS any non-geometry board law (today
## just Parity Out, §9b cond 2 — the first non-geometry stud the generic {glyph, color} entry was
## architected for). Each entry is {name, summary, glyph, color, modifier}; geometry entries omit
## glyph/color so board_studs falls back to its per-class dispatch. main pushes this to the studs.
func get_active_board_rules() -> Array[Dictionary]:
	var rules: Array[Dictionary] = get_active_geometry_rules()
	# Glass Cannon overrides Parity Out (any ring outs), so the parity stud would be misleading
	# while it's active — suppress it (the §9b cond 4 mutual-exclusion, mirrored on the studs).
	if checkout_parity != -1 and not glass_cannon_active:
		var even: bool = checkout_parity == 0
		rules.append({
			"name": "%s Out" % ("Even" if even else "Odd"),
			"summary": "Finish double must be on %s wedges" % ("even" if even else "odd"),
			"glyph": "E" if even else "O",
			"color": Color(0.95, 0.75, 0.35),   # amber — reads apart from the geometry hues
			"modifier": null,
		})
	return rules


## A short live-effect summary string for a geometry rule's stud tooltip. `stack_count` folds in
## the §1 decay so a stacked stud reads its true CUMULATIVE effect (e.g. "Grow Red ×3 — red bands
## +71%"), matching exactly what recompute_geometry hands the solver.
func _geometry_rule_summary(m: Resource, stack_count: int = 1) -> String:
	if m is RingTradeModifier:
		var base: float = absf((m as RingTradeModifier).triple_shift)
		var cum: float = GeometrySolver.decayed_cumulative(_repeat_magnitude(base, stack_count), geometry_stack_decay)
		if (m as RingTradeModifier).triple_shift >= 0.0:
			return "Triples +%.0f%% width, doubles pay" % (cum / GEOM_TRIPLE_BASE_WIDTH * 100.0)
		return "Doubles +%.0f%% width, triples pay" % (cum / GEOM_DOUBLE_BASE_WIDTH * 100.0)
	if m is ColorTerritoryModifier:
		var ct: ColorTerritoryModifier = m as ColorTerritoryModifier
		var cum_g: float = GeometrySolver.decayed_cumulative(_repeat_magnitude(ct.growth_factor, stack_count), geometry_stack_decay)
		return "%s bands +%.0f%%" % [ct.get_color_name(), cum_g * 100.0]
	if m is ParityShiftModifier:
		var ps: ParityShiftModifier = m as ParityShiftModifier
		var cum_f: float = 1.0 + GeometrySolver.decayed_cumulative(_repeat_magnitude(ps.weight_factor - 1.0, stack_count), geometry_stack_decay)
		return "%s wedges ×%.2f angular" % ["Even" if ps.grow_even else "Odd", cum_f]
	return ""


## Build a list of `count` copies of `value` (≥1) — the per-stack magnitudes a uniform geometry
## stack feeds GeometrySolver.decayed_cumulative for a cumulative-effect readout.
func _repeat_magnitude(value: float, count: int) -> Array:
	var a: Array = []
	for _i: int in range(maxi(count, 1)):
		a.append(value)
	return a


## Run a raw score result through all active PER_DART modifiers.
## Call this after dartboard.calculate_score() and before x01_game.process_throw().
## Set is_preview to true for hover/tooltip display — runs the full pipeline
## but does NOT record the result to hit history.
func process_score(raw_result: Dictionary, is_preview: bool = false) -> Dictionary:
	var result: Dictionary = raw_result.duplicate()

	# Initialize the modifications tracking array — modifiers append to this
	result["modifications"] = []

	# Mark boss-voided segments up front (synthesized results from the solver/tooltip
	# don't carry is_void; live results from calculate_score already do).
	_mark_void(result)

	# Build context dictionary for modifiers that need history or board state
	var context: Dictionary = {
		"history_turn": hit_history_turn,
		"history_leg": hit_history_leg,
		"history_run": hit_history_run,
		"effective_wedge_values": effective_wedge_values,
		"effective_wedge_colors": effective_wedge_colors,
		"is_preview": is_preview,
	}

	# Run the two-axis scoring pipeline (additive baseline → streak multiply → flip).
	result = _score_through_modifiers(result, context)

	# A voided segment scores 0 regardless of what any modifier did to it — modifiers
	# recompute total_score from face×multiplier, which would otherwise resurrect the
	# void. This is the last word on the score.
	if result.get("is_void", false):
		result["total_score"] = 0

	# Only record to history if this is a real throw, not a hover preview
	if not is_preview:
		var history_entry: Dictionary = result.duplicate()
		hit_history_turn.append(history_entry)
		hit_history_leg.append(history_entry)
		hit_history_run.append(history_entry)

	return result


## Whether any ENABLED active modifier reads a segment's COLOR when scoring a dart — i.e.
## whether the checkout math depends on the live board colors. This is the exact set of
## color-readers in _score_through_modifiers' pipeline:
##   • ColorBonusModifier — a PER_DART bonus gated on result.segment_color == target_color.
##   • any COLOR-category streak (ColorStreakModifier) — its continuation is keyed on color.
## (OddEvenBonusModifier keys on face-value parity, not color; BrushModifier WRITES color on
## acquire but never reads it at score time — neither makes scoring color-dependent.) Disabled
## (toggled-off) modifiers are skipped because the pipeline never invokes them. Used to decide
## whether Prism's reactive recolor actually invalidates the checkout helper: with no color
## build, Prism only changes appearance, not the values the solver computes, so the helper
## stays trustworthy and live.
func has_color_dependent_scoring() -> bool:
	for modifier: Resource in active_modifiers:
		if not (modifier is ScoringModifier):
			continue
		var sm: ScoringModifier = modifier as ScoringModifier
		if not sm.enabled:
			continue
		if sm is ColorBonusModifier:
			return true
		if sm.streak_category == ScoringEnums.StreakCategory.COLOR:
			return true
	return false


## Get all active streak modifiers (those with a non-NONE streak category).
func get_active_streak_modifiers() -> Array:
	var result: Array = []
	for modifier: Resource in active_modifiers:
		if modifier is ScoringModifier and modifier.streak_category != ScoringEnums.StreakCategory.NONE:
			result.append(modifier)
	return result


## Get all active streak modifiers of the same category that would be candidates for
## replacement. Returns empty if that category still has a free slot (no conflict).
## Capacity is per-category and sourced from components (shaft → WEDGE, barrel → COLOR)
## via streak_capacity; base 1 each. When the category is already at capacity, every
## same-category streak is a replacement candidate (the caller asks the player which to
## drop when more than one).
func get_streak_conflicts(new_modifier: ScoringModifier) -> Array:
	if new_modifier.streak_category == ScoringEnums.StreakCategory.NONE:
		return []
	var same_category: Array = []
	for existing: Resource in get_active_streak_modifiers():
		if existing is ScoringModifier and existing.streak_category == new_modifier.streak_category:
			same_category.append(existing)
	var capacity: int = streak_capacity.get(new_modifier.streak_category, 1)
	if same_category.size() < capacity:
		return []
	return same_category


## Convenience: returns the single conflict if exactly one exists, or null.
## When multiple same-category conflicts exist, returns null — caller must
## use get_streak_conflicts() and present a choice to the player.
func get_streak_conflict(new_modifier: ScoringModifier) -> ScoringModifier:
	var conflicts: Array = get_streak_conflicts(new_modifier)
	if conflicts.size() == 1:
		return conflicts[0]
	return null


## Streak "membership level" for a board dart — drives the recurring streak pulse on dart markers.
## Returns the highest active streak count (>= 2, where the multiplier actually kicks in) whose
## continuation criteria this dart's spot matches, or 0 if the dart isn't part of a scoring streak.
## target carries the fields would_continue_streak() reads: wedge_index, ring_name, segment_color,
## is_bull.
func get_streak_level_for(target: Dictionary) -> int:
	var level: int = 0
	for modifier: Resource in active_modifiers:
		if not (modifier is ScoringModifier):
			continue
		var sm: ScoringModifier = modifier as ScoringModifier
		if sm.streak_category == ScoringEnums.StreakCategory.NONE or not sm.enabled:
			continue
		if not sm.has_method("would_continue_streak"):
			continue
		if sm.would_continue_streak(target) and sm.get_streak_count() >= 2:
			level = maxi(level, sm.get_streak_count())
	return level


## Remove a specific modifier from the active list.
## Used when a streak modifier is being replaced by a new one in the same category.
func remove_modifier(modifier: Resource) -> void:
	var idx: int = active_modifiers.find(modifier)
	if idx >= 0:
		active_modifiers.remove_at(idx)
		_bump_state_version()


## Register a new modifier. For ON_ACQUIRE modifiers, immediately applies
## board-state changes. config is a Dictionary with modifier-specific settings
## (e.g., {"wedge_index": 5} for PICK_WEDGE modifiers).
## For NONE config_type modifiers, pass an empty dictionary.
## If the modifier has a streak category that conflicts with an existing modifier,
## the existing one is removed first (replacement). When multiple same-category
## conflicts exist, pass the chosen one via explicit_replacement.
## Returns the replaced modifier, or null if no replacement occurred.
func add_modifier(modifier: Resource, config: Dictionary, explicit_replacement: Resource = null) -> Resource:
	var replaced: Resource = null
	if explicit_replacement != null:
		remove_modifier(explicit_replacement)
		replaced = explicit_replacement
	elif modifier is ScoringModifier:
		var conflict: ScoringModifier = get_streak_conflict(modifier as ScoringModifier)
		if conflict != null:
			remove_modifier(conflict)
			replaced = conflict

	active_modifiers.append(modifier)
	_bump_state_version()

	# If this is an ON_ACQUIRE modifier, apply its board-state changes now
	if modifier.timing == ScoringEnums.ModifierTiming.ON_ACQUIRE:
		modifier.apply_to_board(effective_wedge_values, effective_wedge_colors, config)
		# A swap relocates a wedge's value and colors between two slots. Position-tied
		# per-dart state (sign flips) must travel with it, so notify other modifiers.
		# Keyed on the config shape, not the class, so any swap-style mutation works.
		if config.has("wedge_index_1") and config.has("wedge_index_2"):
			_notify_wedges_swapped(config["wedge_index_1"], config["wedge_index_2"])
		# A hotspot writes board state the manager owns (parallel to voided_rings), not the
		# wedge values/colors, so register it here from the modifier's stored choice.
		if modifier is HotspotModifier:
			_register_hotspot(modifier as HotspotModifier)
		# Geometry is computed from active_modifiers + live values/colors, so any ON_ACQUIRE
		# board mutation (a geometry item, a brush paint, a wedge swap) can change it — recompute
		# now. Cheap (20 wedges) and self-limiting when no geometry items are owned.
		recompute_geometry()
		_bump_state_version()

	UnlockManager.on_item_acquired({
		"rarity": modifier.rarity_tier,
		"active_relic_count": _count_active_relics(),
	})
	if modifier is ScoringModifier and (modifier as ScoringModifier).streak_category != ScoringEnums.StreakCategory.NONE:
		UnlockManager.on_slots_state_changed(_build_slots_context())

	return replaced


## Tell every active modifier that two wedges swapped board positions, so any
## position-tied per-dart state (e.g. FlipSignModifier targets) follows its wedge.
func _notify_wedges_swapped(idx_a: int, idx_b: int) -> void:
	for m: Resource in active_modifiers:
		if m is ScoringModifier:
			(m as ScoringModifier).on_wedges_swapped(idx_a, idx_b)


## Count currently active RELIC-kind modifiers. Used by RelicCountCondition
## to drive "amass N items" unlock conditions. BOARD_MUTATION modifiers don't
## count — they fire once on acquire and don't persist as relics.
func _count_active_relics() -> int:
	var count: int = 0
	for m: Resource in active_modifiers:
		if m is ScoringModifier and (m as ScoringModifier).kind == ScoringEnums.ModifierKind.RELIC:
			count += 1
	return count


## Build the context payload for slots_state_changed events.
## Currently only enforces streak categories; non-streak relic counts are
## handled by RelicCountCondition listening on item_acquired instead.
func _build_slots_context() -> Dictionary:
	var categories: Dictionary = {}
	for m: Resource in active_modifiers:
		if m is ScoringModifier and m.streak_category != ScoringEnums.StreakCategory.NONE:
			categories[m.streak_category] = true
	# Parity streaks were cut, so the two live categories are WEDGE and COLOR.
	var all_streak: bool = (
		categories.has(ScoringEnums.StreakCategory.WEDGE)
		and categories.has(ScoringEnums.StreakCategory.COLOR)
	)
	return {
		"all_streak_categories_filled": all_streak,
	}


## Get the effective face value for a wedge by index (0-19). For display/hover.
func get_effective_value(wedge_index: int) -> int:
	return effective_wedge_values[wedge_index]


## Get the effective SegmentColor for a wedge + ring. ring_key is one of
## "inner_single", "triple", "outer_single", "double".
func get_effective_color(wedge_index: int, ring_key: String) -> ScoringEnums.SegmentColor:
	var color_entry: Dictionary = effective_wedge_colors[wedge_index]
	return color_entry[ring_key]


## Get the SegmentColor for a bullseye hit. Single bull = GREEN, double bull = RED.
func get_bull_color(is_double_bull: bool) -> ScoringEnums.SegmentColor:
	return ScoringEnums.SegmentColor.RED if is_double_bull else ScoringEnums.SegmentColor.GREEN


## Map a display ring name ("Inner Single", "Triple", etc.) to the per-ring dict key.
static func _ring_name_to_key(ring_name: String) -> String:
	match ring_name:
		"Inner Single":
			return "inner_single"
		"Triple":
			return "triple"
		"Outer Single":
			return "outer_single"
		"Double":
			return "double"
	return "inner_single"


## Clear turn-level history. Call from main.gd at the start of each new turn.
func reset_for_turn() -> void:
	hit_history_turn.clear()
	_reset_modifier_streaks(ScoringEnums.StreakScope.WITHIN_TURN)


## Clear leg-level history (and turn history). Call from main.gd at leg transitions.
func reset_for_leg() -> void:
	hit_history_turn.clear()
	hit_history_leg.clear()
	_reset_modifier_streaks(ScoringEnums.StreakScope.WITHIN_TURN)
	_reset_modifier_streaks(ScoringEnums.StreakScope.WITHIN_LEG)


## Full reset for a new run. Clears all history, all modifiers, resets board state.
func reset_for_run() -> void:
	hit_history_turn.clear()
	hit_history_leg.clear()
	hit_history_run.clear()
	active_modifiers.clear()
	voided_rings.clear()
	hotspot_rings.clear()
	# Reset to base per-category capacity; the build re-applies its grants on run start.
	streak_capacity = {
		ScoringEnums.StreakCategory.WEDGE: 1,
		ScoringEnums.StreakCategory.COLOR: 1,
	}
	# Bull radii are run-scoped (the Bigger Bull relic is earned per run); reset to base before
	# _init_default_board_state recomputes the geometry off them.
	bull_radii = {"single_bull": GEOM_SINGLE_BULL_OUTER, "double_bull": GEOM_DOUBLE_BULL_OUTER}
	_init_default_board_state()
	# Drop the cached checkout-solver candidates and their derived caches. These are
	# built from effective_wedge_values and only rebuilt when empty, so without this
	# the solver (and the checkout helper) would keep suggesting the PREVIOUS run's
	# modified wedges — e.g. proposing a "D22" on a fresh, unmodified board.
	_solver_candidates.clear()
	invalidate_preferred_remainders()
	_last_sync_version = -1
	_bump_state_version()


## Reset streak state on modifiers matching the given scope.
func _reset_modifier_streaks(scope: ScoringEnums.StreakScope) -> void:
	for modifier: Resource in active_modifiers:
		if modifier.streak_scope == scope and modifier.has_method("reset_streak_state"):
			modifier.reset_streak_state()


## Snapshot all active modifiers' streak state for speculative simulation.
func snapshot_all_streak_state() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for modifier: Resource in active_modifiers:
		if modifier is ScoringModifier:
			snapshots.append(modifier.save_streak_state())
		else:
			snapshots.append({})
	return snapshots


## Restore all active modifiers' streak state from a snapshot array.
func restore_all_streak_state(snapshots: Array[Dictionary]) -> void:
	for i: int in range(mini(snapshots.size(), active_modifiers.size())):
		var modifier: Resource = active_modifiers[i]
		if modifier is ScoringModifier and not snapshots[i].is_empty():
			modifier.restore_streak_state_from(snapshots[i])


## Run a score through the modifier pipeline speculatively — mutates streak state
## but does NOT record to hit history. Used by the checkout solver for multi-dart
## simulation where dart-2 must see the streak state dart-1 created.
func speculative_score(raw_result: Dictionary) -> Dictionary:
	var result: Dictionary = raw_result.duplicate()
	result["modifications"] = []

	_mark_void(result)

	var context: Dictionary = {
		"history_turn": hit_history_turn,
		"history_leg": hit_history_leg,
		"history_run": hit_history_run,
		"effective_wedge_values": effective_wedge_values,
		"effective_wedge_colors": effective_wedge_colors,
		"is_preview": false,
	}

	result = _score_through_modifiers(result, context)

	if result.get("is_void", false):
		result["total_score"] = 0

	return result


## The two-axis scoring pipeline, shared by process_score() and speculative_score().
## Enforces apply-order per the scoring-on-the-board spec:
##   1. Additive baseline — non-streak PER_DART modifiers fold bonuses into the multiplier.
##   2. Hotspot fold-in — board-state hotspot bonus added into the same additive baseline.
##   3. Streak multiply — streak modifiers apply their multiplicative factor LAST, so the
##      earned exponential axis multiplies the whole (ring + hotspot) baseline.
##   4. Flip pass — sign flips compose dead-last, after everything else.
## dart_score = face × (ring + Σhotspot) × streak_factor.
func _score_through_modifiers(result: Dictionary, context: Dictionary) -> Dictionary:
	# 1. Additive pass — every non-streak PER_DART modifier (FlipSign held back).
	for modifier: Resource in active_modifiers:
		if modifier.timing != ScoringEnums.ModifierTiming.PER_DART or not modifier.enabled:
			continue
		if modifier is FlipSignModifier:
			continue
		if modifier is ScoringModifier and (modifier as ScoringModifier).streak_category != ScoringEnums.StreakCategory.NONE:
			continue
		result = modifier.apply(result, context)

	# 2. Hotspot fold-in — additive, into the same baseline multiplier as a bonus.
	_apply_hotspot_bonus(result)

	# 3. Streak multiply — the SINGLE multiplicative axis. Combine every active streak's
	#    contribution into ONE factor (streak_factor = 1 + Σ contributions) and apply it
	#    ONCE, after the full additive baseline. Streaks are summed, never compounded: with
	#    no streak continuing, total is 0 → factor 1 → no change; e.g. one wedge streak at
	#    count 2 → factor 2 (×2), not 2ⁿ across n streaks. Each streak still runs its own
	#    continue/break + state update inside streak_contribution().
	# Snapshot the settled additive baseline (ring + bonuses + Σhotspot) before the
	# streak multiply, so display surfaces can show the two axes separately
	# ("oS28 ×3×5" instead of an unreconstructable "×15"). Display-only fields —
	# nothing in the pipeline reads them back.
	result["board_multiplier"] = result["multiplier"]
	result["streak_factor"] = 1

	var streak_total: int = 0
	var top_streak: ScoringModifier = null
	var top_contribution: int = 0
	for modifier: Resource in active_modifiers:
		if modifier.timing != ScoringEnums.ModifierTiming.PER_DART or not modifier.enabled:
			continue
		if not (modifier is ScoringModifier) or (modifier as ScoringModifier).streak_category == ScoringEnums.StreakCategory.NONE:
			continue
		var contribution: int = (modifier as ScoringModifier).streak_contribution(result, context)
		streak_total += contribution
		# Attribute the combined factor to the strongest contributor (for the floating-score icon).
		if contribution > top_contribution:
			top_contribution = contribution
			top_streak = modifier as ScoringModifier
	if streak_total > 0:
		var streak_factor: int = 1 + streak_total
		result["streak_factor"] = streak_factor
		_apply_combined_streak_factor(result, streak_factor, top_streak)
		result["streak_triggered"] = true
		result["streak_name"] = top_streak.modifier_name if top_streak != null else "Streak"
		# Report the dart's actual combined streak multiplier (matches the ×N in the HUD annotation).
		result["streak_count"] = streak_factor

	# 4. Flip sign is the dead-last step so it composes cleanly with everything else.
	result = _apply_flip_pass(result, context)

	return result


## Apply the single combined streak factor to the dart exactly once. The increase is
## emitted as stepwise +1 multiplier increments up to (multiplier × factor) so the
## floating-score countdown animation still reads it; each step is attributed to the
## top-contributing streak so its icon/name/color shows. factor is the already-combined
## 1 + Σ contributions — this multiplies the post-additive-baseline multiplier.
func _apply_combined_streak_factor(result: Dictionary, factor: int, source: ScoringModifier) -> void:
	if factor <= 1:
		return
	var target_mult: int = result["multiplier"] * factor
	while result["multiplier"] < target_mult:
		var old_mult: int = result["multiplier"]
		result["multiplier"] += 1
		result["total_score"] = result["face_value"] * result["multiplier"]
		_track_streak_modification(result, old_mult, result["multiplier"], source)


## Record a single +1 streak multiplier step, attributed to a streak modifier so the
## floating-score grammar shows its icon/name/color (mirrors ScoringModifier._track_modification).
func _track_streak_modification(result: Dictionary, old_value: int, new_value: int, source: ScoringModifier) -> void:
	if not result.has("modifications"):
		result["modifications"] = []
	var entry: Dictionary = {
		"field": "multiplier",
		"old_value": old_value,
		"new_value": new_value,
	}
	if source != null:
		entry["source_name"] = source.modifier_name
		entry["source_description"] = source.description
		entry["source_rarity_color"] = source.rarity_color
		entry["source_modifier"] = source
	else:
		entry["source_name"] = "Streak"
		entry["source_description"] = ""
		entry["source_rarity_color"] = Color(0.9, 0.8, 0.2)
		entry["source_modifier"] = null
	result["modifications"].append(entry)


## Fold a hotspot ring's flat multiplier bonus into the additive baseline. Mirrors how an
## additive bonus modifier mutates the result: bumps the multiplier, recomputes total_score,
## and records per-step modification entries (source "Hotspot") so the floating-score flair
## can attribute the points to the board. Bulls (wedge_index < 0) carry no hotspot.
func _apply_hotspot_bonus(result: Dictionary) -> void:
	if hotspot_rings.is_empty():
		return
	var wedge_index: int = result.get("wedge_index", -1)
	if wedge_index < 0:
		return
	var key: String = "%d:%s" % [wedge_index, result.get("ring_name", "")]
	var bonus: int = hotspot_rings.get(key, 0)
	if bonus <= 0:
		return
	for i: int in range(bonus):
		var old_mult: int = result["multiplier"]
		result["multiplier"] += 1
		result["total_score"] = result["face_value"] * result["multiplier"]
		_track_hotspot_modification(result, old_mult, result["multiplier"])


## Record a single +1 hotspot multiplier step in the result's modifications array. The
## hotspot is board state, not a ScoringModifier instance, so source_modifier is null —
## the floating-score grammar reads source_name "Hotspot" to flair it from the board.
func _track_hotspot_modification(result: Dictionary, old_value: int, new_value: int) -> void:
	if not result.has("modifications"):
		result["modifications"] = []
	result["modifications"].append({
		"source_name": "Hotspot",
		"source_description": "Hot ring: +%d to the multiplier" % new_value,
		"source_rarity_color": Color(1.0, 0.55, 0.1),
		"source_modifier": null,
		"field": "multiplier",
		"old_value": old_value,
		"new_value": new_value,
	})


## Flag a result as voided if its wedge+ring is in the boss void set. Synthesized
## results (solver, checkout segments, hover preview) don't carry is_void, so this is
## how those paths learn about drifted ring voids that aren't reflected in wedge values.
func _mark_void(result: Dictionary) -> void:
	if result.get("is_void", false):
		return
	var wi: int = result.get("wedge_index", -1)
	if wi < 0:
		return
	if voided_rings.has("%d:%s" % [wi, result.get("ring_name", "")]):
		result["is_void"] = true


## Whether a given board segment is voided this turn. Used by the hover tooltip so the
## player can see a zone is dead before committing a dart.
func is_segment_voided(wedge_index: int, ring_name: String) -> bool:
	if wedge_index < 0:
		return false
	return voided_rings.has("%d:%s" % [wedge_index, ring_name])


## Register a hotspot from an acquired HotspotModifier's stored choice. The picker stores
## the ring by its lowercase dict key (e.g. "triple"); hotspot_rings is keyed by display
## name (e.g. "Triple") to match live scoring results and voided_rings. No-stack is
## enforced upstream by the segment picker (see main._complete_pick_segment), so this is a
## plain write; if a ring is somehow already hot we keep the higher tier rather than
## downgrading.
func _register_hotspot(modifier: HotspotModifier) -> void:
	if modifier.applied_wedge_index < 0 or modifier.applied_ring_key == "":
		return
	var ring_name: String = _ring_key_to_name(modifier.applied_ring_key)
	var key: String = "%d:%s" % [modifier.applied_wedge_index, ring_name]
	hotspot_rings[key] = maxi(hotspot_rings.get(key, 0), modifier.hotspot_bonus)
	invalidate_preferred_remainders()


## Whether a segment already carries a hotspot. ring_key is the lowercase dict key from
## the segment picker. Used to disallow stacking a second hotspot on the same ring.
func is_segment_hotspotted(wedge_index: int, ring_key: String) -> bool:
	if wedge_index < 0:
		return false
	return hotspot_rings.has("%d:%s" % [wedge_index, _ring_key_to_name(ring_key)])


## Hotspot multiplier bonus on a segment (display ring name), or 0 if none. For the
## dartboard indicator and tooltips.
func get_hotspot_bonus(wedge_index: int, ring_name: String) -> int:
	if wedge_index < 0:
		return 0
	return hotspot_rings.get("%d:%s" % [wedge_index, ring_name], 0)


## Inverse of _ring_name_to_key: lowercase dict key ("triple") → display name ("Triple").
static func _ring_key_to_name(ring_key: String) -> String:
	match ring_key:
		"inner_single":
			return "Inner Single"
		"triple":
			return "Triple"
		"outer_single":
			return "Outer Single"
		"double":
			return "Double"
	return ring_key


## Apply all enabled FlipSignModifiers as the final scoring step. Held back from the
## main PER_DART loop so the sign flip always runs after every other modifier,
## regardless of acquisition order.
func _apply_flip_pass(result: Dictionary, context: Dictionary) -> Dictionary:
	for modifier: Resource in active_modifiers:
		if modifier is FlipSignModifier and modifier.enabled:
			result = modifier.apply(result, context)
	return result


## Board positions (0-19) currently flipped by a FlipSignModifier. Used by the HUD
## to draw a "+" suffix on those wedge numbers.
func get_flipped_wedge_indices() -> Array[int]:
	var indices: Array[int] = []
	for modifier: Resource in active_modifiers:
		if modifier is FlipSignModifier and modifier.enabled:
			var idx: int = (modifier as FlipSignModifier).target_wedge_index
			if idx >= 0 and not indices.has(idx):
				indices.append(idx)
	return indices


## Build a synthetic score result for a candidate target (used by the solver).
## target: {wedge_index, ring_name, face_value, multiplier, is_bull, segment_color}
func synthesize_result(target: Dictionary) -> Dictionary:
	return {
		"face_value": target["face_value"],
		"multiplier": target["multiplier"],
		"total_score": target["face_value"] * target["multiplier"],
		"ring_name": target["ring_name"],
		"wedge_index": target.get("wedge_index", -1),
		"segment_color": target.get("segment_color", -1),
		"is_bull": target.get("is_bull", false),
	}


## Maximum checkout paths to return from the solver.
@export var max_displayed_paths: int = 5

## Hard ceiling on speculative-score evaluations per solve_checkout enumeration. The enumerator
## fragments its cache by streak-hash, so a pathological board (deep checkout, many candidates)
## can burn unbounded time producing few usable paths — this budgets the WORK, not the stored
## path count, and bails with whatever partial results it has. Iterative deepening keeps real
## solves far under this; it's a backstop, not the primary bound. 0 disables the cap.
@export var solver_spec_call_budget: int = 15000

## Cached candidate targets for the solver (rebuilt when board state changes).
var _solver_candidates: Array[Dictionary] = []

## Per-(wedge, ring) fatness lookup (20 entries; ring_key → fatness float = −effective area).
## Rebuilt on geometry change so path ranking reads an O(1) table instead of recomputing the
## annular-sector area (dict access + float math) on every _compare comparison. Bull/off-board
## fatness is computed inline (cheap constants).
var _fatness_cache: Array[Dictionary] = []

## Cached preferred remainders for the setup solver.
var _preferred_remainders: Array[int] = []

## Whether preferred remainders need recomputing.
var _preferred_remainders_dirty: bool = true

## Cached map of 1-dart-finishable remainders → fatness of best finishing target.
## Used by setup recommendation to prefer setups that leave the player at a
## single-dart finish next turn. Key = remainder value, value = fatness score
## (lower fatness = fatter, more reliable double).
## Computed cheaply: only iterates 22 double candidates through the preview pipeline.
var _one_dart_finishable: Dictionary = {}

## Whether the 1-dart finishable cache needs recomputing.
var _one_dart_finishable_dirty: bool = true

## Highest total_score any single scoring dart produces under current modifiers.
## Cached alongside preferred remainders; invalidated by the same call.
var _max_single_dart_score: int = 0

## Highest value in _preferred_remainders (last element, since it's sorted ascending).
var _max_preferred_remainder: int = 0


## Build the 83 candidate targets from current effective board state.
func _build_solver_candidates() -> void:
	_solver_candidates.clear()

	for wedge_idx: int in range(20):
		var face_value: int = effective_wedge_values[wedge_idx]
		var colors: Dictionary = {}
		if effective_wedge_colors.size() == 20:
			colors = effective_wedge_colors[wedge_idx]
		else:
			var is_even: bool = wedge_idx % 2 == 0
			var sc: int = ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
			var mc: int = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
			colors = {"inner_single": sc, "triple": mc, "outer_single": sc, "double": mc}

		# Inner Single
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Inner Single",
			"face_value": face_value, "multiplier": 1,
			"segment_color": colors["inner_single"], "is_bull": false,
		})
		# Outer Single
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Outer Single",
			"face_value": face_value, "multiplier": 1,
			"segment_color": colors["outer_single"], "is_bull": false,
		})
		# Double
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Double",
			"face_value": face_value, "multiplier": 2,
			"segment_color": colors["double"], "is_bull": false,
		})
		# Triple
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Triple",
			"face_value": face_value, "multiplier": 3,
			"segment_color": colors["triple"], "is_bull": false,
		})

	# Single Bull
	_solver_candidates.append({
		"wedge_index": -1, "ring_name": "Single Bull",
		"face_value": 25, "multiplier": 1,
		"segment_color": ScoringEnums.SegmentColor.GREEN, "is_bull": true,
	})
	# Double Bull
	_solver_candidates.append({
		"wedge_index": -1, "ring_name": "Double Bull",
		"face_value": 25, "multiplier": 2,
		"segment_color": ScoringEnums.SegmentColor.RED, "is_bull": true,
	})
	# Deliberate off-board (streak breaker)
	_solver_candidates.append({
		"wedge_index": -1, "ring_name": "Off Board",
		"face_value": 0, "multiplier": 0,
		"segment_color": -1, "is_bull": false,
	})


## Solve for all valid checkout paths from a given remaining score and darts left.
## Returns an Array of paths, each path is an Array of {target, result} dicts.
## Ranked by: fewest darts, fattest segments, fewest off-board darts.
func solve_checkout(remaining: int, darts_left: int) -> Array[Array]:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	# #4 — arm the single-dart prune (remaining > max_single × darts_left) used by BOTH the
	# deepening existence pass and the enumeration, so neither runs unpruned on a fresh board.
	if _one_dart_finishable_dirty:
		_compute_one_dart_finishable()

	var _perf_start: int = Time.get_ticks_usec() if debug_perf_log else 0
	var _perf_counters: Array[int] = [0, 0, 0, 0]

	# Iterative deepening (#1): find the MINIMAL checkout length k via the existence solver, then
	# enumerate ONLY at depth k. Enumerating at the full darts_left would also build every padded
	# longer finish (a 2-dart checkout fluffed to 4–5 darts) — that cross-product is the d=4/5
	# explosion. Minimal-length path counts stay small, so full semantics are kept (a genuine
	# 4-dart route at r=201 with 5 darts IS found) at roughly d=3 cost.
	var exist_cache: Dictionary = {}
	var k: int = 0
	for d: int in range(1, darts_left + 1):
		if _solve_first(remaining, d, exist_cache):
			k = d
			break

	var raw_paths: Array[Array] = []
	if k > 0:
		var enum_cache: Dictionary = {}
		raw_paths = _solve_recursive(remaining, k, enum_cache, _perf_counters)

	# Capture the enumeration size BEFORE the display trim — raw_count is the perf story; the
	# trimmed size is always ≤ max_displayed_paths and hides it.
	var raw_count: int = raw_paths.size()
	var enum_ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0 if debug_perf_log else 0.0

	# Rank + trim, decorating each path's fatness ONCE (#3) instead of recomputing it per
	# comparison across an O(n log n) sort.
	_rank_and_trim(raw_paths)

	if debug_perf_log:
		var ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0
		_perf_log("solve_checkout r=%d d=%d k=%d  %.1fms (deepen+enum %.1fms, sort %.1fms)  recursive_calls=%d  spec_calls=%d  cache_hits=%d  cache_misses=%d  raw_paths=%d  shown=%d" % [remaining, darts_left, k, ms, enum_ms, ms - enum_ms, _perf_counters[0], _perf_counters[1], _perf_counters[2], _perf_counters[3], raw_count, raw_paths.size()])

	return raw_paths


## Decorate each path with (length, summed fatness, off-board count) ONCE, sort the decorations,
## and trim `paths` in place to max_displayed_paths. Avoids _target_fatness being recomputed on
## every comparison (the pre-change _compare_paths summed fatness inside the comparator). With
## iterative deepening all paths share length k, so the tiebreaks (fatter, then fewer off-board)
## do the ordering.
func _rank_and_trim(paths: Array[Array]) -> void:
	if paths.size() <= 1:
		return
	var decorated: Array = []
	for p: Array in paths:
		var fat: float = 0.0
		var off: int = 0
		for step: Dictionary in p:
			fat += _target_fatness(step["target"])
			if step["target"]["ring_name"] == "Off Board":
				off += 1
		decorated.append({"p": p, "len": p.size(), "fat": fat, "off": off})
	decorated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["len"] != b["len"]:
			return a["len"] < b["len"]
		if not is_equal_approx(a["fat"], b["fat"]):
			return a["fat"] < b["fat"]
		return a["off"] < b["off"])
	paths.clear()
	for i: int in range(mini(decorated.size(), max_displayed_paths)):
		paths.append(decorated[i]["p"] as Array)


## Public wrapper for the finish-validity seam, so live consumers (main's bust preview /
## checkout highlights) resolve checkouts through the SAME predicate the solver uses — no
## drifting copies of the out-rule. wedge_index is needed for the parity predicate (-1 = bull /
## no wedge, always exempt).
func is_valid_finish(ring_name: String, wedge_index: int = -1) -> bool:
	return _is_valid_finish(ring_name, wedge_index)


## The finish-validity seam (geometry spec §9b cond 1): a generalized out-rule rather than a
## hardcoded double-out. Composed of (a) which RING types finish — doubles always, triples when
## allow_triple_checkout (the Triple Outs reward = superset; doubles-off is the natural future
## flag, unused today), and (b) the Parity Out predicate that narrows wedge finishes by parity.
## Glass Cannon takes precedence over everything: any ring (except off-board) outs. Because
## Glass Cannon is a REWARD and Parity Out a HANDICAP, the spec's "they can't both hold"
## mutual-exclusion (§9b cond 4) is resolved HERE at runtime — the reward wins — rather than via
## the reward-to-reward excludes[] array (which only governs RuleModifierReward pairs).
func _is_valid_finish(ring_name: String, wedge_index: int = -1) -> bool:
	if ring_name == "Off Board":
		return false
	if glass_cannon_active:
		return true
	# (a) Ring-type gate. Bull is a double for finish purposes; triples only when enabled.
	var ring_ok: bool = ring_name == "Double" or ring_name == "Double Bull"
	if allow_triple_checkout and ring_name == "Triple":
		ring_ok = true
	if not ring_ok:
		return false
	# (b) Parity Out narrowing. Only wedge-based finishes (wedge_index ≥ 0) are filtered; the
	# bull (wedge_index -1) is always exempt. Parity reads the LIVE effective face value.
	if checkout_parity != -1 and wedge_index >= 0 and wedge_index < effective_wedge_values.size():
		var face_even: bool = (effective_wedge_values[wedge_index] % 2) == 0
		var want_even: bool = checkout_parity == 0
		if face_even != want_even:
			return false
	return true


func _solve_recursive(remaining: int, darts_left: int, cache: Dictionary, _pc: Array[int] = [0, 0, 0, 0]) -> Array[Array]:
	_pc[0] += 1
	if darts_left <= 0 or remaining <= 0:
		return []

	# Work budget (#2): bail this subtree once the speculative-score count is spent, so a
	# pathological enumeration degrades to partial results instead of freezing the frame. NOT
	# cached (the budget is global to the call, so caching a truncated [] would poison reuse).
	if solver_spec_call_budget > 0 and _pc[1] >= solver_spec_call_budget:
		return []

	if _max_single_dart_score > 0 and remaining > _max_single_dart_score * darts_left:
		var cache_key_neg: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
		cache[cache_key_neg] = []
		return []

	var cache_key: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
	if cache.has(cache_key):
		_pc[2] += 1
		return cache[cache_key]
	_pc[3] += 1

	var paths: Array[Array] = []

	for target: Dictionary in _solver_candidates:
		var base_score: int = target["face_value"] * target["multiplier"]
		# Quick prune: if base score alone exceeds remaining, skip
		# (modifiers can only increase score, so this is safe)
		if base_score > remaining and base_score > 0:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		_pc[1] += 1
		var scored: int = result["total_score"]

		var ring_name: String = target["ring_name"]

		var step: Dictionary = {"target": target, "result": result}

		if scored == remaining and _is_valid_finish(ring_name, target.get("wedge_index", -1)):
			# Checkout on this dart
			paths.append([step])
		elif scored < remaining and scored >= 0 and darts_left > 1:
			var new_remaining: int = remaining - scored
			# Prune the one UNIVERSALLY dead remainder: from 1 you can never finish (the minimum
			# valid finish scores 2). Rule-specific dead remainders (e.g. Even Out stranding 2)
			# need no extra prune — the recursion simply finds no valid finish there and returns
			# [], and the setup solver steers around them via _one_dart_finishable (§9b cond 1).
			# Glass Cannon makes 1 finishable (single 1), so it skips the prune.
			if new_remaining != 1 or glass_cannon_active:
				var sub_paths: Array[Array] = _solve_recursive(new_remaining, darts_left - 1, cache, _pc)
				for sub: Array in sub_paths:
					var full_path: Array = [step]
					full_path.append_array(sub)
					paths.append(full_path)

		restore_all_streak_state(snapshot)

	cache[cache_key] = paths
	return paths


## Rank a target by "fatness" — larger physical areas rank as fatter (more reliable).
## Returns a LOWER number for fatter targets (so path sorting prefers them). Reads the EFFECTIVE
## annular-sector area off the live geometry (per-wedge weight × ring band radii) rather than the
## old static ring assumption, so suggested paths prefer geometry-enlarged targets and avoid
## floor-squeezed singles. Returns -area: fatter (bigger area) sorts first; off-board/unknowns
## get the worst (highest) cost.
func _target_fatness(target: Dictionary) -> float:
	var ring: String = target.get("ring_name", "")
	if ring == "Off Board" or ring == "":
		return 1000.0
	if ring == "Double Bull":
		var rdb: float = float(bull_radii.get("double_bull", GEOM_DOUBLE_BULL_OUTER))
		return -PI * rdb * rdb
	if ring == "Single Bull":
		var rsb: float = float(bull_radii.get("single_bull", GEOM_SINGLE_BULL_OUTER))
		var rdb2: float = float(bull_radii.get("double_bull", GEOM_DOUBLE_BULL_OUTER))
		return -PI * maxf(rsb * rsb - rdb2 * rdb2, 0.0)
	# Wedge ring: O(1) lookup from the table rebuilt on each geometry change.
	var wi: int = target.get("wedge_index", -1)
	var key: String = _ring_name_to_key(ring)
	if wi >= 0 and wi < _fatness_cache.size() and _fatness_cache[wi].has(key):
		return _fatness_cache[wi][key]
	# Fallback (cache not yet built / no wedge context): compute from the band directly.
	var band: Array = _fatness_ring_band(wi, ring)
	var weight: float = 1.0
	if wi >= 0 and wi < effective_wedge_weights.size():
		weight = effective_wedge_weights[wi]
	return -weight * maxf(float(band[1]) * float(band[1]) - float(band[0]) * float(band[0]), 0.0)


## Effective [inner, outer] normalized radii for a wedge ring, from the live geometry bounds if
## available, else the base constants (no wedge context / geometry not yet computed).
func _fatness_ring_band(wedge_index: int, ring_name: String) -> Array:
	var key: String = _ring_name_to_key(ring_name)
	if wedge_index >= 0 and wedge_index < effective_ring_bounds.size():
		var bounds: Dictionary = effective_ring_bounds[wedge_index]
		if bounds.has(key):
			return [float(bounds[key][0]), float(bounds[key][1])]
	match key:
		"inner_single":
			return [GEOM_SINGLE_BULL_OUTER, GEOM_INNER_SINGLE_OUTER]
		"triple":
			return [GEOM_INNER_SINGLE_OUTER, GEOM_TRIPLE_OUTER]
		"outer_single":
			return [GEOM_TRIPLE_OUTER, GEOM_OUTER_SINGLE_OUTER]
		"double":
			return [GEOM_OUTER_SINGLE_OUTER, GEOM_DOUBLE_OUTER]
	return [0.0, 0.0]


## Check if a wedge's inner and outer singles produce different total_score
## under the current scoring pipeline (preview mode, no streak mutation).
func singles_diverge(wedge_index: int) -> bool:
	if wedge_index < 0 or wedge_index >= effective_wedge_values.size():
		return false
	var face_value: int = effective_wedge_values[wedge_index]
	var colors: Dictionary = effective_wedge_colors[wedge_index]
	var inner_synth: Dictionary = {
		"face_value": face_value, "multiplier": 1, "total_score": face_value,
		"ring_name": "Inner Single", "wedge_index": wedge_index,
		"segment_color": colors.get("inner_single", -1), "is_bull": false,
	}
	var outer_synth: Dictionary = {
		"face_value": face_value, "multiplier": 1, "total_score": face_value,
		"ring_name": "Outer Single", "wedge_index": wedge_index,
		"segment_color": colors.get("outer_single", -1), "is_bull": false,
	}
	var inner_result: Dictionary = process_score(inner_synth, true)
	var outer_result: Dictionary = process_score(outer_synth, true)
	return inner_result["total_score"] != outer_result["total_score"]


## Get a display-friendly name for a target (e.g., "T20", "D-Bull", "S5").
## Singles show "Inner S18" / "Outer S18" only when the wedge's two singles diverge.
func get_target_display_name(target: Dictionary) -> String:
	var ring: String = target["ring_name"]
	var face: int = target["face_value"]
	match ring:
		"Inner Single":
			var wi: int = target.get("wedge_index", -1)
			if wi >= 0 and singles_diverge(wi):
				return "Inner S%d" % face
			return "S%d" % face
		"Outer Single":
			var wi: int = target.get("wedge_index", -1)
			if wi >= 0 and singles_diverge(wi):
				return "Outer S%d" % face
			return "S%d" % face
		"Double":
			return "D%d" % face
		"Triple":
			return "T%d" % face
		"Single Bull":
			return "Bull"
		"Double Bull":
			return "D-Bull"
		"Off Board":
			return "Off"
	return "?"


## Compute which remainders (2-180) have at least one valid 3-dart checkout.
## Cached and invalidated on modifier state changes.
##
## Two key optimizations over the naive 179-solve approach:
##   1. Shared cache across all 179 iterations — sub-problems repeat heavily
##      (e.g., the 2-dart sub-problem from r=170 and r=169 overlap), so a
##      single shared cache turns redundant work into cache hits.
##   2. Find-first-path semantics (_solve_first) — we only need to know
##      WHETHER a checkout exists, not enumerate all of them, so we return
##      as soon as the first valid path is discovered.
##
## Combined, this drops the precompute from O(seconds) to O(milliseconds) in
## vanilla configurations.
func compute_preferred_remainders() -> void:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	if _one_dart_finishable_dirty:
		_compute_one_dart_finishable()

	var _perf_start: int = Time.get_ticks_usec() if debug_perf_log else 0

	_preferred_remainders.clear()
	# Save current streak state so the computation doesn't pollute it
	var saved: Array[Dictionary] = snapshot_all_streak_state()

	# Shared cache across all 179 iterations (see comment above).
	var shared_cache: Dictionary = {}

	for r: int in range(2, 181):
		# Reset streaks to turn-fresh state for V1
		for modifier: Resource in active_modifiers:
			if modifier.has_method("reset_streak_state"):
				modifier.reset_streak_state()
		if _solve_first(r, 3, shared_cache):
			_preferred_remainders.append(r)

	restore_all_streak_state(saved)
	_preferred_remainders_dirty = false
	_max_preferred_remainder = _preferred_remainders[-1] if _preferred_remainders.size() > 0 else 0

	if debug_perf_log:
		var ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0
		_perf_log("compute_preferred_remainders  %.1fms  results=%d" % [ms, _preferred_remainders.size()])


## Existence-only checkout solver. Returns true as soon as any valid path is
## found, without enumerating the full set. Used by compute_preferred_remainders
## which only cares about whether checkouts exist, not what they look like.
## Cache stores bool results keyed by (remaining, darts_left, streak_state).
func _solve_first(remaining: int, darts_left: int, cache: Dictionary) -> bool:
	if darts_left <= 0 or remaining <= 0:
		return false

	if _max_single_dart_score > 0 and remaining > _max_single_dart_score * darts_left:
		return false

	var cache_key: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
	if cache.has(cache_key):
		return cache[cache_key]

	var found: bool = false

	for target: Dictionary in _solver_candidates:
		if found:
			break
		var base_score: int = target["face_value"] * target["multiplier"]
		# Prune: base score alone exceeds remaining (modifiers only add)
		if base_score > remaining and base_score > 0:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]

		var ring_name: String = target["ring_name"]

		if scored == remaining and _is_valid_finish(ring_name, target.get("wedge_index", -1)):
			found = true
		elif scored < remaining and scored >= 0 and darts_left > 1:
			var new_remaining: int = remaining - scored
			if new_remaining != 1 or glass_cannon_active:
				if _solve_first(new_remaining, darts_left - 1, cache):
					found = true

		restore_all_streak_state(snapshot)

	cache[cache_key] = found
	return found


## Compute the map of remainders that have a 1-dart checkout under the
## current modifier configuration. Cheap — only runs the VALID finishing ring candidates
## (doubles, plus triples when allow_triple_checkout) through the preview pipeline (no
## recursion). Maps remainder → fatness of the best finishing target so setup ranking can
## prefer fatter finishes. Each candidate is gated by _is_valid_finish, so the Parity Out
## out-rule automatically drops dead-parity wedges from the map — and the setup solver, which
## steers toward 1-dart-finishable remainders, steers around the rule's dead remainders for free
## (Even Out stranding remaining=2 falls out here, §9b cond 1). Bull stays exempt.
func _compute_one_dart_finishable() -> void:
	var _perf_start: int = Time.get_ticks_usec() if debug_perf_log else 0
	_one_dart_finishable.clear()

	# Save and reset to turn-fresh streak state for V1 consistency
	var saved: Array[Dictionary] = snapshot_all_streak_state()
	for modifier: Resource in active_modifiers:
		if modifier.has_method("reset_streak_state"):
			modifier.reset_streak_state()

	var double_bull_fatness: float = _target_fatness({"ring_name": "Double Bull"})

	# The wedge finishing rings to sweep: doubles always, triples only when they out. Each is
	# still per-wedge parity-gated below via _is_valid_finish.
	var finish_rings: Array[String] = ["Double"]
	if allow_triple_checkout:
		finish_rings.append("Triple")

	# 20 wedges × valid finishing rings — what score does each produce under current modifiers?
	for wedge_idx: int in range(20):
		var face: int = effective_wedge_values[wedge_idx]
		for ring_name: String in finish_rings:
			if not _is_valid_finish(ring_name, wedge_idx):
				continue   # dead under the out-rule (e.g. Parity Out drops the wrong parity)
			var ring_key: String = _ring_name_to_key(ring_name)
			var mult: int = 3 if ring_name == "Triple" else 2
			var color: int = (ScoringEnums.SegmentColor.RED if wedge_idx % 2 == 0 else ScoringEnums.SegmentColor.GREEN)
			if effective_wedge_colors.size() == 20:
				color = effective_wedge_colors[wedge_idx][ring_key]
			var synth: Dictionary = synthesize_result({
				"wedge_index": wedge_idx, "ring_name": ring_name,
				"face_value": face, "multiplier": mult,
				"segment_color": color, "is_bull": false,
			})
			# Preview mode — does NOT mutate streak state
			var result: Dictionary = process_score(synth, true)
			var score: int = result["total_score"]
			if score > 0:
				# Keep the fattest finishing target if several produce the same score.
				var fat: float = _target_fatness({"ring_name": ring_name, "wedge_index": wedge_idx})
				var current: float = _one_dart_finishable.get(score, 999.0)
				if fat < current:
					_one_dart_finishable[score] = fat

	# Double bull (always a valid finish — exempt from Parity Out)
	var bull_synth: Dictionary = synthesize_result({
		"wedge_index": -1, "ring_name": "Double Bull",
		"face_value": 25, "multiplier": 2,
		"segment_color": ScoringEnums.SegmentColor.RED, "is_bull": true,
	})
	var bull_result: Dictionary = process_score(bull_synth, true)
	var bull_score: int = bull_result["total_score"]
	if bull_score > 0:
		var current: float = _one_dart_finishable.get(bull_score, 999.0)
		if double_bull_fatness < current:
			_one_dart_finishable[bull_score] = double_bull_fatness

	# Compute _max_single_dart_score by sweeping all scoring candidates.
	# Streak state is already turn-fresh from the reset above.
	if _solver_candidates.is_empty():
		_build_solver_candidates()
	_max_single_dart_score = 0
	for target: Dictionary in _solver_candidates:
		if target["face_value"] * target["multiplier"] <= 0:
			continue
		var snap: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = process_score(synth, true)
		if result["total_score"] > _max_single_dart_score:
			_max_single_dart_score = result["total_score"]
		restore_all_streak_state(snap)

	restore_all_streak_state(saved)
	_one_dart_finishable_dirty = false

	if debug_perf_log:
		var ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0
		_perf_log("_compute_one_dart_finishable  %.1fms  entries=%d" % [ms, _one_dart_finishable.size()])


## Get the 1-dart finishable map, computing it if dirty.
## Map structure: { remainder_value: fatness_of_best_finishing_target }.
func get_one_dart_finishable() -> Dictionary:
	if _one_dart_finishable_dirty:
		_compute_one_dart_finishable()
	return _one_dart_finishable


## Get the preferred remainders list, computing if dirty.
func get_preferred_remainders() -> Array[int]:
	if _preferred_remainders_dirty:
		compute_preferred_remainders()
	return _preferred_remainders


## Mark preferred remainders + 1-dart finishable cache for recomputation.
## Call on any modifier state change (acquire, sell, swap, toggle).
func invalidate_preferred_remainders() -> void:
	_preferred_remainders_dirty = true
	_one_dart_finishable_dirty = true
	if debug_perf_log:
		_perf_log("invalidate_preferred_remainders")
		print_stack()


## Recommend a single setup target when no checkout exists this turn.
## Returns {target, result, resulting_remainder, mode} where mode is a
## ScoringEnums.SetupMode value. Modes evaluated in priority order:
##   ENDGAME_SETUP — scoring dart lands at a 1-dart-finishable remainder.
##   SCORE_REDUCTION — too far from checkout range; just score points.
##   MID_ZONE_SETUP — scoring dart lands in preferred remainders.
##   OFF_BOARD_PRESERVE — every scoring dart busts or leaves remainder=1.
func get_setup_recommendation(remaining: int) -> Dictionary:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	var one_dart: Dictionary = get_one_dart_finishable()
	var preferred: Array[int] = get_preferred_remainders()

	# Mode 2: Endgame setup — scan for candidates landing at 1-dart finishable.
	var endgame_best: Dictionary = {}
	var endgame_key: Array = []

	var saved: Array[Dictionary] = snapshot_all_streak_state()

	for target: Dictionary in _solver_candidates:
		var base_score: int = target["face_value"] * target["multiplier"]
		if base_score <= 0 or base_score > remaining:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]
		restore_all_streak_state(snapshot)

		var new_remaining: int = remaining - scored
		if new_remaining < 2 or scored > remaining:
			continue

		if one_dart.has(new_remaining):
			var key: Array = [one_dart[new_remaining], new_remaining]
			if endgame_key.is_empty() or key < endgame_key:
				endgame_best = {
					"target": target, "result": result,
					"resulting_remainder": new_remaining,
					"mode": ScoringEnums.SetupMode.ENDGAME_SETUP,
				}
				endgame_key = key

	restore_all_streak_state(saved)

	if not endgame_best.is_empty():
		return endgame_best

	# Mode 3: Score-reduction — no scoring dart can reach preferred remainders.
	if remaining - _max_single_dart_score > _max_preferred_remainder:
		return {
			"target": {}, "result": {},
			"resulting_remainder": remaining,
			"mode": ScoringEnums.SetupMode.SCORE_REDUCTION,
		}

	# Mode 4: Mid-zone setup — scoring dart lands in preferred remainders.
	var midzone_best: Dictionary = {}
	var midzone_key: Array = []

	saved = snapshot_all_streak_state()

	for target: Dictionary in _solver_candidates:
		var base_score: int = target["face_value"] * target["multiplier"]
		if base_score <= 0 or base_score > remaining:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]
		restore_all_streak_state(snapshot)

		var new_remaining: int = remaining - scored
		if new_remaining < 2 or scored > remaining:
			continue

		if new_remaining in preferred:
			var key: Array = [999, new_remaining]
			if midzone_key.is_empty() or key < midzone_key:
				midzone_best = {
					"target": target, "result": result,
					"resulting_remainder": new_remaining,
					"mode": ScoringEnums.SetupMode.MID_ZONE_SETUP,
				}
				midzone_key = key

	restore_all_streak_state(saved)

	if not midzone_best.is_empty():
		return midzone_best

	# Mode 5: Off-board preservation — every scoring dart busts.
	return {
		"target": {"ring_name": "Off Board", "face_value": 0, "multiplier": 0,
			"wedge_index": -1, "segment_color": -1, "is_bull": false},
		"result": {"total_score": 0},
		"resulting_remainder": remaining,
		"mode": ScoringEnums.SetupMode.OFF_BOARD_PRESERVE,
	}


## Calculate which segments would win the leg at the given remaining score.
## Checks doubles (always), triples (if allow_triple_checkout), and all rings (if glass_cannon_active).
func calculate_checkout_segments(remaining_score: int) -> Array[Dictionary]:
	var checkout_segments: Array[Dictionary] = []

	# Rings to check for wedge-based finishes
	var finish_rings: Array[Dictionary] = [
		{"ring_name": "Double", "multiplier": 2, "type": "wedge"},
	]
	if allow_triple_checkout or glass_cannon_active:
		finish_rings.append({"ring_name": "Triple", "multiplier": 3, "type": "triple_wedge"})
	if glass_cannon_active:
		finish_rings.append({"ring_name": "Inner Single", "multiplier": 1, "type": "single_wedge", "ring_key": "inner_single"})
		finish_rings.append({"ring_name": "Outer Single", "multiplier": 1, "type": "single_wedge", "ring_key": "outer_single"})

	for wedge_idx: int in range(20):
		var face_value: int = effective_wedge_values[wedge_idx]
		var colors: Dictionary = {}
		if effective_wedge_colors.size() == 20:
			colors = effective_wedge_colors[wedge_idx]
		else:
			var is_even: bool = wedge_idx % 2 == 0
			var sc: int = ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
			var mc: int = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
			colors = {"inner_single": sc, "triple": mc, "outer_single": sc, "double": mc}

		for ring_info: Dictionary in finish_rings:
			var mult: int = ring_info["multiplier"]
			var ring_name: String = ring_info["ring_name"]
			var ring_key: String = _ring_name_to_key(ring_name)
			# Parity Out drops the wrong-parity wedges from the checkout highlight set so the
			# board's gold finishes match what actually outs (and dead doubles read as dimmed).
			if not _is_valid_finish(ring_name, wedge_idx):
				continue
			var synthetic_result: Dictionary = {
				"face_value": face_value,
				"multiplier": mult,
				"total_score": face_value * mult,
				"ring_name": ring_name,
				"wedge_index": wedge_idx,
				"segment_color": colors[ring_key],
				"is_bull": false,
			}
			var modified_result: Dictionary = process_score(synthetic_result, true)
			if modified_result["total_score"] == remaining_score:
				var seg_entry: Dictionary = {"type": ring_info["type"], "wedge_idx": wedge_idx}
				if ring_info.has("ring_key"):
					seg_entry["ring_key"] = ring_info["ring_key"]
				checkout_segments.append(seg_entry)

	# Check double bull (always a valid finish)
	var bull_result: Dictionary = {
		"face_value": 25,
		"multiplier": 2,
		"total_score": 50,
		"ring_name": "Double Bull",
		"wedge_index": -1,
		"segment_color": ScoringEnums.SegmentColor.RED,
		"is_bull": true,
	}
	var modified_bull: Dictionary = process_score(bull_result, true)
	if modified_bull["total_score"] == remaining_score:
		checkout_segments.append({"type": "double_bull"})

	# Check single bull (Glass Cannon only)
	if glass_cannon_active:
		var single_bull: Dictionary = {
			"face_value": 25,
			"multiplier": 1,
			"total_score": 25,
			"ring_name": "Single Bull",
			"wedge_index": -1,
			"segment_color": ScoringEnums.SegmentColor.GREEN,
			"is_bull": true,
		}
		var modified_sb: Dictionary = process_score(single_bull, true)
		if modified_sb["total_score"] == remaining_score:
			checkout_segments.append({"type": "single_bull"})

	return checkout_segments


## Find all board segments that produce a given total_score under the current
## scoring pipeline. Used by path illumination to highlight equivalent aims.
## When is_finish is true, only includes segments with valid checkout rings.
func find_equivalent_segments(target_score: int, is_finish: bool = false) -> Array[Dictionary]:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	var equivalents: Array[Dictionary] = []
	for candidate: Dictionary in _solver_candidates:
		var ring_name: String = candidate["ring_name"]
		if ring_name == "Off Board":
			continue
		if is_finish and not _is_valid_finish(ring_name, candidate.get("wedge_index", -1)):
			continue
		var synth: Dictionary = synthesize_result(candidate)
		var result: Dictionary = process_score(synth, true)
		if result["total_score"] == target_score:
			equivalents.append(_candidate_to_segment_descriptor(candidate))
	return equivalents


func _candidate_to_segment_descriptor(candidate: Dictionary) -> Dictionary:
	var ring: String = candidate["ring_name"]
	var wedge_idx: int = candidate.get("wedge_index", -1)
	match ring:
		"Double":
			return {"type": "wedge", "wedge_idx": wedge_idx}
		"Triple":
			return {"type": "triple_wedge", "wedge_idx": wedge_idx}
		"Inner Single":
			return {"type": "single_wedge", "wedge_idx": wedge_idx, "ring_key": "inner_single"}
		"Outer Single":
			return {"type": "single_wedge", "wedge_idx": wedge_idx, "ring_key": "outer_single"}
		"Double Bull":
			return {"type": "double_bull"}
		"Single Bull":
			return {"type": "single_bull"}
	return {}
