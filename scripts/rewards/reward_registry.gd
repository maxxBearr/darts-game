class_name RewardRegistry
extends RefCounted
## Pool of all boss rewards. Handles filtering and random selection.

static var ALL_REWARDS: Array[RuleModifierReward] = [
	preload("res://resources/rewards/extra_dart.tres"),
	preload("res://resources/rewards/extra_turn.tres"),
	preload("res://resources/rewards/streak_slot_extension.tres"),
	preload("res://resources/rewards/lucky_eye.tres"),
	preload("res://resources/rewards/pool_widener.tres"),
	preload("res://resources/rewards/frequent_shopping.tres"),
	preload("res://resources/rewards/triple_outs.tres"),
	preload("res://resources/rewards/glass_cannon.tres"),
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
