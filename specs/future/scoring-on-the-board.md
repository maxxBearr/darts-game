---
Spec date: 2026-06-03
Status: SUPERSEDED 2026-06-03 by the build spec `specs/2026-06-03-scoring-on-the-board.md` (ready for
  implementation). This file is the original brainstorm, kept for design-history context only — read the
  build spec for current decisions. Key things the build spec changed/locked beyond this brainstorm:
  streaks become the *multiplicative* lever (additive face-value baseline × earned streak factor);
  the "global conditional" cut is concretely ColorBonus + OddEvenBonus; even/odd is cut as both bonus and
  streak; thematic streak split LOCKED (shaft = wedge slots, barrel = color slots); three board-item
  families (Scoring/Placement/Brush); hotspots no-stack (max +3/ring); FlipSign sidelined; tools-first
  sequencing (this scoring infra before the map). Sibling to `specs/future/map-pool-filtration.md`.
---

# Scoring Lives on the Board

## The problem

Mid/late game scales wrong. Stacked scoring multipliers let the player score absurd amounts, and
the *kind* of difficulty that creates is the wrong kind. There are three different "hard"s:

1. **Hard to reach zero** — scoring / route challenge (legit skill).
2. **Hard to reach zero *correctly*** — the double-out precision endgame (legit skill).
3. **Bookkeeping load** — tracking a huge, wildly-fluctuating number ("I'm at 380, this dart puts
   me at 20") even with the checkout helper. This is NOT difficulty, it's friction.

The real enemy is **unbounded multiplicative stacking**, which pushes numbers into a range where
the game stops being a precision test and becomes a mental-math test (#3). Fix the stacking and the
legibility problem dissolves. Note: this pairs with the map/fronted-darts work, which re-seats the
*primary* difficulty axis onto dart-efficiency under scarcity — so big-number-go-up stops being the
imperative and precise-finish-under-constraint becomes it. This doc covers the scoring/items half.

## Thesis: scoring power lives ON THE BOARD, not in a passive list

Move scoring power from a passive sidebar of stacking items into **spatial, aimed-for** effects on
the board. This single shift does a lot at once:

- **Bounds scaling by geometry + dart count** instead of item count — you only have so many darts to
  thread through the hot spots, and the board can only hold so much.
- **Makes a run a visual build snapshot** — glance at someone's board 10 minutes in and you see
  their build. Big identity / shareability win (clips, screenshots).
- **Makes it a *darts* game**, not a number-go-up game — power is about where you aim.
- **Unifies with everything else:** your accuracy zone (shipped accuracy-as-shape) is the tool you
  *shaped* to exploit the board you *built*.

### Two multiplier languages (and the one we drop)

- **Categorical** — streaks / bonuses that reward hitting a **type** (this color, this wedge).
- **Spatial** — **hotspots**: pick a ring/spot, it gets a multiplier (e.g. ×3). Player-placed,
  aimed-for.
- **DROPPED: global conditional multipliers** ("hit any X → ×N"). They're a muddy duplicate of the
  categorical language and don't coexist cleanly with hotspots. Cutting them isn't losing a
  mechanic, it's clarifying the taxonomy: categorical = streaks, spatial = hotspots, nothing in
  between.

**Why hotspots beat passive multipliers on legibility (not just on bounding):** a *located*
multiplier makes the math local and predictable — "the hot treble is 180, everything else is
normal." Passive ×items make *every* dart's value opaque, which is the source of the bookkeeping
pain. So hotspots fix #3 even at similar magnitude, because scoring becomes spatially knowable.

### Bounding has three legs, not one

Slot-capping alone bounds **breadth** (how many bonuses you run), NOT **depth** (the multiplicative
interaction of the few you hold). Watch the compound case: a streak × a hotspot × a board treble on
one well-placed dart. The ceiling needs all three:

1. **Slots** cap breadth (see components, below).
2. **Modest individual magnitudes** so a single held item can't explode.
3. **Spatial gating** (hotspots) so depth requires threading one dart through several conditions at
   once — which dart-count scarcity then limits.

## Components govern streak capacity

Tie **streak-slot capacity** to the dart components. This keeps components relevant all run (it
retroactively fixes the old "components stop mattering late-game" worry) and makes the component
build **declare your streak archetype** — a 2-color-slot barrel *is* a color-streak build, visibly,
on your dart. Build identity expressed through components and shown to the player.

- Make components the **single source of streak-capacity truth.** The existing
  `streak_slot_extension_reward` (noted buggy / not working as intended) becomes moot — cut it
  rather than fix it; component-governed capacity supersedes it.
- **Open fork:** streak capacity **consolidated on the barrel** (barrel owns all streak slots —
  cleanest for "one slot, one domain") vs **split by streak type** (barrel = color, shaft = wedge —
  more cross-slot tension, but muddies the clean domains and competes with shaft-owns-accuracy).
  Leaning consolidated for legibility; unresolved.

### Component role specialization (lean, don't silo)

Current component stats are ad-hoc ("all over the place" — each part got a different layout to make
unique combos). Streamline toward **thematic domains**, because the metaphor teaches the mechanic:

- **Shaft = accuracy shape** (the dart's spine / trajectory; sets your V-vs-H zone — the home for
  the shipped accuracy-as-shape system).
- **Barrel = handling + streak slots** (where the hand grips; control + your scoring engine).
- **Flight = the archetype verb** (already an ability/archetype pick).

**Do NOT hard-silo.** Disjoint domains would over-correct to "flat columns, pick one per slot" and
gut the weight/balance axis and cross-component combos that "parts = ceiling, balance = delivery"
depends on. Give each slot a clear *center of gravity* with residual stat spread — legible mental
model, still combinatorially deep.

## Board-state items (two risk tiers — sequence accordingly)

**Tier 1 — property edits on fixed geometry (low risk, do first):** the board shape stays put, only
values/properties change, and the checkout solver just reads current board state.
- **Hotspot multiplier** — select a ring, it gets ×N. (The cleanest expression of the thesis.)
- **Recolor / ring repaint** — already partly exists (per-ring color, `BrushModifier`).
- Other ring/property-based effects.

**Tier 2 — geometry edits (spicy, defer):** these touch hit detection AND force the checkout helper
to solve against a non-uniform board.
- Increase a wedge's size at the expense of its two neighbors.
- Bigger bullseye.
- Make all even (or odd) wedges bigger at the expense of the others.

Start with Tier 1 (hotspots especially), prove the "board as canvas" feel, defer Tier 2. ~80% of the
identity-and-control payoff comes from hotspots + recolors alone.

## Cut the even/odd streak (as part of this pivot)

Even/odd is **location-agnostic** — evens are scattered all over the board, so an even streak rewards
no spatial play and is trivially easy to maintain (you barely aim). In a game pivoting to "scoring is
about *where* you aim," it's the anti-spatial outlier *and* the low-effort dominant pick. Color and
wedge streaks are inherently spatial (colors cluster by ring and are paintable; wedge = same spot) —
keep those. Cut even/odd **as part of the rework**, not as an isolated nerf, since it's load-bearing
in current balance.

## Board as contested territory (boss payoff)

The reactive boss family already mutates the board (recolor-on-hit, drift). Once the *player* is a
board-editor, the boss's mutations **fight the player's edits** — you set a hot ring, the boss
recolors it, you re-paint, it drifts. A live contest over a shared visible surface, far richer than
"boss applies debuff," and it gives every board-boss clean counterplay (board-editing items).
Reinforces the build-counter-vs-environmental principle from the boss system.

## Art-direction constraint: legibility through flash

On-board scoring is the most shareable *and* the most prone to visual overload. The thing that makes
it work — "I know where the points are" — collapses if the board is recolored, hotspotted, resized,
*and* boss-debuffed at once and becomes noise. The art discipline is **information layering**: the
scoring-relevant state must stay readable *through* the flash. Pretty must never bury legible. Hold
this rule and visual identity + mechanical clarity reinforce each other.

## Open questions

- **Streak capacity: consolidated (barrel) vs split by type** across components.
- **Depth-stacking ceiling** — keep streak × hotspot × treble bounded (legs 2 + 3 above).
- **Component specialization** — how far to lean toward thematic domains vs preserving combo spread.
- **Checkout solver must read edited board state** — fine for Tier 1 property edits; Tier 2 geometry
  edits are a genuine solver/hit-detection lift (interacts with `specs/future/async-checkout-solver.md`).
- **Art direction / legibility-through-flash** — the central visual problem to solve.

## Related
- `specs/future/map-pool-filtration.md` — map + reward-pool steering; the acquisition-frequency half.
- CLAUDE.md / `specs/future/darts-as-currency-economy.md` — fronted darts as the difficulty axis.
- `specs/2026-06-02-accuracy-upgrades-as-shape.md` — shaft owns the zone shape; the spatial tool.
- Boss system (reactive families) — board-as-contested-territory counterplay.
