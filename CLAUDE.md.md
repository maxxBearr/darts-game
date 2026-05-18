# Hover/Inspect Mode + Enum Refactor + Modifier Panel — Spec for Claude Code

---

## Overview

This spec adds three things:

1. **Enum refactor** — Extract all shared enums (`SegmentColor`, `ModifierTiming`, `StreakScope`, `ConfigType`) into a standalone `scoring_enums.gd` file with a `class_name`. All files that reference these enums switch from raw ints to proper enum types.

2. **Board hover feedback** — When the mouse is free (during AIMING phase and between darts/turns/legs), hovering over the dartboard highlights the segment under the cursor and shows a tooltip with the effective score for that segment. Uses the enriched scoring data including effective wedge values and segment colors.

3. **Modifier panel (relic bar)** — A horizontal row of placeholder squares along the bottom of the screen showing all active scoring modifiers. Each square is tinted by rarity color. Hovering over a square shows a tooltip with the modifier's name and description. Visible at all times, populated as modifiers are added.

**GDScript conventions:**
- Static typing on ALL variables
- Frequent commenting for readability
- `##` doc comments on all `@export` vars
- `@export` vars wherever applicable for developer/inspector control

---

## Part 1: Enum Refactor

### New File: `res://scripts/scoring_enums.gd`

```gdscript
class_name ScoringEnums
## Shared enums used by the scoring modifier system.
## Centralized here so both Resource scripts (ScoringModifier and subclasses)
## and Node scripts (ScoringModifierManager, dartboard) can reference them
## with full type safety instead of raw ints.

## The four segment colors on a standard dartboard.
## Even-index wedges: BLACK (singles), RED (doubles/triples).
## Odd-index wedges: WHITE (singles), GREEN (doubles/triples).
## Bulls: GREEN (single bull), RED (double bull).
enum SegmentColor {
	RED,
	GREEN,
	BLACK,
	WHITE,
}

## When a modifier fires in the scoring pipeline.
enum ModifierTiming {
	ON_ACQUIRE,  ## Fires once when the modifier is added (e.g., wedge value changes)
	PER_DART,    ## Fires every dart through the scoring pipeline
}

## How long streak history persists before resetting.
enum StreakScope {
	NONE,         ## Not a streak-based modifier
	WITHIN_TURN,  ## History resets every 3-dart turn
	WITHIN_LEG,   ## History resets when a new leg starts
	WITHIN_RUN,   ## History persists the entire run
}

## Whether the player needs to configure the modifier after acquiring it.
enum ConfigType {
	NONE,            ## Activates immediately, no player input needed
	PICK_WEDGE,      ## Player picks one wedge on the board to target
	PICK_TWO_WEDGES, ## Player picks two wedges (for swaps, etc.)
}
```

### Changes to `scoring_modifier_manager.gd`

**Remove** the four enum blocks (`SegmentColor`, `ModifierTiming`, `StreakScope`, `ConfigType`) from the top of the file. They now live in `ScoringEnums`.

**Replace all references** throughout the file:
- `SegmentColor.RED` → `ScoringEnums.SegmentColor.RED` (and same for GREEN, BLACK, WHITE)
- `ModifierTiming.ON_ACQUIRE` → `ScoringEnums.ModifierTiming.ON_ACQUIRE`
- `ModifierTiming.PER_DART` → `ScoringEnums.ModifierTiming.PER_DART`
- Any other enum references follow the same pattern

Specifically in `_init_default_board_state()`:
```gdscript
effective_wedge_colors.append({
	"single": ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE,
	"multi": ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN,
})
```

In `process_score()`:
```gdscript
if modifier.timing == ScoringEnums.ModifierTiming.PER_DART:
```

In `add_modifier()`:
```gdscript
if modifier.timing == ScoringEnums.ModifierTiming.ON_ACQUIRE:
```

In `get_effective_color()` return type:
```gdscript
func get_effective_color(wedge_index: int, is_multi: bool) -> ScoringEnums.SegmentColor:
```

In `get_bull_color()` return type:
```gdscript
func get_bull_color(is_double_bull: bool) -> ScoringEnums.SegmentColor:
	return ScoringEnums.SegmentColor.RED if is_double_bull else ScoringEnums.SegmentColor.GREEN
```

