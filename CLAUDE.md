# Spec: MAP SUBSTRATE — Phase 01, slice 1 (ready to build)

**Active spec: `specs/map/01-substrate-impl.md`** (impl) + `specs/map/01-substrate.md` (rationale). Part of the
Map Program (`specs/map/00-overview.md`, the multi-phase index). The map is "the house" the shipped scoring
tools get arranged into; the substrate is its frame — a navigable graph that first just hosts the *current* run
flow (legs/shops/bosses), mostly a reorganization of what exists.

**Slice 1 scope (decided 2026-06-04 Cowork session): full rough-rect topology + ported difficulty ladder.**
- New `scripts/map/`: `MapNode` (RefCounted data — type/depth/lane/act + `(target_score, darts_fronted)` payload
  + edges), `MapGraph` (seeded-RNG generator + traversal API, headless-testable), `MapView` (code-built
  `Control`, grey-rect `Button` per node, **type-only** — follows the `LevelSelectScreen` instantiation pattern).
- Generator steps: skeleton → depth grid → wire edges (2 lanes + in-lane reconverging forks + bridges + funnel
  chokepoints) → slot specials by type-mix + one distance-decay weight → assign params → validate-or-assert.
- Active node types this slice: LEG / SHOP / BOSS. CHALLENGE + EVENT slots reserved (off-branch marked), filled
  as legs/stubs until Phases 02/03.
- **The seam** (the one invasive change): run structure is *implicit* today — `x01_game.advance_leg()` self-
  increments the target ladder; shop = `leg % shop_cadence` in `_show_leg_upgrades`; boss = `leg % boss_cadence`
  in `BossManager`. The map makes it explicit: generate at `_on_run_confirmed`; show `MapView` between legs; on
  node pick apply `(target_score, max_turns = darts_fronted / darts_per_turn)` to `x01_game` (add a
  `start_leg_with()` helper). **Two `advance_leg()` call sites** to intercept — normal next-leg (main.gd:1027)
  and post-shop (`_end_shop`, main.gd:1647); the latter because **shop becomes its own node** (leaving a shop
  returns to the map, no auto-advance). Run victory = reaching the terminal act-3 BOSS node.
- Slice-1 difficulty = **ported ladder**: `target(depth)`, both parallel nodes at a depth share the tier, so
  branches differ by *type composition*, not hardness. `darts_fronted = 15` for all.

**Deferred (explicit follow-ups):** slice 2 = the pressure-ratio generator (`(target/darts)/expected_per_dart`
roll + the static curve — held back because its numbers can't be tuned until the map is playable); Phase 02
challenge content (fills the reserved fork off-branch); Phase 03 typed shop + codex + event/family glyphs; the
arrival ceremony (center readout dock + dart print-out reusing the bank-save animation); art reskin (graph/view
split means `MapGraph` is untouched); Phase 04 path-biasing (made load-bearing by the type-only info model).

Design laws this leans on: *frame before furniture* (build the rough substrate before node types — positional
features need a run-position to feel-test) and *chosen friction is spice*. Build-steering spine stays: exposure
(codex) + informed shop + earned challenge selection; **no free typed picks** (power stays earned — protects the
darts-as-currency "bank is the climb" thesis).

**Board-scoring rework SHIPPED 2026-06-03** — `specs/2026-06-03-scoring-on-the-board.md`. Two-axis scoring:
additive face-value baseline (ring + hotspot + wedge value) × ONE combined multiplicative streak factor
(`1 + Σ`). Per-category streak capacity from components (`DartComponent.streak_slot_grant`). `HotspotModifier`
live; hotspot smoke shader + streak pulse visuals. The shipped `family` tag is the steering prerequisite the
map's event/shop glyphs key off. Also deferred from that pass: **Tier-2 geometry** (wedge resize, bigger bull)
behind the checkout-solver lift; hotspot **"value-in-the-smoke"** (`use_glyph`).

When this phase ships, archive it per the Workflow Notes and replace this section with the next spec.

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
