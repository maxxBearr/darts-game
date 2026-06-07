class_name MapGraph
extends RefCounted
## The generated run-map data model plus its generator. No Node/scene dependency,
## so it is headless unit-testable. See specs/map/01-substrate-impl.md §3 for the
## ordered algorithm and §2b for the API contract.
##
## Topology (tuning pass 2026-06-06, "sideways H"): a shared funnel entry per act
## fans into two CONTINUOUS parallel lanes. Between segments the lanes no longer
## merge into a chokepoint (the old "> shape"); instead each lane runs straight on,
## and a CROSSOVER node sits between them — an optional interchange you can step
## onto to switch lanes (or return to your own). Only the pre-boss chokepoint still
## reconverges, funnelling into the act's BOSS. Acts chain boss→entry.
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

## A dedicated sub-RNG for COSMETIC-only rolls (the event reward family) so they never perturb
## the structural _rng stream. Event family choice doesn't affect graph STRUCTURE (placement,
## depth, lane runs), so it must not ride the structural stream — otherwise adding an eligible
## family (e.g. geometry) shifts every downstream structural roll and changes the generated map.
## Lazily seeded from _rng.seed (read-only — doesn't consume _rng's state), so it stays
## deterministic per run while leaving the structural stream byte-identical. See _roll_event_node.
var _family_rng: RandomNumberGenerator = null
var _generated_acts: int = 0           ## how many acts have been appended so far
var _prev_boss_id: int = -1            ## the most-recently generated boss (the frontier sink)
var _next_depth: int = 0               ## the running global depth counter (next free column)

# Per-act detour bookkeeping (round 2), reset at the top of each _build_act:
var _act_entry_depth: int = 0          ## depth of the current act's entry (gates act-0 challenges)
var _detour_challenge_used: bool = false  ## a crossover/branch challenge was placed this act (≤1 cap)

# ── Leg lattice (2026-06-07) — per-act monotone (score, turns) frontier ──────
# Replaces slice-2's per-leg turn roll + the claim_unplayed_leg_params no-repeat dodge with a
# per-act difficulty lattice drawn LAZILY at arrival (see the leg-lattice spec). Cells are
# (score, turns); a cell's pressure is the depth-independent score / (turns · BASE_DARTS_PER_TURN)
# — the §1 table value (201/6 = 11.2, etc.), NOT the depth-based pressure_of() the challenges read.
# Within an act, cells unlock left→right per row (6t→5t→4t) and row→row (a row's loosest cell
# unlocks the next row's loosest once resolved); any UNDRAWN cell at/below the highest CLEARED
# pressure is culled, so difficulty is strictly monotone. Bosses sit at the act ceiling, off the
# drawable lattice (rows stop one increment below it). Ordinary legs carry target_score = 0 at
# generation — they get their pair from draw_leg_from_frontier on arrival.

## Drawable turn columns, loosest → tightest (the LOCKED 6/5/4 grid). The lowest row of each act
## drops the loosest (6t) column — a 6-turn opener score is trivially easy (the §1 table omits it).
const LATTICE_TURNS: Array[int] = [6, 5, 4]

## Every lattice cell across all generated acts. Each is a Dictionary:
##   {act, score, turns, pressure, drawn, cleared, culled, is_opener}
## drawn = assigned to a leg node; cleared = that leg was won; culled = expired by the monotone
## rule; resolved (cleared OR culled) gates unlocking; is_opener marks act 0's fixed calibration
## leg (101/5) the run auto-plays at start — never drawn from the frontier.
var _lattice_cells: Array[Dictionary] = []

## act -> highest CLEARED cell pressure (the cull threshold for that act).
var _act_cleared_pressure: Dictionary = {}

## Dedicated RNG for the arrival-time frontier draw, so lazy draws never perturb the structural
## _rng stream (which would reshape later generate_next_act calls). Seeded lazily from _rng.seed,
## mirroring _family_rng. Path-dependent by nature (the live frontier depends on the route walked).
var _lattice_rng: RandomNumberGenerator = null


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
	# The new act wired fresh forward edges off the just-cleared boss, but the per-node
	# `reachable` flags were last computed by advance_to(boss) BACK WHEN the boss had no
	# successors (the next act didn't exist yet). Refresh now so the new act's entry is
	# pickable the instant the map is shown — the graph owns this invariant rather than
	# leaving it to the next advance_to. (Without this, MapView enables the entry's button
	# from the live edge query but its stale reachable=false would reject the click — the
	# act-boundary "first leg does nothing" bug.)
	_refresh_reachable()


# ── Generation (per-act, incremental — §2 / §3 / §3.6) ──────────────────────

