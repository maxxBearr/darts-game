---
Spec date: 2026-06-03
Status: SHIPPED 2026-06-03 (core), via Claude Code + this session's debug & visuals pass. Honed from the `specs/future/scoring-on-the-board.md` brainstorm into
  a build spec. Decisions locked this session with Max: thematic streak-slot split; **two separated
  scaling axes** — a bounded *additive* face-value baseline (hotspots + wedge values, item-driven) and an
  earned *multiplicative* ceiling (streaks become the one multiplier, gated by skill + component capacity);
  drop the unslotted global bonuses; **three board-item families** (Scoring / Placement / Brush) plus
  streaks as a separate axis; sideline FlipSign for now. Full item catalog (geometry defined but staged).
  Tools-first: prove this scoring infrastructure + visuals standalone, then do the map. Magnitudes are
  starting points, not gospel.
Implementation: Shipped via Claude Code, then debugged & extended this session. AS-BUILT: streaks went
  additive→multiplicative but combine into ONE factor (streak_factor = 1 + Σ contributions) applied last,
  NOT per-streak compounding (that was the ×64 bug — fixed). Per-category streak capacity from components
  (DartComponent.streak_slot_grant, base 1 wedge + 1 color) replaced the global max_streak_slots;
  StreakSlotExtensionReward removed. Pool migration done (ColorBonus + OddEvenBonus + all parity/even-odd
  streak classes dropped; FlipSign unlisted but class + Mirror-Zone relic kept; ColorStreak weight raised;
  `family` tag Scoring/Placement/Brush added, streaks excluded). HotspotModifier live (no-stack, +1/+2/+3,
  segment-picked; checkout solver + tooltip read it and the live streak factor). Visuals shipped: hotspot
  smoke shader (toggle `use_hotspot_shader`, multi-tone per-wedge-color on alpha blend) + smokified "+N"
  label + recurring streak pulse on dart markers (count ≥ 2, grey→white brightness + slow→fast speed ramp).
  Also fixed two pre-existing bugs: Pool Widener (shop loop now reads `shop_pick_count`) and the post-leg
  replace-streak warning (now uses `_get_replacement_text` like every other path).
  DEFERRED: Tier-2 geometry; **shop/pool steering by family (the NEXT spec — typed shop)**; map/fronted-darts;
  hotspot "value-in-the-smoke" (the shader's `use_glyph` path). MAX-MANUAL: component stat layouts +
  streak_slot_grant values (inspector). CAVEATS: result.streak_count is repurposed as the combined
  multiplier for the HUD readout; a debug bulk-grant path can exceed streak capacity (not reachable in
  normal play).
Supersedes: `specs/future/scoring-on-the-board.md` (brainstorm) once this ships. Pairs with the parked
  map / fronted-darts work (`specs/future/map-pool-filtration.md`) — see Sequencing.
---

# Spec: Scoring Lives on the Board

**Two goals drive this spec, per Max:** (1) nail down *exactly what the items are*, and (2) nail down
*exactly how to balance the dart components*. Everything below serves those two. The art/boss/sequencing
sections are context so the build doesn't paint itself into a corner.

## The problem (recap)

Mid/late game scales wrong. Stacked scoring multipliers let the player score absurd amounts, and the
*kind* of difficulty that creates is the wrong kind. Three different "hard"s: hard to reach zero (legit
skill), hard to reach zero *correctly* (the double-out precision endgame, legit skill), and **bookkeeping
load** — tracking a huge, wildly-fluctuating number ("I'm at 380, this dart puts me at 20"). The third is
friction, not difficulty. The root cause is **unbounded passive accumulation** — stack enough always-on
bonuses (by playing long enough) and every dart is huge without thought. Fix *that* — separate the bounded
item-driven baseline from an earned, skill-gated ceiling — and the legibility problem dissolves.

This spec is the scoring/items half of the mid-game rebalance. The difficulty-axis half (map + variable
fronted darts) lives in `specs/future/map-pool-filtration.md` and is built first (see Sequencing).

## Thesis + the bounding model (the balance backbone)

**Scoring power lives ON the board** — spatial, aimed-for effects — not in a passive sidebar of stacking
items. Two multiplier languages, nothing in between:

- **Categorical** — streaks that reward hitting a *type* (this color, this wedge), capacity-gated by
  components.
- **Spatial** — hotspots / board edits that reward hitting a *place* (this ring), player-placed.

### What's broken, and the fix: two separated scaling axes

Scoring is **already a single additive multiplier per dart** — confirmed in code (`color_bonus_modifier.gd`,
`odd_even_bonus_modifier.gd`, and the streaks all do `result["multiplier"] += N` then recompute
`face_value × multiplier`). A triple-20 with a Red +2 and an Even +2 is `20 × (3 + 2 + 2) = 140` — the
"four extra twenties on the 60." A streakless great dart around ~140 feels right (Max: "that scoring is
okay").

The explosion is **unbounded breadth driven by time-in-run**. The global bonuses (`ColorBonusModifier`,
`OddEvenBonusModifier`) aren't slot-restricted, so you accumulate an arbitrary pile of always-on `+N` and
one dart creeps to ×15–20 = 300–400 — *passively*, just by playing long enough to acquire enough items.
You always meet your scoring criteria without thought. The leak is attrition, not skill.

**The fix Max landed on: split scoring into two separated axes, and gate the big one behind skill.**

- **Face-value axis — additive, bounded, item-driven.** Ring mult + hotspot bonuses + wedge-value boosts,
  all added into the multiplier exactly as today. This is your *reliable baseline*: items give a dependable
  floor, capped by modest magnitudes. A streakless great dart tops out ~140.
- **Exponential axis — multiplicative, earned, the only way past baseline.** Streaks become the one
  multiplicative lever: a running streak multiplies the dart. To put a real one-dart dent in 1001 (the old
  600-point dart), you now need a *long maintained streak*, not five black modifiers acquired by attrition.

```
dart_score = face_value × (ring_mult + Σ hotspot_bonus + Σ wedge_value_bonus) × streak_factor
             └────────────────── additive, bounded baseline ──────────────────┘   └─ earned ─┘
```

Why this is the real structural fix (not just the breadth band-aid):

- **It removes the time-in-run dependency.** The only path to runaway scoring is now *active* — maintain a
  streak, which resets on a miss and is capacity-gated by your components. Scaling is something you *do*,
  not something you *accumulate*.
- **It cleanly separates the two scalings.** Hotspots/wedge-values move the *face-value* needle (bounded,
  legible); streaks own the *exponential* needle (earned, run-defining). No more muddle where both pour out
  of the same passive pile.
- **Two complementary ways to scale a hot ring, different risk profiles.** *Board-built (safe):* stack a
  hotspot `×` and a wedge-value `+` on the same ring — make treble-20 a hotspot *and* add +6–10 to the 20,
  and that ring pays a lot every time you hit it, persistently, no reset. *Streak (risky):* multiply it
  further by running a streak through it. A board-scaler builds a high, reliable ring and can largely skip
  the keep-streak dilemma; a streak-scaler takes the risk for a higher ceiling. Both are **aim-gated** (you
  must hit the juiced ring), which is what bounds the face-value path — concentration on a spot you have to
  thread, not an always-on pile. So scaling becomes a *choice of route*, not "play long enough."
- **It supercharges Goal 2.** Components govern streak capacity, and streaks are now the exponential
  engine, so your component build literally sets your scaling ceiling — components matter to the very end.

**The tension this buys (intentionally, and opt-in):** for a *streak-scaler*, a hot streak near a checkout
becomes a real dilemma — keep it and risk a massive overshoot/bust, or break it to land the exact double.
That's *legit* "hard to reach zero correctly" difficulty, and it's **predictable** (you know your streak
count and your hot ring), not opaque bookkeeping. A *board-scaler* who leaned on hotspot + wedge-value
faces it far less — their scaling is persistent and swings less, so they trade ceiling for control. Either
way the checkout helper must compute against live streak state (the solver already snapshots it — see Touch
points).

**Reference anchor:** a *typical* streakless great dart sits ~140 (the feel you already like). Heavy board
investment on one ring (hotspot + wedge value) can push that single ring higher — fine, because it's gated
by having to hit that exact spot; streaks are the sanctioned multiplicative way past it. Key tuning dials:
streak growth shape, and whether a single ring needs a soft stacking cap (Open Questions).

**Don't over-tune scoring difficulty in this pass.** Once the map / variable-fronted-darts layer lands,
difficulty *zigzags* — tension comes from the fronted-dart count changing per node, not only the score
climbing. So scoring here only needs to be **bounded and legible**, not the sole difficulty driver. Leave
headroom; the map adds the non-vertical tension later (reinforces tools-first).

## Goal 2 — Component balance

### Thematic streak-slot split (LOCKED)

Streak-slot capacity is **split by streak type and mapped to the part it thematically belongs to**:

- **Shaft → wedge-streak capacity.** A wedge streak is hitting the *same number repeatedly* — pure
  precision/repetition, which is what the shaft (spine, trajectory, accuracy shape) already governs. So
  wedge-slot capacity on the shaft is *synergy*, not domain overload.
- **Barrel → color-streak capacity.** The barrel is the handling / scoring-engine part; color is the
  paintable, ring-clustered "engine" axis.
- **Flight → the archetype verb** (unchanged — already an ability/archetype pick via `throw_modifier`).

This yields two legible build identities straight out of the components: a **sniper** (high-accuracy
shaft, wedge-locking) and a **painter** (color barrel, paint/spread). It also delivers the balance-axis
depth Max wanted: a *skewed* shaft that trades vertical accuracy for an extra wedge slot becomes a real,
tempting choice ("imbalance can be correct"). Cost over consolidating on the barrel: one extra capacity
dial (two numbers, not one) — cheap.

### Per-category capacity data model (replaces the global slot count)

Today `ScoringModifierManager.max_streak_slots` is a single global `int` (default 3) and the conflict
logic (`get_streak_conflicts()`) is a convoluted `bonus_used < bonus_slots` scheme. Replace it with
**per-category capacity sourced from the equipped components:**

- Add to `DartComponent` a `streak_slot_grant: int` export (`## How many streak slots this component
  grants. On a shaft → wedge-streak slots; on a barrel → color-streak slots. Ignored on flights.`).
- `DartBuild.get_total_stat_bonuses()` (or a sibling `get_streak_capacity()`) routes the grant by
  `component_type`: shaft's grant → WEDGE capacity, barrel's grant → COLOR capacity. Base of 1 each so a
  vanilla build can still hold one of each.
- `ScoringModifierManager` holds `streak_capacity: Dictionary` keyed by `StreakCategory` (WEDGE, COLOR),
  set from the build on assembly/equip. `get_streak_conflicts()` enforces *per-category* capacity against
  it. No PARITY key (even/odd is cut — see below).
- **Cut `StreakSlotExtensionReward`** and remove `streak_slot_extension` from `RewardRegistry.ALL_REWARDS`.
  Component-governed capacity is now the single source of truth; the reward is moot (and was noted buggy).
  Cutting beats fixing.

### Stat-domain refactor — lean, don't silo (MAX-MANUAL, not a Claude Code task)

**Max tunes the per-component stat layouts and the streak-grant values himself, in the inspector.** Claude
Code's only component job is to add the inspector-editable `streak_slot_grant` export + the plumbing that
routes it (above). The guidance below is Max's *reference* for that manual pass, not work to automate.

Current component stats are ad-hoc ("each part a different layout, no two alike"). The streak split above
already gives each part a center of gravity; finish the job *lightly*:

- **Shaft** leads with **accuracy** (`h_accuracy_bonus`/`v_accuracy_bonus`, the home of the shipped
  accuracy-as-shape system) + carries `streak_slot_grant` → wedge slots.
- **Barrel** leads with **handling** (`h_range`/`v_range`/`h_speed`/`v_speed`) + carries
  `streak_slot_grant` → color slots.
- **Flight** leads with the **verb** (`throw_modifier`) + minimal stat spread.

Do **not** hard-silo (disjoint columns, one stat domain per slot) — that flattens combos and guts the
weight axis "parts = ceiling, balance = delivery" depends on. Each slot gets a *center of gravity with
residual spread*: keep "no two alike" as *within-domain* variety (two shafts both lean accuracy+wedge,
but one is high-accuracy/few-slots, the other skewed/many-slots). Legible mental model, still
combinatorially deep. This is the one component decision still open to discourse — see Open Questions.

**Assembly-paralysis watch:** a component now carries stats + weight + a streak grant (+ flight verbs).
That's a lot of decision weight per pick. Keep the streak grant a small number (0–2) and let it read at a
glance on the part.

## Goal 1 — The item catalog

### Migration: every current modifier gets a verdict

The current `ModifierRegistry.MODIFIER_TYPES` is a flat pool of 10. Under the new taxonomy:

| Current modifier | Weight | Verdict | Reason |
|---|---|---|---|
| `ColorBonusModifier` | 30 | **DROP** | A global conditional ("hit red → ×N"). Redundant with color *streaks*. Its fans move to color-streak + paint builds. |
| `OddEvenBonusModifier` | 25 | **DROP** | Global conditional *and* parity — doubly against the thesis (even/odd is cut entirely). |
| `WedgeValueModifier` | 25 | **KEEP → Scoring family** | Adds to a wedge's face value = the additive face-value axis. Tier-1 property edit on fixed geometry. |
| `StreakBonusModifier` (wedge) | 15 | **KEEP → Streak axis (now multiplicative)** | The wedge streak — inherently spatial (same spot). Capacity from shaft. Becomes the exponential lever. |
| `ColorStreakModifier` | 4 | **KEEP → Streak axis, raise weight** | The color streak — spatial (colors cluster/are paintable). Capacity from barrel. Bump weight (4 is vestigial). |
| `WedgeSwapModifier` | 10 | **KEEP → Placement family** | Board edit (swap two wedges). Property edit, Tier-1. |
| `BrushModifier` (recolor) | 15 | **KEEP → Brush family** | Per-ring recolor; already `BOARD_MUTATION`/`ON_ACQUIRE`. Core to painter/color-streak builds. |
| `FlipSignModifier` | 15 | **SIDELINE** | Pull from the pool this pass (see below). Was a band-aid for overscoring, which we now fix structurally. Mechanic + Mirror-Zone relic stay intact. |
| `EvenStreakModifier` | 15 | **DROP** | Even/odd streak — anti-spatial (parity is scattered, rewards no aiming). |
| `OddStreakModifier` | 15 | **DROP** | Same. |
| `ParityStreakModifier` (base) | — | **DROP** | Base class for the above; remove with them. |

**Net pool after migration:** the **streak axis** = {wedge streak, color streak}; **board items** across
three families (below) = {hotspot (new), wedge value, wedge swap, brush recolor}. Dropping ColorBonus +
OddEvenBonus + the three parity classes + sidelining FlipSign removes ~125 weight, so **the pool must be
reweighted** — raise color-streak off 4 and tune board items up so the choice board still feels full. Pool
weights are static per class, so this is code-only tuning.

### Three board-item families (+ streaks as a separate axis)

With the globals gone, nearly every *item* is now a board modification. Tag each with a **family** so the
shop / reward pool can be steered (e.g. always surface one of each). This `family` field is exactly the
prerequisite `specs/future/map-pool-filtration.md` flagged as missing — adding it here resolves that
blocker and locks the player-facing taxonomy:

- **Scoring** — moves the face-value axis: `HotspotModifier` (ring multiplier bonus), `WedgeValueModifier`
  (+X to a wedge face). *(FlipSign would live here — sidelined for now.)*
- **Placement** — moves things around: `WedgeSwapModifier`, and the deferred Tier-2 geometry edits (resize
  wedge, bigger bull, even/odd-wedge resize).
- **Brush** — recolor: `BrushModifier`. Its own utility family because color drives color-streak builds.
- **Streaks** are **not** a board-item family — they're the separate *multiplicative* axis, acquired into
  component-gated slots, not the shop's board-item pool. Keep them out of the family taxonomy.

Implementation: add a `family` enum/field to the scoring-modifier base (today there's only the
RELIC/BOARD_MUTATION `kind`, which is about behavior, not the player-facing category). Don't wire shop
steering yet (shop is later) — just land the tag so the data's ready.

### Sidelining FlipSign (the de-escalated band-aid)

`FlipSignModifier` (the item that flips a wedge's sign so it subtracts) was introduced to counter
overscoring — when items pushed you past a clean checkout, a negative wedge let you claw back down. We're
now fixing overscoring *structurally* (bounded baseline + skill-gated streaks), so its main use case
shrinks. Max doesn't hate it but wants it **out of the pool for this pass** to test the new items cleanly,
then revisit whether it still earns a slot. Important: this only removes the *item* from `MODIFIER_TYPES`.
The intrinsic wedge-flip mechanic and the **Mirror-Zone relic** (which grants flips + "busts don't end
turn") stay shipped and untouched — confirm Mirror Zone still functions with no FlipSign item in the pool
(it grants its own flips, so it should). Flag for the branch.

### New item — Hotspot multiplier (Tier 1, the headline)

The cleanest expression of the thesis. A `HotspotModifier`:

- `kind = BOARD_MUTATION`, `timing = ON_ACQUIRE`, `config_type = PICK_SEGMENT` (reuse the BrushModifier
  selection flow — it already lets the player pick a ring on a wedge).
- On acquire, marks a chosen ring (`<wedge_index>:<RingName>`) as a hotspot granting a flat
  `hotspot_bonus` to the combined multiplier for darts landing there.
- Store it parallel to `voided_rings`: add `ScoringModifierManager.hotspot_rings: Dictionary` keyed
  `"<wedge_index>:<RingName>"` → bonus int. The per-dart scoring path adds the bonus into
  `effective_multiplier` (see bounding model).
- **Magnitude:** common `+1`, uncommon `+2`, rare `+3` to the multiplier (NOT a ×3 standalone — it folds
  into the additive baseline). Tune against the ~140 streakless anchor.
- **No stacking on a ring (LOCKED).** One hotspot tier per ring, max `+3`. A second hotspot must go on a
  *different* ring — so duplicates spread the board (more hot rings = more spatial play, better "board as
  canvas"), they never over-juice one spot. This is the per-ring cap, by construction. Concentration on a
  single power ring is still available the intended way: hotspot + wedge-value + thread a streak through it.
  Implementation: the segment picker disallows (or no-ops) selecting an already-hotspotted ring; never a
  silent downgrade. Same-tier *merge* (two `+2` → one `+3`, capped) is parked as an optional future sink
  for duplicates, not built this pass.
- **The checkout solver must read it.** Same pattern as `voided_rings`: the solver already consults
  `effective_wedge_values` + `voided_rings`; it now also consults `hotspot_rings` so checkout math reflects
  the hot ring. This is a Tier-1 property edit, so the board *shape* is unchanged — the solver reads new
  values on fixed geometry, no hit-detection change.
- **The target tooltip must read it** — when hovering a hot ring, the tooltip shows the boosted value
  (and, ideally, the streak-multiplied value at current streak), same as it surfaces streak state today.

### Hotspot visual / shader (groundwork for a reusable item-flair shader)

The visual has to *sell* the headline mechanic, so it's an explicit goal of this pass, not polish-later.
Direction from Max:

- **Smoky look, like the shop shader, with the value baked in** — a legible "smoky ×3" sitting *in* the
  smoke so the multiplier reads at a glance on the board. The number is part of the effect, not a separate
  label floating over it.
- **Respect, don't override, the ring's painted color.** Unlike the shop shader (which overrides), the
  hotspot shader should *enhance* the underlying ring color — read as an intensification of what's painted
  there, so hotspot + brush compose visually instead of fighting (and the painter build's colors survive).
- **Build it as reusable groundwork.** Same shader family could later flair shop items with a symbol per
  item *family* (Scoring / Placement / Brush). Shop is out of scope now, but design the shader so a
  baked-in glyph/number is a parameter, not a one-off.
- Obeys the legibility-through-flash rule (below): the hot ring's indicator must survive recolor and boss
  overlay.

**Feasibility (number/glyph that's made of smoke, not pasted on it):** yes, this is doable and the right
instinct. The technique is to feed the glyph into the shader as a *mask*, not a sprite on top: bake the
digit(s) to an SDF/MSDF texture (or a plain alpha glyph), then in the fragment shader let the smoke noise
*flow through* the mask — domain-warp the UV with curl/flow noise so the glyph's edges wisp and dissipate
like smoke, while a slightly steadier inner core keeps it readable. Tint by sampling the ring's painted
color (multiply/screen) so it enhances rather than overrides. The one real craft challenge is exactly the
legibility-through-flash tension: too much warp and the number melts. The fix is the two-layer trick — a
calmer, higher-contrast core + a turbulent outer that's pure flavor. In Godot this is a single
`ShaderMaterial` with the glyph as a texture uniform + animated noise; very tractable. Build the baked
glyph/number as a *parameter* so the same shader later flairs shop items with a per-family symbol.

### Source-located scoring flair (the feedback grammar)

A clean visual grammar falls out of the two axes, and it's worth designing in from the start because it
*teaches the mechanic through feedback* and reduces reliance on the scoring-source text label "chiming in":

- **Spatial scoring comes from the board.** Hotspot bonus points emanate from the hotspot itself — extra
  20s that *float out of the smoke* looking smoky, so you literally see the hot ring pay out. The source
  of the number is the place that scored it.
- **Streak scoring comes from the dart.** Because streaks are dart-dependent (governed by component
  capacity set in assembly), their scoring should visibly originate at the *dart marker*: a glow/aura
  around the marker indicates an active streak (and its intensity = streak strength), and streak-multiplied
  points spill out of that glow. The active streak wedge can also light up. This makes "your darts are your
  streak engine" legible in the moment, reinforcing the assembly-screen build identity.
- **Net effect:** spatial points read from the board, multiplicative points read from the dart — you learn
  *where your power lives* by watching where the numbers come from. This serves legibility, spectacle, and
  the build-identity goal at once, and it's the kind of punchy on-board feedback that makes clips/screenshots
  pop. The generic scoring-source label can shrink to a fallback rather than the primary readout.

### Tier-1 board items (build first)

Hotspot (above) + the kept board items: wedge value (Scoring), wedge swap (Placement), brush recolor
(Brush). All are property edits on fixed geometry; the solver reads current state, no hit-detection lift.
This is ~80% of the "board as canvas" payoff and carries zero solver-geometry risk. FlipSign is sidelined,
not built.

### Streaks — the multiplicative axis (changes from additive)

Wedge streak (capacity from shaft) and color streak (capacity from barrel), capacity-gated per category by
components. **The meaningful scoring change in this spec lives here:** streaks move from additive
(`result["multiplier"] += N`, linear, today) to **multiplicative** — a running streak applies a
`streak_factor` to the dart *after* the additive baseline is computed. This is what makes streaks the
exponential lever and the only way past the ~140 baseline.

- Apply order matters: compute `face × (ring + Σhotspot + Σwedge_value)` first (the streak modifiers must
  run *last* in the scoring pipeline, after the additive bonuses), then multiply by `streak_factor`.
- `streak_factor` shape is the headline tuning dial — linear-in-count (`×streak_count`) is the likely
  sweet spot; geometric (`×r^n`) explodes too fast. See Open Questions; validate on branch.
- Existing reset/scope behavior (per turn / leg / run, `save_streak_state()` / `restore_streak_state_from()`
  for the solver) is untouched — only the *magnitude application* changes from add to multiply.

### Tier 2 — geometry edits (DEFINED here, DEFERRED in build)

These complete the catalog (Goal 1) but are staged behind Tier 1 + checkout-solver readiness because they
touch **hit detection** AND force the solver to solve a **non-uniform board**:

- **Wedge resize** — grow one wedge at the expense of its two neighbors.
- **Bigger bullseye.**
- **Even/odd-wedge resize** — grow all even (or odd) wedges at the expense of the others. (Note: this is a
  *spatial* parity effect, which is fine — it's about *where*, unlike the cut parity *streaks*.)

Build gate: land Tier 1, prove the feel, then take geometry once the checkout solver can solve against
non-uniform geometry (interacts with `specs/future/async-checkout-solver.md`).

## Cutting even/odd (migration, not an isolated nerf)

Even/odd is **location-agnostic** — evens are scattered, so a parity streak rewards no aiming and is the
low-effort dominant pick: the anti-spatial outlier in a game pivoting to "scoring is about *where* you
aim." Cut it as part of this rework (it's load-bearing in current balance, so don't pull it alone):

- Remove `EvenStreakModifier`, `OddStreakModifier`, `ParityStreakModifier` from the pool and registry.
- Remove `OddEvenBonusModifier` (the non-streak parity bonus) too.
- Drop the `PARITY` value's *streak* role (the enum value can stay for safety, but nothing populates it).
- Tutorial/help and any pool-weight tables that reference parity need a scrub (see Touch points).

Color and wedge streaks stay — both are inherently spatial (colors cluster by ring and are paintable;
wedge = same spot).

## Board as contested territory (boss payoff)

The reactive boss family already mutates the board (recolor-on-hit, drift via `voided_rings`). Once the
*player* is a board-editor (hotspots, paint), boss mutations **fight player edits** — you set a hot ring,
the boss recolors/drifts it, you re-paint or re-place. A live contest over a shared visible surface, far
richer than "boss applies debuff," and it gives every board-boss clean counterplay (board-editing items).
No new boss work in this spec; just don't build the player's edits in a way that can't be contested
(store hotspots/paint as board state the boss hooks can already read/mutate — `hotspot_rings` parallel to
`voided_rings` does exactly this).

## Art-direction constraint: legibility through flash

On-board scoring is the most shareable *and* the most overload-prone. The thing that makes it work — "I
know where the points are" — collapses if the board is recolored, hotspotted, resized, *and* boss-debuffed
at once and becomes noise. The discipline is **information layering**: scoring-relevant state stays
readable *through* the flash. Pretty must never bury legible. Concretely: the hot ring needs a persistent,
high-contrast indicator that survives recolor and boss overlay; the per-dart combined multiplier should
surface as one readable number. Not a build blocker for Tier 1, but design the hotspot indicator with this
in mind from day one.

## Sequencing — tools before the house (Max's call, 2026-06-03)

The earlier instinct was "lock the map / fronted-darts feel first." **Max has overridden it: build and
test this scoring/items infrastructure — and its visuals — standalone first, then do the map.** Reasoning:
"we need the tools to work first before we try to build the house." The map is the progression layer; this
spec is the toolkit it will arrange. So this pass proves the toolkit in isolation, on the *current* leg
cadence, and the map is a separate spec afterward.

Order within this pass:

1. **Component capacity refactor** — per-category streak slots sourced from components; cut the extension
   reward. (Establishes the breadth cap everything else relies on.)
2. **Pool migration** — drop the unslotted globals (`ColorBonus`, `OddEvenBonus`) and the parity-streak
   classes; sideline `FlipSign`; raise `ColorStreak` weight; add the `family` tag; reweight. (Closes the
   passive-accumulation leak.)
3. **Streaks → multiplicative** — convert streak modifiers from additive to a `streak_factor` applied last;
   update checkout solver + tooltip to account for live streak state. (The core scoring change; the
   exponential axis.)
4. **Tier-1 items** — `HotspotModifier` (the headline) + the family-tagged board items; hotspot folds into
   the additive baseline and the checkout solver reads `hotspot_rings`.
5. **Visuals / feel test** — hotspot shader (smoky baked-in value, enhances ring color), board-as-canvas
   feel. Explicit goal of the pass, not polish-later.
6. **Tier-2 geometry** — deferred behind checkout-solver readiness; out of scope for this pass.

Then, separately: the **map + variable fronted darts** progression spec arranges these proven tools into a
run. Keep magnitudes exported/tunable so that later layer can rebalance without code surgery.

## Implementation handoff (for Claude Code)

**Conventions (house style):** static-type every variable; comment frequently; `##` doc comments on all
`@export` vars stating what they do and what the values mean (these render as inspector hover text); use
`@export` liberally for anything Max will want to tune. There's no Godot in the sandbox, so a headless
parse isn't possible — note that, and Max opens the project to confirm it compiles.

**Component streak qualities must be inspector-editable.** `streak_slot_grant` (and any future streak
quality) is an `@export var` on `DartComponent` with a `##` hover description, set per-component in the
inspector. Claude Code adds the field + the routing plumbing (DartBuild → per-category capacity → manager);
**it does not choose the numbers.**

**Out of scope for this pass (Max-manual or deferred):**

- **Component stat layouts + streak-grant values** — Max tunes these manually in the inspector. The
  thematic guidance (shaft = accuracy + wedge, barrel = handling + color) is his reference, not a task.
- **Tier-2 geometry items** — defined in the catalog, deferred behind the checkout-solver lift.
- **Shop / pool steering by family** — land the `family` tag only; don't wire steering (that's the map spec).
- **The map / fronted-darts progression** — a separate later spec.
- **FlipSign** — unlisted from the pool, not deleted; revisit later. **Merge-stacking for hotspots** —
  parked future option, not built.

## Touch points (code, confirmed 2026-06-03)

- `scripts/scoring_modifier_manager.gd` — **the scoring pipeline changes in one specific way: the additive
  face-value baseline stays, but streaks now apply a multiplicative `streak_factor` *last*, after all
  additive bonuses.** Enforce apply-order (additive bonuses → then streak multiply). Replace
  `max_streak_slots: int` with `streak_capacity: Dictionary` (per `StreakCategory`); rewrite
  `get_streak_conflicts()`/`get_streak_conflict()` for per-category capacity. Add `hotspot_rings:
  Dictionary` parallel to `voided_rings`; the additive path adds the hotspot bonus into the multiplier just
  like a bonus does today.
- `scripts/scoring_modifier.gd` (base) — add a `family` field/enum (Scoring / Placement / Brush; streaks
  excluded) for the player-facing taxonomy. Distinct from the existing `kind` (RELIC/BOARD_MUTATION), which
  is about behavior. Don't wire shop steering yet — just land the tag.
- `scripts/dart_components/dart_component.gd` — add `streak_slot_grant: int` `@export` with a `##` hover
  doc, inspector-editable per component. **Do not edit the stat layouts** — Max tunes those + the grant
  values himself in the inspector.
- `scripts/dart_build.gd` — `get_total_stat_bonuses()` / new `get_streak_capacity()`: route each
  component's grant by `component_type` (shaft→WEDGE, barrel→COLOR), base 1 each.
- `scripts/modifier_registry.gd` — remove `ColorBonusModifier`, `OddEvenBonusModifier`,
  `EvenStreakModifier`, `OddStreakModifier`, `ParityStreakModifier` from `MODIFIER_TYPES`; **remove
  `FlipSignModifier` from the pool too (sideline — keep the class/mechanic, just unlist it)**; add
  `HotspotModifier`; reweight remaining (raise `ColorStreakModifier` off 4) and set `family` on each.
- `scripts/modifiers/hotspot_modifier.gd` — **new**; model on `brush_modifier.gd` (BOARD_MUTATION /
  ON_ACQUIRE / PICK_SEGMENT). Writes into `hotspot_rings`. Family = Scoring.
- `scripts/modifiers/streak_bonus_modifier.gd` + `color_streak_modifier.gd` — **convert additive bonus to
  a multiplicative `streak_factor` applied last.** Keep scope/reset/state-snapshot logic as-is.
- `scripts/modifiers/wedge_value_modifier.gd` — family = Scoring (face-value axis). `wedge_swap_modifier.gd`
  — family = Placement. `brush_modifier.gd` — family = Brush.
- Mirror-Zone relic (`scripts/rewards/mirror_zone_reward.gd`) — verify it still grants/uses wedge flips
  with `FlipSignModifier` out of the pool (it grants its own flips, so expected fine — confirm on branch).
- Checkout solver + target tooltip — must read `hotspot_rings` AND account for current `streak_factor`
  (the solver already snapshots streak state) so suggested checkouts and hovered values reflect a live
  streak. This is the trickiest correctness point of the pass.
- `scripts/rewards/reward_registry.gd` + `scripts/rewards/streak_slot_extension_reward.gd` — remove
  `streak_slot_extension` from `ALL_REWARDS`; delete/retire the reward class.
- Checkout solver (the path reading `effective_wedge_values` + `voided_rings` in `dartboard.gd` /
  `x01_game.gd`) — also read `hotspot_rings` for Tier-1 correctness. Tier-2 geometry is the deferred lift.
- Dartboard rendering (`dartboard.gd`) — hotspot indicator (legibility-through-flash); reads
  `hotspot_rings`.
- Tutorial / help (`specs/2026-05-27-tutorial-revamp.md`, rules slideshow) — scrub parity/even-odd and
  global-bonus references once those items are gone.

## Open questions

- **Stat-domain refactor depth** — how hard to lean into thematic centers of gravity vs. preserving the
  current "no two alike" spread. Recommendation above (light pass, within-domain variety); still open to
  discourse, validate on branch.
- **Streak growth shape (the headline dial)** — how `streak_factor` scales with count. Linear-in-count
  (`×streak_count`) vs a gentler curve vs capped. This sets how big an "earned" dart can get and how sharp
  the keep-streak-vs-finish-clean dilemma is near checkout. Pure playtest, but the most important number in
  the spec.
- **What the streak multiplies** — the whole dart (`face × baseline × streak_factor`, recommended and
  assumed above) vs only the streak-qualifying contribution. Whole-dart is simpler and matches "put a dent
  in 1001"; confirm.
- **Hotspot magnitudes** — common/uncommon/rare at `+1/+2/+3` to the multiplier (Max's call, mirrors the
  current rarity ladder). Validate the typical streakless great dart stays ~140.
- **Hotspot stacking — RESOLVED:** no stacking; one tier per ring, second goes elsewhere (see Hotspot
  item). Merge parked as a future option.
- **Wedge-value stacking — uncapped for now (Max's call).** Reason: magnitudes are low (rare tops out ~+6/7)
  *and* it's self-balancing — raising a wedge's face value works against your own checkout precision (you
  overshoot more easily), so over-stacking carries a real strategic downside rather than being free power.
  Watch in playtest; add a per-wedge cap only if it runs away.
- **Pool reweighting** — target distribution after dropping ~125 weight of globals + parity + FlipSign, so
  the choice board still feels full and varied across the three families.
- **FlipSign revisit** — does it earn a slot back once overscoring is structurally fixed, or stay retired?
  Decide after the new items are tested. Confirm Mirror Zone is unaffected by its removal.
- **Base streak capacity** — start every build at 1 wedge + 1 color slot? Or 1 total until a component
  grants more? (Leaning 1+1 so a vanilla dart isn't streak-locked.)
- **Hotspot vs. boss drift interaction details** — exactly how a boss recolor/drift should affect a hot
  ring (clear it? move it? halve it?). Deferred to the boss-contest pass; just keep the state contestable.
- **Tier-2 solver lift** — non-uniform-geometry checkout solving (ties to
  `specs/future/async-checkout-solver.md`).

## Acceptance criteria

- [ ] **Two scaling axes work as specified:** the additive face-value baseline (`face × (ring + Σhotspot +
      Σwedge_value)`) is computed first, then **streaks apply a multiplicative `streak_factor` last**. With
      no streak, a great dart tops out ~140; streaks are the only way past it.
- [ ] Late-game runaway scoring requires an *active* maintained streak, not item attrition — a long run
      with no streak cannot passively reach the old ×15–20 territory.
- [ ] Streak capacity is per-category and sourced from components (shaft→wedge, barrel→color), base 1+1;
      `max_streak_slots` global removed; `StreakSlotExtensionReward` removed from the pool.
- [ ] A skewed shaft that grants an extra wedge slot is a visibly meaningful build choice.
- [ ] `HotspotModifier` exists, is picked via the segment picker, marks a ring, adds into the additive
      baseline, and **both the checkout solver and the target tooltip reflect it at the live streak factor.**
- [ ] Hotspots do **not** stack on a ring (max +3); selecting an already-hot ring is disallowed/no-op, never
      a silent downgrade. Wedge-value remains uncapped this pass.
- [ ] Every board item carries a `family` tag (Scoring / Placement / Brush); streaks excluded. (Shop
      steering NOT wired yet — tag only.)
- [ ] `ColorBonusModifier`, `OddEvenBonusModifier`, and all parity-streak classes are removed from the
      pool; `FlipSignModifier` is unlisted from the pool but its class + Mirror-Zone relic still function;
      remaining pool reweighted; the choice board still feels full.
- [ ] No ghost effects from removed/sidelined modifiers; a new run initializes clean (no parity slots, no
      extension reward, no FlipSign in offers).
- [ ] Tier-2 geometry is documented but NOT implemented; no hit-detection changes shipped in this pass.
- [ ] Hotspot has a legible on-board indicator: value baked into the effect ("smoky ×3"), *enhances* the
      ring's painted color rather than overriding it, and survives recolor + boss overlay.

## Related

- `specs/future/scoring-on-the-board.md` — the brainstorm this hones (archive on ship).
- `specs/future/map-pool-filtration.md` — the difficulty-axis half (map + variable fronted darts); built
  first per Sequencing.
- `specs/2026-06-02-accuracy-upgrades-as-shape.md` — shaft owns the accuracy zone; the spatial tool you
  shape to exploit the board you build.
- `specs/2026-05-21-streak-slots-and-modifiers.md` — the one-per-category system this replaces with
  per-category, component-sourced capacity.
- `specs/2026-05-30-color-brushes-per-ring-color.md` — per-ring color + `BrushModifier`, the model for
  `HotspotModifier`.
- `specs/2026-06-01-boss-redesign-reactive-counters.md` — board-as-contested-territory counterplay.
- `specs/future/async-checkout-solver.md` — the Tier-2 geometry solver dependency.
- `specs/2026-06-02-darts-currency-phase-a.md` — the shipped economy that measures efficiency under scarcity.
