# ACTIVE: Geometry items — the GEOMETRY family (2026-06-07)

A NEW item family: board-wide, rarity-less, zero-sum reshapes of the board's physical layout. Designed in
a Cowork sparring session (Max + Claude, 2026-06-07); round-3 spec archived at
`specs/2026-06-06-playtest-round-3.md`. Conventions as always: static-type everything, comment frequently,
exported tunables with hover descriptions.

## 0. Thesis + the family laws (LOCKED this session)

**The family proper is eight rarity-less trades: Ring Trade ×2, Color Territory ×4, Parity Shift ×2.**
Plus one boss-reward relic (Bigger Bull, §7) that touches the same state but lives OUTSIDE the family/pool.

1. **Board-wide only — never single-target.** Every existing board item is single-target (hotspot, wedge
   value, swap, brush); single-target geometry would stack onto the same power ring as a hit-rate
   multiplier = a flat accuracy upgrade in disguise. Worse, "grow a wedge, neighbors pay" is a *fake*
   trade for exactly the wedge everyone wants: 20 is flanked by 1 and 5, so shrinking the neighbors is the
   board's native punishment being bought out. **Fat Wedge is CUT.** Geometry = the only family that
   reshapes the whole board's risk profile; that's its identity. (Bonus: no PICK_SEGMENT plumbing —
   geometry items need no picker.)
2. **Conservation — the board never gets bigger.** For something to grow, something shrinks. This is why
   every geometry item is inherently a trade. **Rim Overflow is CUT** (it grew the double ring into the
   dead rim — the one non-zero-sum growth; parked as a future boss-reward candidate only, see Deferred).
3. **Rarity-less — conservation eats the rarity axis.** Rarity elsewhere means *better-priced* (event
   swings: more gain for barely more penalty). A zero-sum reshape cannot be better-priced — its `+` and
   `−` are the same area — so rarity could only mean "bigger swing in both directions," a volume knob that
   breaks the rarity grammar. Geometry items have ONE fixed power level. Event UI renders them with no
   rarity frame; the section rarity ramp does not apply to geometry options.
4. **GEOMETRY is its own family — NOT Placement.** New `ScoringEnums.Family.GEOMETRY` value. Challenges
   keep `[SCORING, PLACEMENT]` untouched (challenge rewards stay flat / high-risk-high-reward); events
   gain geometry as an active family (trades are free); the shop sells both. No trade/flat flag needed
   anywhere — the family boundary IS the tier boundary.
5. **Dynamic — geometry rules recompute against live board state.** Color Territory tracks current paint
   (brush, Prism recolor-on-hit); Parity Shift tracks current face values (Wedge Swap). Self-limiting by
   renormalization (paint a whole wedge red → nothing left to shrink → no-op). This makes geometry
   contestable (board-as-contested-territory law) and composes with the painter build: paint it, then
   grow it. Singles are the board's brakes — a geometry build trades checkout control for scoring
   consistency, and the player feels it at 32-left.

## 1. The eight items (all: `family = GEOMETRY`, `kind = BOARD_MUTATION`, `timing = ON_ACQUIRE`, no config picker)

