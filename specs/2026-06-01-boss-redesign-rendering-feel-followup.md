---
Spec date: 2026-06-01
Status: Shipped 2026-06-01
Implementation: Claude Code. No Godot CLI available — verification is manual playtest.
Notes: Implemented the two genuine gaps — item 2 (Void two-phase migration) and item 4 (Drunkard perpendicular wander folded into the landing). **Items 1 and 3 were already satisfied by the predecessor pass and needed no work:** all the `dartboard.gd` methods the spec lists as "missing" (`set_boss_void_wedges`, `set_boss_void_rings`, `set_double_ring_scale`, `set_boss_recession_wedges`, `clear_boss_overlays`) already exist and are called without error, and `double_ring_width_scale` is already applied via `_effective_double_inner()` in both `_draw` and `calculate_score`, with `set_double_ring_scale` already tweening — so the "nonexistent function" premise did not hold against the shipped code, and Narrow Double already animates + matches hit detection. The Void migration now passes drift moves to the new `dartboard.play_void_turn()`, which sequences phase 1 (whole-wedge fade-in via `void_fill_duration`) then phase 2 (drifted rings slide source→neighbor via `void_drift_duration`). Prism different-color recolor was already done by Max in the design session (not redone). DEFERRED (carried over): Weak Board scuff/damage shader (`set_boss_recession_wedges` just stores + redraws for now).
---

# Spec: Boss Redesign — Rendering & Feel Follow-up

Status: **Designed 2026-06-01, ready for implementation.** Finishes a *partial* pass.
**Predecessor:** `specs/2026-06-01-boss-redesign-reactive-counters.md` (the logic pass — shipped, then playtested). This addresses gaps that playtest surfaced.

## Problem

The boss-redesign logic layer shipped, but the **dartboard rendering layer is incomplete**. The boss scripts call several `dartboard.gd` methods that are **not defined**, so those calls error at runtime and the matching visuals never appear. The state vars and the `@export_group("Void Overlay")` exports exist, and the scoring-side effects work (void zeroes `effective_wedge_values`; Weak Board reduces values; the checkout solver reads them) — but the setters, the tweens that drive them, and the actual drawing/geometry application were never written.

Confirm during implementation: the Godot console should currently be throwing "nonexistent function" errors on void / narrow-double / weak-board legs. Those should be gone when this lands.

Already fixed in the design session (do **not** redo): **Prism** now recolors to a color *different* from the current one (`prism_boss.gd::_recolor`), so every hit visibly changes — the green→green "no impact" case is gone.

## Items

### 1. Define the missing `dartboard.gd` methods (root cause)

The boss scripts call these; they don't exist. Each assigns the already-declared state vars and kicks the relevant tween, then `queue_redraw()`:

- `set_boss_void_wedges(wedges: Array[int])` — move current `_boss_void_wedges` → `_boss_void_wedges_prev`, store new set, start the void fade tween (`_void_transition_t` 0→1).
- `set_boss_void_rings(rings: Array[Dictionary])` — move current → `_boss_void_rings_prev`, store new (key `"<wedge>:<RingName>"`). Used for the drifted rings.
- `set_double_ring_scale(scale: float)` — tween `double_ring_width_scale` from current → `scale` over a new export (item 3).
- `set_boss_recession_wedges(wedges: Array[int])` — store `_boss_recession_wedges` (the Weak Board scuff overlay is deferred per the predecessor spec, so this can just store + `queue_redraw` for now; defining it stops the call from erroring).
- `clear_boss_overlays()` — clear all void/ring/recession sets + prev sets, reset `_void_transition_t = 1.0`, reset `double_ring_width_scale = 1.0`, `queue_redraw`.

### 2. Void: draw the overlay + a two-phase migration tween

The drift is *computed* in `void_boss.gd` but never *drawn*. Max's note: the player should see the **whole wedges void first, then the drift migrate** — and it needs to be slow enough to read.

- **Draw the void overlay** in `_draw` for `_boss_void_wedges` (whole) and `_boss_void_rings` (drifted single rings), using `void_fill_color` / `void_border_color`, alpha driven by `_void_transition_t`, fading `_boss_void_wedges_prev` / `_boss_void_rings_prev` out. (Today calculate_score zeroes voided segments at ~L862 for *scoring*, but there's no visible fill drawn.)
- **Two-phase reveal.** Phase 1: the freshly-chosen whole wedges fade in fully voided (matches the easy version exactly — continuity). Phase 2: the drifted rings visibly migrate from their source wedge to the neighbor. To support this, change `void_boss.gd::on_turn_start` to hand the dartboard the **drift moves** (e.g. `Array[{from_wedge, to_wedge, ring}]`) in addition to the final sets, so the board can animate source→neighbor rather than just popping the end state.
- **New exports** (separate from the existing `void_transition_duration`): `void_fill_duration` (phase 1) and `void_drift_duration` (phase 2). Suggested defaults ~0.45s / ~0.6s — Max will tune. Sequence them: phase 2 starts after phase 1 completes.

### 3. Narrow Double: apply the scale + a visible shrink tween

`double_ring_width_scale` is declared (L146) but **never applied anywhere**, so the ring doesn't actually narrow.

- Apply it to the double-ring **inner** boundary in BOTH `_draw` (segment radii) and `calculate_score` (hit detection must match the drawn width). Outer edge fixed; inner boundary moves outward as the scale shrinks.
- Drive it through a tween in `set_double_ring_scale` over a new export `double_ring_transition_duration` (default ~0.4s) so the player watches it narrow at leg start instead of it snapping. Redraw each step (follow the existing `flash_segment` tween-and-`queue_redraw` pattern).

### 4. Drunkard: fold the perpendicular wander into the actual landing

Right now the *along-the-meter* warp (`_drunk_warp_pos`) is committed to the hit, but the *perpendicular* squiggle (`_drunk_perp_offset`) the marker visibly rides is **draw-only**. Max wants the dart to respect the line it sees.

- In `throw_mechanic.gd` where `hit_position` is assembled (~L631), add the same `_drunk_perp_offset(u)` the release draws use (`_draw_vertical_release` / `_draw_horizontal_release`, ~L787–852): the horizontal-release marker's perp is an offset perpendicular to its travel, vertical likewise. Mirror the draw math exactly so the committed point equals the drawn marker. Leave the along-meter warp as-is.

## Acceptance

- No "nonexistent function" console errors on void / narrow-double / weak-board legs.
- Void: whole wedges visibly fill in as voids, *then* the drifted rings visibly migrate to neighbors; phase durations are exported and tunable.
- Narrow Double: the double ring visibly animates narrower at leg start, and hit detection matches the drawn (narrowed) width.
- Drunkard: the dart lands on the squiggly path the marker rode, not the straight line underneath it.
- Prism (already shipped this session): every hit recolors to a different color.

## Deferred

- Weak Board scuff/damage shader on degraded wedges (carried over from the predecessor spec; `set_boss_recession_wedges` is defined here only so the call doesn't error).
