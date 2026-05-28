class_name AllInReward
extends RuleModifierReward
## Trade: shops only offer modifiers — no more accuracy upgrades.


func apply(run_state: Dictionary) -> void:
	var main_node: Node2D = run_state["main"]
	main_node.all_in_active = true
