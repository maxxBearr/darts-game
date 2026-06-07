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
	# Round 2: challenges may sit in ANY act (the post-boss-1 gate was dropped). 501 (1 act)
	# now hosts act-0 challenges too, just not within the first challenge_act0_min_depth
	# columns; all three levels generate challenges.
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
	_test_challenge_family_rarities()
	_test_challenge_family_spread()
	_test_streak_supply_wrinkle()
	_test_parity_out_finish()
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


func _cfg_for(level: LevelDefinition) -> MapGenConfig:
	return level.map_gen_config if level.map_gen_config != null else MapGenConfig.new()


func _test_level(level: LevelDefinition) -> void:
	print("— Level %s (max %d, %d acts/bosses)" % [level.display_name, level.max_score_target, level.boss_count])
	var cfg: MapGenConfig = _cfg_for(level)
	var total_challenges: int = 0
	var band_samples: Array[String] = []
	# Round-3 item-2 cap accounting: how often the affordability clamp pulls the target down
	# (bound) vs leaves a cheap-enough config alone (passthrough) vs hits the degenerate corner.
	var cap_accum: Dictionary = {"bound": 0, "passthrough": 0, "degenerate": 0}
	for seed_value: int in range(SEEDS_PER_LEVEL):
		var g: MapGraph = _generate_full(level, seed_value)
		for id: int in g.nodes:
			var n: MapNode = g.get_node_by_id(id)
			if n.type != MapNode.Type.CHALLENGE:
				continue
			total_challenges += 1
			_test_placement(g, n, cfg, seed_value)
			# Compute params at a spread of plausible post-boss-1 highest_cleared values.
			for hc: int in _highest_cleared_samples(g, n):
				var prng: RandomNumberGenerator = RandomNumberGenerator.new()
				prng.seed = seed_value * 31 + hc
				g.compute_challenge_params(n, hc, prng)
				_test_anchor(g, n, hc, seed_value)
				_test_deposit_band(g, n, hc, seed_value)
				_test_deposit_cap(g, n, hc, seed_value, cap_accum)
				_test_dpt(n, seed_value)
				if band_samples.size() < 6:
					band_samples.append("d%d hc%d → T%d E%.0f rel%d dep[%d,%d] dpt%d" % [
						n.depth, hc, n.challenge.target_score, g.expected_per_dart(n.depth),
						_reliable(g, n), n.challenge.min_deposit, n.challenge.max_deposit, n.challenge.darts_per_turn])
	print("   challenge nodes seen across %d seeds: %d" % [SEEDS_PER_LEVEL, total_challenges])
	for s: String in band_samples:
		print("     %s" % s)
	print("   deposit cap: %d bound (target pulled down), %d passthrough, %d degenerate-corner" % [cap_accum["bound"], cap_accum["passthrough"], cap_accum["degenerate"]])
	# Round 2: every level (including 501) generates challenges now (act 0 included).
	_check(total_challenges > 0, "level generates at least some challenge nodes", -1)
	# Round-3 item 2: the cap must be neither inert (it pulls SOME targets down) nor
	# always-binding (cheap/deep configs pass through unclamped) — a default tuning value
	# can ship a feature inert, so assert the distribution, not just the bounds.
	_check(cap_accum["bound"] > 0, "deposit cap actually binds on some configs (not inert)", -1)
	_check(cap_accum["passthrough"] > 0, "deposit cap leaves cheap-enough configs unclamped (not always-binding)", -1)


