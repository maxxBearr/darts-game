extends SceneTree
## Headless tests for the reward pool + §6 shop relic channel. RewardRegistry is a pure RefCounted
## (it only preloads the reward .tres resources), so it loads under --script once the reward
## script_classes are registered (run --import first). Covers:
##   §2 — extra_dart / extra_turn are GONE from ALL_REWARDS; the cut is clean.
##   §4 — the old "all_in" reward was retooled+renamed to "tunnel_vision".
##   §6 — shop_eligible tagging (utilities vs run-definers), eligible-pool filtering, the
##        unique-pulled-once-owned vs stackable-re-offered dedup, and the roll.
## Run:  godot --headless --script res://tests/test_rewards.gd  — exits non-zero on any failure.

const SHOP_ELIGIBLE: Array[StringName] = [&"lucky_eye", &"triple_outs", &"bigger_bull", &"pool_widener"]
const BOSS_ONLY: Array[StringName] = [&"glass_cannon", &"tunnel_vision", &"mirror_zone", &"relic_subscription"]

## Stand-in for the main node: RelicSubscriptionReward.apply() flips main._relic_shop_unlocked, so
## the run_state's "main" must be an Object carrying that property. main itself is a full scene
## Node2D with autoload deps — too heavy to instantiate under --script — so we use this stub.
class _MainStub:
	var _relic_shop_unlocked: bool = false

var _failures: int = 0
var _checks: int = 0
## A real x01_game node — TripleOutsReward.is_applicable reads x01_game.allow_triple_checkout, so
## the run_state every eligibility check sees must carry it (mirrors main._build_run_state). The
## script has no class_name + no autoload deps at construction, so .new() is safe under --script.
var _x01: Node = load("res://scripts/x01_game.gd").new()


