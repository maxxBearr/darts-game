class_name RuleModifierReward
extends Resource
## Base class for boss rewards — durable, run-wide rule tweaks.
## Subclass this and override apply() and is_applicable().

## Unique stable identifier for this reward.
@export var reward_id: StringName

## Display name shown on the reward pick card.
@export var display_name: String = ""

## One-line description of the effect.
@export var description: String = ""

## Whether multiple copies of this reward can be picked in one run.
@export var stackable: bool = false

## Whether this is a trade (has a downside). Affects card styling.
@export var is_trade: bool = false


## Apply this reward's effect to the run state.
## run_state contains: "x01_game", "scoring_modifier_manager", "main", "active_rewards".
func apply(_run_state: Dictionary) -> void:
	pass


## Check if this reward would have any effect given the current run state.
## Return false to exclude from the pick pool.
func is_applicable(run_state: Dictionary) -> bool:
	if not stackable:
		var active: Array = run_state.get("active_rewards", [])
		for r: Resource in active:
			if r is RuleModifierReward and r.reward_id == reward_id:
				return false
	return true