## REALISTIC highest_cleared values for a node in act `a` at depth `d`. To stand on this
## node the player has cleared the previous act's boss (act_ceiling(a-1) — for act 1 that
## is the 501-tier boss-1), and has been clearing legs around the local power level, so
## their best cleared score sits in [prev_boss, baseline_target(d)]. Pairing a deep, high
## build-power node with an unrealistically low highest_cleared (e.g. 501 at act 2) is the
## case that can't occur in play, so we don't sample it. See §4's depth↔anchor coupling.
func _highest_cleared_samples(g: MapGraph, n: MapNode) -> Array[int]:
	var samples: Array[int] = []
	var prev_boss: int = g.act_ceiling(n.act - 1)     # cleared to enter this act (act_ceiling(-1)=101 for act 0)
	var local: int = maxi(g.baseline_target(n.depth), prev_boss)
	samples.append(prev_boss)
	# A real highest_cleared is always a cleared TARGET (101 + n·100), so keep the midpoint
	# sample ON the leg lattice — an off-lattice value (e.g. 251) never occurs in play and
	# would only exercise compute_challenge_params' clamp against an impossible input.
	var mid: int = 101 + int(round(float(prev_boss + (local - prev_boss) / 2 - 101) / 100.0)) * 100
	if mid > prev_boss:
		samples.append(mid)
	if local > mid:
		samples.append(local)
	return samples


func _reliable(g: MapGraph, n: MapNode) -> int:
	var e: float = g.expected_per_dart(n.depth)
	return maxi(int(ceil(float(n.challenge.target_score) / maxf(e, 0.0001))), 1)


# ── §13 placement ────────────────────────────────────────────────────────────

func _test_placement(g: MapGraph, n: MapNode, cfg: MapGenConfig, seed_value: int) -> void:
	_check(n.challenge != null, "challenge node carries a ChallengeNode resource", seed_value)
	# Round 2: the post-boss-1 hard gate is gone — challenges may sit in any act. An act-0
	# challenge must instead be ≥ challenge_act0_min_depth columns past the act-0 entry (the
	# highest_cleared anchor needs a few cleared legs to mean anything); later acts have no
	# depth gate.
	if n.act == 0:
		var entry_depth: int = 1 << 30
		for id: int in g.nodes:
			var o: MapNode = g.get_node_by_id(id)
			if o.act == 0:
				entry_depth = mini(entry_depth, o.depth)
		_check(n.depth - entry_depth >= cfg.challenge_act0_min_depth,
			"act-0 challenge respects depth gate (depth %d, entry %d, gate %d)" % [n.depth, entry_depth, cfg.challenge_act0_min_depth], seed_value)
	# The Skip path (§12) is the parallel run — a sibling node at the SAME depth in the other
	# lane — OR, for a typed-crossover challenge, the straight lane edges that pass it (a
	# crossover's built-in skip, round 2). Either way the player can route around the wager.
	var parallel_found: bool = n.is_crossover
	for id: int in g.nodes:
		var o: MapNode = g.get_node_by_id(id)
		if o.id != n.id and o.depth == n.depth:
			parallel_found = true
			break
	_check(parallel_found, "challenge has a skip (parallel run or crossover)", seed_value)


# ── §3 anchor ─────────────────────────────────────────────────────────────────

func _test_anchor(g: MapGraph, n: MapNode, hc: int, seed_value: int) -> void:
	var c: ChallengeNode = n.challenge
	_check(c.target_score <= hc, "target (%d) <= highest_cleared (%d)" % [c.target_score, hc], seed_value)
	# The anchor floor is hc - undercut, BUT the round-3 affordability cap (item 2) may
	# legitimately pull the target BELOW it — concise rematches of cheaper numbers — down to
	# the cap_target floor. So the real lower bound is min(anchor floor, cap_target).
	var floor_anchor: int = maxi(hc - c.target_undercut, 101)
	var reliable_cap: int = maxi(c.max_deposit_cap - c.deposit_cushion, 1)
	var cap_target: int = maxi(_snap_down_lattice(float(reliable_cap) * g.expected_per_dart(n.depth)), 101)
	var effective_floor: int = mini(floor_anchor, cap_target)
	_check(c.target_score >= effective_floor, "target (%d) >= effective floor (%d: anchor %d / cap %d)" % [c.target_score, effective_floor, floor_anchor, cap_target], seed_value)
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


# ── Round-3 item 2: deposit cap via target clamp ──────────────────────────────

