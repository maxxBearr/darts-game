# Target Declaration & Accuracy Scaling System

## Overview

When the player clicks to place the aim ellipse, the clicked board segment becomes their **declared target**. During the meter phases, the accuracy zone dynamically scales based on how close the final locked marker position is to the **centroid of the declared target segment** — not the center of the aim ellipse. Landing near the target centroid rewards tight accuracy (green zone bonus). Landing far from it penalizes with a bloated accuracy zone (red zone penalty). This creates a skill/risk tradeoff on every throw without punishing imprecise mouse placement during aiming.

Additionally, the **horizontal meter width now follows the ellipse geometry** — it bounces across the ellipse width at the locked Y position, not the full ellipse width.

---

## Coding Conventions

- Static typing on ALL variables
- Frequent commenting for readability
- `##` doc comments on all `@export` vars describing what they do and what values mean
- `@export` vars liberally for developer control

---

## System 1: Target Declaration

### When the Target is Declared

During `AIMING`, when the player clicks (or presses Space/Enter) to place the ellipse, the click position is passed through the dartboard's scoring system to identify which segment was clicked. That segment becomes the declared target for this throw.

### What Gets Stored

```gdscript
## The board segment the player declared as their target when placing the aim zone.
## Contains the same keys as dartboard.calculate_score() output:
## face_value, multiplier, total_score, ring_name, wedge_index, segment_color, is_bull.
var _declared_target: Dictionary = {}

## The centroid (center point) of the declared target segment in global coordinates.
## Used as the reference point for accuracy scaling distance checks.
var _target_centroid: Vector2 = Vector2.ZERO
```

### Computing the Segment Centroid

The dartboard needs a new public function to compute the centroid of any segment. The centroid is the geometric center of the arc-segment (wedge slice of a ring).

Add to `dartboard.gd`:

```gdscript
## Compute the global-space centroid of a board segment identified by wedge_index and ring_name.
## For bullseyes, returns the board center. For wedge segments, returns the midpoint
## of the arc segment (center angle of the wedge, midpoint radius of the ring).
func get_segment_centroid(wedge_index: int, ring_name: String) -> Vector2:
    # Bullseye centroids are at (or near) board center
    if ring_name == "Double Bull" or ring_name == "double_bull":
        return global_position
    if ring_name == "Single Bull" or ring_name == "single_bull":
        # Midpoint of single bull ring
        var mid_r: float = board_radius * (RING_DOUBLE_BULL_OUTER + RING_SINGLE_BULL_OUTER) / 2.0
        # Could offset slightly but center is fine for a ring around center
        return global_position

    # For wedge segments, compute center angle and midpoint radius
    var center_angle_deg: float = wedge_index * WEDGE_ANGLE_DEG
    var center_angle_rad: float = deg_to_rad(center_angle_deg)
    var direction: Vector2 = Vector2(sin(center_angle_rad), -cos(center_angle_rad))

    # Determine inner and outer normalized radius for this ring
    var inner_norm: float = 0.0
    var outer_norm: float = 0.0
    # Accept both display names (from calculate_score) and internal names (from flash/hover)
    match ring_name:
        "Inner Single", "inner_single":
            inner_norm = RING_SINGLE_BULL_OUTER
            outer_norm = RING_INNER_SINGLE_OUTER
        "Triple", "triple":
            inner_norm = RING_INNER_SINGLE_OUTER
            outer_norm = RING_TRIPLE_OUTER
        "Outer Single", "outer_single":
            inner_norm = RING_TRIPLE_OUTER
            outer_norm = RING_OUTER_SINGLE_OUTER
        "Double", "double":
            inner_norm = RING_OUTER_SINGLE_OUTER
            outer_norm = RING_DOUBLE_OUTER

    var mid_r: float = board_radius * (inner_norm + outer_norm) / 2.0
    return global_position + direction * mid_r
```

### Flow Integration

In `throw_mechanic.gd`, when transitioning from `AIMING` to `VERTICAL_RELEASE`:

1. Capture the click/placement position.
2. Call `dartboard.calculate_score(placement_position)` to get the target segment info.
3. Call `dartboard.get_segment_centroid(result.wedge_index, result.ring_name)` to get the centroid.
4. Store both in `_declared_target` and `_target_centroid`.

