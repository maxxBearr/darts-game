class_name BiggerBullReward
extends RuleModifierReward
## Boss-reward relic (OUTSIDE the geometry family + pool — the sanctioned flat). Bull has no other
## upgrade path, and boss rewards are the existing premium-flat channel (Glass Cannon's shelf).
## On acquire it grows both bull radii into the inner single; the inner single pays (conservation
## holds, but it's low-value real estate — which is why this is earned-flat tier, not a pool item).
##
## It touches ScoringModifierManager.bull_radii (the only mover of bull radii) and then recomputes
## the geometry so the inner single re-pays the space. One-time acquire, no stack (standard reward
## semantics; not stackable).

## New double-bull outer radius after acquire (~+50% from the base 0.032). Hover-tunable.
@export var double_bull_radius: float = 0.048

## New single-bull outer radius after acquire (~+50% from the base 0.080). Hover-tunable.
@export var single_bull_radius: float = 0.112


func apply(run_state: Dictionary) -> void:
	var smm: Node = run_state["scoring_modifier_manager"]
	smm.bull_radii = {"single_bull": single_bull_radius, "double_bull": double_bull_radius}
	# Rebuild geometry so the inner single re-pays the space the bull took (and the board re-flows).
	smm.recompute_geometry()
	# Push the new geometry to the dartboard (rewards don't otherwise resync the board).
	var main: Node = run_state.get("main", null)
	if main != null and main.has_method("_sync_board_state"):
		main._sync_board_state()
