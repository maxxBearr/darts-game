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


## The number of distinct (target, turns) leg configs an act can host — its combo capacity
## MINUS the reserved boss pair. The no-repeat rule is allowed to repeat only once a path's
## claims exceed this (the documented exhaustion fallback in claim_unplayed_leg_params).
func _act_leg_capacity(g: MapGraph, cfg: MapGenConfig, act: int) -> int:
	var num_targets: int = (g.act_ceiling(act) - g.act_floor(act)) / INCREMENT + 1
	var num_turns: int = cfg.turns_max - cfg.turns_min + 1
	return num_targets * num_turns - 1   # boss pair (ceiling @ reference_turns) is reserved


# ── Per-level suite ───────────────────────────────────────────────────────────

func _test_level(level: LevelDefinition) -> void:
	print("— Level %s (max %d, %d acts/bosses)" % [level.display_name, level.max_score_target, level.boss_count])
	var turns_dist: Dictionary = {}   ## max_turns value -> count of non-boss legs across all seeds
	for seed_value: int in range(SEEDS_PER_LEVEL):
		# _generate_full asserts internally (each act runs _validate); a bad roll halts here.
		var g: MapGraph = _generate_full(level, seed_value)
		_assert_structure(level, g, seed_value)
		for id: int in g.nodes:
			var n: MapNode = g.get_node_by_id(id)
			if n.type != MapNode.Type.BOSS:
				turns_dist[n.max_turns] = turns_dist.get(n.max_turns, 0) + 1
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
		_assert_no_repeat_claims(level, g, seed_value)
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
	# Spread guarantee: the generator must NOT silently go inert (every leg == ref).
	_assert_spread(level, turns_dist)
	# Parity guarantee: forcing the roll to reference_turns reproduces the slice-1 ladder.
	_assert_parity(level)
	_dump_example(level)


## The slice was inert once (every leg rolled reference_turns) and the bounds-only suite
## stayed green. Assert the rolled max_turns actually spreads.
func _assert_spread(level: LevelDefinition, turns_dist: Dictionary) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	var keys: Array = turns_dist.keys()
	keys.sort()
	var dist_str: String = ""
	for t: int in keys:
		dist_str += "%d×%d  " % [t, turns_dist[t]]
	print("   max_turns distribution (non-boss legs, %d seeds): %s" % [SEEDS_PER_LEVEL, dist_str.strip_edges()])
	_check(keys.size() > 1, "turns roll produces >1 distinct value (not inert)", -1)
	_check(turns_dist.has(cfg.turns_min), "turns_min (%d) appears across seeds" % cfg.turns_min, -1)
	_check(turns_dist.has(cfg.turns_max), "turns_max (%d) appears across seeds" % cfg.turns_max, -1)


## "Ships at parity": with turns forced to reference_turns and pressure 1.0, every node's
## target must equal baseline_target(depth) — i.e. the slice-1 ladder value.
func _assert_parity(level: LevelDefinition) -> void:
	var cfg: MapGenConfig = _cfg_for(level).duplicate()
	cfg.turns_min = cfg.reference_turns
	cfg.turns_max = cfg.reference_turns
	cfg.pressure_baseline = 1.0
	var lvl: LevelDefinition = level.duplicate()
	lvl.map_gen_config = cfg
	var g: MapGraph = _generate_full(lvl, 999)
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		_check(n.max_turns == cfg.reference_turns, "parity: turns == reference_turns", 999)
		var want: int = g.baseline_target(n.depth)
		_check(n.target_score == want, "parity: target == slice-1 ladder at depth %d (got %d want %d)" % [n.depth, n.target_score, want], 999)


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

	# Slice 2 contract: each non-boss leg rolls turns in range and targets flat pressure.
	var cfg: MapGenConfig = _cfg_for(level)
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		var fl: int = g.act_floor(n.act)
		var ce: int = g.act_ceiling(n.act)
		_check(n.target_score >= fl and n.target_score <= ce, "target in act %d window [%d,%d]" % [n.act, fl, ce], seed_value)
		if n.type == MapNode.Type.BOSS:
			continue
		_check(n.max_turns >= cfg.turns_min and n.max_turns <= cfg.turns_max, "leg turns in [%d,%d]" % [cfg.turns_min, cfg.turns_max], seed_value)
		var base: int = g.baseline_target(n.depth)
		var ideal_raw: float = cfg.pressure_baseline * float(n.max_turns) / float(cfg.reference_turns) * float(base)
		if ideal_raw < float(fl) or ideal_raw > float(ce):
			_check(n.target_score == fl or n.target_score == ce, "clamped leg target on act boundary", seed_value)
		else:
			var p: float = g.pressure_of(n.target_score, n.max_turns, n.depth)
			var tol: float = 0.5 * 100.0 * float(cfg.reference_turns) / (float(n.max_turns) * float(base)) + 0.001
			_check(absf(p - cfg.pressure_baseline) <= tol, "flat pressure ~%.2f (got %.3f, tol %.3f)" % [cfg.pressure_baseline, p, tol], seed_value)

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
			# Accuracy-only run-state (default) ⇒ the only eligible family is accuracy.
			_check(n.event.reward_family == &"accuracy", "event family is accuracy under empty run-state", seed_value)
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
			if n.is_crossover or n.is_branch:
				continue   # §4: detour content is off the per-path special budget
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