**Important:** The throw mechanic needs a reference to the dartboard node. Currently `start_throw()` receives `board_center` and `board_radius`. This should be extended — either pass the dartboard reference, or add a `dartboard` variable that `main.gd` sets. The cleanest approach is to add an `@export var dartboard: Node2D` on `throw_mechanic.gd` and wire it in the scene tree or in `main.gd._ready()`.

### Edge Case: Off-Board Click

If the player clicks to place the ellipse but the click position is off the board (ring_name == "Off Board"), fall back to using the **ellipse center** as the target centroid, and set `_declared_target` to an empty dictionary. The accuracy scaling system treats an empty target as neutral (no bonus, no penalty). This prevents crashes and handles the edge case gracefully.

### Edge Case: Bullseye Target

If the player clicks on the bull, the centroid is the board center. The accuracy scaling works the same way — distance from board center determines the zone.

---

## System 2: H Meter Width Follows Ellipse Geometry

### Current Behavior (to be changed)

The horizontal meter currently bounces across the full ellipse width regardless of where the vertical meter was stopped.

### New Behavior

After the player locks the vertical position (`_locked_release_y`), compute the ellipse width at that Y coordinate:

```gdscript
## Compute the ellipse half-width at a given Y position.
## Returns 0.0 if y is outside the ellipse's vertical extent.
func _get_ellipse_half_width_at_y(y: float) -> float:
    var dy: float = (y - _placed_center.y) / _aim_half_height
    if absf(dy) >= 1.0:
        return 0.0
    return _aim_half_width * sqrt(1.0 - dy * dy)
```

Store this as `_h_meter_half_width` when entering `HORIZONTAL_RELEASE`:

```gdscript
## The effective half-width for the horizontal meter at the locked Y position.
## Derived from the ellipse width at _locked_release_y.
var _h_meter_half_width: float = 0.0
```

The horizontal marker then bounces between `_placed_center.x - _h_meter_half_width` and `_placed_center.x + _h_meter_half_width`.

### Minimum Floor

No artificial minimum is needed — the accuracy scaling system (System 3) naturally penalizes aiming near the poles, so the "tip exploit" is already handled.

---

## System 3: Accuracy Scaling Based on Target Distance

### Core Mechanic

After both meters are locked (entering `RESOLVING`), compute the normalized distance from the locked marker position to the declared target centroid. This distance determines a multiplier applied to the accuracy zone semi-axes.

### Distance Calculation

```gdscript
## Compute normalized distance from a point to the target centroid,
## scaled relative to the aim ellipse size. Returns 0.0 at the centroid,
## ~1.0 at the ellipse boundary, and >1.0 if somehow outside.
func _get_target_distance_normalized() -> float:
    if _declared_target.is_empty():
        return 0.5  # Neutral fallback for off-board targets
    var dx: float = _horizontal_x - _target_centroid.x
    var dy: float = _locked_release_y - _target_centroid.y
    # Normalize relative to ellipse semi-axes so shape is accounted for
    var norm_x: float = dx / _aim_half_width if _aim_half_width > 0.0 else 0.0
    var norm_y: float = dy / _aim_half_height if _aim_half_height > 0.0 else 0.0
    return sqrt(norm_x * norm_x + norm_y * norm_y)
```

### Three-Zone Accuracy Scaling

The normalized distance `d` maps to three zones with smooth interpolation:

```gdscript
## Normalized distance threshold for the green (bonus) zone.
## At or below this distance, the player gets an accuracy bonus.
## 0.0 = only exact centroid gets bonus. 0.3 = generous green zone.
@export_range(0.0, 0.5, 0.01) var green_zone_threshold: float = 0.25

## Normalized distance threshold where the penalty zone begins.
## Between green_threshold and this value is the neutral zone (no change).
## Above this value, accuracy starts degrading toward the edge.
@export_range(0.3, 0.8, 0.01) var penalty_zone_threshold: float = 0.6

## Accuracy multiplier at the center of the green zone (best case).
## Values < 1.0 mean the accuracy zone shrinks (tighter grouping).
## 0.7 = 30% tighter accuracy at perfect center hits.
@export_range(0.5, 1.0, 0.01) var green_zone_multiplier: float = 0.75

## Accuracy multiplier at the ellipse edge (worst case).
## Values > 1.0 mean the accuracy zone bloats (wider scatter).
## 2.5 = accuracy zone is 2.5x larger at the very edge.
@export_range(1.5, 4.0, 0.1) var max_edge_penalty_multiplier: float = 2.5
```

