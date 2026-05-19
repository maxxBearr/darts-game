# Throw Mechanic Refactor: Ellipse-Based Aiming

## Overview

Replace the current rectangular four-stage throw mechanic (aim band → window positioning → vertical meter → horizontal meter) with a three-stage ellipse-based system (place ellipse zone → vertical meter → horizontal meter). All mouse clicks and Space/Enter serve as input for every stage. WASD provides alternative movement during aiming.

The core stat model (six stats, 1–100 ranges, component bonuses, upgrades, throw modifiers, balance/skew system) is **unchanged**. Only the throw mechanic's interpretation of those stats changes.

---

## Coding Conventions

- Static typing on ALL variables
- Frequent commenting for readability
- `##` doc comments on all `@export` vars describing what they do and what values mean
- `@export` vars liberally for developer control

---

## State Machine

Remove the `POSITIONING` state entirely. New enum:

```
enum ThrowState { IDLE, AIMING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, RESOLVING, DONE }
```

### Flow

```
IDLE → AIMING → VERTICAL_RELEASE → HORIZONTAL_RELEASE → RESOLVING → DONE
```

1. **AIMING** — Ellipse zone follows mouse cursor. WASD also moves the zone. Click / Space / Enter places it.
2. **VERTICAL_RELEASE** — Marker bounces vertically across the full height of the placed ellipse. Click / Space / Enter locks Y.
3. **HORIZONTAL_RELEASE** — Marker bounces horizontally across the full width of the placed ellipse at locked Y. Click / Space / Enter locks X.
4. **RESOLVING** — Accuracy ellipse appears at the locked point, skew animates, dart lands via Gaussian with ellipse rejection.
5. **DONE** — Processing complete, signal emitted.

---

## AIMING Stage Details

### Zone Shape
- The aim zone is an **ellipse** (not a capsule/rectangle).
- Width (horizontal diameter) is derived from `horizontal_range` using the existing `_get_aim_half_width()` mapping (1–100 stat → `max_aim_half_width` down to `min_aim_half_width`). This value becomes the ellipse's horizontal semi-axis.
- Height (vertical diameter) is derived from `vertical_range` using the same style of mapping. Introduce `_get_aim_half_height()` that maps `vertical_range` (1–100) from `max_aim_half_height` down to `min_aim_half_height`. Use similar default pixel values as the horizontal counterpart (e.g., `max_aim_half_height: 200.0`, `min_aim_half_height: 5.0` — expose as `@export` vars for tuning).
- When H range and V range are equal, the ellipse is a perfect circle.

### Input
- **Mouse**: Ellipse center tracks `get_global_mouse_position()`, clamped so the ellipse stays within board bounds (center ± semi-axis ≤ board edge).
- **WASD / Arrow Keys**: Move the ellipse center at `window_move_speed` pixels/second (reuse existing export var). If WASD is pressed, the zone moves from its current position via WASD. On any mouse movement, mouse reclaims positioning (zone snaps to mouse). Track this with a simple `_mouse_controls_aim: bool` flag — set `true` on mouse motion, set `false` on WASD press.
- **Click / Space / Enter**: Lock the ellipse center position. Transition to `VERTICAL_RELEASE`.

### Drawing
- Draw a filled semi-transparent ellipse using `draw_arc()` (full 360° arc with enough points for smoothness, ~64 segments) or a polygon approximation, filled with `aim_line_color`.
- Draw the ellipse outline with a slightly more opaque version of the same color.
- Draw a small crosshair at the ellipse center.

### Variables to Store on Placement
- `_placed_center: Vector2` — the locked ellipse center position
- `_aim_half_width: float` — horizontal semi-axis (computed from `horizontal_range` at time of placement)
- `_aim_half_height: float` — vertical semi-axis (computed from `vertical_range` at time of placement)

---

## VERTICAL_RELEASE Stage Details

### Meter Behavior
- The marker bounces vertically across the **full height** of the placed ellipse: from `_placed_center.y - _aim_half_height` to `_placed_center.y + _aim_half_height`.
- Bounce speed from `vertical_speed` using existing `_get_vertical_bounce_speed()`.
- Marker is drawn as a circle at `(_placed_center.x, _release_y)`.

