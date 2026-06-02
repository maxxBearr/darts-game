---
Spec date: 2026-06-01
Status: Shipped 2026-06-01
Implementation: Separate implementation pass (Max's), reviewed afterward in the design session.
Notes: Shipped as designed — `FlipSignModifier` (per-dart, negate-last), `MirrorZoneReward`
  (single `bust_ends_turn = false` behavior + grants two flips), vanilla-only ±1 bust,
  reliability-gated checkout helper, `+` suffix UI. **One deviation found in review and
  fixed:** the Glass Cannon ↔ Mirror-Zone pooling exclusion shipped one-directional (only
  `MirrorZoneReward.is_applicable` scanned for `glass_cannon`, so taking the relic first
  left Glass Cannon still poolable). Refactored to a **declarative `excludes: Array[StringName]`
  on `RuleModifierReward`**, enforced by the base `is_applicable`, declared on both
  `mirror_zone.tres` and `glass_cannon.tres` so the exclusion is symmetric regardless of
  pick order. `TripleOutsReward` keeps its own one-directional "Glass Cannon supersedes"
  scan on purpose (redundancy, not conflict; plus it carries extra `allow_triple_checkout`
  logic) — left as-is, candidate for the same declarative treatment later.
  The map / category pool-filtration idea spun out to `specs/future/map-pool-filtration.md`.
---

# Spec: Flipped Wedges + Mirror-Zone Boss Relic

Two coupled items that let the player score *upward* and survive an overshoot.

## The one rule that makes it all consistent

A wedge's sign is an **intrinsic property of the wedge**, not of which zone the score is
in. The engine's arithmetic never branches: it is always

```
new_remaining = remaining_score - points
```

`points` carries its own sign. A normal (positive) wedge always *subtracts* — counts you
down. A flipped wedge produces *negative* points, so `remaining - (negative) = remaining +
value` — it always *adds*. A wedge does exactly what it says, every time, in every zone.
The player manages the +/- nature themselves; the system never surprises them.

We explicitly rejected a "mirror x01" model where arithmetic flips sign below zero (so a
vanilla triple-20 at -10 would climb to +50). It read cleaner on paper but made a wedge's
behavior context-dependent. In a stacking roguelike, predictable-but-you-manage-it beats
clever-but-contextual. Under the locked model the vanilla triple-20 at -10 correctly goes
to **-70** (positive always subtracts), and that's the right answer. (Max initially pitched
the mirror behavior, then caught the inconsistency himself and chose the intrinsic-sign rule.)

## Item 1 — Flipped Wedge (flip-sign modifier)

Negates the **final** dart score on a chosen wedge: compute face → face boosts → ring
multiplier → per-dart relic bonuses, *then* `total = -abs(total)`. Because the negate is
the dead-last step, it composes cleanly with everything: +3 on the 5, ×3 triple, flipped =
**-24**, with no ambiguous mid-pipeline sign. This is the decisive reason the flip is a
**per-wedge flag the scoring manager consults last**, NOT a `wedge_values[]` bake-in like
`WedgeValueModifier`. The stored face stays positive (multiplier math needs it); only the
emitted score is negated.

Why it matters on its own: it's the escape valve from being locked low. A player stuck at
3 with non-toggleable multipliers can hit a flipped wedge to climb back to a checkout-able
number — and this already works in the current engine, because a flipped hit yields
`new_remaining > remaining_score`, which is a normal hit, not a bust. Also resolves the
standing "locked-modifier lockout" open question.

UI: a static **`+`** next to the wedge number is enough for now (the wedge's stored face is
unchanged, so the board can't just show "-8"). No animation needed yet.

Shipped as `FlipSignModifier` (`scripts/modifiers/flip_sign_modifier.gd`): `BOARD_MUTATION`
kind (no relic-panel presence), `PER_DART` timing, `PICK_WEDGE` config. The scoring manager
holds it back from the main PER_DART loop and runs it in a final `_apply_flip_pass`. Flip
target follows wedge swaps via `on_wedges_swapped`. Negate is `-abs()`, so stacking two
flips on one wedge still yields negative. Bulls (no wedge index) are unaffected.

## Item 2 — Mirror-Zone Boss Relic

Flavor: *"Busting no longer ends your turn. Flips two wedges."*

Entire new footprint is **one behavior**: a would-be-bust (overshoot below 0) does NOT
revert to `score_at_turn_start` and does NOT end the turn — the player goes negative and
keeps throwing. That's it. The "win from the upside-down" needs **no new win logic**: the
existing `is_leg_won = (new_remaining == 0 and is_double)` already fires from below, because
the only way to climb toward 0 from underneath is to hit a flipped wedge (negative points).
Walk it: at -20, double on a flipped face-10 wedge → raw 20, negated to -20 points →
`-20 - (-20) = 0` on a double → win.

**Load-bearing:** the relic *always grants the two flipped wedges* (`wedge_flips_granted()
== 2`). This is structural, not flavor — only negative points move you up from below, so
without a flipped wedge the negative zone is a soft-lock. Granting them guarantees the
escape tool exists the instant you can go negative. Never let this relic exist without the
flips.

±1 handling: under the relic, negative is just a normal remainder — you overshoot off ±1
and keep going, no bust — so there is **no ±1 special case in relic mode**. The classic
"can't finish on 1" bust survives for **vanilla play only**: in `x01_game.gd::process_throw`
the whole bust block is gated on `bust_ends_turn`, which the relic sets false.

Glass Cannon conflict (it makes any bust end the *run*; this relic makes busts not end the
*turn*): resolved by **inventory-gated pooling exclusion**. Shipped as a declarative
`excludes: Array[StringName]` on `RuleModifierReward`, enforced by the base `is_applicable`
and declared on both `.tres` (each lists the other). Own either one → the other stops
appearing in boss shops. Own neither → both can show. **No swap option** — they aren't the
same category and offering a swap would just confuse. The player never has to adjudicate the
interaction. (The first implementation pass shipped this one-directional; the declarative
refactor in review made it symmetric.)

## Checkout helper

Surface a flipped-wedge route only when it genuinely helps — gate on **reliability, not
existence**. Score paths by minimum ring fatness (reuse the `_one_dart_finishable`
remainder→double-fatness map) and only show the up-route when it beats the best down-only
path on that metric, or when down-only is impossible. Cap upward moves at **one** — never
suggest down-up-down. The canonical trigger is offering a single-single-double over a
double-triple-double. In the negative zone the helper's job is simply "find the flip-wedge
route back to 0 on a double." (Adding upward edges interacts with the parked async-solver
work in `specs/future/async-checkout-solver.md`; the ≤1-up cap keeps it tractable.)

## Touch points (as implemented)

- `scripts/x01_game.gd` `process_throw` — `bust_ends_turn` flag gates the bust block;
  negative `remaining_score` is a legal state when false.
- `scripts/scoring_modifier_manager.gd` — `FlipSignModifier` held back from the main
  PER_DART loop, applied last via `_apply_flip_pass`; flip targets follow wedge swaps.
- `scripts/modifiers/flip_sign_modifier.gd` — the flip-sign item.
- `scripts/rewards/mirror_zone_reward.gd` + `resources/rewards/mirror_zone.tres` — the relic.
- `scripts/rewards/rule_modifier_reward.gd` — declarative `excludes[]` + base `is_applicable`.
- `resources/rewards/{mirror_zone,glass_cannon}.tres` — the mutual `excludes` declaration.
- HUD: `+` suffix on flipped wedge numbers; negative `remaining_score` display.
- Sanity pass: vanilla play (no relic) unchanged, including +1 bust.
