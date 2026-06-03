---
Spec date: 2026-06-02
Status: Shipped 2026-06-02 (Phase 1). Phase 2 (scarcity / map-gated flat boosts) deferred.
Implementation: Claude Code pass, confirmed working by Max ("ran phase 1, all good there").
Notes: Phase 1 shipped as specced — accuracy trades retuned to a net-zero-by-rarity ladder
  (penalty made rarity-aware instead of fixed `penalty_amount: 3`), and the four flat range/speed
  entries converted to sibling-axis trades on the same ladder (one consistent model). The "watch
  for rare-stacking soft-beeline" playtest concern remains an ongoing thing to monitor, not a
  shipped guardrail. Deferred to Phase 2 (downstream of the map): scarce gated *flat* accuracy
  boosts as the real power vent, component swap liquidity. Superseded as the active spec on
  2026-06-02 by the darts-as-currency resource layer (CLAUDE.md), which is the intended
  "replacement climb" for the accuracy climb this rework removed — see
  `specs/future/darts-as-currency-economy.md`.
---

# Spec: Accuracy Upgrades as Shape, Not Climb

**Status: designing (2026-06-02). Phase 1 only — rebalance the existing upgrade pool. No
map, no scarcity, no dart-economy changes yet (those are parked, see below).**

## The problem

By late game the accuracy stats max out, and when they do two things we care about die:

1. **The throw animation loses its suspense.** The fly-in (`specs/2026-06-01-throw-anticipation.md`)
   is the soul of the game — its whole job is to make the accuracy miss *legible as motion*:
   the dart drifts from where you aimed to where it actually landed, and the drift vector *is*
   the miss. If accuracy can climb to near-zero scatter, the drift vanishes and the animation
   becomes "dart appears on board." We are designing our best moment to delete itself over a run.
2. **Dart components stop mattering.** Components mostly feed stats; once stats are capped, the
   only component that still matters late is the flight. We *accept* components being an
   early-to-mid foundation that hands off to relics for the late-game climb (that arc is fine and
   intentional) — but they should shape the run while they're load-bearing, not get flattened.

These are two faces of one root cause: **accuracy is allowed to climb toward determinism.**

## The current state (confirmed in `scripts/main.gd`)

`UPGRADE_TYPES` is 6 entries: H/V Range and H/V Speed are **flat** (`tradeoff: false`); H/V
Accuracy are trades (`tradeoff: true`) but with a **fixed `penalty_amount: 3`** against a gain
of 8–20 from `CONSISTENCY_RARITY_TABLE` (common 8–12, uncommon 13–16, rare 17–20). So a common
accuracy pick nets **+5–9**, a rare nets **+14–17**. That is a flat upgrade wearing a trade
costume — and because the penalty hits the *sibling axis*, alternating V-pick / H-pick climbs
both axes linearly. This is the determinism path. (Max identified this independently before we
found it in code; his own most-successful runs beeline accuracy and ignore relics until 401+,
which is the dominant-strategy symptom of exactly this.)

## The design: total accuracy budget is conserved

Reframe every stat upgrade from *a number you climb* into *a shape you redistribute*. The total
scatter budget stays ~flat across a run; picks only ever **concentrate** it — narrow one axis at
the cost of widening the sibling axis. Because the budget is conserved, the scatter ellipse is
**always nonzero**, so the throw-anticipation drift is preserved permanently. And the strategy
becomes positional: a tall-thin zone (high V accuracy, low H) wants the top/bottom doubles where
a thin-tall target gives the least room to miss; a wide-thin zone wants the side doubles. The
live fly-in is what makes this legible — you watch the skew resolve.

**The "pick two of three" rule** that governs all tuning: an upgrade may be *net-positive*,
*same-axis-pool*, or *abundant* — never all three at once. Two of the three is the determinism
trap.

### Phase 1 changes (this spec)

1. **Accuracy trades become net-zero, scaling toward win-win by rarity.** Replace the fixed
   `penalty_amount: 3` with a per-rarity penalty so net gain is roughly:
   - Common: **net 0** (e.g. +9 / −9) — pure reshape, no climb.
   - Uncommon: **net +1–2** (e.g. +10 / −8).
   - Rare: **net +3–4** (e.g. +10 / −6 or −7).

   Rarity buys a *better exchange rate*, not a bigger raw number. (An alternative we may try if
   net-positive rares still climb too fast: rarity instead buys *magnitude of reshape* — a rare
   is +20 / −18, near-zero net but a dramatic specialization. Decide during playtest.)
2. **Range and Speed upgrades stop being flat.** Convert the four `tradeoff: false` entries to
   trades against their sibling axis (V-range ↔ H-range, V-speed ↔ H-speed) on the same net-zero
   ladder, OR remove them. Leaving them flat just relocates the determinism problem onto range
   and speed. Recommendation: convert, for one consistent model.
3. **The scarce real climb is deferred, not removed.** A small number of rare, gated *flat*
   accuracy boosts (a sought-after treasure) are the intended power vent — but they belong to the
   map/scarcity work, not Phase 1. For now, all in-pool upgrades are trades.

### What Phase 1 deliberately does NOT do

No map, no typed shops, no exposure/scarcity change, no dart-economy. We rebalance the upgrade
pool **under the current every-other-leg cadence** and playtest the *feel* first. **Watch during
playtest:** even net +3–4 rares, shown that often, will slowly climb — if rare-stacking
recreates a soft accuracy-beeline, that's the signal to either pull rares toward net-zero or
move accuracy behind the map's scarcity gate (Phase 2).

## Touch points

- `scripts/main.gd` `UPGRADE_TYPES` — flip the four flat entries to trades; give accuracy entries
  a rarity-scaled penalty instead of fixed `penalty_amount: 3`.
- `scripts/main.gd` `CONSISTENCY_RARITY_TABLE` (+ likely `STANDARD_RARITY_TABLE` /
  `SPEED_RARITY_TABLE` once range/speed are trades) — retune gains so net matches the ladder per
  rarity. The penalty needs to become rarity-aware; today it's a flat field on the upgrade def.
- `_show_accuracy_pick()` and the pick-presentation path — confirm the trade's penalty is shown
  per-rarity (the UI already shows penalty name/amount; it must now read the rarity-scaled value).
- `scripts/dart_build.gd` — components feed the same six stats; nothing changes here in Phase 1,
  but note the green/orange/red balance bonuses still stack on top, so "net-zero" is net-zero
  *before* balance-zone bonuses. Keep that in mind when tuning.

## Parked, downstream of this (do not build in Phase 1)

- **Map + scarcity + typed shops** — `specs/future/map-pool-filtration.md`. The vehicle for
  making flat accuracy scarce and letting the player pre-choose a reward biome. Resolves that
  spec's open fork (#2: does accuracy get promoted into the shoppable pool) — under this
  direction, accuracy trades are poolable; rare flat boosts are the gated treasure.
- **Component swap liquidity** — leaning harder on components requires mid-run ways to swap/alter
  them (shop slots, minigame nodes). A dependency of the "components do the work" direction, not a
  bonus.
- **Darts as ammo + currency** — `specs/future/darts-as-currency-economy.md`. The "greens on the
  plate" idea: a run-spanning resource economy. Captured in full there.
