---
Spec date: 2026-06-01
Status: Parked — idea capture only, not scheduled. Extends the Slay-the-Spire map
already noted as parked in DesignNotes.md (boss-frequency vehicle).
---

# Map-Based Pool Filtration

Parking this so it's out of my head and findable. Not designed, not scheduled.

## The problem it solves

Item acquisition currently plays as "what's the strongest item on offer?" instead of
"what fits my build?" Picks feel scattered. A Slay-the-Spire-style map would let the
player steer the pool toward a category — choosing a path biased toward the kind of item
their run wants, not just taking the locally-best thing.

Categories I had in mind: **accuracy**, **score bonus** (with sub-types: color, even/odd),
**streaks**, and **board modifiers**. The map node you walk into filters/biases what the
shop offers.

This is a *second job* for the map that's already parked as the Slay-the-Spire
boss-frequency vehicle (see DesignNotes.md). The two are compatible — same structure, two
purposes.

## Structural realities to resolve first (found in the code 2026-06-01)

1. **There is no category tag today.** `ModifierRegistry` is one flat weighted pool, and
   `ModifierKind` is only RELIC vs BOARD_MUTATION — not the player-facing
   Score/Streak/Board/Accuracy taxonomy. Filtration needs a new "family" field on the
   modifier base, applied across all nine modifier types. That's the prerequisite, and
   it's the moment to lock down what the categories actually are.

2. **Accuracy lives in a different building.** Score/streak/board modifiers come from the
   shop pool; accuracy comes from **dart components** in the assembly screen (throw
   modifiers — ice veins, nervous sweater, momentum marksman — and flights), a separate
   acquisition channel with its own unlock gating. A map node labeled "accuracy" either
   has to reach into the component system or some accuracy effects get promoted into the
   shoppable pool. This is a genuine design fork, not a detail — decide it early or the
   map feels inconsistent.

3. **Filtration cuts variance.** Reliable steering toward a category makes runs more
   solvable and flattens the "make it work with what you're given" tension that makes the
   current acquisition feel alive. Balatro counters this with scarce rerolls/money. If we
   go this way, gate the steering — soft bias, limited picks — rather than a clean "give
   me only streak items" tap.

## Related

- The map would also raise boss frequency and could demote weak boss effects (Rotation,
  Narrow Double, currently benched) to node mini-encounters — that's the original parked
  framing in DesignNotes.md.
