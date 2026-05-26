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