### Accuracy Glow Preview
- Show a **horizontal band** within the ellipse representing the vertical accuracy zone.
- Band height = `_get_vertical_accuracy_half() * 2`, centered on the current marker Y position.
- The band should be **clipped to the ellipse boundary** — at any given Y, the band's horizontal extent is the ellipse width at that Y: `half_width_at_y = _aim_half_width * sqrt(1 - ((y - center_y) / _aim_half_height)²)`.
- Draw this clipped band with `vertical_glow_color`.

### Drawing
- Dimmed ellipse outline (the placed zone, faded).
- Vertical accuracy glow band (clipped to ellipse).
- Bouncing marker dot.

### Input
- **Click / Space / Enter**: Lock `_locked_release_y = _release_y`. Transition to `HORIZONTAL_RELEASE`.

---

## HORIZONTAL_RELEASE Stage Details

### Meter Behavior
- The marker bounces horizontally across the **full width** of the placed ellipse: from `_placed_center.x - _aim_half_width` to `_placed_center.x + _aim_half_width`.
- Bounce speed from `horizontal_speed` using existing `_get_horizontal_bounce_speed()`.
- Marker is drawn at `(_horizontal_x, _locked_release_y)`.

### Accuracy Glow Preview
- Show a **vertical band** within the ellipse representing the horizontal accuracy zone.
- Band width = `_get_horizontal_accuracy_half() * 2`, centered on the current marker X position.
- Clip to ellipse boundary at any given X: `half_height_at_x = _aim_half_height * sqrt(1 - ((x - center_x) / _aim_half_width)²)`.
- The intersection of the vertical accuracy band and the previously locked horizontal accuracy band forms the visible accuracy region — draw this overlap region with the combined glow.
- Also show the locked vertical glow band (dimmed) from the previous stage.

### Drawing
- Dimmed ellipse outline.
- Locked vertical accuracy band (dimmed, from V release).
- Horizontal accuracy glow band (clipped to ellipse).
- Intersection region highlighted with `resolve_preview_color` or a combined glow.
- Bouncing marker dot at intersection with locked Y.

### Input
- **Click / Space / Enter**: Lock `_horizontal_x`. Transition to `RESOLVING`.

---

## RESOLVING Stage Details

### Accuracy Ellipse
- The final accuracy/variance zone is an **ellipse** centered on `(_horizontal_x, _locked_release_y)`.
- Horizontal semi-axis = `_get_horizontal_accuracy_half()`.
- Vertical semi-axis = `_get_vertical_accuracy_half()`.
- When H accuracy and V accuracy stats are equal, this is a circle.

### Skew Animation
- If `accuracy_skew_v != 0`, tween `_current_skew_offset` from 0 to `accuracy_skew_v` over `resolve_preview_duration`. The accuracy ellipse center shifts vertically by this offset during the animation.
- Same behavior as current system, just applied to ellipse center instead of rectangle center.

### Drawing
- Dimmed placed ellipse outline.
- Accuracy ellipse drawn with `resolve_preview_color`, centered at `(_horizontal_x, _locked_release_y + _current_skew_offset)`.
- Frozen marker dot at the accuracy ellipse center.

### Dart Resolution — Gaussian with Ellipse Rejection
Replace the current independent X/Y clamped Gaussian with ellipse-rejection sampling:

```gdscript
func _resolve_throw() -> void:
    var h_half: float = _get_horizontal_accuracy_half()
    var v_half: float = _get_vertical_accuracy_half()
    var center_x: float = _horizontal_x
    var center_y: float = _locked_release_y + accuracy_skew_v

    # Gaussian sample with ellipse rejection
    var offset_x: float = 0.0
    var offset_y: float = 0.0
    for i: int in range(20):  # Safety cap to avoid infinite loop
        offset_x = randfn(0.0, h_half * gaussian_spread)
        offset_y = randfn(0.0, v_half * gaussian_spread)
        # Check if point is inside the accuracy ellipse
        var ellipse_check: float = (offset_x * offset_x) / (h_half * h_half) + (offset_y * offset_y) / (v_half * v_half)
        if ellipse_check <= 1.0:
            break

    var hit_position: Vector2 = Vector2(center_x + offset_x, center_y + offset_y)
    queue_redraw()
    throw_completed.emit(hit_position)
```