### Changes to `scoring_modifier.gd`

Replace the raw int exports with proper enum types:

```gdscript
## When this modifier fires in the scoring pipeline.
@export var timing: ScoringEnums.ModifierTiming = ScoringEnums.ModifierTiming.PER_DART

## Streak scope — how long hit history persists for this modifier.
## Only relevant for PER_DART modifiers that read hit history.
@export var streak_scope: ScoringEnums.StreakScope = ScoringEnums.StreakScope.NONE

## Config type — whether the player must make a selection after acquiring.
@export var config_type: ScoringEnums.ConfigType = ScoringEnums.ConfigType.NONE
```

Remove the old comments that said "Maps to ScoringModifierManager.X enum values" — they're now the real enum types.

### Changes to `wedge_value_modifier.gd`

In `_init()`:
```gdscript
func _init() -> void:
	modifier_name = "Wedge Boost"
	timing = ScoringEnums.ModifierTiming.ON_ACQUIRE
	config_type = ScoringEnums.ConfigType.PICK_WEDGE
```

### Changes to `color_bonus_modifier.gd`

Replace the raw int `target_color` export with the enum type:

```gdscript
## Which SegmentColor triggers the bonus.
@export var target_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED
```

In `_init()`:
```gdscript
func _init() -> void:
	modifier_name = "Color Bonus"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
```

In `apply()`, the comparison works the same since GDScript enum values compare with `==`:
```gdscript
func apply(result: Dictionary, _context: Dictionary) -> Dictionary:
	if result.get("segment_color", -1) == target_color:
		result["multiplier"] += bonus_multiplier
		result["total_score"] = result["face_value"] * result["multiplier"]
	return result
```

### Changes to `streak_bonus_modifier.gd`

In `_init()`:
```gdscript
func _init() -> void:
	modifier_name = "Color Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	streak_scope = ScoringEnums.StreakScope.WITHIN_LEG
	config_type = ScoringEnums.ConfigType.NONE
```

In `apply()`, update the match statement to use enum values:
```gdscript
match streak_scope:
	ScoringEnums.StreakScope.WITHIN_TURN:
		history = context["history_turn"]
	ScoringEnums.StreakScope.WITHIN_LEG:
		history = context["history_leg"]
	ScoringEnums.StreakScope.WITHIN_RUN:
		history = context["history_run"]
```

### Changes to `dartboard.gd`

In `calculate_score()`, use `ScoringEnums.SegmentColor` enum values instead of raw ints for the bullseye segment colors:

```gdscript
# For Double Bull:
segment_color = ScoringEnums.SegmentColor.RED

# For Single Bull:
segment_color = ScoringEnums.SegmentColor.GREEN
```

In `_lookup_segment_color()`, change the return type and fallback values:

```gdscript
## Look up the segment color for a wedge index and ring type.
## is_multi = true for double/triple rings, false for single rings.
## Uses effective_wedge_colors if populated, otherwise derives from wedge index.
func _lookup_segment_color(wedge_idx: int, is_multi: bool) -> ScoringEnums.SegmentColor:
	if effective_wedge_colors.size() == 20:
		var color_entry: Dictionary = effective_wedge_colors[wedge_idx]
		return color_entry["multi"] if is_multi else color_entry["single"]
	# Fallback: standard board colors based on wedge index parity
	var is_even: bool = wedge_idx % 2 == 0
	if is_multi:
		return ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
	else:
		return ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
```

Also update the `segment_color` variable declaration in `calculate_score()`. Since it starts as a "no value" sentinel before the ring is determined, and `ScoringEnums.SegmentColor` doesn't have a NONE value, keep it as an `int` initialized to `-1` and only assign enum values in each branch. The dictionary stores whatever value is assigned. This is fine — the `-1` sentinel only appears for "Off Board" hits where segment_color is meaningless.

---

## Part 2: Board Hover Feedback

### How Hover Works

Hover feedback is **passively active** whenever the mouse is free and the game is in a state where the player can look around. No Esc press needed — hovering naturally shows info.

