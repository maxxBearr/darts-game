class_name StreakSlotExtensionReward
extends RuleModifierReward
## +1 additional streak slot for the rest of the run.


func apply(run_state: Dictionary) -> void:
	var smm: Node = run_state["scoring_modifier_manager"]
	smm.max_streak_slots += 1
