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


## Build a full run map for `level`, using the seeded `rng` for every roll so runs
## are reproducible. `starting_target` / `target_increment` mirror x01_game so the
## ported ladder lines up with the engine's X01 parity (101, 201, …).
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
	graph._assign_leg_params(level, cfg, starting_target, target_increment)
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


# ── Step 4: ported difficulty ladder ────────────────────────────────────────

## Assign each node its (target_score, darts_fronted). Slice 1 ladder: targets
## climb across the run; both parallel nodes at a depth share the tier (routing
## differs by type composition, not hardness). Each act's boss = the act ceiling.
func _assign_leg_params(level: LevelDefinition, cfg: MapGenConfig, starting_target: int, target_increment: int) -> void:
	var max_target: int = level.max_score_target if level != null else 501

	# Per-act depth span, so we can interpolate floor→ceiling within the act.
	var act_min: Dictionary = {}
	var act_max: Dictionary = {}
	for id: int in nodes:
		var n: MapNode = nodes[id]
		if not act_min.has(n.act) or n.depth < act_min[n.act]:
			act_min[n.act] = n.depth
		if not act_max.has(n.act) or n.depth > act_max[n.act]:
			act_max[n.act] = n.depth

	for id: int in nodes:
		var n: MapNode = nodes[id]
		n.darts_fronted = cfg.darts_fronted
		var ceil_t: int = _act_ceiling(n.act, max_target, starting_target, target_increment)
		if n.type == MapNode.Type.BOSS:
			n.target_score = ceil_t
			continue
		var floor_t: int
		if n.act == 0:
			floor_t = starting_target
		else:
			floor_t = _act_ceiling(n.act - 1, max_target, starting_target, target_increment) + target_increment
		var lo: int = act_min[n.act]
		var hi: int = act_max[n.act]
		var frac: float = 0.0 if hi == lo else float(n.depth - lo) / float(hi - lo)
		n.target_score = _snap(lerpf(float(floor_t), float(ceil_t), frac), starting_target, target_increment)


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
