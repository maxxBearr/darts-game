class_name RewardRegistry
extends RefCounted
## Pool of all boss rewards. Handles filtering and random selection.

# streak_slot_extension was removed: streak-slot capacity is now sourced solely from the
# equipped components (per-category), so a run-wide +1 reward is moot.
static var ALL_REWARDS: Array[RuleModifierReward] = [
	preload("res://resources/rewards/extra_dart.tres"),
	preload("res://resources/rewards/extra_turn.tres"),
	preload("res://resources/rewards/lucky_eye.tres"),
	preload("res://resources/rewards/pool_widener.tres"),
	# Frequent Shopping pulled from the pool 2026-06-04: it only mutates `shop_cadence`,
	# which no longer schedules anything now that shops are map nodes (Phase 01 substrate).
	# Re-point it at the map's shop mix and re-add when that wiring exists (Phase 03/04).
	# preload("res://resources/rewards/frequent_shopping.tres"),
	preload("res://resources/rewards/triple_outs.tres"),
	preload("res://resources/rewards/glass_cannon.tres"),
	preload("res://resources/rewards/all_in.tres"),
	preload("res://resources/rewards/mirror_zone.tres"),
	# Bigger Bull — the sanctioned flat for the bull (no other upgrade path); grows both bull
	# radii into the inner single. Outside the geometry family/pool (earned-flat tier).
	preload("res://resources/rewards/bigger_bull.tres"),
]


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
