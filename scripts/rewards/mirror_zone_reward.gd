class_name MirrorZoneReward
extends RuleModifierReward
## Boss relic: busting no longer ends your turn. A would-be-bust (overshoot below 0)
## keeps the negative remainder and lets the player keep throwing. The relic always
## grants two flipped wedges (via the post-acquisition picker) — the only way to climb
## back up from below — so the negative zone is never a soft-lock.
##
## Mutually exclusive with Glass Cannon: Glass Cannon makes any bust end the run, this
## makes busts not end the turn. Owning either removes the other from boss reward pools.


func apply(run_state: Dictionary) -> void:
	var x01: Node = run_state["x01_game"]
	x01.bust_ends_turn = false


## Player picks two wedges to flip after acquiring this relic. Load-bearing: without a
## flipped wedge, negative points can never move the player back toward 0.
func wedge_flips_granted() -> int:
	return 2

# Mutual exclusion with Glass Cannon is declarative — see the `excludes` array on both
# mirror_zone.tres and glass_cannon.tres, enforced by the base is_applicable().