**Hover is ACTIVE during:**
- `ThrowState.AIMING` — the mouse is already moving freely to position the aim line. Hovering over segments shows what they'd score. The aim line and the hover highlight coexist visually.
- Any "awaiting" state between darts, turns, or legs (when `_awaiting_next_dart`, `_awaiting_next_turn`, or `_awaiting_next_leg` is true in main.gd, or during upgrade selection).

**Hover is INACTIVE during:**
- `ThrowState.POSITIONING` — player is using keyboard, mouse position is irrelevant.
- `ThrowState.VERTICAL_RELEASE` — player is timing the vertical marker.
- `ThrowState.HORIZONTAL_RELEASE` — player is timing the horizontal marker.
- `ThrowState.RESOLVING` — dart is landing.
- `ThrowState.DONE` / `ThrowState.IDLE` — transient states.

### Changes to `dartboard.gd`

Add new exported variables:

```gdscript
## Color overlaid on the hovered board segment for highlighting.
## Uses an outline/border approach to avoid competing with the aim band.
@export var hover_highlight_color: Color = Color(1.0, 1.0, 1.0, 0.15)

## Border color for the hovered segment outline.
@export var hover_border_color: Color = Color(1.0, 1.0, 1.0, 0.5)

## Border thickness for the hovered segment outline in pixels.
@export var hover_border_thickness: float = 2.0

## Whether hover highlighting is currently enabled.
## Controlled by main.gd based on game state.
var hover_enabled: bool = false
```

Add hover tracking state:

```gdscript
# Hover state — tracks which segment the mouse is currently over
var _hover_wedge_idx: int = -1
var _hover_ring_name: String = ""
var _hover_active: bool = false

# Cached hover score result for tooltip display
var _hover_result: Dictionary = {}
```

Add a method for main.gd to call every frame during hover-active states:

```gdscript
## Update hover state based on the current global mouse position.
## Call this from main.gd during hover-active game states.
## Returns the score dictionary for the hovered segment (for tooltip display),
## or an empty dictionary if the mouse is off the board.
func update_hover(global_mouse_pos: Vector2) -> Dictionary:
	if not hover_enabled:
		_clear_hover()
		return {}

	var relative: Vector2 = global_mouse_pos - global_position
	var distance: float = relative.length()
	var normalized_distance: float = distance / board_radius

	# Determine which ring the mouse is in
	var new_ring_name: String = ""
	if normalized_distance <= RING_DOUBLE_BULL_OUTER:
		new_ring_name = "double_bull"
	elif normalized_distance <= RING_SINGLE_BULL_OUTER:
		new_ring_name = "single_bull"
	elif normalized_distance <= RING_INNER_SINGLE_OUTER:
		new_ring_name = "inner_single"
	elif normalized_distance <= RING_TRIPLE_OUTER:
		new_ring_name = "triple"
	elif normalized_distance <= RING_OUTER_SINGLE_OUTER:
		new_ring_name = "outer_single"
	elif normalized_distance <= RING_DOUBLE_OUTER:
		new_ring_name = "double"
	else:
		# Off board — clear hover
		_clear_hover()
		return {}

	# Determine wedge index (not needed for bullseyes)
	var new_wedge_idx: int = -1
	if new_ring_name != "double_bull" and new_ring_name != "single_bull":
		new_wedge_idx = _get_wedge_index(relative)

	# Only redraw if the hovered segment actually changed
	if new_ring_name != _hover_ring_name or new_wedge_idx != _hover_wedge_idx:
		_hover_ring_name = new_ring_name
		_hover_wedge_idx = new_wedge_idx
		_hover_active = true
		# Calculate score for this segment using effective values
		_hover_result = calculate_score(global_mouse_pos)
		queue_redraw()

	return _hover_result


## Clear hover state — call when hover should be disabled.
func clear_hover() -> void:
	_clear_hover()


## Internal clear hover and trigger redraw if needed.
func _clear_hover() -> void:
	if _hover_active:
		_hover_ring_name = ""
		_hover_wedge_idx = -1
		_hover_active = false
		_hover_result = {}
		queue_redraw()
```

