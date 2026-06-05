---
Spec date: 2026-06-04
Status: DESIGN-COMPLETE (this Cowork session) — but **blocked-on-substrate (Phase 01) for feel-testing.**
  The *mechanic* (costed handicap x01 + typed reward grant) is unit-testable standalone; the *design* (does
  it feel right *here*, is the difficulty curve good) cannot be validated without a run-position to sit in,
  because the whole value of these nodes is positional. Capture now while fresh; build after 01.
Part of: the Map Program (`specs/map/00-overview.md`), Phase 02.
---

# Phase 02 — Challenge Nodes (consented-friction earned steering)

## Concept

An **optional** map node. The player pays an entry **wager in banked darts**, then plays a short, handicapped
x01 race against a mini-boss. Win → wager refunded **and** a guaranteed **typed upgrade pick**. Lose → forfeit
the wager, **the run continues** (not a loss). It's the *earned-selection* surface of the build-steering
spine (see overview): the clean "give me a Brush" tap that the filtration spec (`map-pool-filtration.md` #3)
warned would flatten variance — made safe here by gating it behind a genuine skill wall **and** the bank.

Design law it rests on: **chosen friction is spice.** Benched boss handicaps were un-fun as *mandatory*
gates; opt-in with a reward attached, consent flips them into a flex.

## The wager economics (resolved this session)

Deposit darts to enter — "putting your ID down at the door."

- **Refund-on-win, forfeit-on-loss, run continues regardless.** Win returns the deposit + grants the pick;
  loss eats the deposit only. Losing is never a run-ender.
- **The deposit is gated twice, so it's a real cost even though it refunds on a win:**
  1. **A check, not just a choice.** You must *have* the darts banked to enter at all — so qualifying means
     you played efficiently enough to have a reserve. Low bank = the node is simply closed to you.
  2. **Opportunity cost (darts are ammo).** Per the darts-as-currency duality, wagered darts are darts you
     can't spend clearing legs / hitting score targets. Holding 6 darts as a stake is 6 darts of run runway
     pulled out, win or lose.
- **So the precision bar — not the deposit — is the real gate.** EV-wise, with refund-on-win and a valuable
  typed pick, "will I win?" is nearly always worth attempting *if you can afford the stake*. The live
  decision is therefore "is this upgrade worth pulling N darts of runway out of my run," which the economy
  supplies for free. No extra tuning needed to make the wager bite.

## The player-banter dial (the agency fix — the best idea in this design)

Instead of the node dictating difficulty, **hand the risk/reward dial to the player.** They choose how many
turns they get, and **rarity scales inversely with the wall they volunteer for:**

| Player picks | Darts (×3/turn) | Avg needed on 301 | Reward rarity |
|---|---|---|---|
| 2 turns | 6 | ~50 / dart — above a ton-per-turn average; near-perfect, ~5 trebles. A real wall even for great players. | **Rare** |
| 3 turns | 9 | ~33 / dart — tons-and-change; demanding but clearable if sharp. | **Uncommon** |
| 4 turns | 12 | ~25 / dart — ~75 a turn, comfortable. | **Common** |

The rarity ladder **is** the precision ladder — the math self-balances it, so no one can cheese the rare
(6 darts on 301 is brutal regardless of skill). The player picks where on the curve to sit instead of the
designer guessing a coin-flip. **Keep the deposit fixed per node** (set by map-section); let **turns↔rarity
be the single player knob** — one dial the player owns, not two interacting ones.

## Roll sets the frame; the player chooses within it

The node's *rolled ranges* and the *player banter* are layers, not rivals:

- **The node rolls** (within its map-section bounds, see resource): base score target, the offered upgrade
  **type**, the deposit size.
- **The player banters** turns↔rarity *inside* that rolled node.

## Map-section is the difficulty lever — reshape the budget, not just the number

The placement field shifts the whole curve, and crucially it can produce **qualitatively** different
challenges from the *same* score target by reshaping the dart budget — so one target stays fresh all run
(content economy):

- **Pre-boss-1:** 301, player banters 2 / 3 / 4 turns (3 darts each). A *volume/efficiency* check.
- **Between boss 1–2:** 301 again, but only **2 darts per turn** for 1–3 turns. Same number, now a
  *control-and-precision-under-scarcity* check — a different skill, not just "number go up."
- Later sections: raise base score (501), or tighten turns (1 / 2 / 3), for the same rarity ladder.

## Recycled friction — the benched-boss content mine

Mini-bosses for these nodes come from the **cut/benched list**, repurposed as *handicaps* (not the 4
reactive puzzle bosses):

- Rotational board (benched — "not that hard," good for an easy node).
- −1-dart-per-turn (e.g. front 4 turns of 2 darts) — nightmarish as a mandatory boss, a delicious flex here.
- Narrow Double, dart-count reductions, etc.

Keep these as **handicap races** — they *test your aim*. That stays cleanly distinct from the main bosses,
which are **reactive puzzles** that *fight your build* (drift, recolor-on-hit). Different verbs, no overlap.

**Difficulty↔reward stays matched**, so no node is a dominant pick: an easy handicap (rotation) pairs with a
weaker payout or a tighter dart budget; a brutal handicap earns the juicy rare. The player-banter dial
already does most of this work within a node; the map-section + handicap choice tunes the baseline across
nodes.

## The `ChallengeNode` resource (data model — house style, inspector-tuned)

A new `Resource` type, fully `@export`ed with `##` hover docs, so Max authors a handful and the map rolls +
places them:

- `score_target: int` — the x01 number (301, 501…).
- **Fronted layout** — either a fixed `turns × darts_per_turn`, or the **banter range** (allowed turn
  choices) plus the `turns → rarity` mapping. (Decide whether banter is always-on or per-node.)
- `deposit: int` — darts staked to enter (fixed per node; rolled within map-section bounds).
- **Reward** — offered upgrade `type` (rolled) + rarity (from the banter, or rolled if no banter) + count
  (e.g. pick 1 of 2).
- `map_section` — where this node may appear (pre-boss-1, between-boss-1-2, …) — the difficulty-scaling
  lever.
- Mini-boss / handicap reference — which benched effect applies.

## Open questions

- **Deposit scaling** — fixed per node (recommended, one knob) vs scaling with chosen rarity. Leaning fixed.
- **Double-out tax** — the avg-per-dart math above ignores the checkout double; on tight budgets (2 turns)
  the closing double makes the rare even harder. Fine (it's a *rare*), but note it when tuning.
- **Node scarcity** — how many challenge nodes per run / per section; the map's path structure gates this
  (you can't visit them all), which is itself part of the steering gate.
- **Loss cost** — decided: **deposit only, run continues.** Tempo cost is now handled *spatially* (below),
  so no explicit tempo penalty is needed.
- **Tempo cost is paid by the map layout** (resolved in `01-substrate.md`). Challenges sit on an **in-lane
  reconverging fork** (`A1 → (Leg | Challenge) → A3`), so taking the challenge means *forfeiting the parallel
  leg* — its dart-farming and progress. The geometry charges the detour for free; keep challenges on the
  off-branch, never inline in the mandatory sequence. This is "chosen friction has a price" expressed by
  position rather than by a coded penalty.
- **Early-run identity seed** — info comes early (codex + typed shop), but *selection* is gated behind a
  challenge that may not be on leg 1, so the first legs can feel directionless (the economy spec's
  interim-flatness worry). Is the informed first shop enough rudder, or should the very first node be a
  gentle low-fee challenge as a tutorialized identity-seed? Partly eased by **exposure double-duty**
  (`01-substrate.md`): challenges + events are slightly over-exposed early and each shows *more items than it
  grants* (pick 1 of 3), so the player builds item-literacy before the first shop even without taking a pick.
- **Reward type choice grain** — does the player pick the *type* (then 1-of-2 of it), or is the type rolled
  and only rarity is the banter? Leaning: type rolled by node, rarity by banter — keeps it one player dial.

## Dependencies / tentative touch points

- **Phase 01 substrate** — required for feel-testing (positional value).
- **x01 game** — needs handicap params: dart-budget override (turns × darts/turn), applied to a one-off
  short race; reuse the existing x01 flow with a constrained front.
- **Benched boss effects** — Rotation etc. as applicable handicaps (currently cut/benched per the boss
  redesign).
- **Reward grant** — a guaranteed *typed* pick path (type + rarity filtered); reuses the reward pool +
  `family` tag.
- **Darts-as-currency bank** — deposit/refund is a new sink alongside shop + bailout; must read/write the
  persistent `_banked_darts`.

## Related

- `specs/map/00-overview.md` — the program; the build-steering spine this implements the "earned" third of.
- `specs/future/map-pool-filtration.md` — #3 "gate the steering" is satisfied here by skill + held currency.
- `specs/future/darts-as-currency-economy.md` — the bank this wagers against; the deposit is a new sink.
- `specs/2026-06-03-scoring-on-the-board.md` — the `family` tag the typed reward filters on.
