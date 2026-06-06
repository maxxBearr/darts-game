extends SceneTree
## Headless unit test for MapGraph (specs/map/01-substrate-slice3-impl.md §8 + the
## slice-2 pressure contract). Generates maps for every shipped level across many seeds
## and asserts the structural invariants the segment-based, INCREMENTAL generator
## promises. Run with:
##   godot --headless --script res://tests/test_map_graph.gd
## Exits non-zero on any failure.

const SEEDS_PER_LEVEL := 200
const PATH_SEEDS := 30          ## seeds used for the (heavier) full-path enumeration checks

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
	var g: MapGraph = MapGraph.generate(level, rng, 101, 100)
	for a: int in range(1, maxi(level.boss_count, 1)):
		g.generate_next_act({"available_brush_colors": brush_colors, "highest_cleared": 101})
	return g


func _cfg_for(level: LevelDefinition) -> MapGenConfig:
	return level.map_gen_config if level.map_gen_config != null else MapGenConfig.new()


## Enumerate every start→terminal path (the DAG's branch choices). Returns an Array of
## paths, each an Array[int] of node ids. Branching is 2 per segment, so this stays small
## (≤ 2^(segments·acts), e.g. 64 for a 3-act / 2-segment run).
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
	# Heavier per-path checks on a subset of seeds (budget + skip invariant + traversed len).
	for seed_value: int in range(PATH_SEEDS):
		var g: MapGraph = _generate_full(level, seed_value)
		_assert_topology_invariants(level, g, seed_value)
		_assert_per_path_budget(level, g, seed_value)
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


## Slice-3 topology invariants (§5/§8): no specials on chokepoints, every CHALLENGE has a
## live parallel run (the Skip path), per-act placed-node budget, EVENT family eligibility.
func _assert_topology_invariants(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	# A chokepoint is the SOLE node at its depth; a branch-run node has a same-depth sibling.
	var depth_count: Dictionary = {}
	for id: int in g.nodes:
		var d: int = g.get_node_by_id(id).depth
		depth_count[d] = depth_count.get(d, 0) + 1

	var per_act: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		per_act[n.act] = per_act.get(n.act, 0) + 1
		if n.type == MapNode.Type.SHOP or n.type == MapNode.Type.EVENT or n.type == MapNode.Type.CHALLENGE:
			_check(depth_count[n.depth] > 1, "special (type %d) node not on a chokepoint" % n.type, seed_value)
		if n.type == MapNode.Type.CHALLENGE:
			_check(n.act >= 1, "challenge is post-boss-1 (act >= 1)", seed_value)
			_check(depth_count[n.depth] > 1, "challenge has a live parallel run (Skip available)", seed_value)
			_check(n.challenge != null, "challenge node carries a ChallengeNode resource", seed_value)
		if n.type == MapNode.Type.EVENT:
			_check(n.event != null, "event node carries an EventNode resource", seed_value)
			# Accuracy-only run-state (default) ⇒ the only eligible family is accuracy.
			_check(n.event.reward_family == &"accuracy", "event family is accuracy under empty run-state", seed_value)
	for a: int in per_act:
		_check(per_act[a] >= cfg.act_node_budget_min and per_act[a] <= cfg.act_node_budget_max,
			"act %d placed-node count %d in [%d,%d]" % [a, per_act[a], cfg.act_node_budget_min, cfg.act_node_budget_max], seed_value)


## Per-traversal budget (§1.2/§8): enumerate full paths; each act's contribution of each
## special stays ≤ type_max; act-0 paths collect zero challenges; ≥1 challenge appears on
## at least one branch in every act ≥ 1; traversed path length per act ≈ 12 ± slack.
func _assert_per_path_budget(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	var cfg: MapGenConfig = _cfg_for(level)
	var paths: Array = _enumerate_paths(g)
	_check(paths.size() > 0, "at least one start→boss path exists", seed_value)
	# Traversed length bounds: 2 (entry+boss) + segments (chokepoints) + Σ run lengths.
	var trav_min: int = 2 + cfg.branch_segments_min + cfg.branch_segments_min * cfg.branch_len_min
	var trav_max: int = 2 + cfg.branch_segments_max + cfg.branch_segments_max * cfg.branch_len_max
	# Track, per act, the max challenge count any single branch collects (existence check).
	var act_max_challenges: Dictionary = {}
	for path: Array in paths:
		var per_act_count: Dictionary = {}   ## act -> {type -> count}
		var per_act_len: Dictionary = {}
		for id: int in path:
			var n: MapNode = g.get_node_by_id(id)
			per_act_len[n.act] = per_act_len.get(n.act, 0) + 1
			if not per_act_count.has(n.act):
				per_act_count[n.act] = {}
			var tc: Dictionary = per_act_count[n.act]
			tc[n.type] = tc.get(n.type, 0) + 1
		for a: int in per_act_count:
			var tc: Dictionary = per_act_count[a]
			var shops: int = tc.get(MapNode.Type.SHOP, 0)
			var events: int = tc.get(MapNode.Type.EVENT, 0)
			var challenges: int = tc.get(MapNode.Type.CHALLENGE, 0)
			_check(shops <= cfg.shops_per_path_max, "path collects ≤ %d shops in act %d (got %d)" % [cfg.shops_per_path_max, a, shops], seed_value)
			_check(events <= cfg.events_per_path_max, "path collects ≤ %d events in act %d (got %d)" % [cfg.events_per_path_max, a, events], seed_value)
			_check(challenges <= cfg.challenges_per_path_max, "path collects ≤ %d challenges in act %d (got %d)" % [cfg.challenges_per_path_max, a, challenges], seed_value)
			if a == 0:
				_check(challenges == 0, "act-0 path collects zero challenges (post-boss-1 gate)", seed_value)
			act_max_challenges[a] = maxi(act_max_challenges.get(a, 0), challenges)
		for a: int in per_act_len:
			_check(per_act_len[a] >= trav_min and per_act_len[a] <= trav_max,
				"act %d traversed length %d in [%d,%d] (~12)" % [a, per_act_len[a], trav_min, trav_max], seed_value)
	# Every act ≥ 1 offers a challenge on at least one branch (challenges_per_path_min ≥ 1).
	for a: int in range(1, g.acts):
		_check(act_max_challenges.get(a, 0) >= 1, "act %d offers ≥1 challenge on at least one branch" % a, seed_value)


# ── Incremental generation (§3.6 / §8) ────────────────────────────────────────

func _test_incremental_gen() -> void:
	print("— Incremental per-act generation (§3.6)")
	var level: LevelDefinition = load("res://resources/levels/level_1501.tres")  # 3 acts
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var g: MapGraph = MapGraph.generate(level, rng, 101, 100)
	# generate() seeds ONLY act 0 — no act-1+ nodes, terminal unset.
	var act0_only: bool = true
	for id: int in g.nodes:
		if g.get_node_by_id(id).act != 0:
			act0_only = false
	_check(act0_only, "generate() yields only act 0 nodes", -1)
	_check(g.terminal_id == -1, "terminal_id unset before the final act is generated", -1)
	var act0_count: int = g.nodes.size()

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