Add hover drawing to `_draw()`. Add this block **after** the wire drawing and **before** the number drawing, so the hover highlight appears above the segments but below the numbers and any flash overlay:

```gdscript
	# Draw hover highlight on the segment under the mouse (if active)
	if _hover_active and _hover_ring_name != "":
		_draw_hover_segment()
```

Add the hover segment drawing method:

```gdscript
## Draw a subtle highlight on the currently hovered segment.
## Uses a filled overlay + border outline so it's visible but doesn't
## compete with the aim band overlay.
func _draw_hover_segment() -> void:
	match _hover_ring_name:
		"double_bull":
			draw_circle(Vector2.ZERO, board_radius * RING_DOUBLE_BULL_OUTER, hover_highlight_color)
			# Draw border circle
			var points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
			draw_polyline(points, hover_border_color, hover_border_thickness)
		"single_bull":
			# Draw the single bull ring area
			draw_circle(Vector2.ZERO, board_radius * RING_SINGLE_BULL_OUTER, hover_highlight_color)
			# Redraw double bull on top to "cut out" the center
			# (The actual double bull will be drawn over this in the main _draw anyway,
			# but for the hover layer alone we need to handle the donut shape)
			var outer_points: PackedVector2Array = _make_circle_points(RING_SINGLE_BULL_OUTER)
			draw_polyline(outer_points, hover_border_color, hover_border_thickness)
			var inner_points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
			draw_polyline(inner_points, hover_border_color, hover_border_thickness)
		"inner_single":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_INNER_SINGLE_OUTER, RING_SINGLE_BULL_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_INNER_SINGLE_OUTER, RING_SINGLE_BULL_OUTER)
		"triple":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_TRIPLE_OUTER, RING_INNER_SINGLE_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_TRIPLE_OUTER, RING_INNER_SINGLE_OUTER)
		"outer_single":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_OUTER_SINGLE_OUTER, RING_TRIPLE_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_OUTER_SINGLE_OUTER, RING_TRIPLE_OUTER)
		"double":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER)


## Draw a border outline around a wedge segment (used for hover highlighting).
func _draw_segment_border(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_r: float = board_radius * outer_norm
	var inner_r: float = board_radius * inner_norm

	# Outer arc from start to end
	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * outer_r)

	# Inner arc from end back to start
	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * inner_r)

	# Close the polygon outline
	points.append(points[0])
	draw_polyline(points, hover_border_color, hover_border_thickness)


## Generate circle points for a border at a given normalized radius.
func _make_circle_points(normalized_radius: float) -> PackedVector2Array:
	var r: float = board_radius * normalized_radius
	var points: PackedVector2Array = PackedVector2Array()
	var num_points: int = 64
	for i: int in range(num_points + 1):
		var angle: float = TAU * float(i) / float(num_points)
		points.append(Vector2(cos(angle), sin(angle)) * r)
	return points
```

### Changes to `hud.gd` — Hover Tooltip

Add a new label for displaying hover score info. This label sits near the board and updates when the player hovers over segments.

Add to the scene tree under HUD:

```
HUD (CanvasLayer)
├── ... (existing children) ...
└── HoverTooltip (Label)
```

**HoverTooltip properties (set in scene or code):**
- Position: centered horizontally, placed above the board (e.g., y = 30 from top)
- Horizontal alignment: center
- Auto-size or fixed width to accommodate text like "Triple 20 — 60 pts"
- Font size: slightly smaller than the main score label (e.g., 16)
- Starts hidden

Add to hud.gd:

```gdscript
@onready var hover_tooltip: Label = $HoverTooltip
```

In `_ready()`, hide it initially:

```gdscript
hover_tooltip.visible = false
```

Add methods:

