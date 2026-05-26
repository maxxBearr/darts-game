class_name LuckyEyeReward
extends RuleModifierReward
## +2% rare modifier roll chance for the rest of the run.
## Applied via ModifierRegistry.current_rarity_shift.


func apply(_run_state: Dictionary) -> void:
	ModifierRegistry.current_rarity_shift += 0.02
