class_name FrequentShoppingReward
extends RuleModifierReward
## Shops appear every 2 legs instead of every 3.


func apply(run_state: Dictionary) -> void:
	var main_node: Node2D = run_state["main"]
	main_node.shop_cadence = 2


func is_applicable(run_state: Dictionary) -> bool:
	if not super.is_applicable(run_state):
		return false
	var main_node: Node2D = run_state["main"]
	return main_node.shop_cadence > 2
