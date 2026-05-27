---
name: project-open-questions
description: "Unresolved design questions for the Dart Game — dart count scaling, modifier conflict philosophy, absolute weight axis, distribution type, shop run-end behavior, meta-progression scope."
metadata: 
  node_type: memory
  type: project
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

Six design questions that don't have committed answers yet. Surface these whenever a feature decision intersects one — they should inform planning, not be quietly assumed away.

1. **Dart count scaling.** Currently fixed at 15 darts per leg (5 turns × 3) as a *base*. Could decrease as difficulty climbs. Could be modifier-dependent. **Partly addressed 2026-05-26** by the Extra Dart and Extra Turn boss rewards — players can now *opt in* to more darts via reward picks, but the base hasn't moved and difficulty-driven scaling hasn't been added. Open question is now narrower: "should the base shift on top of player choice?"

2. **Modifier stacking/conflicts (locked-non-streak case).** Streak conflicts: resolved by the one-per-category slot rule. Toggleable conflicts: the player can disable the offending modifier. But what about *locked* non-streak modifiers that combine to lock the player out of any valid checkout? The checkout helper makes the failure mode visible (no paths shown) but doesn't prevent the situation. Treat lockout as a high-stakes risk the player accepts, or build a safety net (mutually exclusive picks, UI warning at acquisition)? Still unresolved.

3. **Absolute weight axis.** A potential second weight dimension (total dart mass) affecting throw arc, power, or travel speed. Currently only directional balance (front-heavy ↔ back-heavy) is tracked.

**Resolved since this memory was last updated:**
- *Distribution type for variance.* Resolved 2026-05-22: Gaussian implemented via `gaussian_spread` export on `throw_mechanic.gd` (default 0.4), with green/orange/red accuracy zones driven by normalized distance from the declared target's centroid. The final dart sample uses gaussian draws scaled by the accuracy zone × zone-driven multiplier. Was previously uniform `randf_range`.
- *Currency system.* No currency in the traditional sense — spare darts saved across legs are the de facto currency, and they spend at the shop directly via throwing. Shipped in the [shop spec](../../../../../Documents/GitHub/darts-game/specs/2026-05-21-shop-system.md).
- *Streak modifier conflicts.* Resolved by the one-per-category slot rule. Broader locked-modifier-conflict question still open (#2 above).
- *Player agency vs. helper paternalism.* Resolved by the soft-hint design call in the checkout helper — passive nudges ("try toggling a modifier") over active suggestions ("disable Color Streak to enable T20-T20-Bull"). Should inform all future helper-style features. See [[project-modifier-lock-system]] and the checkout helper spec.
- *Modifier commitment texture.* Resolved by the lock/unlock system — 65% locked / 35% toggleable rolled at generation, rarity is the power axis (not lock status), swap-anytime via shop/post-leg picks keeps commits leg-scale. See [[project-modifier-lock-system]].
- *Shop run-end interaction* (was #4). Resolved structurally 2026-05-26: runs now have a defined end via the level-cap system. Final-leg behavior is implicit — the boss leg terminates the run, no post-final-leg shop fires. See [[project-boss-level-system]].
- *Meta-progression scope* (was #5). Further resolved 2026-05-26: cleared levels persist via `PlayerProgress.cleared_levels` with fewest-darts tracking. Components still persist via `unlocked_ids`. Modifiers and cosmetics remain TBD; the `PlayerProgress` autoload pattern handles both as additive fields when wanted.
- *Rule-modifier category* (was #6, added 2026-05-22). Resolved 2026-05-26: shipped as the boss reward system. Eight initial rewards live as `RuleModifierReward` resources separate from scoring modifiers; players draft them on boss-win events. Trade-style design lean validated with Glass Cannon (canonical trade: checkout flexibility traded for bust-kills-the-run). See [[project-boss-level-system]].

**How to apply:** When a new feature naturally touches one of these (e.g., a modifier proposal that would create a checkout-blocking situation hits #2; an item that affects "total weight" hits #3; a difficulty-scaling proposal hits #1), surface the open question explicitly rather than picking an answer silently. These are conversations to have with Max, not assumptions to make.

See also: [[project-dart-game-concept]], [[project-architecture-rules]], [[reference-design-notes]]
