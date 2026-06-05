---
Spec date: 2026-06-04
Status: Draft (parked) — decisions locked 2026-06-04, ready for a Phase 1 implementation pass
Implementation: TBD
Notes: Scoped from a diagnostic pass over throw_mechanic.gd + main.gd input. The ONLY hard
blocker for mobile-browser play is initial target selection (the AIMING stage). The two
release meters already commit on tap and work on touch unchanged. Everything past Phase 1
here (hover fallbacks, orientation, layout polish) is quality-of-life, not a blocker.
---

# Mobile / touch input — playable in mobile browser

## Goal

Make the game playable in a mobile browser from the **same web build** as desktop, by
detecting touch at runtime and switching only the input scheme that breaks. No second build,
no second scene. Desktop mouse/keyboard behavior is left byte-for-byte unchanged.

## The actual problem (and the part that already works)

The throw has three stages. Only one is broken on touch:

| Stage | Input today | Touch status |
|---|---|---|
| **AIMING** | Crosshair *follows the cursor every frame* (`get_global_mouse_position()` polled in `throw_mechanic._process`), **left-click places it** | ❌ **Blocker** |
| **VERTICAL_RELEASE** | Tap/click anytime locks the bouncing marker | ✅ works on touch as-is |
| **HORIZONTAL_RELEASE** | Tap/click anytime locks | ✅ works on touch as-is |

The release meters lock on a press *regardless of where* the press lands, so an emulated touch
tap already drives them correctly. The aim stage is different: it needs a *position* that the
player adjusts before committing, and touch has no hover state to carry that position.

### Why aiming specifically fails

In `throw_mechanic._unhandled_input`, an `InputEventMouseButton` left-press during AIMING calls
`_place_aim_crosshair()` **immediately**. Under touch (or mouse-from-touch emulation), the very
first finger-down *is* that press — so the crosshair is committed at the first point touched,
with no opportunity to reposition. As Max put it: every tap is read as a left click, so there's
no way to move the click before placing it. There is no "move cursor, then click" because there
is no cursor between taps.

## Solution: drag-to-position + explicit Confirm (Phase 1)

Adopt the standard mobile-aim pattern (think pool/sniper games): **touching the board moves the
crosshair; a separate Confirm button commits the throw.** Lifting the finger does NOT place —
the crosshair persists where it was left, so the player can re-touch and refine as many times as
they want before confirming.

Flow on a touch device, AIMING stage:
1. Crosshair starts at board center (already the case — `start_throw` sets `_aim_center = _board_center`).
2. Finger down / drag anywhere on the board → crosshair tracks the finger position (clamped to board).
3. Finger up → crosshair **stays put** (no placement).
4. Player taps the on-screen **Throw** button → `_place_aim_crosshair()` runs, advancing to VERTICAL_RELEASE.
5. From there, the two meters are tap-to-lock and already work.

This solves finger-occlusion (you commit with a different button, not by lifting off the target)
and gives unlimited refinement. Optional refinement: draw the crosshair a fixed offset *above*
the finger so the fingertip never covers the exact aim point (see Open Questions).

### Recommended implementation path (minimal diff)

Lean on Godot's mouse-from-touch emulation so we don't rewrite the meter stages or the
`_process` position tracking:

1. **Project setting:** enable `input_devices/pointing/emulate_mouse_from_touch = true`.
   - Effect: a finger drag generates mouse-motion (so the existing AIMING `_process` polling of
     `get_global_mouse_position()` tracks the finger for free), and a tap generates a mouse
     button (so both release meters keep working with zero changes).

2. **Input-mode flag.** Add `var touch_mode: bool` to `throw_mechanic.gd`, set by `main.gd` on
   ready from `DisplayServer.is_touchscreen_available()`. (See "Auto-detect" below.)

3. **Suppress place-on-press in AIMING when `touch_mode`.** In `throw_mechanic._unhandled_input`,
   the `ThrowState.AIMING` → `_place_aim_crosshair()` branch (both the mouse-button path ~L567
   and the Enter/Space path) returns early under `touch_mode`. Drag still updates `_aim_center`
   via the untouched `_process` polling; only the *commit* is rerouted. The VERTICAL/HORIZONTAL
   press branches are left alone — they should still fire on tap.

4. **Confirm method + button.** Add a public `confirm_aim_placement()` to `throw_mechanic.gd`
   that simply calls `_place_aim_crosshair()`. Add a **Throw** `Button` to the HUD that calls it.
   Visibility rule: shown only when `touch_mode AND throw state == AIMING`; hidden on desktop and
   in every other state. Wire its show/hide off the existing `state_changed` signal that the HUD
   already listens to.

