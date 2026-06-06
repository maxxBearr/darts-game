class_name MapGraph
extends RefCounted
## The generated run-map data model plus its generator. No Node/scene dependency,
## so it is headless unit-testable. See specs/map/01-substrate-impl.md §3 for the
## ordered algorithm and §2b for the API contract.
##
## Topology (slice 1, "rough rect"): a shared funnel entry per act → lane_count
## parallel middle columns (with bridge crossovers + an optional in-lane
## reconverging fork) → a single terminal BOSS per act. Acts chain boss→entry.
## acts == LevelDefinition.boss_count (501→1 act, 1001→2, 1501→3).

var nodes: Dictionary = {}        ## id -> MapNode
var start_id: int = -1            ## the act-0 entry (the shared funnel the run starts on)
var current_id: int = -1          ## where the player is now (-1 before the first step)
var terminal_id: int = -1         ## the final act's boss; reaching it == run victory
var acts: int = 1
var lane_count: int = 2

var _next_id: int = 0

## Base darts a turn fronts at generation time. NOT a config knob — it mirrors
## x01_game.darts_per_turn's default (3). The generator runs the pressure math at
## run-start, before any power item raises darts_per_turn, so the base is correct
## here; items then ease the live leg (more darts/turn) without changing the rolled
## target. See specs/map/01-substrate-slice2-impl.md §4.
const BASE_DARTS_PER_TURN: int = 3

# Pressure-math context, captured during _assign_leg_params so the public seam
# functions (baseline_target / expected_per_dart / pressure_of) stay callable
# after generation — Phase 02 challenge nodes read the same curve (§6).
var _starting_target: int = 101
var _target_increment: int = 100
var _max_target: int = 501
var _reference_turns: int = 5
var _act_min_depth: Dictionary = {}   ## act -> shallowest depth in that act
var _act_max_depth: Dictionary = {}   ## act -> deepest depth (the boss) in that act
var _depth_act: Dictionary = {}       ## depth -> act (each depth sits in exactly one act)

# Incremental per-act generation state (§3.6). The graph is an accumulating container:
# generate() seeds act 0, generate_next_act() appends each later act on a boss clear.
# These persist the cfg/level/rng and the running frontier across those calls.
var _cfg: MapGenConfig = null          ## the tuning config, captured at run start
var _level: LevelDefinition = null     ## the level, captured at run start (max target / acts)
var _rng: RandomNumberGenerator = null ## the SEEDED generator, threaded across act gens
var _generated_acts: int = 0           ## how many acts have been appended so far
var _prev_boss_id: int = -1            ## the most-recently generated boss (the frontier sink)
var _next_depth: int = 0               ## the running global depth counter (next free column)


## Build a run map for `level`, using the seeded `rng` for every roll so runs are
## reproducible. Slice 3 generates ONE act at a time: generate() seeds only act 0;
## generate_next_act(run_state) appends each later act when its predecessor boss is
## cleared, so a runtime-gated event family (brush) can be rolled against the live state
## at the moment the section is shown (§3.6). `starting_target` / `target_increment`
## mirror x01_game so the rolled targets land on the engine's X01 parity lattice (101, …).
static func generate(level: LevelDefinition, rng: RandomNumberGenerator, starting_target: int = 101, target_increment: int = 100) -> MapGraph:
	var graph: MapGraph = MapGraph.new()
	if level != null and level.map_gen_config != null:
		graph._cfg = level.map_gen_config
	else:
		graph._cfg = MapGenConfig.new()
	graph._level = level
	graph._rng = rng
	graph.acts = maxi(level.boss_count if level != null else 1, 1)
	graph.lane_count = maxi(graph._cfg.lane_count, 1)
	# Capture the pressure-math context once at run start (before any power item raises
	# darts_per_turn) so the public seam stays valid across each incremental act gen.
	graph._starting_target = starting_target
	graph._target_increment = target_increment
	graph._max_target = level.max_score_target if level != null else 501
	graph._reference_turns = maxi(graph._cfg.reference_turns, 1)
	# Seed ONLY act 0. At run start nothing is owned, so an empty run-state ⇒ events roll
	# the always-eligible accuracy family (brush has no colors yet).
	graph._build_act(0, {})
	graph._validate()
	return graph