## Build one act's subgraph and fold it onto the accumulating graph: entry chokepoint
## → two continuous parallel lanes split into branch segments, with a CROSSOVER
## interchange between consecutive segments (the "sideways H" rung — lanes run
## straight through; the crossover is an optional extra node that lets you switch
## lanes or double back into your own) → pre-boss chokepoint → boss. Then slot
## specials onto the branch runs (consulting run_state) and assign leg params to the
## new nodes. Chains the previous act's boss into this act's entry; advances the
## running depth/frontier across calls.
func _build_act(act: int, run_state: Dictionary) -> void:
	# Per-act detour bookkeeping (round 2): the entry depth gates act-0 challenges, and at
	# most ONE challenge may sit across all of this act's crossovers + mini-branches combined.
	_act_entry_depth = _next_depth
	_detour_challenge_used = false

	# Step 1 — act entry: a single shared funnel node (act 0's is the global start).
	var entry: MapNode = _new_node(MapNode.Type.LEG, _next_depth, 0, act)
	if act == 0:
		start_id = entry.id
	else:
		_connect(_prev_boss_id, entry.id)
	_next_depth += 1

	# Step 2 — lanes + crossovers (round 2). Roll the crossover COUNT and the TOTAL per-lane
	# length INDEPENDENTLY, then cut the length into (crossovers + 1) stretches of ≥2 nodes
	# each. Each stretch is two parallel runs (lanes 0/1); a crossover interchange sits
	# between consecutive stretches — sole at its depth (the view centres it), fed by BOTH
	# lane-ends and exiting to BOTH next runs, with the lanes continuing straight past it
	# (the stay edges). Decoupling count from length keeps the traversed path ~constant
	# however many lane-switch points an act rolls. Crossovers are typed in step 5.
	var lane_len: int = maxi(_rng.randi_range(_cfg.lane_len_min, _cfg.lane_len_max), 2)
	# Clamp the crossover count so every stretch can keep its ≥2 floor (lane_len ≥ 2·stretches).
	var crossovers: int = clampi(_rng.randi_range(_cfg.crossovers_min, _cfg.crossovers_max), 0, lane_len / 2 - 1)
	var num_stretches: int = crossovers + 1
	var stretch_lens: Array[int] = _partition_lane(lane_len, num_stretches)

	var stretches: Array = []        # each: { "run0": Array[int], "run1": Array[int] }
	var crossover_nodes: Array[MapNode] = []
	var prev_end0: int = -1          # lane 0's frontier node (last of the previous stretch)
	var prev_end1: int = -1          # lane 1's frontier node
	for s: int in range(num_stretches):
		# Crossover interchange between the previous stretch and this one (never before
		# stretch 0 — the entry funnel already provides that fork).
		var crossover_id: int = -1
		if s > 0:
			var crossover: MapNode = _new_node(MapNode.Type.LEG, _next_depth, 0, act)
			crossover.is_crossover = true
			_connect(prev_end0, crossover.id)
			_connect(prev_end1, crossover.id)
			crossover_id = crossover.id
			crossover_nodes.append(crossover)
			_next_depth += 1
		var run_len: int = stretch_lens[s]
		var run0: Array[int] = []
		var run1: Array[int] = []
		for i: int in range(run_len):
			run0.append(_new_node(MapNode.Type.LEG, _next_depth + i, 0, act).id)
			run1.append(_new_node(MapNode.Type.LEG, _next_depth + i, 1, act).id)
		if s == 0:
			# The act entry fans into the first node of BOTH lanes.
			_connect(entry.id, run0[0])
			_connect(entry.id, run1[0])
		else:
			# Lanes continue straight (the long parallel paths)…
			_connect(prev_end0, run0[0])
			_connect(prev_end1, run1[0])
			# …and the crossover feeds both, so stepping onto it opens either lane.
			_connect(crossover_id, run0[0])
			_connect(crossover_id, run1[0])
		# Wire each run depth→depth+1 (a run is consecutive depths at one lane).
		for i: int in range(run_len - 1):
			_connect(run0[i], run0[i + 1])
			_connect(run1[i], run1[i + 1])
		_next_depth += run_len
		stretches.append({"run0": run0, "run1": run1})
		prev_end0 = run0[run_len - 1]
		prev_end1 = run1[run_len - 1]

	# Pre-boss chokepoint — the ONE remaining reconvergence: both lanes funnel into a
	# single shared LEG before the boss (the boss fight is never dodgeable by lane).
	var pre_boss: MapNode = _new_node(MapNode.Type.LEG, _next_depth, 0, act)
	_connect(prev_end0, pre_boss.id)
	_connect(prev_end1, pre_boss.id)
	_next_depth += 1

	# Step 3 — terminal boss for this act: the pre-boss chokepoint funnels into it.
	var boss: MapNode = _new_node(MapNode.Type.BOSS, _next_depth, 0, act)
	_connect(pre_boss.id, boss.id)
	_next_depth += 1
	_prev_boss_id = boss.id
	# terminal_id is set ONLY when the final act generates (reaching it == run victory).
	if act == acts - 1:
		terminal_id = boss.id

	# Step 4 — mini-branch detours (off-budget; may consume the act's one detour challenge).
	_slot_branches(act, stretches, run_state)

	# Step 5 — type the crossovers (off-budget; may consume the act's one detour challenge).
	_type_crossovers(crossover_nodes, run_state)

	# Step 6 — distribute lane-run specials. The per-traversal budget counts these ONLY
	# (crossover/branch content is off-budget spice, §4), so this still walks run0/run1.
	_slot_specials(act, stretches, run_state)

	# Step 7 — rebuild the depth→act maps + assign the boss its tier pair (ordinary legs are
	# drawn lazily at arrival, so this no longer rolls leg params — see _assign_leg_params).
	_assign_leg_params(_level, _cfg, _rng, _starting_target, _target_increment)

	# Step 8 — build this act's leg lattice (the per-act monotone (score, turns) grid drawn at
	# arrival). Depends on the act window math set in _assign_leg_params; idempotent per act.
	_build_act_lattice(act)

	_generated_acts = act + 1


