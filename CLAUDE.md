# Spec: Throw Anticipation Animation

Adds a pre-impact "fly-in" to the dart throw. The intent is to inject anticipation into the moment between the RNG resolving the landing point and the scoring juice firing, and to make the accuracy miss *legible* as motion: the dart visibly travels from where you aimed to where it actually landed.

Shipped 2026-06-01 (manual implementation in this session). This section documents the design so future work doesn't undo the reasoning.

## Problem

When a throw resolves, `throw_mechanic` samples the final landing point (gaussian + accuracy-ellipse math) and emits `throw_completed(hit_pos)`. The old `_on_throw_completed` then did everything on a single frame: dropped the marker (`_place_dart`), played the thunk, popped the floating score, and fired `flash_segment` (which drives the shader shockwave). No travel, no build-up — the juiciest moment of the game had zero anticipation, and the accuracy system (how far off you landed from your aim) was invisible after the fact.

## Design

A **pure pre-step**. The entire existing impact flow is unchanged; the animation is bolted on in front of it. Sequence: **fly-in/shrink → impact → all the normal stuff**.

- **Start anchor = aim center → land point.** The flying dart spawns large, centered on the aim point the player locked (`throw_mechanic.get_resolve_center()` = the accuracy-ellipse center), then shrinks to normal marker size while drifting onto the actual RNG landing point. The drift vector *is* the accuracy miss made visible — this was the deliberate choice over a pure in-place zoom (which would lose the accuracy story) or a fixed off-board "hand" anchor (literal flight, but a long travel path occludes the board and the drift no longer maps to accuracy).
- **The shrink reads as the dart flying away from the player** (big = close, small = stuck in the distant board). A faint→opaque fade-in reinforces the far-to-near read.
- **Easing is EASE_IN (accelerate)** so arrival lands like a sudden thunk — the anticipation payoff. Build slow, snap on contact.
- **Nothing about the impact changed.** Per Max: "basically everything after the dart impact is the same. this just adds a step before the dart impact." All scoring juice (marker, thunk, shockwave, floating score, remaining-score countdown, game logic) fires together at arrival exactly as it did before.

**Seamless hand-off:** the transient flyer is the same visual as the real marker (`dart_marker.gd`, same colors and `dart_size`). It ends at `hit_position` at exactly final marker size, at which point it is freed and `_resolve_throw_impact()` places the real marker on the same spot — no pop. The `throw_mechanic` stops drawing its frozen marker/ellipse the instant it resolves (DONE state draws nothing), so there's no double-marker during the flight. The declared-target highlight stays lit through the fly-in, which reinforces the aim-vs-land read.

## Implementation (as shipped)

- `scripts/throw_mechanic.gd` — added `get_resolve_center() -> Vector2`, returning `Vector2(_horizontal_x, _locked_release_y + accuracy_skew_v)`, the same point used as the ellipse center in `_resolve_throw`. Valid immediately after a resolve.
- `scripts/main.gd`:
  - New `@export_group("Throw Anticipation")`: `throw_anticipation_enabled` (bool, default true — off = instant land, original behavior), `anticipation_start_scale` (default 3.0×), `anticipation_start_alpha` (default 0.45; 1.0 disables the fade-in), `anticipation_duration` (default 0.3s).
  - `play_throw_anticipation(hit_position, outer_color, inner_color, on_landed)` is the **shared, public** fly-in used by every throw path. It spawns the transient flyer (in the caller's marker colors, for a seamless hand-off) and runs a parallel tween (position + scale + modulate alpha) chained to `_on_anticipation_landed`, which frees the flyer and invokes `on_landed` — a zero-arg Callable (each caller binds its `hit_position`). When `throw_anticipation_enabled` is false, `on_landed` fires immediately.
  - Normal throw: `_on_throw_completed` calls `play_throw_anticipation(..., _resolve_throw_impact.bind(hit_position))`. The former body of `_on_throw_completed` (everything from `clear_declared_target` onward) moved verbatim into `_resolve_throw_impact(hit_position)`.
  - Shop throw: `_on_shop_throw_completed` calls `play_throw_anticipation(..., _resolve_shop_impact.bind(hit_position))`; its former body moved into `_resolve_shop_impact`.
- `scripts/tutorial_controller.gd` — `_on_tutorial_throw_completed` routes through `get_parent().play_throw_anticipation(...)` (guarded by `has_method`), passing the tutorial's yellow marker colors and `_resolve_tutorial_throw.bind(hit_position)`; its former body (place marker + advance beat) moved into `_resolve_tutorial_throw`.
- The fly-in is universal: normal, shop, and tutorial throws all play it (and all honor the single `throw_anticipation_enabled` flag on `main.gd`).

## Acceptance
- Anticipation on: throw resolves → large dart flies in from aim center, shrinking/drifting to the landing point → on arrival, marker + thunk + shockwave + score all fire as before. No double marker, no pop.
- Anticipation off (`throw_anticipation_enabled = false`): every path lands instantly, byte-identical to old behavior.
- Applies to ALL throws — normal, shop, and tutorial — each with a seamless color-matched hand-off to its own marker.
- Drift direction/magnitude matches the actual accuracy miss (start = locked aim, end = RNG sample).

## Deferred / easy follow-ups
- Scale **overshoot** at the end (tween to ~0.9× then settle to 1.0) for a squash-on-impact pop.
- A faint motion-trail / streak behind the flyer.
Both are additive and don't touch the impact flow.

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