## Append the next act on a boss clear, chaining the previous boss → the new act's entry.
## `run_state` (≥ available_brush_colors / highest_cleared) gates state-dependent event
## families: a family is eligible only if its prereq holds NOW (brush ⇒ colors non-empty).
## No-op once every act is generated; terminal_id is set when the FINAL act appends. §3.6.
func generate_next_act(run_state: Dictionary) -> void:
	if _generated_acts >= acts:
		return
	_build_act(_generated_acts, run_state)
	_validate()


# ── Generation (per-act, incremental — §2 / §3 / §3.6) ──────────────────────

## Build one act's subgraph and fold it onto the accumulating graph: entry chokepoint
## → branch segments (each two parallel L-node runs that reconverge at a chokepoint) →
## pre-boss chokepoint → boss. Then slot specials onto the branch runs (consulting
## run_state) and assign leg params to the new nodes. Chains the previous act's boss
## into this act's entry; advances the running depth/frontier across calls.
func _build_act(act: int, run_state: Dictionary) -> void:
	# Step 1 — act entry: a single shared funnel node (act 0's is the global start).
	var entry: MapNode = _new_node(MapNode.Type.LEG, _next_depth, 0, act)
	if act == 0:
		start_id = entry.id
	else:
		_connect(_prev_boss_id, entry.id)
	_next_depth += 1

	# Step 2 — branch segments. Each is two parallel runs of L nodes (lanes 0/1) that
	# fan out of the preceding chokepoint and reconverge into a single shared chokepoint.
	# The last segment's reconvergence chokepoint IS the pre-boss chokepoint (§3 step 2/3).
	var num_segments: int = maxi(_rng.randi_range(_cfg.branch_segments_min, _cfg.branch_segments_max), 1)
	var segments: Array = []        # each: { "run0": Array[int], "run1": Array[int] }
	var prev_chokepoint: int = entry.id
	for s: int in range(num_segments):
		var run_len: int = maxi(_rng.randi_range(_cfg.branch_len_min, _cfg.branch_len_max), 1)
		var run0: Array[int] = []
		var run1: Array[int] = []
		for i: int in range(run_len):
			run0.append(_new_node(MapNode.Type.LEG, _next_depth + i, 0, act).id)
			run1.append(_new_node(MapNode.Type.LEG, _next_depth + i, 1, act).id)
		# Wire: the preceding chokepoint fans into the first node of BOTH runs.
		_connect(prev_chokepoint, run0[0])
		_connect(prev_chokepoint, run1[0])
		# Wire each run depth→depth+1 (a run is consecutive depths at one lane).
		for i: int in range(run_len - 1):
			_connect(run0[i], run0[i + 1])
			_connect(run1[i], run1[i + 1])
		_next_depth += run_len
		# Reconvergence chokepoint — both runs' last nodes funnel into a single shared LEG.
		# For the final segment this same node serves as the pre-boss chokepoint (§3 step 3).
		var chokepoint: MapNode = _new_node(MapNode.Type.LEG, _next_depth, 0, act)
		_connect(run0[run_len - 1], chokepoint.id)
		_connect(run1[run_len - 1], chokepoint.id)
		_next_depth += 1
		segments.append({"run0": run0, "run1": run1})
		prev_chokepoint = chokepoint.id

	# Step 3 — terminal boss for this act: the pre-boss chokepoint funnels into it.
	var boss: MapNode = _new_node(MapNode.Type.BOSS, _next_depth, 0, act)
	_connect(prev_chokepoint, boss.id)
	_next_depth += 1
	_prev_boss_id = boss.id
	# terminal_id is set ONLY when the final act generates (reaching it == run victory).
	if act == acts - 1:
		terminal_id = boss.id

	# Step 4 — distribute specials across this act's branch runs (never chokepoints),
	# meeting the per-traversal budget and rolling state-gated event families.
	_slot_specials(act, segments, run_state)

	# Step 5 — assign leg params to the new act's nodes off the slice-2 pressure curve
	# (the helper skips already-assigned earlier-act nodes, so visited legs never re-roll).
	_assign_leg_params(_level, _cfg, _rng, _starting_target, _target_increment)

	_generated_acts = act + 1