## The affordability clamp (compute_challenge_params): max_deposit must ALWAYS stay ≤ the
## cap, the clamp must not be inert (some configs get their target pulled down) nor
## always-binding (cheap-enough configs pass through), and the degenerate corner — when even
## the lattice-floored target costs more than the cap allows — must yield exactly
## [min_deposit_floor, max_deposit_cap]. Re-derives the UNCAPPED anchor from the same seed
## the real compute call used, to tell "would have exceeded the cap" from "fit anyway".
func _test_deposit_cap(g: MapGraph, n: MapNode, hc: int, seed_value: int, accum: Dictionary) -> void:
	var c: ChallengeNode = n.challenge
	# (a) hard ceiling — never exceeded.
	_check(c.max_deposit <= c.max_deposit_cap, "max_deposit (%d) <= cap (%d)" % [c.max_deposit, c.max_deposit_cap], seed_value)
	# Reproduce the uncapped anchored target (same seed/window as the real compute call).
	var prng: RandomNumberGenerator = RandomNumberGenerator.new()
	prng.seed = seed_value * 31 + hc
	var lo_t: int = maxi(hc - c.target_undercut, 101)
	var hi_t: int = maxi(hc, lo_t)
	var raw: int = prng.randi_range(lo_t, hi_t)
	var anchored: int = clampi(_snap_nearest(raw), 101, hc)
	var e: float = g.expected_per_dart(n.depth)
	var uncapped_max: int = maxi(int(ceil(float(anchored) / maxf(e, 0.0001))), 1) + c.deposit_cushion
	if uncapped_max > c.max_deposit_cap:
		accum["bound"] += 1
		# The clamp engaged: target was pulled to ≤ the uncapped anchor.
		_check(c.target_score <= anchored, "capped target (%d) <= uncapped anchor (%d)" % [c.target_score, anchored], seed_value)
	else:
		accum["passthrough"] += 1
		# Cap inert here: the cheap-enough target passes through unchanged.
		_check(c.target_score == anchored, "uncapped-fit config passes target through (%d == %d)" % [c.target_score, anchored], seed_value)
	# (e) degenerate corner: if even the FINAL target's reliable+cushion still exceeds the cap,
	# the safety net must have produced exactly [min_deposit_floor (vs cap), max_deposit_cap].
	var reliable_final: int = maxi(int(ceil(float(c.target_score) / maxf(e, 0.0001))), 1)
	if reliable_final + c.deposit_cushion > c.max_deposit_cap:
		accum["degenerate"] += 1
		_check(c.max_deposit == c.max_deposit_cap, "degenerate band max == cap (%d)" % c.max_deposit, seed_value)
		_check(c.min_deposit == mini(c.min_deposit_floor, c.max_deposit_cap), "degenerate band min == bankable floor (%d)" % c.min_deposit, seed_value)


## Nearest-snap to the leg lattice (mirrors MapGraph._snap with starting 101 / increment 100).
func _snap_nearest(value: int) -> int:
	var k: int = int(round((float(value) - 101.0) / 100.0))
	if k < 0:
		k = 0
	return 101 + k * 100


## Snap DOWN to the leg lattice (mirrors MapGraph._snap_down) — the affordability cap_target.
func _snap_down_lattice(value: float) -> int:
	var k: int = int(floor((value - 101.0) / 100.0))
	if k < 0:
		k = 0
	return 101 + k * 100


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


# ── §9a regression: every challenge-draw family generates at all three rarities ──

## The bug (geometry spec §9a): a flat family whose only item ignored the requested rarity
## (Wedge Swap's generate() forced [100,0,0]) made the challenge channel's earned-rarity ladder
## structurally unfulfillable. Guard the STRUCTURE going forward: every family the challenge draw
## can roll must produce at least one pool item AT each of the three rarities (the same family ==
## sample.family + rarity_tier == rarity match _generate_challenge_reward_picks uses). The
## draw_families list mirrors map_graph._roll_challenge_node — keep them in sync. §10 added STREAK
## (both streak classes ladder 50/30/20, so they satisfy this as-is).
func _test_challenge_family_rarities() -> void:
	print("— §9a/§10 challenge-draw families generate at all three rarities")
	var draw_families: Array[ScoringEnums.Family] = [ScoringEnums.Family.SCORING, ScoringEnums.Family.STREAK]
	var rarities: Array[ScoringEnums.Rarity] = [
		ScoringEnums.Rarity.COMMON, ScoringEnums.Rarity.UNCOMMON, ScoringEnums.Rarity.RARE]
	for family: ScoringEnums.Family in draw_families:
		for rarity: ScoringEnums.Rarity in rarities:
			var found: bool = false
			for type in ModifierRegistry.MODIFIER_TYPES:
				var sample: ScoringModifier = type.generate(rarity)
				if sample != null and sample.family == family and sample.rarity_tier == rarity:
					found = true
					break
			_check(found, "family %d has a pool item honoring rarity %d" % [family, rarity], -1)
	# And the sidelined item is truly gone from the live pool (never rolled again).
	var placement_in_pool: bool = false
	for type in ModifierRegistry.MODIFIER_TYPES:
		var s: ScoringModifier = type.generate(ScoringEnums.Rarity.COMMON)
		if s != null and s.family == ScoringEnums.Family.PLACEMENT:
			placement_in_pool = true
	_check(not placement_in_pool, "PLACEMENT (Wedge Swap) is no longer in the live pool", -1)


