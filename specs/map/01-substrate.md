---
Spec date: 2026-06-04
Status: CONCEPTUAL DESIGN COMPLETE (Cowork sparring session, Max + Claude) — architecture call, topology,
  difficulty model, generator shape, and information model all resolved. **Not yet built.** Ready for a
  code-first rough-rect pass when scheduled; remaining opens are tuning numbers + the art handoff, not
  structural unknowns. When this phase moves to build, it takes CLAUDE.md's active-spec slot.
Part of: the Map Program (`specs/map/00-overview.md`), Phase 01.
---

# Phase 01 — Map Substrate (the frame)

The navigable graph the rest of the program hangs off. **Frame before furniture:** before any new node type,
the substrate first just hosts the *current* run flow (legs, shops, bosses) as a graph — mostly a
*reorganization* of what already exists, so it's a contained first build, and it's what makes every later
phase felt-testable in context.

This spec captures the full conceptual flow agreed this session. Architecture, topology, the difficulty
model, the two-model generator, and the information model are all settled below; the open list at the end is
deliberately short and is all *tuning*, not *design*.

## Architecture call (decided)

**Separate the map graph (data) from the map view (scene).**

- **Graph = data.** What nodes exist, how they connect, what each contains — generated or authored, pure
  data, no visuals.
- **View = scene.** Instantiate a node *scene* per graph entry and position it. This is the Slay-the-Spire
  card model (dynamic instantiation from a data model).

Why this specifically, given Max's art plan: decoupling graph from skin means **rough grey rects now → test
the flow → redraw the node scene later, and the generation logic never moves.** It directly supports "make
it work, then tailor code to art."

**The trap to avoid:** hand-placed `Marker2D`s or manually-positioned buttons. That welds layout to content —
the moment you iterate art, or want the map to roll differently per run, you re-place everything by hand.
Manual placement is only acceptable for a *fixed-layout, non-procedural* map, which the "sections with rolled
contents" framing rules out.

Shape: `MapGraph` (data/generated) → `MapView` scene that instantiates `MapNode` scenes per graph node → each
node carries its *type* and its *run-position*.

## Topology — lanes + in-lane forks + bridges, funneling to the boss

Not pure StS lattice (too deep for our act length) and not pure parallel lanes (too few decisions). A
**shallow mix**, scaled to an act of **~7–12 nodes** (current flow is 6 with shop-cadence 2, so this is a
modest expansion, not a reinvention):

- **Lanes.** A small number of roughly-parallel routes (lean 2; 3 is an open tuning call) running start → boss.
- **In-lane forks.** At a step, a lane can split into two reconverging nodes — e.g. `A1 → (Leg A2 | Challenge)
  → A3`. You pick one; they rejoin. This is a **local content choice**, *not* a lane change.
- **Bridges (crossovers).** A node that edges across to the other lane, so you can enter it from either lane
  and exit onto either lane. This is a **structural lane-switch**. (See "Bridges are a position, not a type.")
