---
name: project-open-questions
description: "Unresolved design questions for the Dart Game — dart count scaling, modifier conflict philosophy, absolute weight axis, distribution type, shop run-end behavior, meta-progression scope."
metadata: 
  node_type: memory
  type: project
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

Six design questions that don't have committed answers yet. Surface these whenever a feature decision intersects one — they should inform planning, not be quietly assumed away.

1. **Dart count scaling.** Currently fixed at 15 darts per leg (5 turns × 3). Could decrease as difficulty climbs. Could be modifier-dependent. Open question because it's a major difficulty lever and changing it affects every other balance assumption — including shop yield, since `shop_darts` is derived from leg dart budgets.

2. **Modifier stacking/conflicts (locked-non-streak case).** Streak conflicts: resolved by the one-per-category slot rule. Toggleable conflicts: the player can disable the offending modifier. But what about *locked* non-streak modifiers that combine to lock the player out of any valid checkout? The checkout helper makes the failure mode visible (no paths shown) but doesn't prevent the situation. Treat lockout as a high-stakes risk the player accepts, or build a safety net (mutually exclusive picks, UI warning at acquisition)? Still unresolved.

3. **Absolute weight axis.** A potential second weight dimension (total dart mass) affecting throw arc, power, or travel speed. Currently only directional balance (front-heavy ↔ back-heavy) is tracked.

4. **Shop run-end interaction.** What happens if a shop would fire after the final leg of a run? Deferred from the shop spec ([[project-dart-game-concept]] references the shipped shop). Depends partly on whether runs are open-ended or have a fixed length, which itself depends on question #5.

5. **Meta-progression scope.** What persists across runs? Unlocked parts? Unlocked modifiers? Cosmetics only? Affects the long-term retention design — and implicitly the answer to #4, since "run length" depends on whether the run is an arc or an endless climb. **Partly resolved 2026-05-23** — dart components now persist as global (not per-profile) progression via the `PlayerProgress` autoload → `user://progress.tres`. Modifiers and cosmetics still TBD; `PlayerProgress` is structured so adding `unlocked_modifier_ids` later mirrors the component pattern. See [[project-component-unlock-system]] for the system shape, and `DartComponentGuide.md` for usage.

6. **Rule-modifier category (new as of 2026-05-22).** Discussed during the checkout helper design pass but explicitly sidelined: items that affect run-structure rather than scoring (+1 turn per leg, rethrow each leg, see +1 option at upgrade pick, etc.). Likely wants its own slot system distinct from the six scoring slots, and the checkout helper will need to learn about extra-darts / rethrows when this lands. Pure design space, no implementation yet.

**Resolved since this memory was last updated:**
- *Distribution type for variance.* Resolved 2026-05-22: Gaussian implemented via `gaussian_spread` export on `throw_mechanic.gd` (default 0.4), with green/orange/red accuracy zones driven by normalized distance from the declared target's centroid. The final dart sample uses gaussian draws scaled by the accuracy zone × zone-driven multiplier. Was previously uniform `randf_range`.
- *Currency system.* No currency in the traditional sense — spare darts saved across legs are the de facto currency, and they spend at the shop directly via throwing. Shipped in the [shop spec](../../../../../Documents/GitHub/darts-game/specs/2026-05-21-shop-system.md).
- *Streak modifier conflicts.* Resolved by the one-per-category slot rule. Broader locked-modifier-conflict question still open (#2 above).
- *Player agency vs. helper paternalism.* Resolved by the soft-hint design call in the checkout helper — passive nudges ("try toggling a modifier") over active suggestions ("disable Color Streak to enable T20-T20-Bull"). Should inform all future helper-style features. See [[project-modifier-lock-system]] and the checkout helper spec.
- *Modifier commitment texture.* Resolved by the lock/unlock system — 65% locked / 35% toggleable rolled at generation, rarity is the power axis (not lock status), swap-anytime via shop/post-leg picks keeps commits leg-scale. See [[project-modifier-lock-system]].

**How to apply:** When a new feature naturally touches one of these (e.g., a modifier proposal that would create a checkout-blocking situation hits #2; an item that affects "total weight" hits #3; a run-structure question hits #5/#6; anything proposing turn-count or rethrow mechanics hits #7), surface the open question explicitly rather than picking an answer silently. These are conversations to have with Max, not assumptions to make.

See also: [[project-dart-game-concept]], [[project-architecture-rules]], [[reference-design-notes]]