## Cut a total lane length into `parts` stretch lengths of ≥2 each, summing to `total`.
## Deterministic (seeded): every stretch starts at 2, then the remainder is sprinkled one
## node at a time onto a randomly chosen stretch. The caller clamps the crossover count so
## total ≥ 2·parts always holds (no stretch is starved below its 2-node floor).
func _partition_lane(total: int, parts: int) -> Array[int]:
	var lens: Array[int] = []
	for i: int in range(parts):
		lens.append(2)
	var remainder: int = total - 2 * parts
	for r: int in range(maxi(remainder, 0)):
		lens[_rng.randi_range(0, parts - 1)] += 1
	return lens


## Distribute SHOP / EVENT / CHALLENGE across an act's branch-run nodes only, meeting the
## §1.2 per-traversal budget. CHALLENGE only when act ≥ 1 (post-boss-1 gate). For each
## type a per-traversal target is rolled in [type_min, type_max] and hosted in that many
## DISTINCT segments — one occurrence per placed run — so the worst-case path (one run per
## segment) collects at most `target` ≤ type_max. Each hosting segment places the type in
## ONE run (high branch_contrast → the two branches differ in content, a real composition
## choice) or BOTH runs (low contrast → either branch collects it). §3.
func _slot_specials(act: int, stretches: Array, run_state: Dictionary) -> void:
	if stretches.is_empty():
		return
	var specs: Array[Dictionary] = [
		{"type": MapNode.Type.SHOP, "lo": _cfg.shops_per_path_min, "hi": _cfg.shops_per_path_max, "min_depth": 0},
		{"type": MapNode.Type.EVENT, "lo": _cfg.events_per_path_min, "hi": _cfg.events_per_path_max, "min_depth": 0},
	]
	# Challenges (round 2): allowed in EVERY act now (the post-boss-1 hard gate is gone). Act 0
	# uses a leaner band and a depth gate — no challenge in the first challenge_act0_min_depth
	# columns after the entry (the highest_cleared anchor needs a few cleared legs to mean
	# anything). Later acts keep the full band with no depth restriction.
	if act == 0:
		specs.append({"type": MapNode.Type.CHALLENGE, "lo": _cfg.challenges_act0_per_path_min, "hi": _cfg.challenges_act0_per_path_max,
			"min_depth": _act_entry_depth + _cfg.challenge_act0_min_depth})
	else:
		specs.append({"type": MapNode.Type.CHALLENGE, "lo": _cfg.challenges_per_path_min, "hi": _cfg.challenges_per_path_max, "min_depth": 0})

	for spec: Dictionary in specs:
		var target: int = _rng.randi_range(maxi(spec["lo"], 0), maxi(spec["hi"], 0))
		var host_count: int = mini(target, stretches.size())
		if host_count <= 0:
			continue
		var order: Array[int] = _shuffled_indices(stretches.size())
		for k: int in range(host_count):
			var seg: Dictionary = stretches[order[k]]
			if _rng.randf() < _cfg.branch_contrast:
				# Content contrast: place into ONE run only so the lanes differ.
				var pick_run: Array[int] = seg["run0"] if _rng.randi_range(0, 1) == 0 else seg["run1"]
				_place_special_in_run(pick_run, spec["type"], run_state, spec["min_depth"])
			else:
				# No contrast: both runs host it, so either lane pick collects it.
				_place_special_in_run(seg["run0"], spec["type"], run_state, spec["min_depth"])
				_place_special_in_run(seg["run1"], spec["type"], run_state, spec["min_depth"])


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
## two of the SAME type within that many indices in the run), never overwriting a node
## that is already a special, and never placing below `min_depth` (the act-0 challenge
## depth gate; 0 = unrestricted). Hangs the type's payload (challenge roll / event family)
## on the chosen node. Returns the chosen node, or null if no slot fits.
func _place_special_in_run(run_ids: Array[int], type: MapNode.Type, run_state: Dictionary, min_depth: int = 0) -> MapNode:
	var eligible: Array[int] = []
	for i: int in range(run_ids.size()):
		var cand: MapNode = nodes[run_ids[i]]
		if cand.type != MapNode.Type.LEG:
			continue   # already a special — never stack two on one node
		if cand.depth < min_depth:
			continue   # act-0 challenge depth gate (no-op for unrestricted types)
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
	_assign_special_payload(node, type, run_state)
	return node


## Convert `node` to a special TYPE and hang its payload (challenge roll / event family).
## Shared by lane-run placement (_place_special_in_run), crossover typing and branch specials.
func _assign_special_payload(node: MapNode, type: MapNode.Type, run_state: Dictionary) -> void:
	node.type = type
	match type:
		MapNode.Type.CHALLENGE:
			node.challenge = _roll_challenge_node(_rng, _cfg)
		MapNode.Type.EVENT:
			node.event = _roll_event_node(run_state)
		_:
			pass


