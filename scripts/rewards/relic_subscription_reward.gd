class_name RelicSubscriptionReward
extends RuleModifierReward
## Boss-only unlock (§6): opens the shop RELIC channel for the rest of the run. Until a player owns
## this, the gold bull spot in shops never lights — so a relic can never appear before the player
## has beaten a boss, keeping relics earned/premium rather than always-on. apply() just flips
## main._relic_shop_unlocked; the per-shop chance roll (relic_spot_chance) and the eligible-pool /
## owned-dedup logic stay exactly as they were and only kick in AFTER unlock.
##
## shop_eligible = false: this can't live in the relic shop it unlocks (chicken-and-egg), so it
## stays an earned boss prize. stackable = false: once unlocked, stays unlocked — a second copy
## would be inert, so the base owned-dedup is_applicable drops it from the pool once owned.


## 501 dead-pick guard: in a single-boss level the boss is the terminal node — no shop comes after
## it — so unlocking the shop relic channel can never pay off. Don't offer an inert reward there.
## boss_count comes from the run_state snapshot (main._build_run_state reads _current_level); we
## default to a multi-boss assumption when it's absent so the reward isn't wrongly hidden.
func is_applicable(run_state: Dictionary) -> bool:
	if not super.is_applicable(run_state):
		return false
	var boss_count: int = run_state.get("boss_count", 2)
	return boss_count > 1


func apply(run_state: Dictionary) -> void:
	run_state["main"]._relic_shop_unlocked = true
