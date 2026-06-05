extends SceneTree
## Headless unit test for MapGraph.generate (specs/map/01-substrate-impl.md §5).
## Generates maps for every shipped level across many seeds and asserts the
## structural invariants the generator promises. Run with:
##   godot --headless --script res://tests/test_map_graph.gd
## Exits non-zero on any failure.

const SEEDS_PER_LEVEL := 200

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
	print("\nMapGraph test: %d checks, %d failures across %d seeds/level." % [_checks, _failures, SEEDS_PER_LEVEL])
	quit(1 if _failures > 0 else 0)


func _test_level(level: LevelDefinition) -> void:
	print("— Level %s (max %d, %d acts/bosses)" % [level.display_name, level.max_score_target, level.boss_count])
	var turns_dist: Dictionary = {}   ## max_turns value -> count of non-boss legs across all seeds
	for seed_value: int in range(SEEDS_PER_LEVEL):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		# generate() asserts internally; if a roll is invalid the engine halts here.
		var g: MapGraph = MapGraph.generate(level, rng, 101, 100)
		_assert_structure(level, g, seed_value)
		for id: int in g.nodes:
			var n: MapNode = g.get_node_by_id(id)
			if n.type != MapNode.Type.BOSS:
				turns_dist[n.max_turns] = turns_dist.get(n.max_turns, 0) + 1
	# Spread guarantee: the generator must NOT silently go inert (every leg == ref).
	_assert_spread(level, turns_dist)
	# Parity guarantee: forcing the roll to reference_turns reproduces the slice-1 ladder.
	_assert_parity(level)
	# Spot-check one seed in detail.
	_dump_example(level)


## The slice was inert once (every leg rolled reference_turns) and the bounds-only
## suite stayed green. Assert the rolled max_turns actually spreads: more than one
## distinct value, and both ends of the configured range appear across the seeds.
func _assert_spread(level: LevelDefinition, turns_dist: Dictionary) -> void:
	var cfg: MapGenConfig = level.map_gen_config if level.map_gen_config != null else MapGenConfig.new()
	var keys: Array = turns_dist.keys()
	keys.sort()
	var dist_str: String = ""
	for t: int in keys:
		dist_str += "%d×%d  " % [t, turns_dist[t]]
	print("   max_turns distribution (non-boss legs, %d seeds): %s" % [SEEDS_PER_LEVEL, dist_str.strip_edges()])
	_check(keys.size() > 1, "turns roll produces >1 distinct value (not inert)", -1)
	_check(turns_dist.has(cfg.turns_min), "turns_min (%d) appears across seeds" % cfg.turns_min, -1)
	_check(turns_dist.has(cfg.turns_max), "turns_max (%d) appears across seeds" % cfg.turns_max, -1)


## "Ships at parity": with turns forced to reference_turns and pressure 1.0, every
## node's target must equal baseline_target(depth) — i.e. the slice-1 ladder value.
func _assert_parity(level: LevelDefinition) -> void:
	var cfg: MapGenConfig = level.map_gen_config.duplicate() if level.map_gen_config != null else MapGenConfig.new()
	cfg.turns_min = cfg.reference_turns
	cfg.turns_max = cfg.reference_turns
	cfg.pressure_baseline = 1.0
	var lvl: LevelDefinition = level.duplicate()
	lvl.map_gen_config = cfg
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 999
	var g: MapGraph = MapGraph.generate(lvl, rng, 101, 100)
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		_check(n.max_turns == cfg.reference_turns, "parity: turns == reference_turns", 999)
		var want: int = g.baseline_target(n.depth)
		_check(n.target_score == want, "parity: target == slice-1 ladder at depth %d (got %d want %d)" % [n.depth, n.target_score, want], 999)


func _assert_structure(level: LevelDefinition, g: MapGraph, seed_value: int) -> void:
	_check(g.acts == level.boss_count, "acts==boss_count", seed_value)
	_check(g.start_id != -1 and g.terminal_id != -1, "start/terminal set", seed_value)

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

	# Terminal boss is the only sink; it has the level's max target.
	var sinks: int = 0
	for id: int in g.nodes:
		if g.get_node_by_id(id).next_ids.is_empty():
			sinks += 1
	_check(sinks == 1, "exactly one terminal sink", seed_value)
	_check(g.get_node_by_id(g.terminal_id).target_score == level.max_score_target, "terminal target == max_score_target", seed_value)
	_check(g.get_node_by_id(g.terminal_id).type == MapNode.Type.BOSS, "terminal is a BOSS", seed_value)

	# Exactly one BOSS per act. (Slice 2 drops strict ladder monotonicity: a
	# low-turn leg deeper than a high-turn one can carry a lower raw target.)
	var boss_per_act: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		if n.type == MapNode.Type.BOSS:
			boss_per_act[n.act] = boss_per_act.get(n.act, 0) + 1
	for a: int in range(g.acts):
		_check(boss_per_act.get(a, 0) == 1, "exactly one boss in act %d" % a, seed_value)

	# Slice 2 contract: each non-boss leg rolls turns in range and targets flat
	# pressure_baseline (within the half-increment _snap can introduce), unless the
	# act-window clamp pushed it onto a boundary. Every target stays in its window.
	var cfg: MapGenConfig = level.map_gen_config if level.map_gen_config != null else MapGenConfig.new()
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
			# Clamped: the snapped ideal landed outside the window, so it sits on a
			# boundary by construction. Pressure is intentionally off here (§2c).
			_check(n.target_score == fl or n.target_score == ce, "clamped leg target on act boundary", seed_value)
		else:
			var p: float = g.pressure_of(n.target_score, n.max_turns, n.depth)
			# Half-increment snap tolerance, expressed in pressure units at this node.
			var tol: float = 0.5 * 100.0 * float(cfg.reference_turns) / (float(n.max_turns) * float(base)) + 0.001
			_check(absf(p - cfg.pressure_baseline) <= tol, "flat pressure ~%.2f (got %.3f, tol %.3f)" % [cfg.pressure_baseline, p, tol], seed_value)

	# At least one shop exists across the run (soft coverage; counts are rolled).
	var shop_count: int = 0
	for id: int in g.nodes:
		if g.get_node_by_id(id).type == MapNode.Type.SHOP:
			shop_count += 1
	_check(shop_count >= g.acts, "at least one shop per act on average (>= acts total)", seed_value)


func _dump_example(level: LevelDefinition) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var g: MapGraph = MapGraph.generate(level, rng, 101, 100)
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
