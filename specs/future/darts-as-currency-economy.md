---
Spec date: 2026-06-02
Status: Parked — vision capture, refined in design discussion 2026-06-02. Not scheduled.
  Downstream of the active "Accuracy Upgrades as Shape" spec (CLAUDE.md) and entangled with
  `specs/future/map-pool-filtration.md`. We are shipping + playtesting the accuracy rebalance
  FIRST. Goal of this system: push the *current, map-less* version of the game as far as it goes
  for variety and complexity before committing to a map.
---

# Darts as Ammo + Currency (run-spanning resource economy)

The "greens on the plate" idea. Max's framing: the **steak** is the throwing mechanic (what you
spend the most time chewing on), the **potatoes/starch** is upgrade acquisition and build
strategy (the Hades-boon / Balatro-Joker pleasure of *choosing what to acquire*). What's missing
is the third thing — a system that carries **strategy and deliberation across the whole run**, so
a run feels continuous instead of a string of isolated legs. Right now leg 2 barely touches leg
12. This system makes every leg press on the next (somewhat — enough to reward foresight, never so
much that a bad early leg makes a later one unwinnable).

## Core model

Darts are a single resource that is **both ammo and currency**. Resource management is a dynamic
layer the game currently lacks.

- Each leg **fronts you 15 darts** (5 turns × 3), unconditionally. 15 is already designed to be
  enough to win a leg — that's the existing baseline.
- A turn **costs 3 darts** and gives 3 throws. **Keep 3-darts-per-turn** so busting still matters
  (faithful to real darts; differentiates from generic number-go-up roguelikes).
- Unspent darts **bank and carry across legs**. Banked darts are spendable as **bailout turns**
  (need a full 3 to use one) and as **shop currency** (below).
- The existing **save-darts logic stays and extends to bought/bailout turns.** Check out on the
  first dart of a turn → the other two return to the bank. A bailout is therefore partially
  refunded if you finish efficiently on it.

## Why the economy is safe (concerns raised and resolved 2026-06-02)

These were live worries in design; recording the resolutions so we don't relitigate them.

