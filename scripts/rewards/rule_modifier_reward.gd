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

## Whether multiple copies of this reward can be picked in one run. For the §6 shop relic channel
## this decides REPEAT offers: a stackable relic is re-offered after purchase, a unique one drops
## out of the pool once owned (is_applicable returns false). Orthogonal to shop_eligible.
@export var stackable: bool = false

## §6: whether this relic can appear on the gold RELIC spot in the shop. true = an incremental
## UTILITY relic the player chose to fish for (Lucky Eye, Triple Outs, Bigger Bull, Pool Widener);
## false = a run-DEFINER that stays an earned boss prize (Glass Cannon, Tunnel Vision, Mirror Zone).
## The cut is run-definer vs utility, NOT unique-vs-stackable — a unique relic is perfectly
## shop-able (you buy it once and it leaves the pool via the owned-dedup is_applicable runs).
@export var shop_eligible: bool = false

## Whether this is a trade (has a downside). Affects card styling.
@export var is_trade: bool = false

## reward_ids that make this reward ineligible — if the player already owns any
## reward whose reward_id is listed here, this one is excluded from the pick pool.
## Declared on both sides of a mutually-exclusive pair so the exclusion is symmetric
## regardless of pick order (e.g. glass_cannon <-> mirror_zone). No swap is offered;
## owning either simply removes the other.
@export var excludes: Array[StringName] = []


## Apply this reward's effect to the run state.
## run_state contains: "x01_game", "scoring_modifier_manager", "main", "active_rewards".
func apply(_run_state: Dictionary) -> void:
	pass


## How many wedges the player must pick to flip after acquiring this reward.
## 0 means no post-acquisition picker. Overridden by MirrorZoneReward to grant
## the two flipped wedges its mechanic depends on.
func wedge_flips_granted() -> int:
	return 0


## Check if this reward would have any effect given the current run state.
## Return false to exclude from the pick pool.
func is_applicable(run_state: Dictionary) -> bool:
	var active: Array = run_state.get("active_rewards", [])
	for r: Resource in active:
		if not (r is RuleModifierReward):
			continue
		# Already owned (and not stackable) — don't offer a duplicate.
		if not stackable and r.reward_id == reward_id:
			return false
		# Mutually-exclusive with something already owned.
		if r.reward_id in excludes:
			return false
	return true
