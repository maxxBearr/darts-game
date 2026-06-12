class_name PoolWidenerReward
extends RuleModifierReward
## Relic (§5, retooled): +1 option on EVERY choice surface for the rest of the run — shop spots,
## events, and challenge rewards (the per-leg upgrade drip was retired in 03 §5b). A single
## run-scoped lever (main.option_bonus) so one relic widens every surface uniformly, instead of the
## old muddy shop_pick_count bump that only some paths read. Shop-eligible + stackable (§6): a
## second copy buys a +2 ceiling (the card UI renders up to 4 — base 3 events + one widener).


func apply(run_state: Dictionary) -> void:
	var main_node: Node2D = run_state["main"]
	main_node.option_bonus += 1
