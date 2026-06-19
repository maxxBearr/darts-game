extends SceneTree
## Headless unit test for MapGraph (specs/map/01-substrate-slice3-impl.md §8, the slice-2
## pressure contract, and the 2026-06-06 round-2 topology: decoupled crossovers, typed
## crossovers, mini-branches, act-0 challenges). Generates maps for every shipped level
## across many seeds and asserts the structural invariants the generator promises. Run with:
##   godot --headless --script res://tests/test_map_graph.gd
## Exits non-zero on any failure.

const SEEDS_PER_LEVEL := 200
const PATH_SEEDS := 30          ## seeds used for the (heavier) full-path enumeration checks
const INCREMENT := 100          ## X01 target lattice step (mirrors _generate_full's 101/100)

var _failures: int = 0
var _checks: int = 0
var _max_legs_seen: int = 0   ## widest entry→boss leg count observed (informs path_leg_budget tuning)


func _init() -> void:
	var levels: Array[String] = [
		"res://resources/levels/level_501.tres",
		"res://resources/levels/level_1001.tres",
		"res://resources/levels/level_1501.tres",
	]
	for path: String in levels:
		var level: LevelDefinition = load(path)
		_test_level(level)
	_test_incremental_gen()
	_test_state_aware_family_roll()
	_test_reproducibility()
	# Leg lattice (2026-06-07, §6): monotone difficulty, frontier legality, spread, exhaustion.
	_test_lattice_monotone()
	_test_lattice_spread()
	_test_lattice_exhaustion()
	print("   widest entry→boss leg count observed: %d (path_leg_budget tuning signal)" % _max_legs_seen)
	print("\nMapGraph test: %d checks, %d failures across %d seeds/level." % [_checks, _failures, SEEDS_PER_LEVEL])
	quit(1 if _failures > 0 else 0)


# ── Helpers ──────────────────────────────────────────────────────────────────

## Generate the WHOLE run incrementally: generate() seeds act 0, then one
## generate_next_act per later act (slice 3 §3.6). `brush_colors` is the run-state's
## available_brush_colors handed to every appended act (empty ⇒ accuracy-only events).
func _generate_full(level: LevelDefinition, seed_value: int, brush_colors: Array = []) -> MapGraph:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var g: MapGraph = MapGraph.generate(level, rng, 101, INCREMENT)
	for a: int in range(1, maxi(level.boss_count, 1)):
		g.generate_next_act({"available_brush_colors": brush_colors, "highest_cleared": 101})
	return g


func _cfg_for(level: LevelDefinition) -> MapGenConfig:
	return level.map_gen_config if level.map_gen_config != null else MapGenConfig.new()


## Enumerate every start→terminal path (the DAG's branch choices). Returns an Array of
## paths, each an Array[int] of node ids. Round-2 topology: at each stretch boundary a path
## may STAY in lane or CROSS via the interchange, and within a stretch it may take a
## mini-branch detour or the straight run, so the path set fans out with crossovers + branches.
func _enumerate_paths(g: MapGraph) -> Array:
	var paths: Array = []
	var stack: Array = [[g.start_id]]
	while not stack.is_empty():
		var path: Array = stack.pop_back()
		var last: int = path[path.size() - 1]
		var nexts: Array[int] = g.get_node_by_id(last).next_ids
		if nexts.is_empty():
			paths.append(path)
		else:
			for nid: int in nexts:
				stack.append(path + [nid])
	return paths


## How many nodes share `depth` in the whole graph (the funnel/crossover sole-ness test).
func _depth_population(g: MapGraph, depth: int) -> int:
	var c: int = 0
	for id: int in g.nodes:
		if g.get_node_by_id(id).depth == depth:
			c += 1
	return c


# ── Per-level suite ───────────────────────────────────────────────────────────

func _test_level(level: LevelDefinition) -> void:
	print("— Level %s (max %d, %d acts/bosses)" % [level.display_name, level.max_score_target, level.boss_count])
	for seed_value: int in range(SEEDS_PER_LEVEL):
		# _generate_full asserts internally (each act runs _validate); a bad roll halts here.
		var g: MapGraph = _generate_full(level, seed_value)
		_assert_structure(level, g, seed_value)
	# Heavier per-path checks on a subset of seeds, plus cross-seed spread/existence signals.
	var crossover_count_dist: Dictionary = {}   ## act-0 crossover count -> seeds with it
	var total_branches_seen: int = 0
	var act0_challenges_seen: int = 0
	for seed_value: int in range(PATH_SEEDS):
		var g: MapGraph = _generate_full(level, seed_value)
		_assert_topology_invariants(level, g, seed_value)
		_assert_per_path_budget(level, g, seed_value)
		_assert_crossover_invariants(level, g, seed_value)
		_assert_branch_invariants(level, g, seed_value)
		_assert_path_leg_budget(level, g, seed_value)
		_assert_shop_spacing(level, g, seed_value)
		_assert_no_leg_droughts(level, g, seed_value)
		_assert_branches_diverge(level, g, seed_value)
		var c0: int = 0
		for id: int in g.nodes:
			var n: MapNode = g.get_node_by_id(id)
			if n.act == 0 and n.is_crossover:
				c0 += 1
			if n.act == 0 and n.type == MapNode.Type.CHALLENGE:
				act0_challenges_seen += 1
			if n.is_branch and n.prev_ids.size() == 1 and not g.get_node_by_id(n.prev_ids[0]).is_branch:
				total_branches_seen += 1   # count branch HEADS (one per detour)
		crossover_count_dist[c0] = crossover_count_dist.get(c0, 0) + 1
	# Round-2 spread/existence: the crossover count must not be pinned to one value, branches
	# must occur, and act-0 challenges (newly allowed) must appear across seeds.
	_check(crossover_count_dist.size() > 1, "act-0 crossover count spreads across seeds (not pinned)", -1)
	_check(total_branches_seen > 0, "mini-branches appear across seeds", -1)
	_check(act0_challenges_seen > 0, "act-0 challenges appear across seeds (round 2)", -1)
	# Leg lattice (2026-06-07): legs are no longer rolled at generation — they're drawn from the
	# per-act monotone frontier at arrival. The lattice mechanics are exercised by the dedicated
	# suite-level tests (_test_lattice_*); per-level here we only check the per-path leg cap above.
	_dump_example(level)