# ── Round 2: crossover typing + mini-branches (detours; off the per-path budget) ──

## Give each crossover a rolled type: mostly LEG, sometimes a special (crossover_weight_*).
## A typed crossover is off-budget and its straight lane edges are its built-in skip, so a
## special there is still dodgeable. Challenge respects the act-0 depth gate and the ≤1
## detour-challenge-per-act cap (shared with mini-branches).
func _type_crossovers(crossover_nodes: Array[MapNode], run_state: Dictionary) -> void:
	for cx: MapNode in crossover_nodes:
		var t: MapNode.Type = _roll_detour_type(cx, run_state, true)
		if t != MapNode.Type.LEG:
			_assign_special_payload(cx, t, run_state)


## Roll a detour node's type from the crossover weights. `include_leg` keeps LEG in the mix
## (crossovers may stay plain legs); mini-branches pass false (they only call this once they
## have already decided to host a special). CHALLENGE is offered only when the act-0 depth
## gate passes AND the act's single detour-challenge slot is unused; picking it consumes that
## slot. EVENT family eligibility is resolved later in _assign_special_payload.
func _roll_detour_type(node: MapNode, _run_state: Dictionary, include_leg: bool) -> MapNode.Type:
	var types: Array[MapNode.Type] = [MapNode.Type.SHOP, MapNode.Type.EVENT]
	var weights: Array[float] = [maxf(_cfg.crossover_weight_shop, 0.0), maxf(_cfg.crossover_weight_event, 0.0)]
	if include_leg:
		types.append(MapNode.Type.LEG)
		weights.append(maxf(_cfg.crossover_weight_leg, 0.0))
	if not _detour_challenge_used and _challenge_depth_ok(node):
		types.append(MapNode.Type.CHALLENGE)
		weights.append(maxf(_cfg.crossover_weight_challenge, 0.0))
	var total: float = 0.0
	for w: float in weights:
		total += w
	if total <= 0.0:
		return MapNode.Type.LEG
	var roll: float = _rng.randf() * total
	var acc: float = 0.0
	for i: int in range(types.size()):
		acc += weights[i]
		if roll < acc:
			if types[i] == MapNode.Type.CHALLENGE:
				_detour_challenge_used = true
			return types[i]
	return types[types.size() - 1]


## Act-0 challenges must sit at least challenge_act0_min_depth columns past the act entry —
## their target anchors on highest_cleared, meaningless until a few legs are cleared. Always
## true for acts ≥ 1 (no depth gate there).
func _challenge_depth_ok(node: MapNode) -> bool:
	if node.act != 0:
		return true
	return node.depth - _act_entry_depth >= _cfg.challenge_act0_min_depth


## Place mini-branch detours (round 2). Roll a count, then place at most one per lane on an
## outer render row. A branch forks off a lane node, runs parallel on the outer row, and
## rejoins THE SAME lane with an equal node count (a stay-vs-detour choice). Off-budget.
func _slot_branches(act: int, stretches: Array, run_state: Dictionary) -> void:
	if stretches.is_empty():
		return
	var want: int = maxi(_rng.randi_range(_cfg.branches_min, _cfg.branches_max), 0)
	# At most one branch per lane (only two lanes). want≥2 ⇒ both lanes; want==1 ⇒ a rolled
	# lane; want==0 ⇒ none. Lane order is fixed so the seed reproduces.
	var lanes_to_branch: Array[int] = []
	if want >= 2:
		lanes_to_branch = [0, 1]
	elif want == 1:
		lanes_to_branch = [_rng.randi_range(0, 1)]
	for lane: int in lanes_to_branch:
		_place_one_branch(act, stretches, lane, run_state)


