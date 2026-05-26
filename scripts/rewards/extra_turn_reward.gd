class_name ExtraTurnReward
extends RuleModifierReward
## +1 turn per leg for the rest of the run.


func apply(run_state: Dictionary) -> void:
	var x01: Node = run_state["x01_game"]
	x01.max_turns += 1
