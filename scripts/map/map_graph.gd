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


## Build a full run map for `level`, using the seeded `rng` for every roll so runs
## are reproducible. `starting_target` / `target_increment` mirror x01_game so the
## rolled targets land on the engine's X01 parity lattice (101, 201, …).
static func generate(level: LevelDefinition, rng: RandomNumberGenerator, starting_target: int = 101, target_increment: int = 100) -> MapGraph:
	var graph: MapGraph = MapGraph.new()
	var cfg: MapGenConfig = null
	if level != null and level.map_gen_config != null:
		cfg = level.map_gen_config
	else:
		cfg = MapGenConfig.new()
	graph.acts = maxi(level.boss_count if level != null else 1, 1)
	graph.lane_count = maxi(cfg.lane_count, 1)
	graph._build(cfg, rng)
	graph._assign_leg_params(level, cfg, rng, starting_target, target_increment)
	graph._validate()
	return graph


# ── Generation ────────────────────────────────────────────────────────────

func _build(cfg: MapGenConfig, rng: RandomNumberGenerator) -> void:
	var prev_boss_id: int = -1
	var depth: int = 0
	for act: int in range(acts):
		# Step 1 — act entry: a single shared funnel node (act 0's is the global start).
		var entry: MapNode = _new_node(MapNode.Type.LEG, depth, 0, act)
		if act == 0:
			start_id = entry.id
		else:
			_connect(prev_boss_id, entry.id)
		depth += 1

		# Step 1 — middle columns: lane_count parallel slots each.
		var mid_cols: int = rng.randi_range(cfg.mid_cols_min, cfg.mid_cols_max)
		var mid_columns: Array = []
		var prev_col: Array[int] = [entry.id]
		for c: int in range(mid_cols):
			var col: Array[int] = []
			for lane: int in range(lane_count):
				col.append(_new_node(MapNode.Type.LEG, depth, lane, act).id)
			# Step 2 — lane edges (entry fans into the whole first column).
			_wire_columns(prev_col, col)
			mid_columns.append(col)
			prev_col = col
			depth += 1

		# Step 1 — terminal boss: lanes reconverge into a single node (the pre-boss
		# funnel chokepoint is the boss itself this slice).
		var boss: MapNode = _new_node(MapNode.Type.BOSS, depth, 0, act)
		for nid: int in prev_col:
			_connect(nid, boss.id)
		depth += 1
		if act == acts - 1:
			terminal_id = boss.id
		prev_boss_id = boss.id

		# Step 2 — bridges (crossover lane-switches) and an optional in-lane fork.
		_add_bridges(mid_columns, rng)
		_add_fork(mid_columns, rng, cfg)

		# Step 3 — slot shops by count + spacing within this act's middle columns.
		_slot_shops(mid_columns, rng, cfg)


## Wire one column to the next. A single-node column (the act entry) fans into the
## whole next column; otherwise nodes connect by matching lane index.
func _wire_columns(prev_col: Array[int], col: Array[int]) -> void:
	if prev_col.size() == 1:
		for nid: int in col:
			_connect(prev_col[0], nid)
	else:
		var n: int = mini(prev_col.size(), col.size())
		for lane: int in range(n):
			_connect(prev_col[lane], col[lane])


## Add one crossover at a rolled interior boundary so a player can switch lanes by
## *playing* the crossover node (lane commitment stays meaningful). Lanes 0/1 only.
func _add_bridges(mid_columns: Array, rng: RandomNumberGenerator) -> void:
	if mid_columns.size() < 2 or lane_count < 2:
		return
	var c: int = rng.randi_range(0, mid_columns.size() - 2)
	var a: Array = mid_columns[c]
	var b: Array = mid_columns[c + 1]
	_connect(a[0], b[1])
	_connect(a[1], b[0])


## Inject one in-lane reconverging fork: an extra off-branch node sharing a lane
## node's predecessors and successors, so picking it forgoes the parallel leg but
## rejoins immediately. This is the reserved CHALLENGE/EVENT home (Phase 02/03).
func _add_fork(mid_columns: Array, rng: RandomNumberGenerator, cfg: MapGenConfig) -> void:
	if mid_columns.is_empty() or rng.randf() > cfg.fork_chance:
		return
	var c: int = rng.randi_range(0, mid_columns.size() - 1)
	var lane: int = rng.randi_range(0, lane_count - 1)
	var base: MapNode = nodes[mid_columns[c][lane]]
	if base.prev_ids.is_empty() or base.next_ids.is_empty():
		return
	var fork: MapNode = _new_node(MapNode.Type.LEG, base.depth, lane_count, base.act)
	fork.is_off_branch = true
	for p: int in base.prev_ids.duplicate():
		_connect(p, fork.id)
	for n: int in base.next_ids.duplicate():
		_connect(fork.id, n)
	# Phase 02: a POST-BOSS-1 off-branch fork becomes a challenge node (§1.1 — never
	# pre-boss-1, so a 501/1-act run gets none and the early-anchor case vanishes). The
	# parallel leg always remains, so Skip (§12) is structurally guaranteed. The target
	# and deposit band are computed later, at arrival, from the live highest_cleared.
	if base.act >= 1:
		fork.type = MapNode.Type.CHALLENGE
		fork.challenge = _roll_challenge_node(rng, cfg)


## Roll a challenge node's STABLE knobs (the ones independent of runtime progress):
## darts_per_turn (shown before deposit), the offered reward family, and an optional
## recycled benched-boss handicap. The target + deposit band are deferred to arrival
## (compute_challenge_params), since they anchor on the live highest_cleared. §5/§7/§8.
func _roll_challenge_node(rng: RandomNumberGenerator, cfg: MapGenConfig) -> ChallengeNode:
	var c: ChallengeNode = ChallengeNode.new()
	# darts-per-turn ∈ [dpt_min, dpt_max], the bust-grain shown up front (§5).
	c.darts_per_turn = rng.randi_range(c.dpt_min, c.dpt_max)
	# Offer one board-item family (Scoring / Placement / Brush) — the typed pick the
	# player earns; rarity comes from finish-efficiency at win time (§6).
	var families: Array[ScoringEnums.Family] = [
		ScoringEnums.Family.SCORING,
		ScoringEnums.Family.PLACEMENT,
		ScoringEnums.Family.BRUSH,
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

func _validate() -> void:
	assert(start_id != -1 and nodes.has(start_id), "Map has no start node")
	assert(terminal_id != -1 and nodes.has(terminal_id), "Map has no terminal boss")
	assert((nodes[start_id] as MapNode).prev_ids.is_empty(), "Start node must have no predecessors")
	assert((nodes[terminal_id] as MapNode).next_ids.is_empty(), "Terminal boss must have no successors")

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

	# Every node can reach the terminal boss (reverse walk via prev edges).
	var can_reach: Dictionary = {}
	var rstack: Array[int] = [terminal_id]
	while not rstack.is_empty():
		var id: int = rstack.pop_back()
		if can_reach.has(id):
			continue
		can_reach[id] = true
		for pid: int in (nodes[id] as MapNode).prev_ids:
			rstack.append(pid)
	assert(can_reach.size() == nodes.size(), "Map has dead-end nodes that cannot reach the boss")

	# Per-act node budget stays in the design's 7–12 band.
	var per_act: Dictionary = {}
	for id: int in nodes:
		var a: int = (nodes[id] as MapNode).act
		per_act[a] = per_act.get(a, 0) + 1
	for a: int in per_act:
		assert(per_act[a] >= 7 and per_act[a] <= 12, "Act %d node count %d outside 7–12 budget" % [a, per_act[a]])


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