## Distribute SHOP / EVENT / CHALLENGE across an act's branch-run nodes only, meeting the
## §1.2 per-traversal budget. CHALLENGE only when act ≥ 1 (post-boss-1 gate). For each
## type a per-traversal target is rolled in [type_min, type_max] and hosted in that many
## DISTINCT segments — one occurrence per placed run — so the worst-case path (one run per
## segment) collects at most `target` ≤ type_max. Each hosting segment places the type in
## ONE run (high branch_contrast → the two branches differ in content, a real composition
## choice) or BOTH runs (low contrast → either branch collects it). §3.
func _slot_specials(act: int, segments: Array, run_state: Dictionary) -> void:
	if segments.is_empty():
		return
	var specs: Array[Dictionary] = [
		{"type": MapNode.Type.SHOP, "lo": _cfg.shops_per_path_min, "hi": _cfg.shops_per_path_max},
		{"type": MapNode.Type.EVENT, "lo": _cfg.events_per_path_min, "hi": _cfg.events_per_path_max},
	]
	# Challenges are post-boss-1 only (§1.5 / 02 §1.1) — act 0 never hosts one.
	if act >= 1:
		specs.append({"type": MapNode.Type.CHALLENGE, "lo": _cfg.challenges_per_path_min, "hi": _cfg.challenges_per_path_max})

	for spec: Dictionary in specs:
		var target: int = _rng.randi_range(maxi(spec["lo"], 0), maxi(spec["hi"], 0))
		var host_count: int = mini(target, segments.size())
		if host_count <= 0:
			continue
		var order: Array[int] = _shuffled_indices(segments.size())
		for k: int in range(host_count):
			var seg: Dictionary = segments[order[k]]
			if _rng.randf() < _cfg.branch_contrast:
				# Content contrast: place into ONE run only so the branches differ.
				var pick_run: Array[int] = seg["run0"] if _rng.randi_range(0, 1) == 0 else seg["run1"]
				_place_special_in_run(pick_run, spec["type"], run_state)
			else:
				# No contrast: both runs host it, so either branch pick collects it.
				_place_special_in_run(seg["run0"], spec["type"], run_state)
				_place_special_in_run(seg["run1"], spec["type"], run_state)