func _assert_structure(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	_check(g.acts == maxi(level.boss_count, 1), "acts==boss_count", seed_value)
	_check(g.start_id != -1 and g.terminal_id != -1, "start/terminal set (full run)", seed_value)

	# Reachability forward from start covers every node.
	var seen: Dictionary = {}
	var stack: Array[int] = [g.start_id]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		for nid: int in g.get_node_by_id(id).next_ids:
			stack.append(nid)
	_check(seen.size() == g.nodes.size(), "all nodes reachable from start", seed_value)

	# Terminal boss is the only sink; it carries the level's max target.
	var sinks: int = 0
	for id: int in g.nodes:
		if g.get_node_by_id(id).next_ids.is_empty():
			sinks += 1
	_check(sinks == 1, "exactly one terminal sink", seed_value)
	_check(g.get_node_by_id(g.terminal_id).target_score == level.max_score_target, "terminal target == max_score_target", seed_value)
	_check(g.get_node_by_id(g.terminal_id).type == MapNode.Type.BOSS, "terminal is a BOSS", seed_value)

	# Exactly one BOSS per act.
	var boss_per_act: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		if n.type == MapNode.Type.BOSS:
			boss_per_act[n.act] = boss_per_act.get(n.act, 0) + 1
	for a: int in range(g.acts):
		_check(boss_per_act.get(a, 0) == 1, "exactly one boss in act %d" % a, seed_value)

	# Leg lattice (2026-06-07): ordinary legs carry NO (target, turns) at generation — they are
	# drawn from the per-act frontier at arrival, so a leg node's target_score is 0 here. Only the
	# BOSS carries a fixed pair: the act ceiling at reference turns, sitting one increment ABOVE the
	# drawable lattice top (boss off-grid). Assert the boss pair; ordinary legs are left unassigned.
	var cfg: MapGenConfig = _cfg_for(level)
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		if n.type == MapNode.Type.BOSS:
			_check(n.target_score == g.act_ceiling(n.act), "boss target == act %d ceiling" % n.act, seed_value)
			_check(n.max_turns == cfg.reference_turns, "boss turns == reference_turns", seed_value)
		else:
			_check(n.target_score == 0, "ordinary leg unassigned at generation (drawn at arrival)", seed_value)

	# At least one shop exists per act on average (per-path budget guarantees ≥1/act).
	var shop_count: int = 0
	for id: int in g.nodes:
		if g.get_node_by_id(id).type == MapNode.Type.SHOP:
			shop_count += 1
	_check(shop_count >= g.acts, "at least one shop per act (>= acts total)", seed_value)


## Topology invariants (§5/§8, round 2): every special has a skip (same-depth sibling OR
## is_crossover); act-0 challenges respect the depth gate; ≤1 detour challenge per act; the
## per-act placed-node budget holds; EVENT families are eligible under the run-state.
func _assert_topology_invariants(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	var depth_count: Dictionary = {}
	var act_min_depth: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		depth_count[n.depth] = depth_count.get(n.depth, 0) + 1
		if not act_min_depth.has(n.act) or n.depth < act_min_depth[n.act]:
			act_min_depth[n.act] = n.depth

	var per_act: Dictionary = {}
	var detour_challenges_per_act: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		per_act[n.act] = per_act.get(n.act, 0) + 1
		var has_skip: bool = depth_count[n.depth] > 1 or n.is_crossover
		if n.type == MapNode.Type.SHOP or n.type == MapNode.Type.EVENT or n.type == MapNode.Type.CHALLENGE:
			_check(has_skip, "special (type %d) node %d has a skip (sibling or crossover)" % [n.type, n.id], seed_value)
		if n.type == MapNode.Type.CHALLENGE:
			if n.act == 0:
				_check(n.depth - int(act_min_depth[0]) >= cfg.challenge_act0_min_depth,
					"act-0 challenge %d respects depth gate (depth %d, entry %d, gate %d)" % [n.id, n.depth, int(act_min_depth[0]), cfg.challenge_act0_min_depth], seed_value)
			_check(has_skip, "challenge %d has a skip (Skip available)" % n.id, seed_value)
			_check(n.challenge != null, "challenge node carries a ChallengeNode resource", seed_value)
			if n.is_crossover or n.is_branch:
				detour_challenges_per_act[n.act] = detour_challenges_per_act.get(n.act, 0) + 1
		if n.type == MapNode.Type.EVENT:
			_check(n.event != null, "event node carries an EventNode resource", seed_value)
			# Event family is UNGATED at generation (typed-shop slice, Max 2026-06-07): accuracy,
			# brush, or geometry may roll regardless of run-state — only the routed map icon is
			# fixed here; brush affinity (and the colorless→accuracy downgrade) resolves at arrival.
			_check(n.event.reward_family == &"accuracy" or n.event.reward_family == &"brush" or n.event.reward_family == &"geometry",
				"event family is one of accuracy / brush / geometry", seed_value)
	for a: int in detour_challenges_per_act:
		_check(detour_challenges_per_act[a] <= 1, "act %d has ≤1 detour challenge (got %d)" % [a, detour_challenges_per_act[a]], seed_value)
	for a: int in per_act:
		_check(per_act[a] >= cfg.act_node_budget_min and per_act[a] <= cfg.act_node_budget_max,
			"act %d placed-node count %d in [%d,%d]" % [a, per_act[a], cfg.act_node_budget_min, cfg.act_node_budget_max], seed_value)


## Per-traversal budget (§1.2/§4/§8): enumerate full paths; each act's contribution of each
## special — counting LANE-RUN nodes only, crossover/branch content excluded (§4) — stays ≤
## its per-path max; ≥1 lane-run challenge appears on at least one branch in every act ≥ 1;
## traversed path length per act ≈ lane_len + 3 + crossovers taken.
func _assert_per_path_budget(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	var paths: Array = _enumerate_paths(g)
	_check(paths.size() > 0, "at least one start→boss path exists", seed_value)
	# Traversed length: entry + boss + pre-boss = 3, plus lane_len lane nodes (branches swap
	# equal-length spans), plus 0 … crossovers_max interchanges taken.
	var trav_min: int = cfg.lane_len_min + 3
	var trav_max: int = cfg.lane_len_max + cfg.crossovers_max + 3
	var act_max_challenges: Dictionary = {}   ## act -> max lane-run challenges any single branch collects
	for path: Array in paths:
		var per_act_count: Dictionary = {}   ## act -> {type -> count} (lane-run nodes only)
		var per_act_len: Dictionary = {}     ## act -> total nodes on path (incl detours)
		for id: int in path:
			var n: MapNode = g.get_node_by_id(id)
			per_act_len[n.act] = per_act_len.get(n.act, 0) + 1
			if n.is_crossover or n.is_branch or n.is_offbudget:
				continue   # §4: detour content + §8 drought/divergence spice are off the per-path budget
			if not per_act_count.has(n.act):
				per_act_count[n.act] = {}
			var tc: Dictionary = per_act_count[n.act]
			tc[n.type] = tc.get(n.type, 0) + 1
		for a: int in per_act_count:
			var tc: Dictionary = per_act_count[a]
			var shops: int = tc.get(MapNode.Type.SHOP, 0)
			var events: int = tc.get(MapNode.Type.EVENT, 0)
			var challenges: int = tc.get(MapNode.Type.CHALLENGE, 0)
			var chal_max: int = cfg.challenges_act0_per_path_max if a == 0 else cfg.challenges_per_path_max
			_check(shops <= cfg.shops_per_path_max, "path collects ≤ %d shops in act %d (got %d)" % [cfg.shops_per_path_max, a, shops], seed_value)
			_check(events <= cfg.events_per_path_max, "path collects ≤ %d events in act %d (got %d)" % [cfg.events_per_path_max, a, events], seed_value)
			_check(challenges <= chal_max, "path collects ≤ %d lane-run challenges in act %d (got %d)" % [chal_max, a, challenges], seed_value)
			act_max_challenges[a] = maxi(act_max_challenges.get(a, 0), challenges)
		for a: int in per_act_len:
			_check(per_act_len[a] >= trav_min and per_act_len[a] <= trav_max,
				"act %d traversed length %d in [%d,%d]" % [a, per_act_len[a], trav_min, trav_max], seed_value)
	# Every act ≥ 1 offers a lane-run challenge on at least one branch (challenges_per_path_min ≥ 1).
	for a: int in range(1, g.acts):
		_check(act_max_challenges.get(a, 0) >= 1, "act %d offers ≥1 lane-run challenge on at least one branch" % a, seed_value)


## Crossover invariants (round 2): every is_crossover node is sole at its depth, fed by BOTH
## lane-ends and exits to BOTH next runs, with the lanes also continuing straight past it
## (the stay edges); the per-act count sits in [crossovers_min, crossovers_max]; and the
## feature is not inert — both crossing and staying paths exist.
func _assert_crossover_invariants(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	var crossover_ids: Dictionary = {}
	var crossovers_per_act: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		if not n.is_crossover:
			continue
		crossover_ids[n.id] = true
		crossovers_per_act[n.act] = crossovers_per_act.get(n.act, 0) + 1
		_check(_depth_population(g, n.depth) == 1, "crossover %d is sole at its depth (centred)" % n.id, seed_value)
		_check(n.next_ids.size() == 2, "crossover %d exits to 2 nodes" % n.id, seed_value)
		_check(n.prev_ids.size() == 2, "crossover %d fed by 2 nodes" % n.id, seed_value)
		var in_lanes: Dictionary = {}
		var out_lanes: Dictionary = {}
		for pid: int in n.prev_ids:
			in_lanes[g.get_node_by_id(pid).lane] = true
		for nid: int in n.next_ids:
			out_lanes[g.get_node_by_id(nid).lane] = true
		_check(in_lanes.has(0) and in_lanes.has(1), "crossover %d fed by BOTH lanes" % n.id, seed_value)
		_check(out_lanes.has(0) and out_lanes.has(1), "crossover %d exits to BOTH lanes" % n.id, seed_value)
		# Stay edges: each feeder also continues straight into its own lane's next run.
		for pid: int in n.prev_ids:
			var p: MapNode = g.get_node_by_id(pid)
			var stays: bool = false
			for nnid: int in p.next_ids:
				if nnid != n.id and g.get_node_by_id(nnid).lane == p.lane:
					stays = true
			_check(stays, "lane-end %d keeps a straight stay edge past crossover %d" % [pid, n.id], seed_value)
	# Per-act count in [crossovers_min, crossovers_max] (clamp can't bite at default lane_len).
	for a: int in range(g.acts):
		var got: int = crossovers_per_act.get(a, 0)
		_check(got >= cfg.crossovers_min and got <= cfg.crossovers_max,
			"act %d crossover count %d in [%d,%d]" % [a, got, cfg.crossovers_min, cfg.crossovers_max], seed_value)
	# Not-inert: with ≥1 crossover, the path set holds BOTH a crossing path and a stay path.
	if cfg.crossovers_min >= 1:
		var any_cross: bool = false
		var any_stay: bool = false
		for path: Array in _enumerate_paths(g):
			var crossed: bool = false
			for id: int in path:
				if crossover_ids.has(id):
					crossed = true
			if crossed:
				any_cross = true
			else:
				any_stay = true
		_check(any_cross, "some path crosses lanes via an interchange", seed_value)
		_check(any_stay, "some path stays in-lane the whole run", seed_value)


## Mini-branch invariants (round 2): every detour forks off a lane node, runs on the correct
## OUTER row, rejoins THE SAME lane within ONE stretch (a straight stay path of equal length
## exists), and — when any branch is present — both a path that takes a branch and one that
## skips every branch exist. Branches may not fit a given seed (clamped/skipped), so this
## validates the ones found; cross-seed existence is asserted in _test_level.
func _assert_branch_invariants(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var branch_count: int = 0
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		if not n.is_branch:
			continue
		_check(n.prev_ids.size() == 1, "branch node %d has exactly one predecessor" % n.id, seed_value)
		if n.prev_ids.size() != 1:
			continue
		var fork: MapNode = g.get_node_by_id(n.prev_ids[0])
		if fork.is_branch:
			continue   # interior chain node — validate the chain from its head only
		branch_count += 1
		var chain_lane: int = n.lane
		# Walk to the tail of the chain.
		var cur: MapNode = n
		while cur.next_ids.size() == 1 and g.get_node_by_id(cur.next_ids[0]).is_branch:
			cur = g.get_node_by_id(cur.next_ids[0])
			_check(cur.lane == chain_lane, "branch chain stays on one outer row", seed_value)
		_check(cur.next_ids.size() == 1, "branch tail %d has one successor (the rejoin)" % cur.id, seed_value)
		var rejoin: MapNode = g.get_node_by_id(cur.next_ids[0])
		_check(not rejoin.is_branch, "branch tail rejoins a non-branch lane node", seed_value)
		_check(fork.lane == rejoin.lane, "branch forks and rejoins the SAME lane (%d→%d)" % [fork.lane, rejoin.lane], seed_value)
		var expected_outer: int = -1 if fork.lane == 0 else 2
		_check(chain_lane == expected_outer, "branch off lane %d uses outer row %d (got %d)" % [fork.lane, expected_outer, chain_lane], seed_value)
		_check(_straight_lane_reaches(g, fork, rejoin), "branch %d→%d has a same-stretch straight stay path" % [fork.id, rejoin.id], seed_value)
	# Optionality: if any branch exists, the path set holds both a detour-taking and a
	# branch-free path (the straight stay path guarantees the latter).
	if branch_count > 0:
		var any_with: bool = false
		var any_without: bool = false
		for path: Array in _enumerate_paths(g):
			var has_branch: bool = false
			for id: int in path:
				if g.get_node_by_id(id).is_branch:
					has_branch = true
			if has_branch:
				any_with = true
			else:
				any_without = true
		_check(any_with, "some path takes a mini-branch detour", seed_value)
		_check(any_without, "some path skips every mini-branch (straight)", seed_value)


## True if the straight main-lane chain from `fork` reaches `rejoin` without stepping onto a
## branch or a crossover — confirms the detour stays inside one stretch (the stay edges exist).
func _straight_lane_reaches(g: MapGraph, fork: MapNode, rejoin: MapNode) -> bool:
	var walker: MapNode = fork
	var guard: int = 0
	while guard < 64:
		if walker.id == rejoin.id:
			return true
		var nxt: int = -1
		for nid: int in walker.next_ids:
			var c: MapNode = g.get_node_by_id(nid)
			if not c.is_branch and not c.is_crossover and c.lane == fork.lane:
				nxt = nid
				break
		if nxt == -1:
			return false
		walker = g.get_node_by_id(nxt)
		guard += 1
	return false


# ── Leg lattice (§6) — draw-from-frontier, monotone cull, exhaustion fallback ──

## Act-wide shop spacing (typed-shop spec §8, Max 2026-06-08): no two SHOP nodes sit within
## shop_min_graph_gap UNDIRECTED edges of each other — across lane/crossover/branch placement and
## across stretch boundaries. Recomputed independently here (BFS over next+prev) to validate the
## generator's _shop_within guard rather than trust it.
func _assert_shop_spacing(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var gap: int = _cfg_for(level).shop_min_graph_gap
	if gap <= 0:
		return
	for sid: int in g.nodes:
		if g.get_node_by_id(sid).type != MapNode.Type.SHOP:
			continue
		# BFS up to `gap` hops over undirected edges; no OTHER shop may appear in that ball.
		var seen: Dictionary = {sid: true}
		var frontier: Array[int] = [sid]
		for _step: int in range(gap):
			var nxt: Array[int] = []
			for id: int in frontier:
				var n: MapNode = g.get_node_by_id(id)
				for nb: int in n.next_ids + n.prev_ids:
					if seen.has(nb):
						continue
					seen[nb] = true
					if g.get_node_by_id(nb).type == MapNode.Type.SHOP:
						_check(false, "shop %d within %d hops of shop %d (act-wide spacing §8)" % [nb, gap, sid], seed_value)
					nxt.append(nb)
			frontier = nxt


## Drought breaker (spec §8 follow-up, Max 2026-06-08; mandatory-path fix 2026-06-15): no MANDATORY
## traversal may hold more than max_consecutive_legs plain LEGs in a row. The swept lane sequence now
## includes the act-entry funnel and pre-boss chokepoint legs (every traversal is forced through
## them); crossovers stay excluded (optional detours). Branch chains are swept separately. Sweeps
## each sequence for the longest leg run, PLUS a targeted check for the original bug: a legal run of
## `cap` lane legs landing on the always-present pre-boss leg = cap+1 legs into the boss.
func _assert_no_leg_droughts(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cap: int = _cfg_for(level).max_consecutive_legs
	if cap <= 0:
		return
	var depth_count: Dictionary = {}
	for id: int in g.nodes:
		var d: int = g.get_node_by_id(id).depth
		depth_count[d] = depth_count.get(d, 0) + 1
	var seqs: Array = _lane_and_branch_sequences(g, depth_count)
	for seq: Array in seqs:
		var streak: int = 0
		for id: int in seq:
			if g.get_node_by_id(id).type == MapNode.Type.LEG:
				streak += 1
				_check(streak <= cap, "lane/branch plain-leg run ≤ max_consecutive_legs %d (got %d)" % [cap, streak], seed_value)
			else:
				streak = 0
	# Targeted regression for the traced bug (run-of-cap straight into the act boss): the mandatory
	# lane sequences end at the pre-boss chokepoint leg, so a trailing run of > cap LEGs is exactly
	# the "3 lane legs + pre-boss = 4 into the boss" case the old breaker missed (it excluded the
	# sole pre-boss leg). Count each sequence's trailing contiguous legs and assert ≤ cap.
	for seq: Array in seqs:
		var tail: int = 0
		for i: int in range(seq.size() - 1, -1, -1):
			if g.get_node_by_id(seq[i]).type == MapNode.Type.LEG:
				tail += 1
			else:
				break
		_check(tail <= cap, "drought into chokepoint: %d trailing legs > cap %d (run-of-cap + pre-boss bug)" % [tail, cap], seed_value)


## Reconstruct, per act, each lane's MANDATORY straight run and each mini-branch chain. Mirrors what
## _break_leg_droughts sweeps (mandatory-path fix 2026-06-15): the lane sequence now BOOKENDS the
## lane-run nodes with the two mandatory chokepoint legs — the act-entry funnel (head) and the
## pre-boss chokepoint (tail) — because every traversal is forced through them, so they count toward
## the cap. Crossover legs stay excluded (sole at depth, optional detours — the depth_count>1 filter
## drops them and we never re-add them). Branch chains carry NO chokepoints (a branch bypasses them).
## Returns an Array of Array[int] (depth-ordered node-id sequences).
func _lane_and_branch_sequences(g: MapGraph, depth_count: Dictionary) -> Array:
	var out: Array = []
	for a: int in range(g.acts):
		# Locate this act's mandatory chokepoints: the entry funnel = the act's lowest-depth node
		# (sole, created first); the pre-boss chokepoint = the sole LEG feeding the boss.
		var entry_id: int = -1
		var entry_depth: int = 1 << 30
		var pre_boss_id: int = -1
		for id: int in g.nodes:
			var n: MapNode = g.get_node_by_id(id)
			if n.act != a:
				continue
			if n.type == MapNode.Type.BOSS and n.prev_ids.size() > 0:
				pre_boss_id = n.prev_ids[0]
			if n.depth < entry_depth:
				entry_depth = n.depth
				entry_id = id
		for lane: int in [0, 1]:
			var run: Array[int] = []
			for id: int in g.nodes:
				var n: MapNode = g.get_node_by_id(id)
				if n.act == a and n.lane == lane and not n.is_branch and int(depth_count.get(n.depth, 0)) > 1:
					run.append(id)
			_sort_ids_by_depth(g, run)
			# Bookend with the mandatory chokepoints: [entry] + lane run + [pre_boss].
			var seq: Array[int] = []
			if entry_id != -1:
				seq.append(entry_id)
			seq.append_array(run)
			if pre_boss_id != -1:
				seq.append(pre_boss_id)
			if not seq.is_empty():
				out.append(seq)
		for blane: int in [-1, 2]:
			var br: Array[int] = []
			for id: int in g.nodes:
				var n: MapNode = g.get_node_by_id(id)
				if n.act == a and n.lane == blane and n.is_branch:
					br.append(id)
			_sort_ids_by_depth(g, br)
			if not br.is_empty():
				out.append(br)
	return out


func _sort_ids_by_depth(g: MapGraph, ids: Array[int]) -> void:
	ids.sort_custom(func(x: int, y: int) -> bool: return g.get_node_by_id(x).depth < g.get_node_by_id(y).depth)


## Branch divergence guard (spec §8 follow-up, Max 2026-06-08): every mini-branch's type MULTISET
## must differ from the parallel lane segment it bypasses (composition, not order — a fake choice
## is the SAME reward set either way). Reconstructs each branch chain (head→tail), its fork/rejoin
## on the parent lane, and the parent-lane span strictly between them, and asserts the multisets differ.
func _assert_branches_diverge(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	for id: int in g.nodes:
		var head: MapNode = g.get_node_by_id(id)
		if not head.is_branch or head.prev_ids.size() != 1:
			continue
		var fork: MapNode = g.get_node_by_id(head.prev_ids[0])
		if fork.is_branch:
			continue   # interior chain node — only walk from the head (fork is a real lane node)
		# Walk the branch chain head→tail.
		var chain: Array[int] = [head.id]
		var cur: MapNode = head
		while cur.next_ids.size() == 1 and g.get_node_by_id(cur.next_ids[0]).is_branch:
			cur = g.get_node_by_id(cur.next_ids[0])
			chain.append(cur.id)
		if cur.next_ids.size() != 1:
			continue
		var rejoin: MapNode = g.get_node_by_id(cur.next_ids[0])
		# Parallel = parent-lane run nodes strictly between fork and rejoin (the bypassed span).
		var parallel: Array[int] = []
		for pid: int in g.nodes:
			var pn: MapNode = g.get_node_by_id(pid)
			if pn.lane == fork.lane and not pn.is_branch and not pn.is_crossover and pn.depth > fork.depth and pn.depth < rejoin.depth:
				parallel.append(pid)
		_check(not _same_type_multiset(g, chain, parallel),
			"mini-branch (fork %d) type multiset differs from its bypassed lane span" % fork.id, seed_value)


## True when two node-id lists carry the same MULTISET of node types (order ignored).
func _same_type_multiset(g: MapGraph, a_ids: Array[int], b_ids: Array[int]) -> bool:
	var counts: Dictionary = {}
	for id: int in a_ids:
		var t: int = int(g.get_node_by_id(id).type)
		counts[t] = int(counts.get(t, 0)) + 1
	for id: int in b_ids:
		var t: int = int(g.get_node_by_id(id).type)
		counts[t] = int(counts.get(t, 0)) - 1
	for t: int in counts:
		if int(counts[t]) != 0:
			return false
	return true


## Per-path leg cap (§4): an "entry→boss route" is ONE act, so cap LEG-type nodes PER ACT along a
## path (not the whole multi-act run). SOFT pacing target — checked over the seed grid (the cull
## rule already bounds the meaningful legs; this just keeps the node count from sprawling).
func _assert_path_leg_budget(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	for path: Array in _enumerate_paths(g):
		var per_act: Dictionary = {}
		for id: int in path:
			var n: MapNode = g.get_node_by_id(id)
			if n.type == MapNode.Type.LEG:
				per_act[n.act] = per_act.get(n.act, 0) + 1
		for a: int in per_act:
			_max_legs_seen = maxi(_max_legs_seen, int(per_act[a]))
			_check(int(per_act[a]) <= cfg.path_leg_budget,
				"act %d path leg count %d <= path_leg_budget %d" % [a, int(per_act[a]), cfg.path_leg_budget], seed_value)


## Walk a start→boss PATH the way main.gd does: the act-0 entry is the fixed 101/5 opener
## (auto-cleared at run start), then each ordinary LEG node DRAWS its pair from the live frontier
## and clears it (raising the cull threshold). Returns per-act ordered records
## { act -> {"draws": Array[Vector2i], "pressures": Array[float], "legal": bool} }. legal=false if
## a drawn cell was NOT in the live frontier at draw time while the frontier was non-empty (a
## fallback repeat on an empty frontier is allowed). Mutates the graph's lattice — fresh g per call.
func _walk_lattice(g: MapGraph, path: Array) -> Dictionary:
	var per_act: Dictionary = {}
	for id: int in path:
		var n: MapNode = g.get_node_by_id(id)
		if n.id == g.start_id:
			g.record_leg_cleared(101, 5)   # the fixed calibration opener (cumulative leg 1)
			continue
		if n.type != MapNode.Type.LEG:
			continue   # specials / boss play no lattice leg
		var act: int = n.act
		if not per_act.has(act):
			per_act[act] = {"draws": [], "pressures": [], "legal": true}
		var frontier: Array[Dictionary] = g.get_frontier(act)
		g.draw_leg_from_frontier(n)
		var pair: Vector2i = Vector2i(n.target_score, n.max_turns)
		if not frontier.is_empty():
			var found: bool = false
			for f: Dictionary in frontier:
				if int(f["score"]) == pair.x and int(f["turns"]) == pair.y:
					found = true
					break
			if not found:
				per_act[act]["legal"] = false
		(per_act[act]["draws"] as Array).append(pair)
		(per_act[act]["pressures"] as Array).append(float(pair.x) / float(pair.y * 3))
		g.record_leg_cleared(pair.x, pair.y)
	return per_act


## §6: cleared pressures are monotone nondecreasing (the "easier leftover" leak is closed), every
## drawn leg was in the live frontier (frontier legality), and 101/4 — culled the instant any
## harder cell clears — can only ever be the FIRST drawn leg (cumulative leg 2).
func _test_lattice_monotone() -> void:
	print("— Leg lattice: monotone cleared pressure + frontier legality + 101/4-as-leg-2")
	var level: LevelDefinition = load("res://resources/levels/level_501.tres")
	var saw_101_4: int = 0
	for seed_value: int in range(SEEDS_PER_LEVEL):
		var g: MapGraph = _generate_full(level, seed_value)
		var paths: Array = _enumerate_paths(g)
		var path: Array = paths[seed_value % paths.size()]
		var per_act: Dictionary = _walk_lattice(g, path)
		for act: int in per_act:
			var rec: Dictionary = per_act[act]
			_check(rec["legal"], "every drawn leg was in the live frontier (act %d)" % act, seed_value)
			var pressures: Array = rec["pressures"]
			for i: int in range(1, pressures.size()):
				_check(float(pressures[i]) >= float(pressures[i - 1]) - 0.0001,
					"cleared pressures nondecreasing (act %d: %.2f then %.2f)" % [act, float(pressures[i - 1]), float(pressures[i])], seed_value)
			if act == 0:
				var draws: Array = rec["draws"]
				for j: int in range(draws.size()):
					if (draws[j] as Vector2i) == Vector2i(101, 4):
						_check(j == 0, "101/4 only appears as the first drawn leg (cumulative leg 2)", seed_value)
						saw_101_4 += 1
	_check(saw_101_4 > 0, "101/4 actually appears across seeds (not inert)", -1)


## §6 spread (the rolled-generator-spread lesson): the first drawn leg opens to BOTH "tighten"
## (101/4) and "climb" (201/6) across seeds, and walks visit DIFFERENT cell sequences — not one
## canonical walk.
func _test_lattice_spread() -> void:
	print("— Leg lattice: first-pick spread (tighten vs climb) + sequence variety")
	var level: LevelDefinition = load("res://resources/levels/level_501.tres")
	var first_tighten: int = 0   # 101/4
	var first_climb: int = 0     # 201/6
	var distinct_seqs: Dictionary = {}
	for seed_value: int in range(SEEDS_PER_LEVEL):
		var g: MapGraph = _generate_full(level, seed_value)
		var paths: Array = _enumerate_paths(g)
		var path: Array = paths[seed_value % paths.size()]
		var per_act: Dictionary = _walk_lattice(g, path)
		if per_act.has(0) and (per_act[0]["draws"] as Array).size() > 0:
			var draws: Array = per_act[0]["draws"]
			var first: Vector2i = draws[0]
			if first == Vector2i(101, 4):
				first_tighten += 1
			elif first == Vector2i(201, 6):
				first_climb += 1
			distinct_seqs[str(draws)] = true
	_check(first_tighten > 0, "some seeds open by tightening (101/4 first)", -1)
	_check(first_climb > 0, "some seeds open by climbing (201/6 first)", -1)
	_check(distinct_seqs.size() > 1, "walks visit different cell sequences (not one canonical walk)", -1)
	print("   first pick: tighten(101/4)=%d climb(201/6)=%d, distinct act-0 sequences=%d" % [first_tighten, first_climb, distinct_seqs.size()])


## §6 exhaustion: after the lattice empties (fast climb + long path), the next draw repeats the
## hardest CLEARED pair — never an easier one.
func _test_lattice_exhaustion() -> void:
	print("— Leg lattice: exhaustion fallback repeats the hardest cleared pair")
	var level: LevelDefinition = load("res://resources/levels/level_501.tres")
	for seed_value: int in range(20):
		var g: MapGraph = _generate_full(level, seed_value)
		g.record_leg_cleared(101, 5)   # opener
		var hardest: Vector2i = Vector2i(101, 5)
		var guard: int = 0
		while not g.get_frontier(0).is_empty() and guard < 50:
			var d: MapNode = MapNode.new()
			d.act = 0
			d.type = MapNode.Type.LEG
			g.draw_leg_from_frontier(d)
			g.record_leg_cleared(d.target_score, d.max_turns)
			if float(d.target_score) / float(d.max_turns * 3) > float(hardest.x) / float(hardest.y * 3):
				hardest = Vector2i(d.target_score, d.max_turns)
			guard += 1
		# Frontier now empty → the next draw is the fallback.
		var fb: MapNode = MapNode.new()
		fb.act = 0
		fb.type = MapNode.Type.LEG
		g.draw_leg_from_frontier(fb)
		var fb_pair: Vector2i = Vector2i(fb.target_score, fb.max_turns)
		_check(fb_pair == hardest, "fallback repeats hardest cleared pair (got %s want %s)" % [str(fb_pair), str(hardest)], seed_value)
		_check(float(fb_pair.x) / float(fb_pair.y * 3) >= float(hardest.x) / float(hardest.y * 3) - 0.0001,
			"fallback is never easier than the hardest cleared", seed_value)


# ── Incremental generation (§3.6 / §8) ────────────────────────────────────────

func _test_incremental_gen() -> void:
	print("— Incremental per-act generation (§3.6)")
	var level: LevelDefinition = load("res://resources/levels/level_1501.tres")  # 3 acts
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var g: MapGraph = MapGraph.generate(level, rng, 101, INCREMENT)
	# generate() seeds ONLY act 0 — no act-1+ nodes, terminal unset.
	var act0_only: bool = true
	for id: int in g.nodes:
		if g.get_node_by_id(id).act != 0:
			act0_only = false
	_check(act0_only, "generate() yields only act 0 nodes", -1)
	_check(g.terminal_id == -1, "terminal_id unset before the final act is generated", -1)
	var act0_count: int = g.nodes.size()

	# Simulate the real boss-clear flow: the player steps onto the act-0 boss (current_id =
	# boss) BEFORE the next act exists, so reachability is last computed when the boss has no
	# successors. advance_to here mirrors _on_map_node_chosen picking the boss node in main.gd.
	var act0_boss_id: int = -1
	for id: int in g.nodes:
		var bn: MapNode = g.get_node_by_id(id)
		if bn.type == MapNode.Type.BOSS and bn.act == 0:
			act0_boss_id = id
	_check(act0_boss_id != -1, "act-0 boss exists to clear", -1)
	g.advance_to(act0_boss_id)

	# Append act 1 — chained (prev boss → new entry), terminal still unset (act 2 remains).
	g.generate_next_act({"available_brush_colors": [], "highest_cleared": 501})
	_check(g.nodes.size() > act0_count, "generate_next_act appends nodes", -1)
	_check(g.terminal_id == -1, "terminal_id still unset after act 1 (act 2 remains)", -1)
	var entry_chained: bool = false
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		if n.act == 1 and not n.prev_ids.is_empty():
			# the act-1 entry's predecessor is the act-0 boss
			for pid: int in n.prev_ids:
				if g.get_node_by_id(pid).type == MapNode.Type.BOSS and g.get_node_by_id(pid).act == 0:
					entry_chained = true
	_check(entry_chained, "act-1 entry chains off the act-0 boss", -1)

	# Regression (act-boundary "first leg does nothing" bug): generate_next_act must refresh
	# reachability so the freshly-chained act-1 entry is pickable immediately, while the
	# cleared act-0 boss is still current. Without the refresh the entry's reachable flag
	# stays false (computed when the boss had no successors) and the map click is rejected
	# even though its button is enabled.
	_check(g.current_id == act0_boss_id, "current is still the cleared act-0 boss", -1)
	var act1_entry_found: bool = false
	var act1_entry_reachable: bool = false
	for id: int in g.reachable_from(act0_boss_id):
		var en: MapNode = g.get_node_by_id(id)
		if en.act == 1:
			act1_entry_found = true
			act1_entry_reachable = en.reachable
	_check(act1_entry_found, "cleared act-0 boss now has an act-1 successor (the new entry)", -1)
	_check(act1_entry_reachable, "act-1 entry's reachable flag is true after generate_next_act", -1)

	# Append the final act — terminal_id now set to the act-2 boss.
	g.generate_next_act({"available_brush_colors": [], "highest_cleared": 1001})
	_check(g.terminal_id != -1, "terminal_id set once the final act is generated", -1)
	_check(g.get_node_by_id(g.terminal_id).act == 2, "terminal is the final act's boss", -1)
	# Further calls are a no-op.
	var before: int = g.nodes.size()
	g.generate_next_act({"available_brush_colors": [], "highest_cleared": 1501})
	_check(g.nodes.size() == before, "generate_next_act past the final act is a no-op", -1)


## Event family roll is UNGATED at generation (typed-shop slice, Max 2026-06-07): brush + geometry
## roll regardless of run-state — only the routed map icon is fixed at gen; brush affinity (and the
## colorless→accuracy downgrade) resolves at ARRIVAL. So brush appears WITH and WITHOUT colors, and
## all three families show across seeds. (Was the old state-aware gate; superseded by the ungate.)
func _test_state_aware_family_roll() -> void:
	print("— Event family roll is ungated at generation (typed-shop slice)")
	var level: LevelDefinition = load("res://resources/levels/level_1501.tres")
	var brush_seen_with: int = 0
	var brush_seen_without: int = 0
	var families_seen: Dictionary = {}
	for seed_value: int in range(120):
		# WITHOUT brush colors: brush still rolls (ungated).
		var g0: MapGraph = _generate_full(level, seed_value, [])
		for id: int in g0.nodes:
			var n: MapNode = g0.get_node_by_id(id)
			if n.type == MapNode.Type.EVENT:
				families_seen[n.event.reward_family] = true
				if n.event.reward_family == &"brush":
					brush_seen_without += 1
		# WITH brush colors: brush rolls too.
		var g1: MapGraph = _generate_full(level, seed_value, [0, 1])
		for id: int in g1.nodes:
			var n: MapNode = g1.get_node_by_id(id)
			if n.type == MapNode.Type.EVENT and n.event.reward_family == &"brush":
				brush_seen_with += 1
	_check(brush_seen_without > 0, "brush family rolls even with NO colors (ungated at gen, got %d)" % brush_seen_without, -1)
	_check(brush_seen_with > 0, "brush family rolls with colors present (got %d)" % brush_seen_with, -1)
	for fam: StringName in [&"accuracy", &"brush", &"geometry"]:
		_check(families_seen.has(fam), "event family %s appears across seeds" % fam, -1)


## A fixed seed reproduces the full multi-act run identically (node count, types, edges).
func _test_reproducibility() -> void:
	print("— Seed reproducibility")
	var level: LevelDefinition = load("res://resources/levels/level_1501.tres")
	var a: MapGraph = _generate_full(level, 777, [0])
	var b: MapGraph = _generate_full(level, 777, [0])
	_check(_fingerprint(a) == _fingerprint(b), "same seed → identical full run", -1)
	var c: MapGraph = _generate_full(level, 778, [0])
	_check(_fingerprint(a) != _fingerprint(c), "different seed → different run (sanity)", -1)


func _fingerprint(g: MapGraph) -> String:
	var ids: Array = g.nodes.keys()
	ids.sort()
	var parts: Array[String] = []
	for id: int in ids:
		var n: MapNode = g.get_node_by_id(id)
		var nexts: Array = n.next_ids.duplicate()
		nexts.sort()
		parts.append("%d:%d:%d:%d:%d:%s" % [n.id, n.type, n.depth, n.lane, n.target_score, str(nexts)])
	return "|".join(parts)


func _dump_example(level: LevelDefinition) -> void:
	var g: MapGraph = _generate_full(level, 12345)
	var by_act: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		by_act[n.act] = by_act.get(n.act, 0) + 1
	print("   seed 12345: %d nodes total, per-act counts %s" % [g.nodes.size(), str(by_act)])


func _check(condition: bool, label: String, seed_value: int) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL [%s] (seed %d)" % [label, seed_value])
		print("   FAIL [%s] (seed %d)" % [label, seed_value])
