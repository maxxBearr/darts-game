class_name GlassCannonReward
extends RuleModifierReward
## Trade: any dart landing exactly at 0 wins the leg (any ring).
## In exchange, any bust immediately ends the run.


func apply(run_state: Dictionary) -> void:
	var x01: Node = run_state["x01_game"]
	x01.glass_cannon_active = true
	x01.allow_triple_checkout = true
	var smm: Node = run_state["scoring_modifier_manager"]
	smm.glass_cannon_active = true
	smm.allow_triple_checkout = true


func is_applicable(run_state: Dictionary) -> bool:
	if not super.is_applicable(run_state):
		return false
	# Inventory-gated exclusion with the Mirror-Zone relic (no swap option).
	var active: Array = run_state.get("active_rewards", [])
	for r: Resource in active:
		if r is RuleModifierReward and r.reward_id == &"mirror_zone":
			return false
	return true
