class_name PoolWidenerReward
extends RuleModifierReward
## Shops show +1 option per pool for the rest of the run.


func apply(run_state: Dictionary) -> void:
	var main_node: Node2D = run_state["main"]
	main_node.shop_pick_count += 1