## Try to place a single mini-branch off `lane`. Walks the stretches in a seeded-shuffled
## order and uses the first that can host one (run length ≥ branch_node_min + 2). A B-node
## branch forks off run[i] (depths i+1…i+B on the outer row) and rejoins run[i+B+1] of the
## same lane; B is clamped to the host stretch. Outer row: lane 0 detours ABOVE (lane −1),
## lane 1 detours BELOW (lane 2). Skips the lane if no stretch fits.
func _place_one_branch(act: int, stretches: Array, lane: int, run_state: Dictionary) -> void:
	var outer_lane: int = -1 if lane == 0 else 2
	var run_key: String = "run0" if lane == 0 else "run1"
	for si: int in _shuffled_indices(stretches.size()):
		var run: Array = stretches[si][run_key]
		var run_len: int = run.size()
		# A B-node branch needs a fork i and a rejoin i+B+1 inside [0, run_len-1] ⇒ run_len ≥ B+2.
		var max_b: int = mini(_cfg.branch_node_max, run_len - 2)
		if max_b < _cfg.branch_node_min:
			continue
		var b_len: int = _rng.randi_range(_cfg.branch_node_min, max_b)
		var fork_i: int = _rng.randi_range(0, run_len - 2 - b_len)   # i + b_len + 1 ≤ run_len-1
		var fork_id: int = run[fork_i]
		var rejoin_id: int = run[fork_i + b_len + 1]
		var fork_depth: int = (nodes[fork_id] as MapNode).depth
		var branch_ids: Array[int] = []
		for b: int in range(b_len):
			var bn: MapNode = _new_node(MapNode.Type.LEG, fork_depth + 1 + b, outer_lane, act)
			bn.is_branch = true
			branch_ids.append(bn.id)
		_connect(fork_id, branch_ids[0])
		for b: int in range(b_len - 1):
			_connect(branch_ids[b], branch_ids[b + 1])
		_connect(branch_ids[b_len - 1], rejoin_id)
		# Optional single special on the detour (off-budget). LEG excluded — we already rolled
		# to host one — so _roll_detour_type returns a special (or LEG only if weights vanish).
		if _rng.randf() < _cfg.branch_special_chance:
			var host: MapNode = nodes[branch_ids[_rng.randi_range(0, branch_ids.size() - 1)]]
			var t: MapNode.Type = _roll_detour_type(host, run_state, false)
			if t != MapNode.Type.LEG:
				_assign_special_payload(host, t, run_state)
		return   # one branch placed for this lane


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
	# Geometry is ALWAYS eligible: its trades are zero-sum board reshapes, and even a currently
	# inert option (e.g. Grow Red on a board with no red) is a legal build-around purchase, so it
	# needs no state gate (geometry spec §6). Roll the family off the COSMETIC sub-RNG so adding
	# it never perturbs the structural _rng stream (which would reshape the generated map).
	families.append(&"geometry")
	if _family_rng == null:
		_family_rng = RandomNumberGenerator.new()
		_family_rng.seed = _rng.seed ^ 0x9E3779B9  # read-only on _rng — doesn't consume its state.
	e.reward_family = families[_family_rng.randi_range(0, families.size() - 1)]
	return e


## Roll a challenge node's STABLE knobs (the ones independent of runtime progress):
## darts_per_turn (shown before deposit), the offered reward family, and an optional
## recycled benched-boss handicap. The target + deposit band are deferred to arrival
## (compute_challenge_params), since they anchor on the live highest_cleared. §5/§7/§8.
func _roll_challenge_node(rng: RandomNumberGenerator, cfg: MapGenConfig) -> ChallengeNode:
	var c: ChallengeNode = ChallengeNode.new()
	# darts-per-turn ∈ [dpt_min, dpt_max], the bust-grain shown up front (§5).
	c.darts_per_turn = rng.randi_range(c.dpt_min, c.dpt_max)
	# Offer one LADDERED family — the typed pick the player earns; rarity comes from
	# finish-efficiency at win time (§6). The earned surface only carries families that climb a
	# rarity ladder (generate at all three rarities): SCORING (Hotspot / Wedge Value) and, as of
	# the geometry spec §10, STREAK (Wedge / Color streaks — a capacity-gated climb, the natural
	# match for a race that proves repeatable precision). BRUSH and GEOMETRY are rarity-less
	# *trades* and live on the free event surface, not here; PLACEMENT was sidelined in §9a (its
	# only item, Wedge Swap, can't honor earned rarity). Challenge and event never share a family,
	# so there is no cross-surface rarity ceiling. STREAK has only two classes, so a streak draw
	# offers two distinct picks (Wedge + one Color) rather than three — the events-slice "offer
	# fewer" relaxation; the reward UI hides the unused card.
	var families: Array[ScoringEnums.Family] = [
		ScoringEnums.Family.SCORING,
		ScoringEnums.Family.STREAK,
	]
	c.reward_family = families[rng.randi_range(0, families.size() - 1)]
	# Optionally handicap the race with a recycled benched-boss aim effect (§8); empty
	# = a clean precision race. The handicap raises darts-used, nudging rarity down a
	# band on its own (§6/§8 implicit balancing).
	# The aim handicaps test precision (the §8 verb) without touching the dart economy:
	# rotation, narrow_double, and the §9b Parity Out pair (even_out / odd_out — the finishing
	# double must sit on a wedge whose CURRENT face value matches the parity; route-rewiring,
	# not the same checkout made harder). two_darts is excluded: it mutates darts_per_turn,
	# which would clobber the rolled dpt the player saw before wagering (§5) and is anyway
	# redundant with a dpt=2 roll. Its code stays benched.
	if rng.randf() < cfg.challenge_handicap_chance:
		var handicaps: Array[StringName] = [&"rotation", &"narrow_double", &"even_out", &"odd_out"]
		c.handicap_id = handicaps[rng.randi_range(0, handicaps.size() - 1)]
	return c


# ── Step 4: boss tier pairs + the depth→act maps (the pressure seam's context) ──

