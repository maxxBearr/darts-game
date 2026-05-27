---
name: project-modifier-lock-system
description: "Locked/unlocked modifier status — every modifier rolls toggleable at generation (35% unlocked, 65% locked). Rarity is the power axis, not lock status. Locked = constraint, never penalty."
metadata: 
  node_type: memory
  type: project
  originSessionId: 0c1d2013-d6a0-4259-b6d5-6e093add0313
---

The modifier lock/unlock system shipped 2026-05-22 on the `checkout-helper` branch. It's a design lever for *commitment texture* — does the player feel like their modifier picks are real choices? — that supplements (rather than replaces) rarity as the power axis.

**The roll.** Every modifier instance rolls toggleable vs. locked at generation time. The roll is a flat d100 against `UNLOCK_CHANCE: int = 35` (in `scoring_modifier.gd`). About 35% land toggleable, 65% lock. Called from each subclass's `generate()` after rarity is rolled, via `roll_toggleable()`.

**Why 65/35 (locked-majority).** Inverts the intuitive "unlocked is the default, locked is the variant" framing. Instead, **unlocked is the rare/precious state**. Most builds are predominantly locked; toggling becomes a precision tool, not a verb of regular play. This was deliberate over a flipped (majority-unlocked) ratio.

**Why no compensating buff for locked.** Locked is a *pure constraint* (can't click off), not a damage-stronger variant. Rarity does the power-tier lifting — a locked-rare has rare-tier stats, an unlocked-common has common-tier stats. The interesting decision lives at the rarity boundary: "do I take this locked-rare or hold out for an unlocked-uncommon?" If locked carried its own buff, the system would have two intersecting power axes and the choices would muddy.

**Why swap-anytime (leg-scale commits).** Locked modifiers can be swapped at the next shop or post-leg pick — so locked-for-the-run is impossible. Commits run leg-scale, not run-scale. Long enough to feel like a real choice; short enough to not feel punishing. This is also what makes the checkout helper's "try toggling" hint meaningful even on locked-heavy builds: if toggling doesn't help, *swap* the offending modifier at next pick.

**Helper integration.** The checkout helper's soft hint ("Try toggling a modifier to recalculate") is gated on whether any active modifier is `toggleable=true`. If all active modifiers are locked, the hint is correctly suppressed — suggesting a non-action would be worse than no hint.

**Deferred but discussed.** A "Modifier Switchboard" shop unlock gating toggling capability behind acquisition was considered (lock = always locked, even unlocked-tier modifiers can't toggle until you buy the switchboard). Currently *not* shipped — toggling is universally available for unlocked modifiers without needing an unlock item. Streak-reset-on-toggle (toggling off a streak modifier forfeits accumulated streak count) was also discussed and *not* shipped — toggling is free of streak penalty. Both are easy add-ons if playtest shows toggling is too powerful.

**How to apply.** When designing any new modifier or upgrade-style item, ensure it picks up the lock roll via `roll_toggleable()` in its `generate()`. When designing any future helper-style feature, follow the same soft-nudge pattern the checkout helper uses — passive hint that the player has a lever to pull, never an active "do X" prescription. When discussing modifier balance, remember that locked is *not* "worse" — it's a different shape; the player accepts less flexibility for the same raw stats.

See also: [[project-dart-game-concept]], [[project-architecture-rules]], [[project-open-questions]], [[reference-design-notes]]