## Fisher–Yates over [0, n) using the SEEDED generator. Array.shuffle() draws from the
## global RNG and would break seed reproducibility, so it is never used in generation.
func _shuffled_indices(n: int) -> Array[int]:
	var a: Array[int] = []
	for i: int in range(n):
		a.append(i)
	for i: int in range(n - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


## Convert one eligible LEG node in `run_ids` to `type`, honouring special_min_gap (no
## two of the SAME type within that many indices in the run) and never overwriting a node
## that is already a special. Hangs the type's payload (challenge roll / event family) on
## the chosen node. Returns the chosen node, or null if no slot fits.
func _place_special_in_run(run_ids: Array[int], type: MapNode.Type, run_state: Dictionary) -> MapNode:
	var eligible: Array[int] = []
	for i: int in range(run_ids.size()):
		if (nodes[run_ids[i]] as MapNode).type != MapNode.Type.LEG:
			continue   # already a special — never stack two on one node
		var blocked: bool = false
		for j: int in range(run_ids.size()):
			if (nodes[run_ids[j]] as MapNode).type == type and absi(i - j) <= _cfg.special_min_gap:
				blocked = true
				break
		if not blocked:
			eligible.append(i)
	if eligible.is_empty():
		return null
	var idx: int = eligible[_rng.randi_range(0, eligible.size() - 1)]
	var node: MapNode = nodes[run_ids[idx]]
	node.type = type
	match type:
		MapNode.Type.CHALLENGE:
			node.challenge = _roll_challenge_node(_rng, _cfg)
		MapNode.Type.EVENT:
			node.event = _roll_event_node(run_state)
		_:
			pass
	return node


## Roll an EVENT node's trade-family against the live run-state (§3.6). accuracy is always
## eligible; brush only where the run currently owns brush colors (available_brush_colors
## non-empty). The 3 concrete options are rolled at arrival (events slice), so only the
## family — the routed map icon — is fixed here.
func _roll_event_node(run_state: Dictionary) -> EventNode:
	var e: EventNode = EventNode.new()
	var families: Array[StringName] = [&"accuracy"]
	var brush_colors: Variant = run_state.get("available_brush_colors", null)
	if brush_colors is Array and not (brush_colors as Array).is_empty():
		families.append(&"brush")
	e.reward_family = families[_rng.randi_range(0, families.size() - 1)]
	return e


## Roll a challenge node's STABLE knobs (the ones independent of runtime progress):
## darts_per_turn (shown before deposit), the offered reward family, and an optional
## recycled benched-boss handicap. The target + deposit band are deferred to arrival
## (compute_challenge_params), since they anchor on the live highest_cleared. §5/§7/§8.
func _roll_challenge_node(rng: RandomNumberGenerator, cfg: MapGenConfig) -> ChallengeNode:
	var c: ChallengeNode = ChallengeNode.new()
	# darts-per-turn ∈ [dpt_min, dpt_max], the bust-grain shown up front (§5).
	c.darts_per_turn = rng.randi_range(c.dpt_min, c.dpt_max)
	# Offer one high-impact FLAT board family (Scoring / Placement) — the typed pick the
	# player earns; rarity comes from finish-efficiency at win time (§6). Brush was dropped
	# here in the events slice (03 §1.2): brush is a *trade*, so it now lives on the free
	# event surface, not the earned challenge surface — challenge and event never share a
	# family, so there is no cross-surface rarity ceiling to enforce.
	var families: Array[ScoringEnums.Family] = [
		ScoringEnums.Family.SCORING,
		ScoringEnums.Family.PLACEMENT,
	]
	c.reward_family = families[rng.randi_range(0, families.size() - 1)]
	# Optionally handicap the race with a recycled benched-boss aim effect (§8); empty
	# = a clean precision race. The handicap raises darts-used, nudging rarity down a
	# band on its own (§6/§8 implicit balancing).
	# Only the pure AIM handicaps are used (they test precision, the §8 verb). two_darts
	# is excluded: it mutates darts_per_turn, which would clobber the rolled dpt the
	# player saw before wagering (§5) and is anyway redundant with a dpt=2 roll. Its code
	# stays benched. rotation / narrow_double don't touch the dart economy.
	if rng.randf() < cfg.challenge_handicap_chance:
		var handicaps: Array[StringName] = [&"rotation", &"narrow_double"]
		c.handicap_id = handicaps[rng.randi_range(0, handicaps.size() - 1)]
	return c


## Slot shops left-to-right honouring the min column gap, one rolled lane per shop
## column so the parallel lane stays a leg (the routing choice).
func _slot_shops(mid_columns: Array, rng: RandomNumberGenerator, cfg: MapGenConfig) -> void:
	if mid_columns.is_empty():
		return
	var count: int = mini(rng.randi_range(cfg.shops_per_act_min, cfg.shops_per_act_max), mid_columns.size())
	var placed: int = 0
	var last_shop_col: int = -1000
	for c: int in range(mid_columns.size()):
		if placed >= count:
			break
		if c - last_shop_col <= cfg.shop_min_col_gap:
			continue
		var col: Array = mid_columns[c]
		var lane: int = rng.randi_range(0, col.size() - 1)
		(nodes[col[lane]] as MapNode).type = MapNode.Type.SHOP
		last_shop_col = c
		placed += 1


# ── Step 4: the pressure-ratio generator (slice 2) ──────────────────────────

## Assign each node its (target_score, max_turns). The slice-1 ladder is kept as
## baseline_target(depth) — the value a reference_turns leg gets — and defined to
## be pressure 1.0. Each non-boss leg rolls its own turn count, then derives a
## target at flat pressure_baseline against that curve; turns = reference_turns
## reproduces slice 1 exactly (ships at parity). Bosses are unchanged tier
## checkpoints: act ceiling at reference_turns. See spec §2.
func _assign_leg_params(level: LevelDefinition, cfg: MapGenConfig, rng: RandomNumberGenerator, starting_target: int, target_increment: int) -> void:
	# Capture the pressure-math context so the public seam functions stay callable
	# after generation (Phase 02 reads the same curve — §6).
	_starting_target = starting_target
	_target_increment = target_increment
	_max_target = level.max_score_target if level != null else 501
	_reference_turns = maxi(cfg.reference_turns, 1)

	# Per-act depth span (interpolates floor→ceiling) + depth→act map. Depth is a
	# global running counter, so each depth belongs to exactly one act.
	_act_min_depth.clear()
	_act_max_depth.clear()
	_depth_act.clear()
	for id: int in nodes:
		var n: MapNode = nodes[id]
		_depth_act[n.depth] = n.act
		if not _act_min_depth.has(n.act) or n.depth < _act_min_depth[n.act]:
			_act_min_depth[n.act] = n.depth
		if not _act_max_depth.has(n.act) or n.depth > _act_max_depth[n.act]:
			_act_max_depth[n.act] = n.depth

	for id: int in nodes:
		var n: MapNode = nodes[id]
		# Incremental gen (§3.6): only assign nodes from the act being appended. An
		# already-assigned node carries a non-zero target (legs roll ≥ starting_target;
		# bosses get the act ceiling), so this skips every earlier act — a visited leg's
		# params never re-roll, and the depth-map rebuild above still spans all acts.
		if n.target_score != 0:
			continue
		# Bosses: fixed at the act ceiling, reference turns — tier checkpoints, not
		# rolled. baseline_target at the boss depth already equals the act ceiling.
		if n.type == MapNode.Type.BOSS:
			n.target_score = _act_ceiling(n.act, _max_target, _starting_target, _target_increment)
			n.max_turns = _reference_turns
			continue
		# Roll turns, derive the flat-pressure target, snap to X01 parity, clamp to
		# the act window so a high/low roll near an act edge can't over/undershoot.
		var turns: int = _roll_turns(rng, cfg)
		n.max_turns = turns
		var raw: float = cfg.pressure_baseline * float(turns) / float(_reference_turns) * float(baseline_target(n.depth))
		var snapped: int = _snap(raw, _starting_target, _target_increment)
		n.target_score = clampi(snapped, _act_floor(n.act), _act_ceiling(n.act, _max_target, _starting_target, _target_increment))


## Roll a whole turn count in [turns_min, turns_max]. turns_center_bias is the
## *fraction of legs pinned to reference_turns*; the rest roll uniform across the
## range. Bias 0 = fully uniform, bias 1 = always reference_turns. Whole by
## construction → no divisibility problem.
## (The old lerp-then-round was inert at the default: lerp(u, 5, 0.6) over [4,6]
## always landed in [4.6, 5.4], which all rounds to 5 — every leg reproduced slice
## 1. This discrete weighting makes the spread explicit and predictable.)
func _roll_turns(rng: RandomNumberGenerator, cfg: MapGenConfig) -> int:
	var lo: int = cfg.turns_min
	var hi: int = cfg.turns_max
	if hi <= lo:
		return maxi(lo, 1)
	var ref: int = clampi(cfg.reference_turns, lo, hi)
	var bias: float = clampf(cfg.turns_center_bias, 0.0, 1.0)
	if rng.randf() < bias:
		return ref
	return rng.randi_range(lo, hi)


# ── Step 4: the pressure seam (build now, consume in Phase 02 — §6) ──────────
# Public, reusable so the Phase 02 challenge nodes' turns↔rarity dial reads the
# *same* curve _assign_leg_params does — leg and challenge difficulty stay coherent.

## The slice-1 ladder target for a depth — the value a reference_turns leg gets,
## defined to be pressure 1.0. Interpolates the act floor→ceiling on the depth
## axis (frac = 1 at the boss depth → the act ceiling). Snapped to X01 parity.
func baseline_target(depth: int) -> int:
	var act: int = _depth_act.get(depth, 0)
	var ceil_t: int = _act_ceiling(act, _max_target, _starting_target, _target_increment)
	var floor_t: int = _act_floor(act)
	var lo: int = _act_min_depth.get(act, depth)
	var hi: int = _act_max_depth.get(act, depth)
	var frac: float = 0.0 if hi == lo else float(depth - lo) / float(hi - lo)
	return _snap(lerpf(float(floor_t), float(ceil_t), frac), _starting_target, _target_increment)


## The designer's model of reliable score-per-dart at this run-depth, read off the
## seeded ladder: baseline_target(depth) / (reference_turns × BASE_DARTS_PER_TURN).
func expected_per_dart(depth: int) -> float:
	return float(baseline_target(depth)) / float(_reference_turns * BASE_DARTS_PER_TURN)


## The pressure of a (target, turns) pair at a depth: target ÷ the expected total
## output across that turn budget. 1.0 == a nominal coin-flip leg. The exact
## formula Phase 02's banter dial reads.
func pressure_of(target: int, turns: int, depth: int) -> float:
	var epd: float = expected_per_dart(depth)
	if epd <= 0.0 or turns <= 0:
		return 0.0
	return float(target) / (float(turns) * float(BASE_DARTS_PER_TURN) * epd)


## Fill a challenge node's target_score + deposit band from the LIVE highest_cleared
## (the §3 anchor) and the node's own depth (the §4 derivation), using the same pressure
## seam the legs ride so leg and challenge difficulty stay coherent. Idempotent — safe to
## call again if highest_cleared changed. Phase 02 §3/§4. `rng` seeds the target roll
## inside the anchor window; pass a run-scoped generator (or a seeded one in tests).
func compute_challenge_params(node: MapNode, highest_cleared: int, rng: RandomNumberGenerator) -> void:
	var c: ChallengeNode = node.challenge
	if c == null:
		return
	# Anchor: roll a target in [highest_cleared - undercut, highest_cleared] — never above
	# a score they've actually eaten (§3). Snap to the leg lattice (checkout-safe; the
	# finer 251 lattice is deferred, §15), then clamp so snapping can't push it past the
	# ceiling (highest_cleared) or below the engine's starting target.
	var lo_t: int = maxi(highest_cleared - c.target_undercut, _starting_target)
	var hi_t: int = maxi(highest_cleared, lo_t)
	var raw: int = rng.randi_range(lo_t, hi_t)
	var snapped: int = _snap(float(raw), _starting_target, _target_increment)
	c.target_score = clampi(snapped, _starting_target, highest_cleared)

	# Deposit band from the tuned curve (§4): reliable_darts = how many darts an average
	# run needs to clear this target at THIS depth's build power (E rises with depth, so
	# an old number costs fewer darts now — "match concisely"). min = a lean precision
	# floor, max = a forgiving cushion. Both are raw-dart counts.
	var e: float = expected_per_dart(node.depth)
	var reliable: int = maxi(int(ceil(float(c.target_score) / maxf(e, 0.0001))), 1)
	# Lean end = reliable × lean_factor, but never below the bankable floor — and the
	# floor yields to the §4 contract min ≤ reliable when a cheap target makes reliable
	# itself smaller than the floor (a genuinely cheap challenge just has a small stake).
	var lean: int = maxi(int(round(float(reliable) * c.lean_factor)), c.min_deposit_floor)
	c.min_deposit = mini(lean, reliable)
	c.max_deposit = maxi(reliable + c.deposit_cushion, c.min_deposit)


## The act's legal target window [floor, ceiling] — what a rolled leg is clamped
## to. Public so Phase 02 challenges clamp to the same band the legs do.
func act_floor(act: int) -> int:
	return _act_floor(act)


func act_ceiling(act: int) -> int:
	return _act_ceiling(act, _max_target, _starting_target, _target_increment)


## The lowest legal target in an act (its floor) — act 0 starts at starting_target;
## later acts begin one increment above the previous act's ceiling.
func _act_floor(act: int) -> int:
	if act == 0:
		return _starting_target
	return _act_ceiling(act - 1, _max_target, _starting_target, _target_increment) + _target_increment


## Act ceiling = the area's highest required score, snapped to X01 parity. For a
## 1501 run (3 acts) this yields 501 / 1001 / 1501, matching today's boss tiers.
func _act_ceiling(act: int, max_target: int, starting_target: int, target_increment: int) -> int:
	var raw: float = float(max_target) * float(act + 1) / float(acts)
	return _snap(raw, starting_target, target_increment)


## Snap an arbitrary value to the nearest legal X01 target (starting_target + n·inc).
func _snap(value: float, starting_target: int, target_increment: int) -> int:
	var n: int = int(round((value - float(starting_target)) / float(target_increment)))
	if n < 0:
		n = 0
	return starting_target + n * target_increment


# ── Step 5: validation (fail loud on a bad roll) ────────────────────────────

## Validate the graph generated SO FAR (incremental gen calls this after each act, so it
## must tolerate a partial run). The frontier sink is the most-recently generated boss;
## terminal_id is only asserted once every act is built. Adds slice-3's load-bearing
## invariants: no specials on chokepoints, and every challenge sits beside a live parallel
## run (the Skip path). Fail loud in debug so a bad roll never ships a skip-less map. §5.
func _validate() -> void:
	assert(start_id != -1 and nodes.has(start_id), "Map has no start node")
	assert((nodes[start_id] as MapNode).prev_ids.is_empty(), "Start node must have no predecessors")
	# The current frontier sink is the latest boss; terminal_id matches it only when done.
	var sink_id: int = _prev_boss_id
	assert(sink_id != -1 and nodes.has(sink_id), "Map has no boss to anchor on")
	assert((nodes[sink_id] as MapNode).next_ids.is_empty(), "Frontier boss must have no successors")
	if _generated_acts >= acts:
		assert(terminal_id == sink_id, "Terminal boss must be the final act's boss once fully generated")

	# Every node reachable forward from start.
	var seen: Dictionary = {}
	var stack: Array[int] = [start_id]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		for nid: int in (nodes[id] as MapNode).next_ids:
			stack.append(nid)
	assert(seen.size() == nodes.size(), "Map has nodes unreachable from start")

	# Every node can reach the frontier boss (reverse walk via prev edges).
	var can_reach: Dictionary = {}
	var rstack: Array[int] = [sink_id]
	while not rstack.is_empty():
		var id: int = rstack.pop_back()
		if can_reach.has(id):
			continue
		can_reach[id] = true
		for pid: int in (nodes[id] as MapNode).prev_ids:
			rstack.append(pid)
	assert(can_reach.size() == nodes.size(), "Map has dead-end nodes that cannot reach the boss")

	# Exactly one sink overall — the frontier boss (an earlier boss now feeds the next entry).
	var sinks: int = 0
	for id: int in nodes:
		if (nodes[id] as MapNode).next_ids.is_empty():
			sinks += 1
	assert(sinks == 1, "Map must have exactly one sink (the frontier boss), found %d" % sinks)

	# Nodes-per-depth: a chokepoint (entry / reconvergence / pre-boss) is the SOLE node at
	# its depth; a branch-run node always has a sibling at the other lane (its parallel run).
	# This single fact identifies both "no specials on chokepoints" and the challenge Skip.
	var depth_count: Dictionary = {}
	for id: int in nodes:
		var d: int = (nodes[id] as MapNode).depth
		depth_count[d] = depth_count.get(d, 0) + 1

	var per_act: Dictionary = {}
	var boss_per_act: Dictionary = {}
	for id: int in nodes:
		var n: MapNode = nodes[id]
		per_act[n.act] = per_act.get(n.act, 0) + 1
		if n.type == MapNode.Type.BOSS:
			boss_per_act[n.act] = boss_per_act.get(n.act, 0) + 1
		# Specials (SHOP / EVENT / CHALLENGE) never sit on a chokepoint (no parallel run ⇒
		# no opt-out). A special must have a same-depth sibling (a live parallel run).
		if n.type == MapNode.Type.SHOP or n.type == MapNode.Type.EVENT or n.type == MapNode.Type.CHALLENGE:
			assert(depth_count[n.depth] > 1, "Special node %d sits on a chokepoint (no parallel run)" % n.id)
		# Challenge skip invariant (§1.5): post-boss-1 only, and its parallel run (the Skip
		# path) must always exist — guaranteed by the same-depth sibling above.
		if n.type == MapNode.Type.CHALLENGE:
			assert(n.act >= 1, "Challenge node placed pre-boss-1 (act %d)" % n.act)
			assert(depth_count[n.depth] > 1, "Challenge node %d has no parallel run (Skip impossible)" % n.id)
	# Raised per-act PLACED-node budget (two runs per segment make acts larger than slice 1).
	for a: int in per_act:
		assert(per_act[a] >= _cfg.act_node_budget_min and per_act[a] <= _cfg.act_node_budget_max,
			"Act %d placed-node count %d outside [%d,%d] budget" % [a, per_act[a], _cfg.act_node_budget_min, _cfg.act_node_budget_max])
	for a: int in boss_per_act:
		assert(boss_per_act[a] == 1, "Act %d does not have exactly one boss" % a)


# ── Traversal API (consumed by main.gd + MapView) ───────────────────────────

func get_node_by_id(id: int) -> MapNode:
	return nodes.get(id, null)


## The legal next picks from a node (its forward edges).
func reachable_from(id: int) -> Array[int]:
	var n: MapNode = get_node_by_id(id)
	if n == null:
		var empty: Array[int] = []
		return empty
	return n.next_ids.duplicate()


## Step onto a node: set it current, mark it visited, recompute reachability.
func advance_to(id: int) -> void:
	current_id = id
	var n: MapNode = get_node_by_id(id)
	if n != null:
		n.visited = true
	_refresh_reachable()


func _refresh_reachable() -> void:
	for id: int in nodes:
		(nodes[id] as MapNode).reachable = false
	var cur: MapNode = get_node_by_id(current_id)
	if cur != null:
		for nid: int in cur.next_ids:
			(nodes[nid] as MapNode).reachable = true


## The act-3 (final) boss — reaching it is the run victory condition.
func is_terminal(id: int) -> bool:
	return id == terminal_id


# ── Internals ───────────────────────────────────────────────────────────────

func _new_node(type: MapNode.Type, depth: int, lane: int, act: int) -> MapNode:
	var n: MapNode = MapNode.new()
	n.id = _next_id
	_next_id += 1
	n.type = type
	n.depth = depth
	n.lane = lane
	n.act = act
	nodes[n.id] = n
	return n


func _connect(from_id: int, to_id: int) -> void:
	var f: MapNode = nodes[from_id]
	var t: MapNode = nodes[to_id]
	if not f.next_ids.has(to_id):
		f.next_ids.append(to_id)
	if not t.prev_ids.has(from_id):
		t.prev_ids.append(from_id)
