class_name TunnelVisionReward
extends RuleModifierReward
## Relic (§4, retooled from the old "All In"): strikes ACCURACY from the family roll for the rest
## of the run. Accuracy is the one family with a natural FINISHED state — it's redistribution, not
## a climb (see project-accuracy-as-shape) — so once a shape is set you stop wanting aim trades.
## Suppressing it concentrates every future roll into families that still advance the build, and
## collapses events to brush+geometry (which feed each other — paints make boards asymmetric,
## asymmetry makes geometry interesting). Identity: "stop offering me aim trades, double down on
## board-shaping."
##
## Architected generically: we don't literal-reroll (a reroll-until-not-accuracy loop has a
## degenerate all-accuracy case) — apply() just appends &"accuracy" to the run's generic
## suppressed_families, which the two roll sites filter against (main._generate_shop_spots for the
## shop, MapGraph._roll_event_node for events). Challenge rewards are already [SCORING, STREAK], so
## they need no change. A future relic can suppress another family the same way. Boss-only — a
## run-definer, not a shop utility (shop_eligible stays false).


func apply(run_state: Dictionary) -> void:
	var main_node: Node2D = run_state["main"]
	if not (&"accuracy" in main_node.suppressed_families):
		main_node.suppressed_families.append(&"accuracy")