```gdscript
## Show hover tooltip with score info for the segment under the mouse.
## result is the dictionary from dartboard.calculate_score() for the hovered segment.
## effective_wedge_values is used to detect if the value has been modified.
func show_hover_tooltip(result: Dictionary, original_wedge_order: Array[int]) -> void:
	if result.is_empty():
		hover_tooltip.visible = false
		return

	var ring_name: String = result["ring_name"]
	var face_value: int = result["face_value"]
	var total_score: int = result["total_score"]
	var wedge_index: int = result.get("wedge_index", -1)
	var is_bull: bool = result.get("is_bull", false)

	var tooltip_text: String = ""

	if ring_name == "Off Board":
		hover_tooltip.visible = false
		return
	elif is_bull:
		tooltip_text = "%s — %d pts" % [ring_name, total_score]
	else:
		# Check if this wedge has been modified
		var original_value: int = original_wedge_order[wedge_index] if wedge_index >= 0 and wedge_index < original_wedge_order.size() else face_value
		if face_value != original_value:
			# Show modified indicator: "Triple 10 (was 7) — 30 pts"
			tooltip_text = "%s %d (was %d) — %d pts" % [ring_name, face_value, original_value, total_score]
		else:
			tooltip_text = "%s %d — %d pts" % [ring_name, face_value, total_score]

	hover_tooltip.text = tooltip_text
	hover_tooltip.visible = true


## Hide the hover tooltip.
func hide_hover_tooltip() -> void:
	hover_tooltip.visible = false
```

---

## Part 3: Modifier Panel (Relic Bar)

A horizontal row of squares at the bottom of the screen showing all active scoring modifiers. Think Slay the Spire's relic bar — small icons in a row, with tooltip on hover.

### Scene Tree Addition

Add to the HUD scene:

```
HUD (CanvasLayer)
├── ... (existing children) ...
├── HoverTooltip (Label)
└── ModifierPanel (HBoxContainer)
```

**ModifierPanel properties:**
- Anchored to the bottom-center of the screen
- `alignment` = CENTER
- Custom separation between items (e.g., 4px)
- Starts visible but empty (no children until modifiers are added)

### Changes to `hud.gd` — Modifier Panel

Add reference:

```gdscript
@onready var modifier_panel: HBoxContainer = $ModifierPanel
```

Add a tooltip label for modifier hover (reuse the hover_tooltip or create a separate one — separate is cleaner since board hover and modifier hover might be active at different times and show different things). Create a second tooltip:

```gdscript
@onready var modifier_tooltip: Label = $ModifierTooltip
```

Add to scene tree:
```
HUD (CanvasLayer)
├── ... (existing children) ...
├── HoverTooltip (Label)       ← board hover tooltip
├── ModifierTooltip (Label)    ← modifier panel tooltip
└── ModifierPanel (HBoxContainer)
```

**ModifierTooltip properties:**
- Anchored above the modifier panel (bottom of screen, but above the panel)
- Horizontal alignment: center
- Starts hidden

In `_ready()`:

```gdscript
modifier_tooltip.visible = false
```

Add methods for managing the modifier panel:

```gdscript
## Size of each modifier square in the relic bar (pixels).
@export var modifier_square_size: int = 40

## Add a modifier square to the panel. Called when a scoring modifier is acquired.
## modifier is the ScoringModifier resource for tooltip data.
func add_modifier_to_panel(modifier: Resource) -> void:
	var square: ColorRect = ColorRect.new()
	square.custom_minimum_size = Vector2(modifier_square_size, modifier_square_size)
	# Tint by rarity color
	square.color = modifier.rarity_color
	# Store modifier reference for tooltip lookup
	square.set_meta("modifier", modifier)
	# Connect mouse signals for hover tooltip
	square.mouse_entered.connect(_on_modifier_hover.bind(square))
	square.mouse_exited.connect(_on_modifier_unhover)
	# Make sure it accepts mouse events
	square.mouse_filter = Control.MOUSE_FILTER_STOP
	modifier_panel.add_child(square)


## Clear all modifier squares from the panel. Called on new run.
func clear_modifier_panel() -> void:
	for child: Node in modifier_panel.get_children():
		child.queue_free()
	modifier_tooltip.visible = false


## Called when the mouse enters a modifier square.
func _on_modifier_hover(square: ColorRect) -> void:
	var modifier: Resource = square.get_meta("modifier")
	if modifier:
		modifier_tooltip.text = "%s\n%s" % [modifier.modifier_name, modifier.description]
		modifier_tooltip.visible = true


## Called when the mouse exits a modifier square.
func _on_modifier_unhover() -> void:
	modifier_tooltip.visible = false
```