Three new `ScoringModifier` subclasses (mirroring `brush_modifier.gd`'s shape), eight pool entries:

- **`RingTradeModifier`** — a signed global triple↔double width dial. Export `triple_shift: float = 0.015`
  (## Normalized radial width moved from the double band into the triple band per stack; negative moves it
  the other way. Triple base width 0.050, double 0.070.). Two pool entries: **Wide Triple / Narrow Double**
  (scoring-lean, +shift) and **Wide Double / Narrow Triple** (checkout-lean, −shift). The outer single
  band *slides* (same width, shifted) — singles are untouched; this is the clean identity trade. Opposite
  stacks net out arithmetically through the shared accumulated dial — no special-case code (self-inflicted
  if bought; an event 1-of-3 may legitimately show both directions side by side).
- **`ColorTerritoryModifier`** — export `target_color` (the four pool entries: **Grow Red / Green / White /
  Black**) + `growth_factor: float = 0.30` (## Per stack, ring bands currently painted the target color
  widen radially by this fraction within their wedge; the wedge's non-target bands pay proportionally —
  per-wedge renormalization, zero-sum per wedge column.). DYNAMIC: recomputed from
  `effective_wedge_colors` on every repaint. A color with no presence on the board = inert until painted
  (legal, a build-around purchase). Bull is exempt (bull radii are not per-wedge state).
- **`ParityShiftModifier`** — export `grow_even: bool` (two pool entries: **Grow Even / Grow Odd**) +
  `weight_factor: float = 1.25` (## Per stack, the angular weight multiplier applied to wedges whose
  CURRENT effective face value matches the parity; all 20 weights renormalize to 360°.). DYNAMIC:
  recomputed from `effective_wedge_values` on every wedge swap. Note adjacent same-parity wedges exist
  (18–4, 6–10, 16–8; 17–3–19–7 is a run of four odds) — renormalization is exactly why this works with no
  neighbor edge cases. Known polarizing item; ships as the experiment.

**Floors (the brake-preservation clamp, all exported on the manager):**
`ring_band_floor: float = 0.45` (## Minimum fraction of a ring band's BASE width it can be squeezed to by
geometry items; clamped after all rules apply. Protects the singles — the board's brakes.) and
`wedge_angle_floor: float = 0.45` (## Same, for a wedge's base 18° angular width.). Stacking the same item
is allowed; floors are the cap. Starting values are Max's call to tune (playtest experiment — keep dead
easy to mess with).

**Magnitudes are starting points, not gospel** — every number above is an export with a hover doc.

## 2. Substrate — geometry state lives in `ScoringModifierManager` (contestable)

Parallel to `voided_rings` / `hotspot_rings`, the manager owns computed geometry (so boss hooks can read
and fight it, and it persists across legs like every other board mutation):

- `effective_wedge_weights: Array[float]` (20, default 1.0) → cumulative angular boundaries.
- `effective_ring_bounds: Array[Dictionary]` (20 entries; per-wedge normalized ring boundaries, seeded
  from the RING_* constants).
- `bull_radii: Dictionary` (double/single bull normalized radii — only the Bigger Bull relic §7 moves
  these; the eight trades never touch bull).
- `recompute_geometry() -> void` — rebuild from base constants, fold in active rules (ring-trade dial,
  then per-wedge color scaling, then parity weights — weights are multiplicative so order is irrelevant;
  document anyway), clamp floors LAST, renormalize, emit `geometry_changed`.
- **Recompute triggers:** geometry modifier acquired; brush `apply_to_board`; wedge swap; Prism
  recolor-on-hit (fires at score resolution, between darts — never mid-flight); run/leg init. Geometry
  items persist across legs (run-scoped, like hotspots) — verify no leg-end reset path clears them.
- **Narrow-double handicap/boss composes:** `double_ring_width_scale` stays as the dartboard-side final
  multiplier applied AFTER the manager's bounds + floors (a 75% handicap narrowing legitimately goes below
  the item floor — chosen friction may break the brakes; comment the why). A checkout-lean Ring Trade
  player has partially pre-countered the handicap — intended (build-counter vs environmental).

## 3. `dartboard.gd` — hit detection + rendering read the new state

The Narrow Double pattern (`_effective_double_inner()`) generalized:

- **Hit detection (`calculate_score`)**: restructure to bull checks first (read `bull_radii`), then wedge
  index, THEN ring classification against *that wedge's* bounds (today it classifies ring first against
  global constants — per-wedge bounds invert the order).
- **`_get_wedge_index`**: weighted cumulative boundaries (precomputed on `geometry_changed`) instead of
  uniform 18° division; keep `WEDGE_OFFSET_DEG` + `board_rotation_offset` handling. The offset anchors the
  20-wedge's *center*; document what "center" means once widths vary (anchor the cumulative walk at the
  20-wedge's start boundary).
- **Rendering (`_draw`)**: the per-wedge per-ring segment polygons already take explicit start/end degrees
  + inner/outer radii — feed the computed boundaries. **Wires**: full-circle `_draw_ring_wire` is only
  valid where bounds are uniform; replace with per-wedge boundary arcs + radial spokes at the weighted
  wedge boundaries. **Number labels**: position at weighted wedge centers.
- **Same-state consumers to sweep:** `get_segment_at_position` (picker hover), `_build_segment_polygon`
  (hotspot smoke + shockwave clip), the shop-spot overlay drawing — all must read the same per-wedge
  bounds or hotspot smoke will visibly desync from a resized ring.
- **Re-flow animation:** tween the dartboard's working copy of weights/bounds toward the manager's
  computed targets on `geometry_changed` (export `geometry_reflow_duration: float = 0.6` with hover doc).
  Dynamic resizes (a Prism recolor shrinking your fat red triple) MUST animate to read — an instant snap
  is illegible. Hit detection reads the *settled* values (manager state), not the tween's in-between.
- Hotspot / brush / void keys are `"<wedge>:<ring>"` — index-keyed, unaffected by resize; they compose
  free. Throw/accuracy mechanics: untouched (scatter is geometry-independent).
- Mini-boards (rules slideshow, assembly zone preview) stay STATIC — they teach the canonical board.

## 4. Solver — values unchanged, one tiebreak gets eyes