1. **"Skill-fed bank = win-more / rich-get-richer."** Resolved by the **15-dart floor**: every
   leg is always fronted enough to win, so the bank can never pull you *below* a viable baseline
   — it is strictly bounded upside, never a subtractive spiral. This is the Balatro money model
   (you earn more for winning efficiently; you're never starved below playable). Punishing weak
   play with *less extra* is a healthy reward gradient.

2. **"Inventing a fail state to sell insurance."** Not invented — the loss condition already
   exists and is permanent: **lose a leg → lose the run.** Bailout darts are optional upside, not
   a manufactured danger. And because losing a leg ends the run, there's no future leg to hoard
   for *in the moment*, so **auto-using a bailout when you'd otherwise lose is correct** — there's
   no decision there, which is fine; the decision lives upstream (how much to bank vs spend).

3. **"Uncapped reserve lets a hoarder coast."** Resolved without a hard cap: **the difficulty
   curve is the cap.** A static reserve buys less and less as legs scale, and later legs are
   un-winnable by volume alone — they require scaling (multipliers, board upgrades) you can only
   buy by spending. The weak-board boss is the canonical lever (it caps raw scoring so you *need*
   the engine). So hoarding is a slow loss, not an exploit; players must find a spend-vs-protect
   balance. **Design constraint to preserve:** keep late legs unbeatable by pure dart volume, or
   the self-regulation breaks.

   **The accuracy-as-shape rework reinforces this:** because accuracy no longer climbs, a
   hoarder's per-dart scoring power stays flat all run, so they can't brute-force a scaled leg
   with volume — they're forced to spend to scale. The two systems protect each other.

## The currency is the replacement climb

Important coupling, not a side note. The accuracy reshape **removes accuracy as a power-
progression axis on purpose.** Scoring relics partly backfill it, but **banked darts + shop
investment become the primary run-spanning "I'm getting stronger" engine.** That reframes this
system's priority: it isn't garnish, it's the climb that fills the hole the reshape opens.

**Playtest heads-up for the interim build** (accuracy reshape shipped, this not yet): a run that
no longer climbs accuracy and doesn't yet bank darts may read as "nothing happens between legs."
That flatness is *expected* — it's the gap this system fills — not a failure of the reshape.

## Where the agency lives

The **bailout spend itself is not the interesting decision** (you always take it to avoid losing
the run). The real agency is **how much you bank vs spend**, and it shifts over a run:
- **Early:** likely spend nearly everything at the shop to start scaling immediately and compound.
- **Later / under pressure:** hold a minimum (e.g. one safe turn = 3) as insurance.
There's a genuine now-vs-later tension (shop power now vs insurance + bigger shop later) and no
single dominant line — the spend pattern is itself a strategy.

## The shop (mostly already built — this re-skins and types it)

Current behavior: the shop checks your saved darts and lays out **safe darts + 3 reward rings**;
**rarity is positional** — uncommons/rares sit on triples/doubles, so they're harder to hit. You
buy **by throwing**, and **every dart you spend is gone**: hit your target → you get the reward;
miss → you get nothing back. This already produces good play (people burn 4 darts chasing an
unhittable rare; you can hit easy rewards first, then spend your last dart on the rare).

What changes:

- **Each ring randomly represents a type** — **accuracy**, **scoring**, or **board-changing**
  upgrade. Rarity stays positional as it works today.
- This makes type-vs-hittability a **per-shop decision** driven by your accuracy zone. A tall-thin
  zone (high V, low H accuracy) is poor at hitting a rare on the *side* (e.g. double-11) and is
  better off taking a common up *top* — so your zone shape decides which rewards are even worth a
  dart. This is the direct, deep payoff of the accuracy-as-shape rework bleeding into economy
  decisions, not just scoring.

**This is how we get type-steering without a map.** Distributing types across the shop rings gives
the "what am I hunting" decision inside the existing shop, so the map is **deferred, not deleted.**
What the map would still add later and this does *not* cover: cross-leg routing, choosing a reward
biome a leg ahead, and boss cadence (see `specs/future/map-pool-filtration.md`).

## Legendary items under the economy

`extra_turn_reward` and `extra_dart_reward` stop being "more of the same" and integrate:

- **+1 Dart per Turn:** fronts more total darts over a leg (≈5 over 5 turns) and a turn now costs
  4 — so an insurance turn costs 4 to hold, and the bust math changes (more darts to overshoot).
- **+1 Turn:** adds a full turn (≈3 darts) of front. Under the refund model its unused darts bank
  too, so it's no longer obviously a free-currency outlier.
- **Net:** which is stronger now depends on **bust frequency and leg length** — a playtest
  question, not a whiteboard one. (We considered making +1 Turn's darts non-bankable to defang a
  currency-outlier worry; rejected, because the refund model is nicer and the worry dissolves once
  unused bought-turn darts bank like any others.)

Bailout interaction (as Max specified): if you miss with the last dart of your 5th turn (15th
dart), spare darts auto-spend into a bailout turn (else you lose). Finish on the first dart of
that bought 6th turn → the unused two return to the bank via existing save-darts logic.

## Still to design (not just logic — this is why it's a full spec, not a tweak)

- **UI / presentation.** The bank needs a legible at-a-glance readout (banked darts → "= N turns",
  current shop cost, what's insured). Keep decisions **chunky** — surfaced at legs and shops,
  never demanding per-dart arithmetic — or the resource math competes with the throw for
  attention, and the throw is the steak. Note the upside: a growing bank is a **tangible mastery
  meter** (Balatro-money-style), a progress signal even on a losing run.
- **Explainability / onboarding.** Darts-as-currency is a meaningful new mental model (ammo *and*
  money, banking, bailouts, typed rings). It needs to be taught — fold into the tutorial/help
  system; lean on the existing "experience before semantics" onboarding patterns.

## Build order

Strictly after the accuracy-as-shape rebalance ships and feels right. This system can land
**without** the map (typed rings cover in-shop steering); the map remains a separate, later piece
for cross-leg routing and boss cadence.

## Related
- Active spec: `CLAUDE.md` — Accuracy Upgrades as Shape (do first; this is its replacement climb).
- `specs/future/map-pool-filtration.md` — typed-pool steering + boss cadence; partial overlap.
- `scripts/rewards/extra_turn_reward.gd`, `scripts/rewards/extra_dart_reward.gd` — re-contextualized.
- Shop spec `specs/2026-05-21-shop-system.md` — the safe-darts + rings + throw-to-buy base this builds on.
