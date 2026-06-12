class_name RewardRegistry
extends RefCounted
## Pool of all boss rewards. Handles filtering and random selection.

# streak_slot_extension was removed: streak-slot capacity is now sourced solely from the
# equipped components (per-category), so a run-wide +1 reward is moot.
static var ALL_REWARDS: Array[RuleModifierReward] = [
	# extra_dart / extra_turn were CUT (reward-cleanup spec §2): both mutated knobs the map now
	# OWNS (darts_per_turn is baked into bailout cost / streak cadence / the 3-dart assumption;
	# max_turns is set per-leg by the leg lattice, so a run-wide +1 desyncs the generator's
	# pressure math). +turn was doubly redundant — the bank already buys turns via bailout.
	preload("res://resources/rewards/lucky_eye.tres"),
	preload("res://resources/rewards/pool_widener.tres"),
	# Frequent Shopping pulled from the pool 2026-06-04: it only mutates `shop_cadence`,
	# which no longer schedules anything now that shops are map nodes (Phase 01 substrate).
	# Re-point it at the map's shop mix and re-add when that wiring exists (Phase 03/04).
	# preload("res://resources/rewards/frequent_shopping.tres"),
	preload("res://resources/rewards/triple_outs.tres"),
	preload("res://resources/rewards/glass_cannon.tres"),
	preload("res://resources/rewards/tunnel_vision.tres"),
	preload("res://resources/rewards/mirror_zone.tres"),
	# Bigger Bull — the sanctioned flat for the bull (no other upgrade path); grows both bull
	# radii into the inner single. Outside the geometry family/pool (earned-flat tier).
	preload("res://resources/rewards/bigger_bull.tres"),
	# Relic Subscription — boss-only unlock that opens the §6 shop relic channel for the rest of
	# the run. Until owned, the gold bull spot never lights (relics stay earned/premium). Itself
	# can't live in the relic shop it unlocks (shop_eligible == false; chicken-and-egg).
	preload("res://resources/rewards/relic_subscription.tres"),
]


## All shop-eligible relics currently offerable (§6): shop_eligible AND applicable. is_applicable
## already drops a unique relic once owned and respects excludes; a stackable one stays. The
## run-definers (shop_eligible == false) never appear here — they stay earned boss prizes.
static func eligible_shop_relics(run_state: Dictionary) -> Array[RuleModifierReward]:
	var out: Array[RuleModifierReward] = []
	for r: RuleModifierReward in ALL_REWARDS:
		if r.shop_eligible and r.is_applicable(run_state):
			out.append(r)
	return out


## Pick one random shop-eligible relic for the gold bull spot, or null when the eligible pool is
## exhausted (every utility relic owned) — in which case the bull stays dark (§6 fallback).
static func roll_shop_relic(run_state: Dictionary, rng: RandomNumberGenerator) -> RuleModifierReward:
	var pool: Array[RuleModifierReward] = eligible_shop_relics(run_state)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## §6 (gated): decide the relic for a shop's gold bull spot, honoring the run's unlock gate. The
## channel is opt-in — `unlocked` is main._relic_shop_unlocked, flipped on by the Relic Subscription
## boss reward. Returns null (bull stays dark) when the channel is LOCKED, when the chance roll
## misses, or when the eligible pool is exhausted. Pure + seeded so the gate is headless-testable;
## main._roll_shop_relic_spot wraps it with the dartboard wiring.
static func roll_gated_shop_relic(unlocked: bool, chance: float, run_state: Dictionary, rng: RandomNumberGenerator) -> RuleModifierReward:
	if not unlocked:
		return null
	if rng.randf() >= chance:
		return null
	return roll_shop_relic(run_state, rng)


## Generate N distinct applicable rewards from the pool.
static func generate_picks(count: int, run_state: Dictionary) -> Array[RuleModifierReward]:
	var applicable: Array[RuleModifierReward] = []
	for r: RuleModifierReward in ALL_REWARDS:
		if r.is_applicable(run_state):
			applicable.append(r)
	applicable.shuffle()
	var result: Array[RuleModifierReward] = []
	for i: int in range(mini(count, applicable.size())):
		result.append(applicable[i])
	return result
