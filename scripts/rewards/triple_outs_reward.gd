class_name TripleOutsReward
extends RuleModifierReward
## Allows checking out on triples in addition to doubles.


func apply(run_state: Dictionary) -> void:
	var x01: Node = run_state["x01_game"]
	x01.allow_triple_checkout = true
	var smm: Node = run_state["scoring_modifier_manager"]
	smm.allow_triple_checkout = true


func is_applicable(run_state: Dictionary) -> bool:
	if not super.is_applicable(run_state):
		return false
	# Glass Cannon supersedes Triple Outs
	var active: Array = run_state.get("active_rewards", [])
	for r: Resource in active:
		if r is RuleModifierReward and r.reward_id == &"glass_cannon":
			return false
	var x01: Node = run_state["x01_game"]
	return not x01.allow_triple_checkout