`_build_solver_candidates` reads values only, so checkout *math* is untouched (the long-assumed
async-solver dependency was a myth — confirmed against code this session). One touch: the "fattest
segments" path-ranking tiebreak should read effective segment area (angular width × band width at its
radius) instead of the static fatness assumption, so suggested paths prefer enlarged targets and avoid
floor-squeezed singles. Target tooltip: no change (values don't move).

## 5. Stud display — board-rule reminders ON the surround

Dynamic rules need a persistent "this law is active" display, and its home is the board surround (the
effect is spatial; the reminder should be too — Max's call, replacing the old relic-row idea).

- New `scripts/board_studs.gd` (dartboard child, drawn on the surround ring): one stud per active geometry
  rule. Placeholder glyph art (EventFamilyIcons-fallback style — labelled colored shapes); hover tooltip =
  item name + live effect summary (e.g. "Grow Red — red bands +30%"). Exports for stud radius/size/
  spacing/colors with hover docs.
- Legibility-through-flash: small, persistent, high-contrast; must survive recolor + boss overlay; the
  surround also hosts numbers and boss flash — keep studs clear of the number track.
- **Architect the stud entry generically** ({icon, tooltip_provider}) so Mirror Zone + future board-level
  relics can migrate into studs in a later pass (deferred — geometry-only for now).

## 6. Events + pool integration

- `ScoringEnums.Family`: add `GEOMETRY`. Challenge draw list stays `[SCORING, PLACEMENT]` — untouched.
- **Events**: flip `&"geometry"` ACTIVE in the event family table (`03-events-impl.md` §2 scaffolded it;
  its "maps to Family.PLACEMENT trades" line is now WRONG — update that doc). Grant path: GEOMETRY-filtered
  modifier draw, 3 distinct entries of the eight (reuse the challenge pick's distinctness logic). **No
  rarity:** options render without a rarity frame; the §3 section ramp is not rolled for geometry options.
  Update `event_node.gd`'s doc comment ("Later: &"geometry"" → active).
- **Shop**: the eight enter `ModifierRegistry.MODIFIER_TYPES` with pool weights (exported-style tuning —
  suggest 8–10 each to start; the pool must still feel varied). VERIFY the shop draw/pricing machinery
  tolerates rarity-less items — if a rarity is structurally required, treat geometry as fixed common-tier
  pricing; flag, don't redesign.
- The make-it-a-trade retrofit the events spec wanted for flat families: NOT needed for geometry — the
  family is natively trade-shaped (law #2).

## 7. Bigger Bull — boss-reward relic (outside the family)

The sanctioned flat: bull currently has NO upgrade path at all, and boss rewards are the existing
premium-flat channel (Glass Cannon's shelf).

- New `RewardRegistry` entry + reward class (`bigger_bull_reward.gd`): on acquire, grows both bull radii
  into the inner single via `bull_radii` (exports: `double_bull_radius: 0.032 → 0.048`,
  `single_bull_radius: 0.080 → 0.112` — ~+50%, hover-documented, Max tunes). Inner single pays
  (conservation holds, but it's low-value real estate — that's why it's relegated to earned-flat tier).
- Hit detection + rendering read `bull_radii` (§3). Solver: bull values unchanged. One-time acquire,
  no-stack (standard reward semantics).

## 8. Tests (`tests/test_geometry.gd`, headless) + checklist

- **Conservation:** after any rule set, wedge angles sum to 360°; per-wedge ring bounds strictly ascending
  within [0, RING_DOUBLE_OUTER]; the eight trades never move `bull_radii`.
- **Floors hold:** stack one item ×10 → no band below `ring_band_floor × base`, no wedge below
  `wedge_angle_floor × 18°`.
- **Netting:** Wide Triple + Wide Double stacks cancel back to base bounds exactly.
- **Dynamic re-flow:** repaint a ring → Color Territory bounds move; swap two wedges → Parity weights
  re-flow; all-target-color wedge → no-op (renormalization self-limits).
- **NOT inert** (the `[[feedback-rolled-generator-spread]]` lesson — a default tuning value can ship a
  feature inert): with default magnitudes, assert boundary deltas vs base exceed a visible epsilon for
  every item.
- **Hit-detection consistency:** sample points just inside/outside computed boundaries → `calculate_score`
  agrees with the bounds (e.g. a point in a widened triple band scores triple).
- **Solver:** candidate values unchanged by geometry; fattest tiebreak prefers the enlarged segment.
- **Events:** geometry family rolls 3 distinct of the eight, no rarity field set, bank unchanged.
- Existing suites green; `--check-only` parse pass on every changed script.
- **Live:** acquire each item type → board re-flows animated, studs appear with tooltips; paint → red
  territory grows; swap → parity re-flows; Prism recolor visibly contests a grown color; narrow-double
  challenge handicap composes on a checkout-lean board; hotspot smoke + shockwave clip match resized
  segments; numbers stay centered; checkout helper paths sane on a heavily reshaped board; floors stop a
  stack-spam board from deleting its singles.

## Deferred (explicitly out of this pass)

- **Rim Overflow** — cut (breaks conservation); parked as a *future boss-reward candidate* only.
- **Mirror Zone / other relics → studs** — stud architecture supports it; migration is its own pass.
- **Mini-board geometry awareness** — slideshow/assembly stay canonical.
- **`DartboardGeometry` shared-helper dedup** (the long-noted refactor) — opportunistic only if the
  drawing rework makes it free; not required.
- **Soft-biasing event geometry options** toward colors present on the board — only if "inert Grow X"
  offers annoy in playtest.
- **Geometry-flavored challenge handicaps** (e.g. squeezed singles as a race handicap) — content mine note.

**After this ships:** archive per Workflow Notes (`specs/2026-06-07-geometry-items.md`), then the queue
resumes: **typed shop + codex** (Phase 03 remainder). Program index: `specs/map/00-overview.md`. Events
scaffold this activates: `specs/map/03-events-impl.md`. Family-design rationale recorded there + in
session memory (`project_geometry_items`).

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
