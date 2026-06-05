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
	for seed_value: int in range(SEEDS_PER_LEVEL):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		# generate() asserts internally; if a roll is invalid the engine halts here.
		var g: MapGraph = MapGraph.generate(level, rng, 101, 100)
		_assert_structure(level, g, seed_value)
	# Spot-check one seed in detail.
	_dump_example(level)


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

	# Exactly one BOSS per act; ladder is monotonic non-decreasing by depth.
	var boss_per_act: Dictionary = {}
	var max_target_by_depth: Dictionary = {}
	for id: int in g.nodes:
		var n: MapNode = g.get_node_by_id(id)
		if n.type == MapNode.Type.BOSS:
			boss_per_act[n.act] = boss_per_act.get(n.act, 0) + 1
		max_target_by_depth[n.depth] = maxi(max_target_by_depth.get(n.depth, 0), n.target_score)
	for a: int in range(g.acts):
		_check(boss_per_act.get(a, 0) == 1, "exactly one boss in act %d" % a, seed_value)

	var depths: Array = max_target_by_depth.keys()
	depths.sort()
	var prev: int = 0
	for d: int in depths:
		_check(max_target_by_depth[d] >= prev, "ladder non-decreasing at depth %d" % d, seed_value)
		prev = max_target_by_depth[d]

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