## Rebuild the depth→act span maps (so the public pressure seam stays callable — challenge
## pricing reads it) and assign each BOSS its fixed tier pair (act ceiling @ reference turns).
## Ordinary legs are NOT assigned here anymore: they carry target_score = 0 until drawn from the
## per-act lattice on arrival (draw_leg_from_frontier). Idempotent across incremental act gens.
func _assign_leg_params(level: LevelDefinition, cfg: MapGenConfig, _rng_unused: RandomNumberGenerator, starting_target: int, target_increment: int) -> void:
	# Capture the pressure-math context so the public seam functions stay callable
	# after generation (Phase 02 challenge pricing reads the same curve — §6).
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

	# Bosses: fixed at the act ceiling, reference turns — tier checkpoints, not drawn. The boss
	# sits ABOVE the drawable lattice (rows stop one increment below the ceiling), so it never
	# overlaps a drawable cell — no reservation needed. Ordinary legs are left at target 0.
	for id: int in nodes:
		var n: MapNode = nodes[id]
		if n.type == MapNode.Type.BOSS and n.target_score == 0:
			n.target_score = _act_ceiling(n.act, _max_target, _starting_target, _target_increment)
			n.max_turns = _reference_turns


# ── The leg lattice (2026-06-07) — build, frontier, cull, draw, resolve ──────

## Build one act's lattice cells (idempotent — incremental gen may re-enter). Rows = scores from
## act_floor up to act_ceiling − increment (the boss owns the ceiling, off-grid); columns = the
## 6/5/4 turn grid, except the lowest row which drops 6t ({5,4} — the pure turn-squeeze opener
## row). Cell pressure is depth-independent score/(turns·3). Only act 0's lowest-row loosest cell
## is the fixed opener the run auto-plays; acts 2/3 arrive from a boss, so every cell is drawable.
func _build_act_lattice(act: int) -> void:
	for c: Dictionary in _lattice_cells:
		if int(c["act"]) == act:
			return   # already built
	var floor_s: int = act_floor(act)
	var ceil_s: int = act_ceiling(act)
	var score: int = floor_s
	while score <= ceil_s - _target_increment:
		var is_lowest: bool = score == floor_s
		var columns: Array[int] = (LATTICE_TURNS.slice(1) if is_lowest else LATTICE_TURNS) as Array[int]
		for turns: int in columns:
			_lattice_cells.append({
				"act": act,
				"score": score,
				"turns": turns,
				"pressure": float(score) / float(turns * BASE_DARTS_PER_TURN),
				"drawn": false,
				"cleared": false,
				"culled": false,
				"is_opener": act == 0 and is_lowest and turns == columns[0],
			})
		score += _target_increment


## The loosest (highest) turn column present in a given row: 6t normally, 5t for the lowest row
## (act_floor), which drops the trivial 6t column.
func _row_loosest_turns(act: int, score: int) -> int:
	return LATTICE_TURNS[1] if score == act_floor(act) else LATTICE_TURNS[0]


## Find the cell for an exact (act, score, turns); empty Dictionary if none.
func _find_cell(act: int, score: int, turns: int) -> Dictionary:
	for c: Dictionary in _lattice_cells:
		if int(c["act"]) == act and int(c["score"]) == score and int(c["turns"]) == turns:
			return c
	return {}


## Find a cell by its (score, turns) pair across all acts; empty if none. Act windows are
## disjoint in score, so the pair is unique. Used to resolve a cleared leg's cell.
func _find_cell_by_pair(target: int, turns: int) -> Dictionary:
	for c: Dictionary in _lattice_cells:
		if int(c["score"]) == target and int(c["turns"]) == turns:
			return c
	return {}


## The unlock predecessor of a cell (empty = no predecessor, so unlocked from the start):
## the loosest cell of the row below for a row's loosest cell (the 6t→6t row chain), else the
## next-looser cell in the same row (the 6t→5t→4t column chain).
func _cell_predecessor(cell: Dictionary) -> Dictionary:
	var act: int = int(cell["act"])
	var score: int = int(cell["score"])
	var turns: int = int(cell["turns"])
	if turns == _row_loosest_turns(act, score):
		var below: int = score - _target_increment
		if below < act_floor(act):
			return {}   # bottom row — unlocked from the start
		return _find_cell(act, below, _row_loosest_turns(act, below))
	return _find_cell(act, score, turns + 1)   # one column looser, same row


## A cell is resolved (counts for unlocking its successors) once it is cleared OR culled.
func _cell_resolved(cell: Dictionary) -> bool:
	return bool(cell["cleared"]) or bool(cell["culled"])


## A cell is unlocked (eligible to draw, once also undrawn/uncleared/unculled) when its
## predecessor is resolved (or it has none).
func _cell_unlocked(cell: Dictionary) -> bool:
	var pred: Dictionary = _cell_predecessor(cell)
	if pred.is_empty():
		return true
	return _cell_resolved(pred)