## The no-repeat leg rule: claiming every non-boss LEG along any single path yields
## pairwise-distinct (target, turns) configs — never the act boss's reserved pair, always
## inside the act window / turns band — UNTIL the act's leg combo capacity is exhausted, at
## which point the documented fallback may repeat (round-2 act-0 paths can be long enough to
## approach the 15-config space). Mirrors main.gd's arrival flow (record leg 1, claim arrivals).
func _assert_no_repeat_claims(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	var paths: Array = _enumerate_paths(g)
	# One representative path per seed keeps the cost linear (claims mutate the graph).
	var path: Array = paths[seed_value % paths.size()]
	g.record_played_config(101, 5)   # leg 1, as main.gd records it at run start
	var seen: Dictionary = {"101|5": true}
	var claims_in_act: Dictionary = {0: 1}   # leg 1 is an act-0 config
	for id: int in path:
		var n: MapNode = g.get_node_by_id(id)
		# Specials don't play their rolled params (shop/event/challenge arrivals route
		# elsewhere in main.gd), and the boss is its reserved pair's single owner.
		if n.type != MapNode.Type.LEG:
			continue
		if n.id == g.start_id:
			continue   # leg 1 is recorded above, not claimed
		g.claim_unplayed_leg_params(n)
		claims_in_act[n.act] = claims_in_act.get(n.act, 0) + 1
		var key: String = "%d|%d" % [n.target_score, n.max_turns]
		if seen.has(key):
			# A repeat is legal ONLY once this act's leg combo space is exhausted.
			_check(claims_in_act[n.act] > _act_leg_capacity(g, cfg, n.act),
				"claimed leg %s repeats only when act %d combo space is exhausted (claim #%d, cap %d)" % [key, n.act, claims_in_act[n.act], _act_leg_capacity(g, cfg, n.act)], seed_value)
		seen[key] = true
		_check(n.max_turns >= cfg.turns_min and n.max_turns <= cfg.turns_max, "claimed turns in band", seed_value)
		_check(n.target_score >= g.act_floor(n.act) and n.target_score <= g.act_ceiling(n.act), "claimed target in act window", seed_value)
		_check(key != "%d|%d" % [g.act_ceiling(n.act), cfg.reference_turns],
			"claimed leg never replays the act boss's reserved pair", seed_value)


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


## State-aware family roll (§8): an act generated with brush colors in run-state may roll
## the brush event family; an act generated WITHOUT them only ever rolls accuracy.
func _test_state_aware_family_roll() -> void:
	print("— State-aware event family roll (§3.6)")
	var level: LevelDefinition = load("res://resources/levels/level_1501.tres")
	var brush_seen_with: int = 0
	var brush_seen_without: int = 0
	var event_nodes_with: int = 0
	for seed_value: int in range(120):
		# WITHOUT brush colors: every appended act sees an empty palette.
		var g0: MapGraph = _generate_full(level, seed_value, [])
		for id: int in g0.nodes:
			var n: MapNode = g0.get_node_by_id(id)
			if n.type == MapNode.Type.EVENT and n.event.reward_family == &"brush":
				brush_seen_without += 1
		# WITH brush colors: appended acts (1+) may roll brush.
		var g1: MapGraph = _generate_full(level, seed_value, [0, 1])
		for id: int in g1.nodes:
			var n: MapNode = g1.get_node_by_id(id)
			if n.type == MapNode.Type.EVENT and n.act >= 1:
				event_nodes_with += 1
				if n.event.reward_family == &"brush":
					brush_seen_with += 1
	_check(brush_seen_without == 0, "brush family NEVER rolls when run-state has no colors (got %d)" % brush_seen_without, -1)
	_check(brush_seen_with > 0, "brush family DOES roll on act≥1 when colors are present (got %d of %d event nodes)" % [brush_seen_with, event_nodes_with], -1)


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