Compute the final multiplier:

```gdscript
## Compute the accuracy zone multiplier based on distance from target centroid.
## Returns < 1.0 in green zone (bonus), 1.0 in neutral, > 1.0 in penalty zone.
func _get_accuracy_multiplier(normalized_distance: float) -> float:
    if normalized_distance <= green_zone_threshold:
        # Green zone: lerp from green_zone_multiplier (at d=0) to 1.0 (at threshold)
        var t: float = normalized_distance / green_zone_threshold if green_zone_threshold > 0.0 else 0.0
        return lerpf(green_zone_multiplier, 1.0, t)
    elif normalized_distance <= penalty_zone_threshold:
        # Neutral zone: no modification
        return 1.0
    else:
        # Penalty zone: lerp from 1.0 (at penalty_threshold) to max_edge_penalty (at d=1.0)
        var t: float = (normalized_distance - penalty_zone_threshold) / (1.0 - penalty_zone_threshold)
        t = clampf(t, 0.0, 1.0)
        return lerpf(1.0, max_edge_penalty_multiplier, t)
```

### Application to Accuracy Zone

In `_resolve_throw()` and in the resolving draw function, multiply the accuracy semi-axes by this multiplier:

```gdscript
var dist: float = _get_target_distance_normalized()
var accuracy_mult: float = _get_accuracy_multiplier(dist)
var effective_h_accuracy_half: float = _get_horizontal_accuracy_half() * accuracy_mult
var effective_v_accuracy_half: float = _get_vertical_accuracy_half() * accuracy_mult
```

Use `effective_h_accuracy_half` and `effective_v_accuracy_half` everywhere the accuracy zone is drawn or sampled — the resolve preview, the Gaussian rejection sampling, and the ghost preview during meters.

---

## System 4: Accuracy Zone Color Feedback

### Color Lerp Based on Accuracy Multiplier

The accuracy zone color smoothly transitions based on the current accuracy multiplier:

```gdscript
## Color of the accuracy zone when in the green (bonus) zone.
@export var accuracy_green_color: Color = Color(0.2, 0.85, 0.3, 0.25)

## Color of the accuracy zone in the neutral zone (no bonus or penalty).
@export var accuracy_neutral_color: Color = Color(1.0, 0.9, 0.2, 0.25)

## Color of the accuracy zone when in the red (penalty) zone.
@export var accuracy_red_color: Color = Color(0.9, 0.2, 0.15, 0.25)
```

Compute the display color:

```gdscript
## Get the accuracy zone color based on the current accuracy multiplier.
func _get_accuracy_zone_color(accuracy_multiplier: float) -> Color:
    if accuracy_multiplier <= 1.0:
        # Green to neutral: multiplier goes from green_zone_multiplier to 1.0
        var t: float = (accuracy_multiplier - green_zone_multiplier) / (1.0 - green_zone_multiplier)
        t = clampf(t, 0.0, 1.0)
        return accuracy_green_color.lerp(accuracy_neutral_color, t)
    else:
        # Neutral to red: multiplier goes from 1.0 to max_edge_penalty_multiplier
        var t: float = (accuracy_multiplier - 1.0) / (max_edge_penalty_multiplier - 1.0)
        t = clampf(t, 0.0, 1.0)
        return accuracy_neutral_color.lerp(accuracy_red_color, t)
```

This color is used when drawing:
- The ghost accuracy preview during meters (System 5)
- The final accuracy ellipse during RESOLVING

---

## System 5: Live Ghost Accuracy Preview During Meters

### Concept

While the vertical and horizontal meters are bouncing, a **ghost preview** of the accuracy zone is drawn at the current marker position. This ghost updates every frame, showing the player in real time what their accuracy zone would look like if they clicked right now. It changes **size** (based on distance from target centroid) and **color** (green/yellow/red) as the marker moves.

### During VERTICAL_RELEASE