## The current frontier for an act: unlocked ∧ undrawn ∧ uncleared ∧ unculled ∧ not the opener.
func _available_cells(act: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in _lattice_cells:
		if int(c["act"]) != act:
			continue
		if bool(c["drawn"]) or bool(c["cleared"]) or bool(c["culled"]) or bool(c["is_opener"]):
			continue
		if _cell_unlocked(c):
			out.append(c)
	return out


## The hardest CLEARED cell in an act (for the exhaustion fallback). Empty if none cleared.
func _hardest_cleared_cell(act: int) -> Dictionary:
	var best: Dictionary = {}
	for c: Dictionary in _lattice_cells:
		if int(c["act"]) == act and bool(c["cleared"]):
			if best.is_empty() or float(c["pressure"]) > float(best["pressure"]):
				best = c
	return best


## Public, read-only snapshot of an act's frontier — {score, turns, pressure} per available cell.
## For tests / UI; mutating the returned dicts does not touch lattice state.
func get_frontier(act: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in _available_cells(act):
		out.append({"score": int(c["score"]), "turns": int(c["turns"]), "pressure": float(c["pressure"])})
	return out


## Draw `node`'s (target, turns) from the live frontier on ARRIVAL — replaces the old
## roll-then-dodge. Uniform among eligible cells (the frontier is typically 2 — "tighten or
## climb"). On lattice exhaustion (a fast climb + long path can outrun it), repeat the act's
## hardest cleared pair. Bosses are skipped (they carry their reserved tier pair).
func draw_leg_from_frontier(node: MapNode) -> void:
	if node == null or node.type == MapNode.Type.BOSS:
		return
	if _lattice_rng == null:
		_lattice_rng = RandomNumberGenerator.new()
		_lattice_rng.seed = _rng.seed ^ 0x5A17710C   # dedicated stream — never perturb structure
	var act: int = node.act
	var eligible: Array[Dictionary] = _available_cells(act)
	if eligible.is_empty():
		# Exhaustion fallback (spec §3): repeat the hardest cleared pair — never an easier one.
		var hard: Dictionary = _hardest_cleared_cell(act)
		if not hard.is_empty():
			node.target_score = int(hard["score"])
			node.max_turns = int(hard["turns"])
		else:
			# Nothing cleared yet and nothing available (only reachable on a pathological empty
			# act before its first clear) — open at the act floor / reference turns, never strand.
			node.target_score = act_floor(act)
			node.max_turns = _reference_turns
		return
	var pick: Dictionary = eligible[_lattice_rng.randi_range(0, eligible.size() - 1)]
	pick["drawn"] = true
	node.target_score = int(pick["score"])
	node.max_turns = int(pick["turns"])


## Resolve a CLEARED leg: mark its lattice cell cleared, raise the act's cull threshold, and cull
## every undrawn cell at/below it (monotone difficulty, spec §2). Call on a leg WIN with the pair
## the leg was DRAWN at (not the bailout-extended live turns). A boss / challenge / off-lattice
## pair matches no cell → no-op, so it is safe to call broadly. Also marks act 0's auto-played
## opener at run start (record_leg_cleared(starting_target, reference_turns)).
func record_leg_cleared(target: int, turns: int) -> void:
	var cell: Dictionary = _find_cell_by_pair(target, turns)
	if cell.is_empty():
		return
	cell["cleared"] = true
	var act: int = int(cell["act"])
	var p: float = float(cell["pressure"])
	if not _act_cleared_pressure.has(act) or p > float(_act_cleared_pressure[act]):
		_act_cleared_pressure[act] = p
	_apply_cull(act)


## Cull every UNDRAWN cell in `act` whose pressure is at or below the act's highest cleared
## pressure — the monotone rule. Culled cells count as resolved, so a dead row still unlocks the
## climb above it. Lock status is irrelevant (the spec culls "any undrawn cell"); the opener is
## exempt. One pass suffices — culling never lowers the threshold.
func _apply_cull(act: int) -> void:
	if not _act_cleared_pressure.has(act):
		return
	var threshold: float = float(_act_cleared_pressure[act])
	for c: Dictionary in _lattice_cells:
		if int(c["act"]) != act:
			continue
		if bool(c["drawn"]) or bool(c["cleared"]) or bool(c["culled"]) or bool(c["is_opener"]):
			continue
		if float(c["pressure"]) <= threshold + 0.0001:
			c["culled"] = true


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

	var e: float = expected_per_dart(node.depth)

	# Affordability clamp (round 3 item 2): pull the TARGET down so the derived band's top
	# end (max ≈ reliable + cushion) lands ≤ c.max_deposit_cap. Clamping the target — not the
	# band — keeps deposit = wager = race budget achievable (§5); a squeezed band under a
	# too-high target would offer an unwinnable race. reliable_cap is the reliable-dart count
	# whose +cushion hits the cap; cap_target is the score that costs that many darts at this
	# depth, snapped DOWN (nearest-snap could round UP past the cap) and floored at the start.
	var reliable_cap: int = maxi(c.max_deposit_cap - c.deposit_cushion, 1)
	var cap_target: int = maxi(_snap_down(float(reliable_cap) * e, _starting_target, _target_increment), _starting_target)
	c.target_score = mini(c.target_score, cap_target)

	# Deposit band from the tuned curve (§4): reliable_darts = how many darts an average
	# run needs to clear this (clamped) target at THIS depth's build power (E rises with depth,
	# so an old number costs fewer darts now — "match concisely"). min = a lean precision
	# floor, max = a forgiving cushion. Both are raw-dart counts.
	var reliable: int = maxi(int(ceil(float(c.target_score) / maxf(e, 0.0001))), 1)
	# Lean end = reliable × lean_factor, but never below the bankable floor — and the
	# floor yields to the §4 contract min ≤ reliable when a cheap target makes reliable
	# itself smaller than the floor (a genuinely cheap challenge just has a small stake).
	var lean: int = maxi(int(round(float(reliable) * c.lean_factor)), c.min_deposit_floor)
	c.min_deposit = mini(lean, reliable)
	c.max_deposit = maxi(reliable + c.deposit_cushion, c.min_deposit)

	# Degenerate corner (early game — document, don't paper over): when cap_target bottomed
	# out at the lattice floor (_starting_target, kept checkout-legal) yet reliable(101) still
	# exceeds reliable_cap, the band blows past the cap. Net: clamp max to the cap and drop min
	# to the bankable floor so early challenges stay ENTERABLE (challenge_entry_view hard-blocks
	# entry when bank < min) and the rarity thirds don't collapse. This is the ONE place min may
	# sit below lean_factor × reliable — a lean ~5–12 wager against a ~15-reliable target is a
	# very lean race (chosen friction with a rare payoff), not a bug (Max 2026-06-06: act-0 small).
	if c.max_deposit > c.max_deposit_cap:
		c.max_deposit = c.max_deposit_cap
		c.min_deposit = mini(c.min_deposit_floor, c.max_deposit)


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


## Snap DOWN to the nearest legal X01 target at or below `value` (floor, not round). Used by
## the challenge affordability clamp where rounding UP would let max_deposit exceed the cap.
func _snap_down(value: float, starting_target: int, target_increment: int) -> int:
	var n: int = int(floor((value - float(starting_target)) / float(target_increment)))
	if n < 0:
		n = 0
	return starting_target + n * target_increment


# ── Step 5: validation (fail loud on a bad roll) ────────────────────────────

## Validate the graph generated SO FAR (incremental gen calls this after each act, so it
## must tolerate a partial run). The frontier sink is the most-recently generated boss;
## terminal_id is only asserted once every act is built. Load-bearing invariants: every
## special has a skip (same-depth sibling OR is_crossover), act-0 challenges respect the
## depth gate, ≤1 detour challenge per act, and the per-act node budget holds. Fail loud in
## debug so a bad roll never ships a skip-less map. §5 (round-2 topology).
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

	# Nodes-per-depth + per-act entry depth. A funnel (entry / pre-boss) or a crossover
	# interchange is the SOLE node at its depth; lane-run and branch nodes share their depth
	# with a sibling. A special's opt-out is therefore "same-depth sibling OR is_crossover"
	# (a crossover's straight lane edges are its built-in skip — round 2).
	var depth_count: Dictionary = {}
	var act_min_depth: Dictionary = {}   ## act -> shallowest depth (the act entry's column)
	for id: int in nodes:
		var nn: MapNode = nodes[id]
		depth_count[nn.depth] = depth_count.get(nn.depth, 0) + 1
		if not act_min_depth.has(nn.act) or nn.depth < act_min_depth[nn.act]:
			act_min_depth[nn.act] = nn.depth

	var per_act: Dictionary = {}
	var boss_per_act: Dictionary = {}
	var detour_challenges_per_act: Dictionary = {}
	for id: int in nodes:
		var n: MapNode = nodes[id]
		per_act[n.act] = per_act.get(n.act, 0) + 1
		if n.type == MapNode.Type.BOSS:
			boss_per_act[n.act] = boss_per_act.get(n.act, 0) + 1
		# A special needs an opt-out: a same-depth sibling (a live parallel run) OR it is a
		# crossover (its skip is the straight lane edges that pass it).
		var has_skip: bool = depth_count[n.depth] > 1 or n.is_crossover
		if n.type == MapNode.Type.SHOP or n.type == MapNode.Type.EVENT or n.type == MapNode.Type.CHALLENGE:
			assert(has_skip, "Special node %d sits on a chokepoint (no skip)" % n.id)
		if n.type == MapNode.Type.CHALLENGE:
			# Round 2 dropped the post-boss-1 gate — challenges may sit in any act — but an
			# act-0 challenge must be ≥ challenge_act0_min_depth columns past the act entry.
			if n.act == 0:
				assert(n.depth - int(act_min_depth[0]) >= _cfg.challenge_act0_min_depth,
					"Act-0 challenge %d too early (depth %d, entry %d, gate %d)" % [n.id, n.depth, int(act_min_depth[0]), _cfg.challenge_act0_min_depth])
			assert(has_skip, "Challenge node %d has no skip (Skip impossible)" % n.id)
			# Detour (crossover/branch) challenges are capped at one per act (no wager stacking).
			if n.is_crossover or n.is_branch:
				detour_challenges_per_act[n.act] = detour_challenges_per_act.get(n.act, 0) + 1
	for a: int in detour_challenges_per_act:
		assert(detour_challenges_per_act[a] <= 1, "Act %d has %d detour challenges (cap is 1)" % [a, detour_challenges_per_act[a]])
	# Per-act PLACED-node budget (round-2 formula; see MapGenConfig.act_node_budget_*).
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