# ── §10: streaks join the challenge draw (Family.STREAK) ──────────────────────

## Over the seed grid the challenge draw must roll BOTH [SCORING, STREAK] families with REAL
## spread — not just one occurrence of each (the [[feedback-rolled-generator-spread]] lesson: a
## family present once isn't proof the roll isn't pinned). With a uniform 2-way roll each family
## should claim a healthy share; assert each is at least a quarter of all challenge draws and that
## NOTHING off the list ever lands on the earned surface.
func _test_challenge_family_spread() -> void:
	print("— §10 challenge draw rolls SCORING and STREAK with spread")
	var level: LevelDefinition = load("res://resources/levels/level_1501.tres")   # 3 acts → most challenges
	var family_counts: Dictionary = {}
	var total: int = 0
	for seed_value: int in range(SEEDS_PER_LEVEL):
		var g: MapGraph = _generate_full(level, seed_value)
		for id: int in g.nodes:
			var n: MapNode = g.get_node_by_id(id)
			if n.type != MapNode.Type.CHALLENGE or n.challenge == null:
				continue
			var fam: int = n.challenge.reward_family
			family_counts[fam] = family_counts.get(fam, 0) + 1
			total += 1
	_check(total > 0, "challenge nodes exist to sample families from", -1)
	var scoring_n: int = family_counts.get(ScoringEnums.Family.SCORING, 0)
	var streak_n: int = family_counts.get(ScoringEnums.Family.STREAK, 0)
	# Membership: BOTH families appear.
	_check(scoring_n > 0, "challenge draw rolls SCORING (got %d)" % scoring_n, -1)
	_check(streak_n > 0, "challenge draw rolls STREAK (got %d)" % streak_n, -1)
	# Spread: each family is a real share of the draw, not a token single.
	_check(float(scoring_n) / float(total) >= 0.25, "SCORING is a real share (%d/%d)" % [scoring_n, total], -1)
	_check(float(streak_n) / float(total) >= 0.25, "STREAK is a real share (%d/%d)" % [streak_n, total], -1)
	# Purity: nothing off the [SCORING, STREAK] list ever lands on the earned challenge surface.
	for fam: int in family_counts:
		_check(fam == ScoringEnums.Family.SCORING or fam == ScoringEnums.Family.STREAK,
			"challenge family %d is on the [SCORING, STREAK] list" % fam, -1)
	print("   challenge family spread over %d seeds: SCORING=%d STREAK=%d (total %d)" % [SEEDS_PER_LEVEL, scoring_n, streak_n, total])