The ghost accuracy zone is drawn centered at `(_placed_center.x, _release_y)` — the current vertical marker position, at the ellipse center X (since H hasn't been determined yet).

For the distance calculation during this phase, use the X of the placed center as a stand-in for the final horizontal position, since we don't know it yet. This gives the player directional feedback on the vertical axis at least.

```gdscript
func _draw_vertical_release() -> void:
    # ... existing dimmed ellipse and meter drawing ...

    # Ghost accuracy preview at current marker position
    var preview_pos: Vector2 = Vector2(_placed_center.x, _release_y)
    var dist: float = _get_target_distance_normalized_at(preview_pos)
    var mult: float = _get_accuracy_multiplier(dist)
    var ghost_h_half: float = _get_horizontal_accuracy_half() * mult
    var ghost_v_half: float = _get_vertical_accuracy_half() * mult
    var ghost_color: Color = _get_accuracy_zone_color(mult)
    # Draw with reduced alpha so it reads as a preview
    ghost_color.a *= 0.5
    var local_pos: Vector2 = preview_pos - global_position
    _draw_filled_ellipse(local_pos, ghost_h_half, ghost_v_half, ghost_color)
    _draw_ellipse_outline(local_pos, ghost_h_half, ghost_v_half,
        Color(ghost_color, ghost_color.a * 2.0), 1.5)
```

### During HORIZONTAL_RELEASE

The ghost is drawn at `(_horizontal_x, _locked_release_y)` — the current horizontal marker position at the locked Y. This is the actual position that will be used for the distance check, so the preview is fully accurate.

```gdscript
func _draw_horizontal_release() -> void:
    # ... existing drawing ...

    # Ghost accuracy preview at current marker position
    var preview_pos: Vector2 = Vector2(_horizontal_x, _locked_release_y)
    var dist: float = _get_target_distance_normalized_at(preview_pos)
    var mult: float = _get_accuracy_multiplier(dist)
    var ghost_h_half: float = _get_horizontal_accuracy_half() * mult
    var ghost_v_half: float = _get_vertical_accuracy_half() * mult
    var ghost_color: Color = _get_accuracy_zone_color(mult)
    ghost_color.a *= 0.5
    var local_pos: Vector2 = preview_pos - global_position
    _draw_filled_ellipse(local_pos, ghost_h_half, ghost_v_half, ghost_color)
    _draw_ellipse_outline(local_pos, ghost_h_half, ghost_v_half,
        Color(ghost_color, ghost_color.a * 2.0), 1.5)
```

### Helper for Preview Distance

The existing `_get_target_distance_normalized()` uses `_horizontal_x` and `_locked_release_y`, which aren't set during the V meter phase. Add a variant that takes an arbitrary position:

```gdscript
## Compute normalized distance from an arbitrary point to the target centroid.
func _get_target_distance_normalized_at(pos: Vector2) -> float:
    if _declared_target.is_empty():
        return 0.5
    var dx: float = pos.x - _target_centroid.x
    var dy: float = pos.y - _target_centroid.y
    var norm_x: float = dx / _aim_half_width if _aim_half_width > 0.0 else 0.0
    var norm_y: float = dy / _aim_half_height if _aim_half_height > 0.0 else 0.0
    return sqrt(norm_x * norm_x + norm_y * norm_y)
```

---

## System 6: Target Highlight on Board

### Visual Indicator

When the player places the aim ellipse, the declared target segment should be subtly highlighted on the dartboard so the player can see "this is what I'm aiming for."

Add to `dartboard.gd`:

```gdscript
## Color of the target segment highlight (shown during throw after placement).
@export var target_highlight_color: Color = Color(1.0, 0.85, 0.2, 0.12)

## Border color for the target segment highlight.
@export var target_highlight_border_color: Color = Color(1.0, 0.85, 0.2, 0.4)

## The currently declared target segment. Set by main.gd when the player places the aim zone.
## Dictionary with wedge_index, ring_name, is_bull keys. Empty = no target.
var declared_target: Dictionary = {}
```

Add a new function to set/clear the target:

```gdscript
## Set the declared target segment for visual highlighting.
func set_declared_target(target: Dictionary) -> void:
    declared_target = target
    queue_redraw()

## Clear the declared target highlight.
func clear_declared_target() -> void:
    declared_target = {}
    queue_redraw()
```

In `_draw()`, after drawing the board but before the flash overlay, draw the target highlight if set. Reuse the existing `_draw_segment()` and `_draw_segment_border()` functions — same approach as hover highlighting but with the target highlight colors.

For bullseye targets, highlight the appropriate bull circle.

### When to Show/Hide

- **Show:** When `main.gd` receives the target declaration (after aim placement click). Call `dartboard.set_declared_target(target_info)`.
- **Hide:** When the throw resolves (dart lands). Call `dartboard.clear_declared_target()` in `_on_throw_completed()`.
- **Also hide:** On new run, when clearing state.

---

## System 7: Target Tooltip

### Display Format

When the player places the aim zone and declares a target, display a persistent tooltip showing what they're aiming for and what it's worth with current modifiers.

**Format:**
```
Target: [ring_prefix] [face_value] | Worth: [base_score] + [bonus_mult]×[face_value] = [total] | [streak_info]
```

**Ring prefix mapping:**
- "Inner Single" or "Outer Single" → `S`
- "Double" → `D`
- "Triple" → `T`
- "Single Bull" → `SB`
- "Double Bull" → `DB`

**Examples:**
- No modifiers: `Target: D20 | Worth: 40`
- With +1x red bonus: `Target: D20 | Worth: 40 + 1×20 = 60`
- With +1x red and +2x even: `Target: D20 | Worth: 40 + 3×20 = 100`
- Off board: No tooltip shown

**Streak info:** Only shown if the player has an active streak modifier. Shows the current streak count for the relevant streak type. Format: `[Streak Name] ×[count] 🔥` (fire indicator only when streak is actively contributing bonus).

### Implementation

The target tooltip replaces the hover tooltip during the throw (hover is disabled during meters anyway). It appears in the same HUD location.

**When the target is declared** in `main.gd`:
1. Run the target segment through `scoring_modifier_manager.process_score(target_result, true)` in preview mode to get the fully modified score.
2. Compute the bonus breakdown: `bonus_multiplier_total = modified_multiplier - base_multiplier`. If > 0, show the `+ Nx[face_value] = [total]` portion.
3. Check active streak modifiers for current streak counts and include streak info if applicable.
4. Pass the formatted info to the HUD for display.

**Add to `hud.gd`:**

```gdscript
## Show the target declaration tooltip during a throw.
## target_info contains: prefix (S/D/T/SB/DB), face_value, base_score, total_score,
## bonus_multiplier_total, streak_lines (Array[String]).
func show_target_tooltip(target_info: Dictionary) -> void:
    # Build the display string and show in the tooltip label
    pass  # Implementation depends on existing HUD tooltip structure

## Hide the target tooltip (when throw completes or new run starts).
func hide_target_tooltip() -> void:
    pass
```

The actual HUD label formatting and positioning follows the existing hover tooltip pattern — reuse the same label/panel if possible, just change the content.

### Worth Calculation Detail

The "Worth" line needs to show the breakdown clearly. To compute it:

```gdscript
## Build target tooltip info from a declared target and the modifier pipeline.
func _build_target_tooltip(target_result: Dictionary) -> Dictionary:
    var face_value: int = target_result["face_value"]
    var base_multiplier: int = target_result["multiplier"]
    var base_score: int = face_value * base_multiplier

    # Run through modifier pipeline in preview mode
    var modified: Dictionary = scoring_modifier_manager.process_score(target_result.duplicate(), true)
    var modified_multiplier: int = modified["multiplier"]
    var total_score: int = modified["total_score"]
    var bonus_mult: int = modified_multiplier - base_multiplier

    # Build ring prefix
    var prefix: String = _get_ring_prefix(target_result["ring_name"])

    # Build streak info lines from active streak modifiers
    var streak_lines: Array[String] = _get_active_streak_info()

    return {
        "prefix": prefix,
        "face_value": face_value,
        "base_score": base_score,
        "total_score": total_score,
        "bonus_multiplier_total": bonus_mult,
        "streak_lines": streak_lines,
    }


func _get_ring_prefix(ring_name: String) -> String:
    match ring_name:
        "Inner Single", "Outer Single":
            return "S"
        "Double":
            return "D"
        "Triple":
            return "T"
        "Single Bull":
            return "SB"
        "Double Bull":
            return "DB"
    return ""
```

### Streak Info in Tooltip

Only show streak status if the player has an active streak modifier. Query the `scoring_modifier_manager.active_modifiers` for any that have `streak_scope != NONE`, and read their current streak count.

The streak modifier classes need a public getter for current streak count. Add to `streak_bonus_modifier.gd`:

```gdscript
## Get the current streak count for display purposes.
func get_streak_count() -> int:
    return _streak_count
```

New color/even-odd streak modifiers (covered in the separate streak slot spec) would need the same getter.

---

## Files Affected

### `throw_mechanic.gd` — Major changes
- Add `_declared_target`, `_target_centroid` variables
- Add `_h_meter_half_width` variable and `_get_ellipse_half_width_at_y()` helper
- Add accuracy scaling export vars (thresholds, multipliers, colors)
- Add `_get_target_distance_normalized()`, `_get_target_distance_normalized_at()`, `_get_accuracy_multiplier()`, `_get_accuracy_zone_color()` functions
- Modify `HORIZONTAL_RELEASE` to use `_h_meter_half_width` instead of full ellipse width
- Modify `_resolve_throw()` to apply accuracy multiplier before Gaussian sampling
- Modify all `_draw_*` functions to include ghost accuracy preview with color feedback
- Modify `_draw_resolving()` to use accuracy-scaled ellipse with appropriate color
- Need a reference to the dartboard node (add `@export var dartboard: Node2D` or have `main.gd` set it)

### `dartboard.gd` — Moderate changes
- Add `get_segment_centroid()` function
- Add `declared_target`, `target_highlight_color`, `target_highlight_border_color` variables
- Add `set_declared_target()` / `clear_declared_target()` functions
- Add target highlight drawing in `_draw()` (after segments, before flash)

### `main.gd` — Moderate changes
- Wire dartboard reference to throw_mechanic (if using export var approach)
- On aim placement: compute target, call `dartboard.set_declared_target()`, build tooltip info, call `hud.show_target_tooltip()`
- On throw complete: call `dartboard.clear_declared_target()`, call `hud.hide_target_tooltip()`
- Add `_build_target_tooltip()` and `_get_ring_prefix()` helper functions
- Add `_get_active_streak_info()` to query streak modifiers for tooltip display

### `hud.gd` — Minor changes
- Add `show_target_tooltip()` / `hide_target_tooltip()` functions
- Reuse or adapt existing hover tooltip label/panel for target display

### `streak_bonus_modifier.gd` — Minor change
- Add `get_streak_count() -> int` public getter

### `scoring_modifier_manager.gd` — No changes
- Already supports `process_score()` in preview mode, which is all the tooltip needs

---

## Integration with Existing Ellipse Throw Mechanic

This spec builds on top of the already-implemented ellipse-based throw mechanic. It assumes:
- `AIMING` state places an ellipse that follows the mouse
- `_placed_center`, `_aim_half_width`, `_aim_half_height` are already stored on placement
- `VERTICAL_RELEASE` bounces within the ellipse height
- `HORIZONTAL_RELEASE` bounces within the ellipse (width change is part of THIS spec)
- `RESOLVING` draws an accuracy ellipse and does Gaussian rejection sampling
- Drawing utilities (`_draw_filled_ellipse`, `_draw_ellipse_outline`) already exist

---

## Testing Checklist

- [ ] Clicking on a board segment during AIMING stores the correct target (wedge_index, ring_name, face_value)
- [ ] Segment centroid computation returns a point visually centered in the segment
- [ ] Bullseye target centroid returns board center
- [ ] Off-board click falls back to neutral accuracy (no crash, no bonus/penalty)
- [ ] H meter width narrows when V meter is stopped near the ellipse poles
- [ ] H meter runs full width when V meter is stopped at ellipse center
- [ ] Accuracy zone is visibly smaller (green) when marker is near target centroid
- [ ] Accuracy zone is visibly larger (red) when marker is near ellipse edge
- [ ] Accuracy zone is neutral (yellow) in the middle band
- [ ] Color transitions smoothly between green → yellow → red (no hard pops)
- [ ] Ghost preview updates every frame during V meter bouncing
- [ ] Ghost preview updates every frame during H meter bouncing
- [ ] Ghost preview size and color match the final accuracy zone at the same position
- [ ] Target segment is highlighted on the dartboard after placement
- [ ] Target highlight clears when the dart lands
- [ ] Target tooltip shows correct ring prefix and face value
- [ ] Target tooltip shows modifier bonus breakdown when modifiers are active
- [ ] Target tooltip shows streak count only when a streak modifier is equipped
- [ ] Dart always lands within the accuracy-scaled ellipse (never outside)
- [ ] Green zone bonus makes grouping noticeably tighter in gameplay
- [ ] Red zone penalty makes scatter noticeably worse in gameplay
- [ ] Range stat upgrades make the green zone easier to hit (smaller ellipse = closer to everything)