- **Chokepoints.** Lanes diverge through the rolled middle and funnel back together at shared nodes — the
  start, and the stretch just before the boss. Convergence points are the natural home for anything you'd
  *want* every run to encounter (see the generator's guarantee discussion — which we ended up keeping soft).

Two structurally different "off-lane" nodes, kept distinct in the data model:

1. **In-lane alternate** — the reconverging fork. A local "leg or challenge this step?" choice. Carries a
   built-in opportunity cost (below).
2. **Cross-lane bridge** — the lane-switch. Costs you a node to take (you *play* the crossover, you don't
   teleport), so lane commitment stays meaningful.

**Bridges are a position, not a type.** There is no special "bridge" node kind, because **there is never a
non-eventful node.** A bridge is just an ordinary node (leg / challenge / shop / event) that happens to sit
at a crossover and have edges to both lanes. Switching lanes therefore always costs you a *real* encounter,
and never a wasted/empty stop.

**The opportunity cost is spatial and free.** Because the in-lane fork reconverges, taking the Challenge means
*giving up the parallel Leg* (its dart-farming / progress). The geometry charges you for the detour, so
challenges need no artificial tempo penalty — keep challenges on the off-branch, never inline in the
mandatory sequence. This is "chosen friction has a price" expressed by layout. (Resolves an open thread in
`02-challenge-nodes.md`.)

## Node taxonomy

Existing flow first, then the new types. Locked list:

- **Leg** — a standard x01 encounter. The "common fight." Procedurally rolled (see difficulty model).
- **Challenge** — optional costed handicap race for a guaranteed typed pick. The "elite." Hand-authored
  Resources (see `02-challenge-nodes.md`).
- **Shop** — spend banked darts on items.
- **Event** — a free item-acquisition stop. Its icon is the **item-family glyph** (e.g. a bullseye = an
  accuracy pickup), the *same* glyph the shop and codex use. Folds the parked "accuracy lives in a different
  building" fork: events are the clean home for accuracy / component-swap / interest-on-darts / trade-style
  content that doesn't fit the "beat an enemy" frame. Ship the event icon when that content lands; the map
  works with leg/challenge/shop/boss in the meantime.
- **Boss** — the act-ender; always terminal for its act.

(Possible later: rest/heal, treasure — not committed. Add by extending the enum, not the topology.)

## Run-position & the difficulty model

The run reads as **one continuous numeric climb** (targets rise 101 → ~1501 across the whole run) but is
**structurally three acts**, each capped by a boss that is *guaranteed the highest required score of its
area*. So you get the continuous-climb feel **and** act destinations, with no "start over at 101" sensation:

- **Act windows slide.** The floor rises with the ceiling (e.g. Act 1 ≈ 101–501, Act 2 ≈ 301–1001, Act 3 ≈
  601–1501 — exact numbers hand-tuned). The act's center of mass climbs; variety stays wide inside the window;
  a "low" number can still reappear as a *deliberate surgical callback*, not the baseline. The floor is a
  *vibe*, not a hard constant — "whatever's realistic for a 1–2-turn minimum at this power level."
- **The pressure ratio is the difficulty dial:**

  > `pressure = (target ÷ darts_fronted) ÷ expected_per_dart(run_position)`

  - ~0.5 → comfortable, slack (normal legs).
  - ~1.0 → must perform exactly at the expected level (tense).
  - >1.0 → must *exceed* baseline → surgical; leans on RNG or the bank cushion.

  The ratio **unifies both scaling axes.** The generator rolls a `(target, darts_fronted)` pair from the act
  window that lands in the intended pressure band — and *which knob it used sets the flavor:* big target +
  generous darts = a **marathon/volume** leg (variance-forgiving, recoverable); modest target + starved darts
  = a **sniper** leg (every dart counts, double-out bites immediately, variance-punishing). Same difficulty
  number, different verb. (Sanity check: ~65/dart expected vs 301 over 9–12 darts ≈ pressure 0.4–0.5 — a
  comfortable normal leg, as intended. Crank toward 1.0+ for the boss and hard legs.)

- **`expected_per_dart` is run-position only — a static designer's curve for a *median* build, NOT adaptive.**
  Out-scaling the curve is the *reward* for good item/accuracy picks; rubber-banding difficulty to live build
  power would erase that payoff and read as the game cheating. The under-scaled player is already caught by
  the **bank**, which is the catch-up mechanic — not adaptive difficulty.

### Stakes recap (the frame this difficulty sits in)

- **Lose a leg = lose the run.** A leg is an encounter you must win to proceed, or you die. There is no
  separate HP bar.
- **But the bank is a *cushion*, not HP.** The run is *designed beatable on fronted darts alone* by a
  reasonably-scaled player. Banked darts are optional currency that converts into extra turns (bailout) or
  items (shop), smoothing RNG and compensating for a build that under-scaled or missed the hot items.
- **So sudden-death-per-leg is fair:** a death means you fell behind the fair bar *and* had no cushion saved.
  Earned, not a coin-flip. (Design implication for the HUD later: the bank should *read* as survivability so
  a low bank feels dangerous and steers conservative routing.)
- **Challenges never end the run** — they risk only economy/tempo. That asymmetry is why the information
  model can afford to hide leg parameters until arrival (below).

## The two-model generator

`MapGraph` is **not pure-procedural.** It mixes generated and authored content over a fixed skeleton:

- **Fixed skeleton.** Act count (3), boss cadence (boss terminal per act), act windows, lane count. The
  spine the rest rolls inside.
- **Rolled legs.** Each leg's `(target, darts_fronted)` is generated from the act window to hit a target
  pressure band; the knob used (target vs darts) is itself a roll for flavor variety.
- **Authored challenges.** Hand-tuned `ChallengeNode` Resources (see `02`), slotted by map-section. Set-pieces,
  not filler.
- **Slotted shops / events / bosses.** Placed by the type-mix rules below.

### Type mix and spacing

Per lane, soft target ranges (all `@export`ed for inspector tuning):

- **1–3 shops**, **0–2 events**, **1–3 challenges**, **remainder legs**, within the 7–12 node budget.
  (Min 7 = 1 shop + 0 event + 1 challenge + 5 legs; max 12 = 3 + 2 + 3 + 4 legs.)
- **Slightly higher challenge/event exposure than shop is intentional** — see "Exposure double-duty."

**Spacing via one distance-based weight function, not a hard flag + a separate decay.** For each
spacing-sensitive type, `weight = base × f(distance_since_last_of_type)`, where `f = 0` below the type's
minimum spacing and ramps back up with distance. That single curve gives both "never two shops within N nodes"
*and* "still rare-ish just past N" without a separate boolean. Tune the curve per type: shops/challenges
spaced hard, **legs near-flat** (they're allowed to repeat). All exported.

### Guarantees — kept soft (decided this session)

A hard "guaranteed shop on the pre-boss chokepoint" was considered and **declined.** With multiple shops per
lane plus the spacing rules, a zero-shop traversal is statistically rare, and a player who crosses a bridge at
the wrong moment and misses a shop because they didn't look two nodes ahead "should've looked ahead" — that's
a fair social contract, not a design failure. So: **soft coverage via spacing + counts, not a hard chokepoint
mandate.** (If playtesting shows zero-shop runs actually happen and feel bad, the chokepoint-guarantee is the
ready fix — place the must-have on the shared funnel node every path crosses. Noted, not built.)

## Information model — type on the map, parameters on arrival

- **The map shows node *type* only** (leg / challenge / shop / event / boss icons). It does **not** show a
  node's target or dart budget.
- **Parameters are revealed on arrival, as a moment.** At leg start: a center-screen readout (`Score to
  match: 401`) that then docks to its label slot (top-left), a `Darts fronted` readout that docks to the
  fronted-darts container, and the darts **print out one-by-one in sets of 3 with sound** — reusing the
  bank-save animation language (darts "arriving" reads the same whether banked or fronted). This ceremony is
  *why* params stay off the map.
- **This is safe because legs are fair-by-design + bank-cushioned** — blind entry isn't a coin-flip death, so
  hiding params is suspense, not punishment. (Transparency-scales-with-lethality still holds; legs just aren't
  as lethal as their "lose = die" framing first suggests.)

**Load-bearing consequence:** if type is the *only* routing signal, the branches **must differ in type
composition** or the map flattens into "pick any line, they're all the same." This promotes **Phase 04
path-biasing from optional to load-bearing** — it's the system that makes branching a real decision.

**Design-intent example to preserve (the proof the map is a real choice):** player has 5 spare darts, choosing
between `shop → leg → leg → challenge → shop → boss` and `leg → shop → leg → leg → shop → boss`. Same node
types, different order; which is better flips on bank state and run health. With only 5 darts a player may
take the second (another leg *before* the shop, to save up); flush or desperate for scoring, they take the
earlier shop. **If you can't say which is better without context, the branch is a real decision.**

## Exposure double-duty (the build-literacy primer)

Challenges and events are not just content — they're the front half of the **exposure layer** (the codex,
Phase 03, is the rest). Both *show items*, and because the player **picks 1 of 3** they *see more than they
take*. With slightly higher challenge/event exposure than shops, the player fills in their mental dictionary
of "what items exist / what to look for" **before** their first or second shop — so they walk into shopping
already literate instead of FAFO-wasting darts on a type they didn't understand. The same family glyph across
event icon → shop smoke → codex is one alphabet learned once.

## Resolved forks (were open at stub time)

- **Procedural vs hand-authored** → **both**, layered: fixed skeleton + rolled legs + authored challenges +
  slotted shops/events. Generator, not hand-placed map.
- **Topology** → shallow lanes + in-lane reconverging forks + bridge crossovers + funnel chokepoints; scaled
  to a 7–12 node act. Lean 2 lanes.
- **Node taxonomy** → leg, challenge, shop, event, boss (no non-eventful nodes; rest/treasure deferred).
- **Run-position model** → continuous numbers, sliding act windows, position-only pressure ratio; the field
  every downstream phase (challenge scaling, pool biasing, boss cadence) reads.
- **How existing structure maps on** → 3 acts = the 3 boss tiers (501/1001/1501 as act ceilings); legs become
  the rolled traversal between nodes; the every-5-legs cadence becomes the act length (~7–12 with the new
  node types folded in).
- **Information transparency** → type on map, params on arrival with ceremony.
- **Shop guarantee** → soft (spacing + counts), not a hard chokepoint.

## Remaining opens (all tuning / handoff, not structure)

- **Lane count** — 2 (lean) vs 3, and how many bridges per act.
- **The `expected_per_dart(position)` curve** — actual numbers; hand-tuned against playtest, robust to
  whatever the real median build turns out to score (the ratio framing absorbs it).
- **Per-type spacing curves** — the `f(distance)` shapes per node type.
- **Art handoff** — code-first rough visuals (grey rects / placeholder buttons) → Max tests flow → draws art →
  node scene reskinned without touching `MapGraph`.

## Related

- `specs/map/01-substrate-impl.md` — **the buildable companion to this doc** (2026-06-04). Code-grounded:
  current run-flow seam, `MapGraph`/`MapView`/`MapNode` breakdown, generation steps, and the slice-1 boundary
  (full topology, ported ladder; pressure-ratio generator deferred to slice 2). This doc stays as rationale.
- `specs/map/00-overview.md` — the program; sequencing rationale (frame before furniture).
- `specs/map/02-challenge-nodes.md` — the first new node type; the spatial opportunity cost here resolves its
  tempo-penalty question; blocked on this substrate for feel-testing.
- `specs/future/map-pool-filtration.md` — Phase 04 rides on this graph (path biasing); the information model
  makes it load-bearing rather than optional.
- `specs/future/darts-as-currency-economy.md` — the bank these stakes lean on (cushion, not HP).
- `specs/2026-06-03-scoring-on-the-board.md` — the `family` tag the event/shop/codex glyphs key off.