That is the whole blocker fix — on the order of a few dozen lines, because the emulation layer
hands us drag-tracking and meter taps for free, and we're only intercepting one commit path.

### Confirm button UX
- Thumb-reachable: bottom-center, or mirrored bottom-left/right so either thumb works.
- Touch target ≥ 48px; clearly labeled ("Throw" / "Lock Aim").
- Must not overlap the board's lower aim region (it only needs to exist during AIMING).
- Consider a small **Reposition/Cancel** affordance during the release meters to mirror desktop's
  right-click `_cancel_to_aiming()` (out of MVP scope; note it).

## Auto-detect & input-scheme switch

One web build, runtime branch:
- `DisplayServer.is_touchscreen_available()` — primary signal, works in-browser, covers hybrid
  laptops with touchscreens.
- Store one `touch_mode` flag (on `main` or a tiny autoload) and pass it to `throw_mechanic`;
  the HUD reads the same flag for the Confirm button + touch-target sizing.
- Keep it overridable (debug toggle) so the scheme can be tested on desktop without a phone.

## Out of MVP scope (Phase 2+ — quality-of-life, not blockers)

These also lean on hover and will feel rough but do NOT prevent play:
- **Shop / wedge picker / segment picker** (`main._process`, ~L394–427): hover lights a spot and
  shows rarity; click buys. Touch needs tap-to-preview-then-confirm (or long-press preview).
- **HUD hover tooltips** — modifier panel, board-dart hover.
- **Orientation** — game wants landscape. Mobile browsers can't be hard-locked from Godot web;
  realistic answer is a "rotate your phone" overlay shown when portrait is detected. (Hint
  `display/window/handheld/orientation` is best-effort only on web.)
- **Layout / touch targets** — buttons ≥ 44–48px; verify the HUD (now grouped into InfoColumn /
  ScoreReadout / ActionButtons / Tooltips containers) doesn't crowd on narrow screens. Stretch is
  already `canvas_items` + `aspect=expand`, so scaling is mostly handled.
- **Web audio gesture** — mobile browsers require a user gesture before audio starts; add a
  tap-to-start gate if one isn't already present.

## Touchpoints in code
- `throw_mechanic.gd` — add `touch_mode`, gate AIMING commit, add `confirm_aim_placement()`.
  AIMING `_process` polling (~L498–521) and the release-meter input paths stay as-is.
- `main.gd` — set `touch_mode` from `DisplayServer.is_touchscreen_available()` near where it wires
  `throw_mechanic` (`_ready`, ~L329–353); expose to HUD.
- `hud.gd` / `scenes/main.tscn` — add the **Throw** button (in `ActionButtons`?), show/hide on
  `state_changed`.
- `project.godot` — `input_devices/pointing/emulate_mouse_from_touch = true`.

## Effort & risk
- **Phase 1 (the blocker only):** ~1 day. Low risk — additive, gated behind `touch_mode`, desktop
  path untouched.
- **Phase 2 (hover fallbacks + orientation + layout polish):** ~1–3 days for "good feel."
- **Risks:** browser orientation-lock is unreliable (mitigate with overlay); low-end phone perf
  given the per-frame `queue_redraw` board (test on real mid-range hardware, not devtools).

## De-risk experiment before building (≈5 min)
Set `emulate_mouse_from_touch = true`, export web, open on a phone. The two meter stages will
already be tappable; the aim stage will visibly place-on-first-touch. This confirms aiming is the
*only* blocker and surfaces real-screen layout issues before any solution code is written.

## Decisions (locked 2026-06-04)
1. **Aim commit model:** ✅ **Drag + Confirm button.** Touch/drag moves the crosshair, lifting
   leaves it put, the Throw button commits. No tap-to-place, no lift-to-place.
2. **Scope:** ✅ **Phase 1 only** — make aiming work on touch + auto-detect. Ship "playable on
   mobile." Everything in "Out of MVP scope" stays parked.

## Still-open (defer to implementation, not blocking)
- **Finger-occlusion offset:** draw the crosshair a fixed distance above the fingertip while
  dragging? Improves precision, small addition to the AIMING draw/track path. Decide during the
  pass once it's testable on a real screen.
- **Confirm button placement:** single bottom-center vs mirrored dual-thumb buttons. Start with
  bottom-center; revisit if it feels cramped one-handed.
