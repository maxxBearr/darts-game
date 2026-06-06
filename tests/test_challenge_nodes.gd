extends SceneTree
## Headless unit test for Phase 02 challenge nodes (specs/map/02-challenge-nodes-impl.md §13).
## Exercises the generation/placement contract, the §3 anchor, the §4 deposit band
## against the LIVE pressure curve, the §5 dpt/ice-tray total-dart cap (driving the real
## x01_game engine), the §6 rarity bands, and the §11 bank conservation arithmetic.
## Run with:  godot --headless --script res://tests/test_challenge_nodes.gd
## Exits non-zero on any failure.

const SEEDS_PER_LEVEL := 200

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	# 501 = 1 act (no post-boss-1 space → no challenges, asserted in _test_placement).
	# 1001 / 1501 have act ≥ 1 forks that become challenges.
	var levels: Array[String] = [
		"res://resources/levels/level_501.tres",
		"res://resources/levels/level_1001.tres",
		"res://resources/levels/level_1501.tres",
	]
	for path: String in levels:
		var level: LevelDefinition = load(path)
		_test_level(level)
	_test_engine_legacy_budget()
	_test_engine_budget_cap()
	_test_engine_partial_final_turn()
	_test_engine_saved_darts_on_win()
	_test_rarity_bands_standalone()
	_test_ice_tray_standalone()
	print("\nChallengeNodes test: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Generate the WHOLE run incrementally (slice 3 §3.6): generate() seeds act 0, then one
## generate_next_act per later act so the post-boss-1 challenge nodes actually materialize.
func _generate_full(level: LevelDefinition, seed_value: int) -> MapGraph:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var g: MapGraph = MapGraph.generate(level, rng, 101, 100)
	for a: int in range(1, maxi(level.boss_count, 1)):
		g.generate_next_act({"available_brush_colors": [], "highest_cleared": 101})
	return g


func _test_level(level: LevelDefinition) -> void:
	print("— Level %s (max %d, %d acts/bosses)" % [level.display_name, level.max_score_target, level.boss_count])
	var total_challenges: int = 0
	var band_samples: Array[String] = []
	for seed_value: int in range(SEEDS_PER_LEVEL):
		var g: MapGraph = _generate_full(level, seed_value)
		for id: int in g.nodes:
			var n: MapNode = g.get_node_by_id(id)
			if n.type != MapNode.Type.CHALLENGE:
				continue
			total_challenges += 1
			_test_placement(g, n, seed_value)
			# Compute params at a spread of plausible post-boss-1 highest_cleared values.
			for hc: int in _highest_cleared_samples(g, n):
				var prng: RandomNumberGenerator = RandomNumberGenerator.new()
				prng.seed = seed_value * 31 + hc
				g.compute_challenge_params(n, hc, prng)
				_test_anchor(g, n, hc, seed_value)
				_test_deposit_band(g, n, hc, seed_value)
				_test_dpt(n, seed_value)
				if band_samples.size() < 6:
					band_samples.append("d%d hc%d → T%d E%.0f rel%d dep[%d,%d] dpt%d" % [
						n.depth, hc, n.challenge.target_score, g.expected_per_dart(n.depth),
						_reliable(g, n), n.challenge.min_deposit, n.challenge.max_deposit, n.challenge.darts_per_turn])
	print("   challenge nodes seen across %d seeds: %d" % [SEEDS_PER_LEVEL, total_challenges])
	for s: String in band_samples:
		print("     %s" % s)
	if level.boss_count == 1:
		_check(total_challenges == 0, "501 (1-act) generates NO challenge nodes (post-boss-1 only)", -1)
	else:
		_check(total_challenges > 0, "multi-act level generates at least some challenge nodes", -1)


## REALISTIC highest_cleared values for a node in act `a` at depth `d`. To stand on this
## node the player has cleared the previous act's boss (act_ceiling(a-1) — for act 1 that
## is the 501-tier boss-1), and has been clearing legs around the local power level, so
## their best cleared score sits in [prev_boss, baseline_target(d)]. Pairing a deep, high
## build-power node with an unrealistically low highest_cleared (e.g. 501 at act 2) is the
## case that can't occur in play, so we don't sample it. See §4's depth↔anchor coupling.
func _highest_cleared_samples(g: MapGraph, n: MapNode) -> Array[int]:
	var samples: Array[int] = []
	var prev_boss: int = g.act_ceiling(n.act - 1)     # cleared to enter this act (≥ 501)
	var local: int = maxi(g.baseline_target(n.depth), prev_boss)
	samples.append(prev_boss)
	var mid: int = prev_boss + (local - prev_boss) / 2
	if mid > prev_boss:
		samples.append(mid)
	if local > mid:
		samples.append(local)
	return samples


func _reliable(g: MapGraph, n: MapNode) -> int:
	var e: float = g.expected_per_dart(n.depth)
	return maxi(int(ceil(float(n.challenge.target_score) / maxf(e, 0.0001))), 1)


# ── §13 placement ────────────────────────────────────────────────────────────

func _test_placement(g: MapGraph, n: MapNode, seed_value: int) -> void:
	_check(n.act >= 1, "challenge is post-boss-1 (act >= 1)", seed_value)
	_check(n.challenge != null, "challenge node carries a ChallengeNode resource", seed_value)
	# Slice 3: a challenge sits INLINE in a branch run, so the Skip path (§12) is the
	# parallel run — a sibling node at the SAME depth in the other lane, bounded by the
	# same two chokepoints. A chokepoint is the sole node at its depth, so "another node
	# exists at this depth" both confirms the parallel run AND that this isn't a chokepoint.
	var parallel_found: bool = false
	for id: int in g.nodes:
		var o: MapNode = g.get_node_by_id(id)
		if o.id != n.id and o.depth == n.depth:
			parallel_found = true
			break
	_check(parallel_found, "challenge has a live parallel run at its depth (skip available)", seed_value)


# ── §3 anchor ─────────────────────────────────────────────────────────────────

func _test_anchor(g: MapGraph, n: MapNode, hc: int, seed_value: int) -> void:
	var c: ChallengeNode = n.challenge
	_check(c.target_score <= hc, "target (%d) <= highest_cleared (%d)" % [c.target_score, hc], seed_value)
	var floor_anchor: int = maxi(hc - c.target_undercut, 101)
	_check(c.target_score >= floor_anchor, "target (%d) >= anchor floor (%d)" % [c.target_score, floor_anchor], seed_value)
	# On the leg lattice (snapped to 100s, §15 decision).
	_check((c.target_score - 101) % 100 == 0, "target on leg lattice (101+n*100)", seed_value)


# ── §4 deposit band (against the live curve) ──────────────────────────────────

func _test_deposit_band(g: MapGraph, n: MapNode, hc: int, seed_value: int) -> void:
	var c: ChallengeNode = n.challenge
	var reliable: int = _reliable(g, n)
	# The §4 contract: min ≤ reliable ≤ max.
	_check(c.min_deposit <= reliable, "min_deposit (%d) <= reliable (%d)" % [c.min_deposit, reliable], seed_value)
	_check(reliable <= c.max_deposit, "reliable (%d) <= max_deposit (%d)" % [reliable, c.max_deposit], seed_value)
	# The floor is honored unless reliable itself is below it (then the contract wins).
	_check(c.min_deposit >= mini(c.min_deposit_floor, reliable),
		"min_deposit (%d) >= min(floor, reliable)" % c.min_deposit, seed_value)
	_check(c.min_deposit >= 1, "min_deposit is a positive bankable stake", seed_value)
	_check(c.min_deposit <= c.max_deposit, "min_deposit <= max_deposit", seed_value)
	# Sanity ceiling: under realistic play the band stays in a tight range — never an
	# absurd reserve. (Spec §4 quotes ~6–13 with T near the low end; with T able to roll
	# up to highest_cleared the top runs a little higher, but stays modest.)
	_check(c.max_deposit <= 18, "max_deposit (%d) within sane ceiling (<=18)" % c.max_deposit, seed_value)


# ── §5 dpt + ice-tray ─────────────────────────────────────────────────────────

func _test_dpt(n: MapNode, seed_value: int) -> void:
	var c: ChallengeNode = n.challenge
	_check(c.darts_per_turn >= c.dpt_min and c.darts_per_turn <= c.dpt_max,
		"dpt (%d) in [%d,%d]" % [c.darts_per_turn, c.dpt_min, c.dpt_max], seed_value)
	# Ice-tray: rows sum back to the deposit; every row ≤ dpt; only the last may be partial.
	for deposit: int in range(c.min_deposit, c.max_deposit + 1):
		var rows: Array[int] = c.ice_tray_rows(deposit)
		var sum: int = 0
		for i: int in range(rows.size()):
			sum += rows[i]
			var is_last: bool = i == rows.size() - 1
			if is_last:
				_check(rows[i] >= 1 and rows[i] <= c.darts_per_turn, "last ice-tray row in [1,dpt]", seed_value)
			else:
				_check(rows[i] == c.darts_per_turn, "non-final ice-tray row == dpt", seed_value)
		_check(sum == deposit, "ice-tray rows sum to deposit %d" % deposit, seed_value)


# ── §6 rarity bands (standalone) ──────────────────────────────────────────────

func _test_rarity_bands_standalone() -> void:
	print("— Rarity bands (§6)")
	var c: ChallengeNode = ChallengeNode.new()
	c.min_deposit = 6
	c.max_deposit = 12
	# Partition with no gap/overlap: every used in [min, max] maps to exactly one band,
	# lean ⇒ rare, top ⇒ common, and the bands are monotone (rare ≤ uncommon ≤ common cuts).
	var last_rank: int = -1
	for used: int in range(c.min_deposit, c.max_deposit + 1):
		var r: ScoringEnums.Rarity = c.rarity_for_used(used)
		var rank: int = _rarity_rank(r)  # rare=0, uncommon=1, common=2 (worse as used grows)
		_check(rank >= last_rank, "rarity monotone non-decreasing in used (used %d)" % used, -1)
		last_rank = rank
	_check(c.rarity_for_used(c.min_deposit) == ScoringEnums.Rarity.RARE, "leanest used ⇒ RARE", -1)
	_check(c.rarity_for_used(c.max_deposit) == ScoringEnums.Rarity.COMMON, "fattest used ⇒ COMMON", -1)


func _rarity_rank(r: ScoringEnums.Rarity) -> int:
	match r:
		ScoringEnums.Rarity.RARE: return 0
		ScoringEnums.Rarity.UNCOMMON: return 1
		_: return 2


func _test_ice_tray_standalone() -> void:
	print("— Ice-tray decomposition (§5)")
	var c: ChallengeNode = ChallengeNode.new()
	c.darts_per_turn = 2
	_check(c.ice_tray_rows(7) == ([2, 2, 2, 1] as Array[int]), "deposit 7 dpt 2 → [2,2,2,1]", -1)
	c.darts_per_turn = 5
	_check(c.ice_tray_rows(11) == ([5, 5, 1] as Array[int]), "deposit 11 dpt 5 → [5,5,1]", -1)
	c.darts_per_turn = 3
	_check(c.ice_tray_rows(9) == ([3, 3, 3] as Array[int]), "deposit 9 dpt 3 → [3,3,3]", -1)


# ── §9 engine: total-dart cap drives the real x01_game ────────────────────────

func _make_x01() -> Node:
	var x01_script: GDScript = load("res://scripts/x01_game.gd")
	return x01_script.new() as Node


## A miss (no checkout). The engine doesn't validate that total_score matches the ring.
func _miss(score: int = 0) -> Dictionary:
	return {"total_score": score, "ring_name": "Outer Single"}


## Drive a full challenge race of nothing-but-misses and return darts thrown until the
## engine reports game over (the race-lost signal). Mirrors main.gd's turn advancing.
func _run_until_over(x01: Node) -> int:
	var thrown: int = 0
	var guard: int = 0
	while guard < 500:
		guard += 1
		var resp: Dictionary = x01.process_throw(_miss())
		thrown += 1
		if resp["is_game_over"]:
			return thrown
		if resp["is_turn_over"]:
			x01.end_turn()
			x01.start_turn()
	return thrown


func _test_engine_legacy_budget() -> void:
	print("— Engine legacy budget unchanged (regression guard, §9)")
	var x01: Node = _make_x01()
	# A normal leg: dart_budget stays 0, budget = max_turns × darts_per_turn = 5 × 3 = 15.
	x01.start_leg_with(301, 5)
	_check(x01.dart_budget == 0, "normal leg keeps dart_budget == 0 (legacy mode)", -1)
	var thrown: int = _run_until_over(x01)
	_check(thrown == 15, "legacy leg of misses ends after max_turns×dpt = 15 darts (got %d)" % thrown, -1)
	# Saved-darts parity: a fresh leg with no throws would save the whole budget.
	var x02: Node = _make_x01()
	x02.start_leg_with(301, 5)
	_check(x02.get_saved_darts() == 15, "legacy get_saved_darts == full budget before any throw", -1)


func _test_engine_budget_cap() -> void:
	print("— Engine total-dart cap (§9)")
	var x01: Node = _make_x01()
	# Deposit 7, dpt 2 → ice-tray [2,2,2,1]; max_turns = ceil(7/2) = 4.
	x01.start_challenge_race(901, 2, 7)
	_check(x01.dart_budget == 7, "dart_budget set to deposit (7)", -1)
	_check(x01.darts_per_turn == 2, "darts_per_turn override applied (2)", -1)
	_check(x01.max_turns == 4, "max_turns == ice-tray row count ceil(7/2)=4", -1)
	var thrown: int = _run_until_over(x01)
	_check(thrown == 7, "race of misses ends after exactly the deposit (7) darts (got %d)" % thrown, -1)
	_check(x01.darts_used_in_leg == 7, "darts_used_in_leg == budget at loss (got %d)" % x01.darts_used_in_leg, -1)


func _test_engine_partial_final_turn() -> void:
	# The final ice-tray row is partial: deposit 7 dpt 2 → the 7th dart is the only dart
	# of turn 4, after which the budget is exhausted and the race ends.
	var x01: Node = _make_x01()
	x01.start_challenge_race(901, 2, 7)
	var resp: Dictionary = {}
	for _i: int in range(6):  # two full turns of 2 + one full turn of 2 = 6 darts, turns 1-3
		resp = x01.process_throw(_miss())
		if resp["is_turn_over"]:
			x01.end_turn()
			x01.start_turn()
	_check(x01.current_turn == 4, "reached the partial final turn (turn 4)", -1)
	resp = x01.process_throw(_miss())  # the single dart of the partial row
	_check(x01.darts_this_turn == 1, "partial final turn holds exactly 1 dart", -1)
	_check(resp["is_turn_over"], "partial final turn ends after its 1 dart", -1)
	_check(resp["is_game_over"], "budget exhausted on partial final turn ⇒ race over", -1)


func _test_engine_saved_darts_on_win() -> void:
	print("— Engine get_saved_darts on a won race (§11)")
	var x01: Node = _make_x01()
	# Deposit 9, dpt 3. Win on the 3rd dart → 6 unused darts return to the bank.
	x01.start_challenge_race(104, 3, 9)
	x01.process_throw({"total_score": 60, "ring_name": "Triple"})    # rem 44
	x01.process_throw({"total_score": 40, "ring_name": "Outer Single"})  # rem 4
	var resp: Dictionary = x01.process_throw({"total_score": 4, "ring_name": "Double"})  # rem 0, valid finish
	_check(resp["is_leg_won"], "challenge race won on the checkout double", -1)
	_check(x01.darts_used_in_leg == 3, "darts_used == 3 on a 3-dart finish (got %d)" % x01.darts_used_in_leg, -1)
	_check(x01.get_saved_darts() == 6, "get_saved_darts == budget(9) - used(3) = 6 (got %d)" % x01.get_saved_darts(), -1)
	# Bank conservation identity (§11): win banks (deposit - used); net bank delta = -used.
	var bank: int = 50
	var deposit: int = 9
	bank -= deposit                       # withheld for the race
	bank += x01.get_saved_darts()         # unused returned on win
	_check(bank == 50 - x01.darts_used_in_leg, "win: net bank delta == -darts_used (lean win banks more)", -1)


func _check(condition: bool, label: String, seed_value: int) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL [%s] (seed %d)" % [label, seed_value])
		print("   FAIL [%s] (seed %d)" % [label, seed_value])