Note: With `gaussian_spread` at 0.4 and center-weighted rolls, the rejection loop almost never iterates more than once. The `for` loop with a cap of 20 is a safety net — if it somehow exhausts all attempts, it uses the last rolled values, which is fine.

---

## Removed Concepts

- **`POSITIONING` state**: Entirely removed. No more W/S window sliding.
- **Aim band / aim line**: No more vertical rectangular band. Replaced by ellipse.
- **Window shrink tween**: No longer needed since there's no window to shrink.
- **`_full_line_top/bottom/height`**: Remove these variables.
- **`_window_top/bottom/height/center_y`**: Remove these variables.
- **`_is_shrink_complete`**: Remove.
- **`shrink_tween_duration`**: Remove this export var.
- **`window_color` / `window_border_color`**: Remove these export vars (or repurpose for the dimmed ellipse outline).
- **`window_move_speed`**: Keep — repurpose for WASD movement speed during AIMING.

---

## New Variables

```gdscript
## Center of the placed aim ellipse (locked when player confirms placement).
var _placed_center: Vector2 = Vector2.ZERO

## Horizontal semi-axis of the aim ellipse (computed from horizontal_range at placement time).
var _aim_half_width: float = 0.0

## Vertical semi-axis of the aim ellipse (computed from vertical_range at placement time).
var _aim_half_height: float = 0.0

## Whether mouse is currently controlling aim position (vs WASD).
var _mouse_controls_aim: bool = true

## Current aim position during AIMING state (before placement is locked).
var _aim_center: Vector2 = Vector2.ZERO
```

## New Export Vars

```gdscript
## Maximum aim ellipse half-height in pixels (at vertical_range = 1). The worst possible vertical spread.
@export var max_aim_half_height: float = 200.0

## Minimum aim ellipse half-height in pixels (at vertical_range = 100). The tightest possible vertical spread.
@export var min_aim_half_height: float = 5.0
```

## New Helper Function

```gdscript
## Compute the aim ellipse half-height in pixels from the vertical_range stat (1–100).
func _get_aim_half_height() -> float:
    var normalized: float = clampf((vertical_range - 1.0) / 99.0, 0.0, 1.0)
    return lerpf(max_aim_half_height, min_aim_half_height, normalized)
```

---

## Drawing Utilities

### Drawing a Filled Ellipse
Godot's `draw_arc` doesn't fill. Use `draw_colored_polygon` with points generated from the ellipse equation:

```gdscript
## Draw a filled ellipse centered at `center` (local coords) with given semi-axes and color.
func _draw_filled_ellipse(center: Vector2, half_w: float, half_h: float, color: Color, segments: int = 64) -> void:
    var points: PackedVector2Array = PackedVector2Array()
    for i: int in range(segments):
        var angle: float = TAU * float(i) / float(segments)
        points.append(center + Vector2(cos(angle) * half_w, sin(angle) * half_h))
    draw_colored_polygon(points, color)
```

### Drawing an Ellipse Outline
```gdscript
## Draw an ellipse outline centered at `center` (local coords).
func _draw_ellipse_outline(center: Vector2, half_w: float, half_h: float, color: Color, width: float = 2.0, segments: int = 64) -> void:
    for i: int in range(segments):
        var angle_a: float = TAU * float(i) / float(segments)
        var angle_b: float = TAU * float(i + 1) / float(segments)
        var point_a: Vector2 = center + Vector2(cos(angle_a) * half_w, sin(angle_a) * half_h)
        var point_b: Vector2 = center + Vector2(cos(angle_b) * half_w, sin(angle_b) * half_h)
        draw_line(point_a, point_b, color, width)
```

### Drawing a Band Clipped to Ellipse
For the accuracy glow bands, generate a polygon that represents the intersection of a horizontal/vertical strip with the ellipse:

