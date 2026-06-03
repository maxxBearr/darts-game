# Spec: Scoring Lives on the Board — READY FOR IMPLEMENTATION

**Full build spec: `specs/2026-06-03-scoring-on-the-board.md`** (read it before implementing). The
scoring/items half of the mid-game rebalance. Honed from brainstorm to build spec with all decisions
locked; ready for a Claude Code pass.

**Core model — two separated scaling axes:** an *additive* face-value baseline (hotspots + wedge values,
item-driven, bounded) × an *earned multiplicative* ceiling (streaks become the one multiplier, gated by
component capacity). Scaling is a *route you choose*, never "play long enough." Scoring math today is
already a single additive multiplier per dart — the only pipeline change is streaks moving from additive to
a `streak_factor` applied last.

**What ships this pass:**

- **Pool migration:** drop the unslotted global bonuses (`ColorBonus`, `OddEvenBonus`) and all parity /
  even-odd classes; **sideline `FlipSign`** (unlist, keep class + Mirror-Zone relic); raise `ColorStreak`
  weight; reweight. Add a `family` tag (Scoring / Placement / Brush) — streaks excluded.
- **Streaks → multiplicative:** the exponential lever; capacity per-category from components (shaft → wedge
  slots, barrel → color slots) via an inspector-editable `streak_slot_grant` export; cut
  `StreakSlotExtensionReward`; replace the global `max_streak_slots`.
- **Hotspots (new headline item):** `HotspotModifier`, picked via the segment picker, **no-stack** (one
  tier/ring, max +3), folds into the additive baseline. Checkout solver + target tooltip must read it *and*
  the live streak factor.
- **Visuals:** smoky hotspot shader with the value baked into the smoke (enhances ring color, doesn't
  override) + source-located scoring flair (spatial points from the board, streak points from the dart).

**Out of scope (Max-manual or deferred):** component **stat layouts + streak-grant values** (Max tunes in
the inspector — Claude Code only adds the field + plumbing); **Tier-2 geometry items** (deferred behind the
solver lift); **shop/pool steering** (tag only); the **map / fronted-darts** progression (separate later
spec — `specs/future/map-pool-filtration.md`). Build order is in the spec's Sequencing section.

Also still parked: **Darts as Currency Phase B** (typed shop rings) in
`specs/future/darts-as-currency-economy.md` — needs the accuracy-into-shop-pool fork resolved.

---

## Workflow Notes

`CLAUDE.md` holds the **single active spec** — the feature currently being designed or implemented. It auto-loads into every Claude conversation in this repo, so it should stay lean and focused on one thing at a time.

When a feature ships (or work moves on to a new spec), the previous one gets archived:

1. Move everything above this "Workflow Notes" section into `specs/YYYY-MM-DD-feature-slug.md`.
2. Add a status header at the top of the archived file:
   ```
   ---
   Spec date: YYYY-MM-DD
   Status: Shipped YYYY-MM-DD | Partially shipped | Superseded by specs/X
   Implementation: Where the implementation pass ran (Claude Code, manual, etc.)
   Notes: What shipped vs deferred, links to follow-up specs that revisit anything here.
   ---
   ```
3. Reset the spec section in `CLAUDE.md` to this placeholder (or replace it with the next spec).

The archive is for design context, not implementation reference. Code lives in code; the archived spec exists to remind future-Max (and future-Claude) *why* a system was built a certain way, what alternatives were considered, and what the design assumptions were. When making changes that touch an existing system, scan `specs/` for any prior decision that constrains the new work.