---

## Part 4: Integration in `main.gd`

### Hover State Management

Main.gd controls when hover is active by setting `dartboard.hover_enabled` and calling `dartboard.update_hover()` at the right times.

Add a `_process()` method to main.gd (it doesn't currently have one — all updates come through signals). This handles hover updates every frame during hover-active states:

```gdscript
## Track whether hover feedback is currently active (set based on game state).
var _hover_active: bool = false


func _process(_delta: float) -> void:
	if not _hover_active:
		return

	# Feed the current mouse position to the dartboard for hover detection
	var mouse_pos: Vector2 = get_global_mouse_position()
	var hover_result: Dictionary = dartboard.update_hover(mouse_pos)

	# Update the hover tooltip on the HUD
	if hover_result.is_empty():
		hud.hide_hover_tooltip()
	else:
		hud.show_hover_tooltip(hover_result, dartboard.WEDGE_ORDER)
```

Add helper methods to enable/disable hover:

```gdscript
## Enable hover feedback on the board and tooltip display.
func _enable_hover() -> void:
	_hover_active = true
	dartboard.hover_enabled = true


## Disable hover feedback and clear any active highlight/tooltip.
func _disable_hover() -> void:
	_hover_active = false
	dartboard.hover_enabled = false
	dartboard.clear_hover()
	hud.hide_hover_tooltip()
```

### Where to Enable/Disable Hover

**Enable hover in these places:**

1. In `_on_throw_state_changed()`, when entering AIMING:
```gdscript
func _on_throw_state_changed(new_state: int) -> void:
	match new_state:
		throw_mechanic.ThrowState.AIMING:
			# Hover is active during aiming — mouse is free
			_enable_hover()
		throw_mechanic.ThrowState.POSITIONING:
			# Hover off — player is using keyboard for window positioning
			_disable_hover()
			hud.show_instruction("W/S or Up/Down to move window, Enter/Space to lock")
		throw_mechanic.ThrowState.VERTICAL_RELEASE:
			_disable_hover()
			hud.show_instruction("Click or Space to lock vertical position")
		throw_mechanic.ThrowState.HORIZONTAL_RELEASE:
			_disable_hover()
			hud.show_instruction("Click or Space to lock horizontal position")
		throw_mechanic.ThrowState.RESOLVING:
			_disable_hover()
			hud.show_instruction("Releasing...")
```

Note: the AIMING case is new — the existing `_on_throw_state_changed` didn't have a case for AIMING because it only handled instruction text. Now it also enables hover. This is fine because `state_changed` is emitted for all state transitions.

**IMPORTANT:** Check that `throw_mechanic.gd` actually emits `state_changed` when entering AIMING. Looking at `start_throw()` (line 127-136 of throw_mechanic.gd), it sets `_state = ThrowState.AIMING` but does NOT emit `state_changed`. Add the emit:

In `throw_mechanic.gd`, in `start_throw()`, after setting the state:
```gdscript
func start_throw(board_center: Vector2, board_radius: float) -> void:
	_board_center = board_center
	_board_radius = board_radius
	_aim_x = _board_center.x
	_state = ThrowState.AIMING
	_bounce_t = 0.0
	_horizontal_bounce_t = 0.0
	_is_shrink_complete = false
	set_process(true)
	state_changed.emit(ThrowState.AIMING)  # ← ADD THIS LINE
	queue_redraw()
```

2. In the "awaiting" states — after a throw completes and the player is waiting to press a button. In `_on_throw_completed()`, enable hover at the end of the function (after all the branching logic), since regardless of which branch was taken (next dart, next turn, bust, leg won, game over), the player is now in a waiting state:

Add at the very end of `_on_throw_completed()`:
```gdscript
	# Enable hover feedback while player decides what to do next
	_enable_hover()
```

3. During upgrade selection — hover should stay active so the player can check the board while deciding on upgrades. Hover is already enabled from the `_on_throw_completed()` call above, and nothing disables it during upgrade display, so this works automatically.

**Disable hover in these places:**

1. At the start of `_start_new_throw()`, before the throw mechanic takes over. Actually, hover gets re-enabled immediately when AIMING starts (via `_on_throw_state_changed`), so we don't need to explicitly disable it here. But it's cleaner to disable → re-enable so there's no frame where hover state is stale. Add to the start of `_start_new_throw()`:

```gdscript
func _start_new_throw() -> void:
	_disable_hover()
	hud.hide_score()
	# ... rest of existing code ...
```

2. In `_on_new_run()` — clear hover state as part of the full reset. Already implicitly handled if `_start_new_throw()` is called (which it is), but explicitly call `_disable_hover()` for clarity.

### Modifier Panel Integration

When a modifier is added to the scoring modifier manager, also add it to the HUD's modifier panel.

In `main.gd`, wherever a modifier is added (currently this is only via debug modifiers or future shop code), call the HUD after adding:

Add a helper method:
```gdscript
## Add a scoring modifier to the game. Handles both the manager and HUD panel.
func add_scoring_modifier(modifier: Resource, config: Dictionary) -> void:
	scoring_modifier_manager.add_modifier(modifier, config)
	hud.add_modifier_to_panel(modifier)
	_sync_board_state()
```

In `_on_new_run()`, clear the modifier panel:
```gdscript
func _on_new_run() -> void:
	_run_over = false
	_turn_score = 0
	hud.update_turn_score(0)
	scoring_modifier_manager.reset_for_run()
	hud.clear_modifier_panel()  # ← ADD THIS
	_sync_board_state()
	_clear_darts()
	_restore_base_stats()
	x01_game.start_run()
	_update_all_hud()
	_start_new_throw()
```

For debug modifier testing in `_ready()`, after the modifier manager has already added its debug modifiers in its own `_ready()`, sync the panel. Add after `_sync_board_state()`:

```gdscript
	# Sync debug modifiers to the HUD panel (modifier manager already added them in its _ready)
	for modifier: Resource in scoring_modifier_manager.active_modifiers:
		hud.add_modifier_to_panel(modifier)
```

---

## Scene Tree Changes Summary

### Additions to the HUD scene:

```
HUD (CanvasLayer)
├── ... (all existing children unchanged) ...
├── HoverTooltip (Label)
│       - Position: top-center area, above the board
│       - Horizontal alignment: CENTER
│       - Anchors: top-center (anchor_left=0.3, anchor_right=0.7, anchor_top=0.02)
│       - Font size: 16
│       - Visible: false (hidden by default)
├── ModifierTooltip (Label)
│       - Position: bottom area, just above ModifierPanel
│       - Horizontal alignment: CENTER
│       - Anchors: bottom-center (anchor_left=0.2, anchor_right=0.8, anchor_bottom=0.92)
│       - Font size: 14
│       - Visible: false (hidden by default)
└── ModifierPanel (HBoxContainer)
        - Anchors: bottom-center (anchor_left=0.3, anchor_right=0.7, anchor_top=0.95, anchor_bottom=1.0)
        - alignment: CENTER
        - Custom theme constant "separation": 4
        - Starts empty (children added dynamically)
```

### New file:
```
res://scripts/scoring_enums.gd
```

### Modified files:
```
res://scripts/scoring_modifier_manager.gd  (enum references updated)
res://scripts/scoring_modifier.gd          (exports use enum types)
res://scripts/modifiers/wedge_value_modifier.gd  (enum references)
res://scripts/modifiers/color_bonus_modifier.gd  (enum references + target_color type)
res://scripts/modifiers/streak_bonus_modifier.gd (enum references)
res://scripts/dartboard.gd                 (hover system + enum references)
res://scripts/hud.gd                       (hover tooltip + modifier panel)
res://scripts/main.gd                      (hover management + modifier panel integration)
res://scripts/throw_mechanic.gd            (emit state_changed for AIMING)
```

---

## What This Does NOT Change

- Stat upgrades remain in main.gd, unchanged
- X01 game logic unchanged
- Throw mechanic logic unchanged (only addition is emitting state_changed for AIMING)
- No shop/acquisition flow — modifiers are still added via debug_modifiers export or code
- No Esc-to-pause during throws (noted as future feature)
- Modifier panel uses placeholder colored squares — icons/art are future work