```gdscript
## Draw a horizontal band (y_min to y_max) clipped to the aim ellipse.
## center, half_w, half_h are the ellipse parameters in local coords.
func _draw_h_band_clipped(center: Vector2, half_w: float, half_h: float, y_min: float, y_max: float, color: Color, segments: int = 32) -> void:
    var points: PackedVector2Array = PackedVector2Array()
    # Clamp band to ellipse vertical extent
    y_min = maxf(y_min, center.y - half_h)
    y_max = minf(y_max, center.y + half_h)
    if y_min >= y_max:
        return
    # Right edge: top to bottom
    for i: int in range(segments + 1):
        var y: float = y_min + (y_max - y_min) * float(i) / float(segments)
        var dy: float = (y - center.y) / half_h
        var x_extent: float = half_w * sqrt(maxf(1.0 - dy * dy, 0.0))
        points.append(Vector2(center.x + x_extent, y))
    # Left edge: bottom to top
    for i: int in range(segments, -1, -1):
        var y: float = y_min + (y_max - y_min) * float(i) / float(segments)
        var dy: float = (y - center.y) / half_h
        var x_extent: float = half_w * sqrt(maxf(1.0 - dy * dy, 0.0))
        points.append(Vector2(center.x - x_extent, y))
    draw_colored_polygon(points, color)
```

A similar `_draw_v_band_clipped` function handles vertical bands (swap x/y logic).

---

## Files Affected

### `throw_mechanic.gd` — **Major rewrite**
- Remove `POSITIONING` from enum and all associated logic.
- Remove window-related variables, export vars, and draw functions.
- Replace `_draw_positioning()` entirely.
- Rewrite `_process()` AIMING to track mouse + handle WASD.
- Rewrite `_unhandled_input()` to remove POSITIONING input handling; all states now use Click/Space/Enter uniformly.
- Rewrite all `_draw_*` functions to use ellipses instead of rectangles.
- Rewrite `_resolve_throw()` to use ellipse rejection sampling.
- Add new variables, export vars, and helper functions listed above.
- Add drawing utility functions for filled ellipses, outlines, and clipped bands.

### `main.gd` — **Minor updates**
- Remove the `ThrowState.POSITIONING` match arm in `_on_throw_state_changed()`.
- Update HUD instruction text: AIMING instruction should say "Move mouse to aim, click to place" (no more W/S window instructions).
- The POSITIONING instruction is removed entirely.

### `hud.gd` — **Minor updates**
- Update any instruction strings that reference the old positioning phase.
- Stats panel labels remain the same (H Range, V Range, etc.) — no changes needed since stat names are unchanged.

### `dart_build.gd` — **No changes**
All stat names, bonus application, and balance system remain identical.

### `dart_component.gd` — **No changes**
Component stat bonuses remain the same six stats.

### All modifier files — **No changes**
Throw modifiers and scoring modifiers are unaffected.

---

## HUD Instruction Text Updates

| State | Old Text | New Text |
|---|---|---|
| AIMING | "Click or Space to lock aim position" | "Move to aim, click to place zone" |
| POSITIONING | "W/S or Up/Down to move window, Enter/Space to lock" | *(removed)* |
| VERTICAL_RELEASE | "Click or Space to lock vertical position" | "Click or Space to lock vertical" |
| HORIZONTAL_RELEASE | "Click or Space to lock horizontal position" | "Click or Space to lock horizontal" |
| RESOLVING | "Releasing..." | "Releasing..." |

---

## Testing Checklist

- [ ] Ellipse renders correctly with equal H/V range (should be a circle)
- [ ] Ellipse renders correctly with different H/V range (should be visibly elliptical)
- [ ] Mouse placement works — ellipse follows cursor, click locks it
- [ ] WASD placement works — arrow keys / WASD move the zone, mouse reclaims on mouse move
- [ ] Space and Enter work as click alternatives in all three input stages
- [ ] Vertical meter bounces across full ellipse height
- [ ] Horizontal meter bounces across full ellipse width at locked Y
- [ ] Accuracy glow bands clip correctly to ellipse boundary
- [ ] Accuracy ellipse appears during RESOLVING with correct size
- [ ] Balance skew shifts the accuracy ellipse vertically during resolve
- [ ] Dart lands within the accuracy ellipse (never outside it)
- [ ] Equal H/V accuracy produces a circular accuracy zone
- [ ] Throw modifiers still apply correctly (temp bonuses affect the right stats)
- [ ] Dart component bonuses affect zone size and accuracy zone as expected
- [ ] Upgrades affect zone size and accuracy zone correctly
- [ ] Game flow (next dart, next turn, next leg, new run) still works
- [ ] Hover tooltip still works during AIMING (hover should be active)
- [ ] Hover disabled during meter stages