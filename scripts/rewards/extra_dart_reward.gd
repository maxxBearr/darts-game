class_name ExtraDartReward
extends RuleModifierReward
## +1 dart per turn for the rest of the run.


func apply(run_state: Dictionary) -> void:
	var x01: Node = run_state["x01_game"]
	x01.darts_per_turn += 1