## The supply wrinkle (§10): STREAK has only two classes, so a family-pure draw offers TWO distinct
## picks (one Wedge + one Color), never padded from another family. Replicates the core of
## _generate_challenge_reward_picks (main.gd can't load headless — it references autoloads): keep
## the pool classes whose sample is STREAK and generate one instance of each.
func _test_streak_supply_wrinkle() -> void:
	print("— §10 STREAK supplies two distinct family-pure picks")
	var rarity: ScoringEnums.Rarity = ScoringEnums.Rarity.UNCOMMON
	var picks: Array[ScoringModifier] = []
	for type in ModifierRegistry.MODIFIER_TYPES:
		var sample: ScoringModifier = type.generate(rarity)
		if sample != null and sample.family == ScoringEnums.Family.STREAK:
			picks.append(type.generate(rarity))
	# Two streak classes → exactly two picks; every one family-pure STREAK (no off-family padding).
	_check(picks.size() == 2, "STREAK draw offers two picks (got %d)" % picks.size(), -1)
	for p: ScoringModifier in picks:
		_check(p.family == ScoringEnums.Family.STREAK, "every streak pick is family-pure STREAK", -1)
	# Distinct fingerprints at the fixed rarity, so the two cards never read as the same item (the
	# two classes differ by script path; Wedge's scope is rarity-fixed, Color carries its color).
	if picks.size() == 2:
		_check(picks[0].get_config_fingerprint() != picks[1].get_config_fingerprint(),
			"the two streak picks have distinct fingerprints", -1)


# ── §9b: Parity Out finish-validity (the out-rule seam, driven through the engine) ──

## The handicap halves the out-set by the finishing wedge's CURRENT face value parity. Drives the
## real x01_game finish-validity (which mirrors ScoringModifierManager._is_valid_finish): a
## matching-parity double checks out, a wrong-parity double busts, and the bull is always exempt.
func _test_parity_out_finish() -> void:
	print("— §9b Parity Out checkout restriction")
	# Even Out (parity 0): even-valued wedge doubles finish.
	var x01: Node = _make_x01()
	x01.checkout_parity = 0
	x01.start_leg_with(40, 5)
	var win: Dictionary = x01.process_throw({"total_score": 40, "ring_name": "Double", "face_value": 20, "is_bull": false})
	_check(win["is_leg_won"], "Even Out: D20 (even) checks out 40", -1)

	# Even Out: an odd-valued wedge double does NOT finish (and busts on the checkout attempt).
	var x02: Node = _make_x01()
	x02.checkout_parity = 0
	x02.start_leg_with(2, 5)
	var bust: Dictionary = x02.process_throw({"total_score": 2, "ring_name": "Double", "face_value": 1, "is_bull": false})
	_check(not bust["is_leg_won"], "Even Out: D1 (odd) does NOT check out 2", -1)
	_check(bust["is_bust"], "Even Out: a wrong-parity finish busts", -1)

	# Bull is exempt — 25 is odd, but D-Bull still outs under Even Out (keeps 50 finishable).
	var x03: Node = _make_x01()
	x03.checkout_parity = 0
	x03.start_leg_with(50, 5)
	var bullwin: Dictionary = x03.process_throw({"total_score": 50, "ring_name": "Double Bull", "face_value": 25, "is_bull": true})
	_check(bullwin["is_leg_won"], "Even Out: bull exempt — D-Bull checks out 50", -1)

	# Odd Out (parity 1): mirror.
	var x04: Node = _make_x01()
	x04.checkout_parity = 1
	x04.start_leg_with(38, 5)
	var oddwin: Dictionary = x04.process_throw({"total_score": 38, "ring_name": "Double", "face_value": 19, "is_bull": false})
	_check(oddwin["is_leg_won"], "Odd Out: D19 (odd) checks out 38", -1)

	var x05: Node = _make_x01()
	x05.checkout_parity = 1
	x05.start_leg_with(40, 5)
	var oddbust: Dictionary = x05.process_throw({"total_score": 40, "ring_name": "Double", "face_value": 20, "is_bull": false})
	_check(not oddbust["is_leg_won"], "Odd Out: D20 (even) does NOT check out 40", -1)

	# No restriction (default -1): any double outs, parity ignored.
	var x06: Node = _make_x01()
	x06.start_leg_with(40, 5)
	var normal: Dictionary = x06.process_throw({"total_score": 40, "ring_name": "Double", "face_value": 20, "is_bull": false})
	_check(normal["is_leg_won"], "No rule: D20 checks out 40 normally", -1)


func _check(condition: bool, label: String, seed_value: int) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL [%s] (seed %d)" % [label, seed_value])
		print("   FAIL [%s] (seed %d)" % [label, seed_value])