func _init() -> void:
	_test_pool_membership()
	_test_shop_eligible_tags()
	_test_eligible_filtering()
	_test_dedup_and_stackable()
	_test_relic_subscription_gate()
	_x01.free()
	print("\nRewards test: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Build a run_state mirroring main._build_run_state (the fields reward is_applicable reads).
## boss_count defaults to 2 (a multi-boss level) so the Relic Subscription guard stays applicable
## unless a test explicitly drops it to 1 (the 501 dead-pick case).
func _run_state(active: Array, boss_count: int = 2) -> Dictionary:
	return {"active_rewards": active, "x01_game": _x01, "scoring_modifier_manager": _x01, "main": null, "boss_count": boss_count}


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  FAIL: %s" % label)


func _ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for r: RuleModifierReward in RewardRegistry.ALL_REWARDS:
		out.append(r.reward_id)
	return out


func _by_id(id: StringName) -> RuleModifierReward:
	for r: RuleModifierReward in RewardRegistry.ALL_REWARDS:
		if r.reward_id == id:
			return r
	return null


# ── §2 / §4 pool membership ──────────────────────────────────────────────────────

func _test_pool_membership() -> void:
	print("— Pool membership: extra_dart/extra_turn cut; all_in → tunnel_vision")
	var ids: Array[StringName] = _ids()
	_check(not (&"extra_dart" in ids), "extra_dart removed from ALL_REWARDS")
	_check(not (&"extra_turn" in ids), "extra_turn removed from ALL_REWARDS")
	_check(not (&"all_in" in ids), "old all_in id is gone (retooled)")
	_check(&"tunnel_vision" in ids, "tunnel_vision (suppress-accuracy relic) present")
	# Every reward exposes the new tags (loads cleanly with shop_eligible/stackable).
	for r: RuleModifierReward in RewardRegistry.ALL_REWARDS:
		_check(r.reward_id != &"", "reward has a non-empty id")


# ── §6 shop_eligible tags ────────────────────────────────────────────────────────

func _test_shop_eligible_tags() -> void:
	print("— shop_eligible: utilities true, run-definers false")
	for id: StringName in SHOP_ELIGIBLE:
		var r: RuleModifierReward = _by_id(id)
		_check(r != null and r.shop_eligible, "%s is shop_eligible" % id)
	for id: StringName in BOSS_ONLY:
		var r: RuleModifierReward = _by_id(id)
		_check(r != null and not r.shop_eligible, "%s stays boss-only (not shop_eligible)" % id)
	# Pool Widener is the stackable example (re-buyable for a +2 ceiling).
	var pw: RuleModifierReward = _by_id(&"pool_widener")
	_check(pw != null and pw.stackable, "pool_widener is stackable")


# ── §6 eligible-pool filtering + roll ────────────────────────────────────────────

func _test_eligible_filtering() -> void:
	print("— eligible_shop_relics: only utilities, never run-definers")
	var run_state: Dictionary = _run_state([])
	var pool: Array[RuleModifierReward] = RewardRegistry.eligible_shop_relics(run_state)
	_check(pool.size() == SHOP_ELIGIBLE.size(), "fresh run offers all %d utilities (got %d)" % [SHOP_ELIGIBLE.size(), pool.size()])
	for r: RuleModifierReward in pool:
		_check(r.shop_eligible, "%s in eligible pool is shop_eligible" % r.reward_id)
		_check(not (r.reward_id in BOSS_ONLY), "%s is not a run-definer" % r.reward_id)
	# The roll returns one of the eligible utilities.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var rolled: RuleModifierReward = RewardRegistry.roll_shop_relic(run_state, rng)
	_check(rolled != null and rolled.reward_id in SHOP_ELIGIBLE, "roll_shop_relic returns a utility relic")


func _test_dedup_and_stackable() -> void:
	print("— Owned dedup: uniques pulled once owned, stackable re-offered")
	# Own all four shop-eligible relics. The three uniques drop out; the stackable Pool Widener
	# stays (re-buyable), so the eligible pool is exactly [pool_widener].
	var owned: Array = []
	for id: StringName in SHOP_ELIGIBLE:
		owned.append(_by_id(id))
	var run_state: Dictionary = _run_state(owned)
	var pool: Array[RuleModifierReward] = RewardRegistry.eligible_shop_relics(run_state)
	_check(pool.size() == 1, "only the stackable relic remains once all owned (got %d)" % pool.size())
	if pool.size() == 1:
		_check(pool[0].reward_id == &"pool_widener", "the re-offered relic is pool_widener (stackable)")
	# A unique relic owned is no longer offerable on its own.
	var le: RuleModifierReward = _by_id(&"lucky_eye")
	_check(not le.is_applicable(_run_state([le])), "owned unique lucky_eye is no longer applicable")
	var pw: RuleModifierReward = _by_id(&"pool_widener")
	_check(pw.is_applicable(_run_state([pw])), "owned stackable pool_widener is still applicable")


# ── Relic Subscription gate (shop relic channel now opt-in) ────────────────────────

func _test_relic_subscription_gate() -> void:
	print("— Relic Subscription: gates the shop relic channel; boss-only, unique, 501-guarded")
	var sub: RuleModifierReward = _by_id(&"relic_subscription")
	_check(sub != null, "relic_subscription is registered in ALL_REWARDS")
	if sub == null:
		return

	# Boss-only: never appears on the shop relic spot it unlocks (chicken-and-egg).
	_check(not sub.shop_eligible, "relic_subscription is boss-only (not shop_eligible)")
	var eligible: Array[RuleModifierReward] = RewardRegistry.eligible_shop_relics(_run_state([]))
	_check(not (sub in eligible), "relic_subscription never appears in eligible_shop_relics")

	# Unique: once owned it drops out of the boss pick pool.
	_check(not sub.is_applicable(_run_state([sub])), "owned relic_subscription is no longer applicable")

	# 501 dead-pick guard: a single-boss level can never cash it in.
	_check(not sub.is_applicable(_run_state([], 1)), "relic_subscription inapplicable when boss_count <= 1")
	_check(sub.is_applicable(_run_state([], 2)), "relic_subscription applicable when boss_count > 1")

	# Gate: while the channel is locked the bull never lights, across many seeds.
	var run_state: Dictionary = _run_state([])
	var locked_lit: int = 0
	for s: int in range(200):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s
		if RewardRegistry.roll_gated_shop_relic(false, 0.40, run_state, rng) != null:
			locked_lit += 1
	_check(locked_lit == 0, "locked channel never lights the relic spot (got %d/200)" % locked_lit)

	# After unlock the spot lights at ~relic_spot_chance (0.40) across seeds.
	var unlocked_lit: int = 0
	var trials: int = 2000
	for s: int in range(trials):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = s
		if RewardRegistry.roll_gated_shop_relic(true, 0.40, run_state, rng) != null:
			unlocked_lit += 1
	var rate: float = float(unlocked_lit) / float(trials)
	_check(absf(rate - 0.40) < 0.05, "unlocked channel lights at ~0.40 (got %.3f over %d seeds)" % [rate, trials])

	# apply() flips the run's unlock flag on the (stub) main node.
	var stub: _MainStub = _MainStub.new()
	var apply_state: Dictionary = {"active_rewards": [], "x01_game": _x01, "scoring_modifier_manager": _x01, "main": stub, "boss_count": 2}
	_check(not stub._relic_shop_unlocked, "main starts with the relic channel locked")
	sub.apply(apply_state)
	_check(stub._relic_shop_unlocked, "relic_subscription.apply() unlocks the shop relic channel")
