extends Node2D
## Procedurally drawn dartboard with polar-coordinate scoring system.
## All visual segments use the same constants as scoring, guaranteeing sync.

# --- Ring radius thresholds (normalized: 0.0 = center, 1.0 = board edge) ---
const RING_DOUBLE_BULL_OUTER: float = 0.032
const RING_SINGLE_BULL_OUTER: float = 0.080
const RING_INNER_SINGLE_OUTER: float = 0.480
const RING_TRIPLE_OUTER: float = 0.530
const RING_OUTER_SINGLE_OUTER: float = 0.760
const RING_DOUBLE_OUTER: float = 0.830

# Standard dartboard number order, clockwise from top
const WEDGE_ORDER: Array[int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

# Each wedge spans 18 degrees; offset by -9 so numbers are centered
const WEDGE_ANGLE_DEG: float = 18.0
const WEDGE_OFFSET_DEG: float = -9.0

## Board pixel radius — determines overall size of the dartboard on screen.
@export var board_radius: float = 300.0

## Number of arc points per segment edge for smooth curves.
@export var arc_points: int = 10

## Color for even-index wedge single areas (black on a traditional board).
@export var wedge_a_single: Color = Color(0.1, 0.1, 0.1)

## Color for even-index wedge double/triple areas (red on a traditional board).
@export var wedge_a_multi: Color = Color(0.8, 0.1, 0.1)

## Color for odd-index wedge single areas (cream/white on a traditional board).
@export var wedge_b_single: Color = Color(0.95, 0.9, 0.75)

## Color for odd-index wedge double/triple areas (green on a traditional board).
@export var wedge_b_multi: Color = Color(0.0, 0.5, 0.15)

## Single bull (outer bullseye) color.
@export var bull_single_color: Color = Color(0.0, 0.5, 0.15)

## Double bull (inner bullseye) color.
@export var bull_double_color: Color = Color(0.8, 0.1, 0.1)

## Wire/border line color between segments.
@export var wire_color: Color = Color(0.7, 0.7, 0.7)

## Wire thickness in pixels.
@export var wire_thickness: float = 1.5

## Surround (off-board) color.
@export var surround_color: Color = Color(0.15, 0.15, 0.15)

## Surround ring outer radius multiplier (relative to board_radius).
@export var surround_outer_multiplier: float = 1.15

## Font size for the wedge numbers displayed around the board.
## Adjust based on board_radius — 20 works well for a 300px radius board.
@export var number_font_size: int = 20

## Color of the wedge numbers.
@export var number_color: Color = Color(0.9, 0.9, 0.85)

## Color for wedge numbers that have been modified by upgrades.
## Should stand out from the default number_color so players can spot changes.
@export var modified_number_color: Color = Color(0.2, 1.0, 0.4)

## Color overlaid on the hovered board segment for highlighting.
@export var hover_highlight_color: Color = Color(1.0, 1.0, 1.0, 0.15)

## Border color for the hovered segment outline.
@export var hover_border_color: Color = Color(1.0, 1.0, 1.0, 0.5)

## Border thickness for the hovered segment outline in pixels.
@export var hover_border_thickness: float = 2.0

## Color of the checkout pulse glow on valid finishing doubles.
@export var checkout_pulse_color: Color = Color(1.0, 0.85, 0.2, 0.8)

## Speed of the checkout pulse animation (higher = faster shimmer).
@export var checkout_pulse_speed: float = 3.0

## Minimum opacity of the checkout pulse (the "dim" part of the cycle).
@export var checkout_pulse_min_alpha: float = 0.15

## Maximum opacity of the checkout pulse (the "bright" part of the cycle).
@export var checkout_pulse_max_alpha: float = 0.7

## Border thickness for checkout pulse outlines.
@export var checkout_border_thickness: float = 3.0

## Normalized radius for number placement. Controls how far from center
## the numbers are drawn. Should be between RING_DOUBLE_OUTER (0.83) and
## surround_outer_multiplier (1.15). Default 0.93 centers them in the surround.
@export var number_radius_multiplier: float = 0.93

## Color of the segment flash overlay on dart landing (white = bright flash).
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 0.6)

## Duration of the segment flash in seconds.
@export var flash_duration: float = 0.2

# Flash state — tracks which segment to highlight and the current flash alpha
var _flash_alpha: float = 0.0
var _flash_ring_name: String = ""
var _flash_wedge_idx: int = -1

## The effective wedge values used for scoring and number display.
## Set by ScoringModifierManager. When empty, falls back to WEDGE_ORDER.
var effective_wedge_values: Array[int] = []

## The effective wedge colors for segment color reporting.
## Set by ScoringModifierManager. Each entry is a dict with "single" and "multi" keys.
## When empty, derives colors from wedge index (standard board colors).
var effective_wedge_colors: Array[Dictionary] = []

## Whether hover highlighting is currently enabled. Controlled by main.gd.
var hover_enabled: bool = false

# Hover state — tracks which segment the mouse is currently over
var _hover_wedge_idx: int = -1
var _hover_ring_name: String = ""
var _hover_active: bool = false
var _hover_result: Dictionary = {}

# Checkout highlight state — which segments would win the leg
var _checkout_segments: Array[Dictionary] = []
var _checkout_pulse_active: bool = false
var _checkout_pulse_time: float = 0.0

## The currently declared target segment. Set by main.gd when the player places the aim zone.
## Dictionary with wedge_index, ring_name, is_bull keys. Empty = no target.
var declared_target: Dictionary = {}

## Picker mode state — for interactive wedge selection UI
var picker_mode: bool = false
var _picker_hover_wedge: int = -1
var _picker_selected_wedges: Array[int] = []

## Color of the target segment highlight (shown during throw after placement).
@export var target_highlight_color: Color = Color(1.0, 0.85, 0.2, 0.12)

## Border color for the target segment highlight.
@export var target_highlight_border_color: Color = Color(1.0, 0.85, 0.2, 0.4)

@export var picker_highlight_color: Color = Color(0.2, 0.7, 1.0, 0.25)
@export var picker_selected_color: Color = Color(0.2, 1.0, 0.4, 0.3)
@export var picker_border_color: Color = Color(0.2, 0.7, 1.0, 0.6)

## Speed of the shop lit-spot pulse animation.
@export var shop_pulse_speed: float = 2.5

## Minimum opacity of the shop lit-spot pulse.
@export var shop_pulse_min_alpha: float = 0.45

## Maximum opacity of the shop lit-spot pulse.
@export var shop_pulse_max_alpha: float = 0.85

## Border thickness for shop lit-spot outlines.
@export var shop_border_thickness: float = 2.5

# Shop lit-spot state
var _shop_spots: Array[Dictionary] = []
var _shop_active: bool = false
var _shop_pulse_time: float = 0.0

## Rarity colors for shop lit spots.
const SHOP_RARITY_COLORS: Dictionary = {
	ScoringEnums.Rarity.COMMON: Color(0.85, 0.85, 0.85, 0.8),
	ScoringEnums.Rarity.UNCOMMON: Color(0.3, 0.5, 1.0, 0.8),
	ScoringEnums.Rarity.RARE: Color(0.7, 0.3, 0.9, 0.8),
}

## Ring name to inner/outer normalized radii mapping for segment drawing.
const RING_BOUNDS: Dictionary = {
	"Inner Single": [RING_SINGLE_BULL_OUTER, RING_INNER_SINGLE_OUTER],
	"Triple": [RING_INNER_SINGLE_OUTER, RING_TRIPLE_OUTER],
	"Outer Single": [RING_TRIPLE_OUTER, RING_OUTER_SINGLE_OUTER],
	"Double": [RING_OUTER_SINGLE_OUTER, RING_DOUBLE_OUTER],
}


func _draw() -> void:
	# Draw surround ring (off-board area)
	draw_circle(Vector2.ZERO, board_radius * surround_outer_multiplier, surround_color)

	# Draw each wedge's rings from outermost to innermost
	for wedge_idx: int in range(20):
		var start_angle_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
		var end_angle_deg: float = start_angle_deg + WEDGE_ANGLE_DEG

		var single_color: Color
		var multi_color: Color
		if effective_wedge_colors.size() == 20:
			single_color = _segment_color_to_render(effective_wedge_colors[wedge_idx]["single"])
			multi_color = _segment_color_to_render(effective_wedge_colors[wedge_idx]["multi"])
		else:
			var is_even: bool = wedge_idx % 2 == 0
			single_color = wedge_a_single if is_even else wedge_b_single
			multi_color = wedge_a_multi if is_even else wedge_b_multi

		# Double ring
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER, multi_color)

		# Outer single
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_OUTER_SINGLE_OUTER, RING_TRIPLE_OUTER, single_color)

		# Triple ring
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_TRIPLE_OUTER, RING_INNER_SINGLE_OUTER, multi_color)

		# Inner single
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_INNER_SINGLE_OUTER, RING_SINGLE_BULL_OUTER, single_color)

	# Bullseyes drawn on top as filled circles
	draw_circle(Vector2.ZERO, board_radius * RING_SINGLE_BULL_OUTER, bull_single_color)
	draw_circle(Vector2.ZERO, board_radius * RING_DOUBLE_BULL_OUTER, bull_double_color)

	# Draw wire lines along ring boundaries
	_draw_ring_wire(RING_DOUBLE_BULL_OUTER)
	_draw_ring_wire(RING_SINGLE_BULL_OUTER)
	_draw_ring_wire(RING_INNER_SINGLE_OUTER)
	_draw_ring_wire(RING_TRIPLE_OUTER)
	_draw_ring_wire(RING_OUTER_SINGLE_OUTER)
	_draw_ring_wire(RING_DOUBLE_OUTER)

	# Draw wire lines along wedge boundaries
	for wedge_idx: int in range(20):
		var angle_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
		var angle_rad: float = deg_to_rad(angle_deg)
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		var inner_point: Vector2 = direction * board_radius * RING_SINGLE_BULL_OUTER
		var outer_point: Vector2 = direction * board_radius * RING_DOUBLE_OUTER
		draw_line(inner_point, outer_point, wire_color, wire_thickness)

	# Draw target segment highlight (declared target during throw)
	if not declared_target.is_empty():
		_draw_target_highlight()

	# Draw hover highlight on the segment under the mouse (if active)
	if _hover_active and _hover_ring_name != "":
		_draw_hover_segment()

	# Draw picker highlights for interactive wedge selection
	if picker_mode:
		_draw_picker_highlights()

	# Draw checkout pulse on valid finishing double segments
	if _checkout_pulse_active and _checkout_segments.size() > 0:
		_draw_checkout_pulses()

	# Draw shop lit spots
	if _shop_active and _shop_spots.size() > 0:
		_draw_shop_spots()

	# Draw wedge numbers around the board in the surround ring
	# Uses effective_wedge_values if available, so modified values are shown
	var font: Font = ThemeDB.fallback_font
	for wedge_idx: int in range(20):
		# Center angle of this wedge (no offset — wedge 0 is centered at 0° / 12 o'clock)
		var angle_deg: float = wedge_idx * WEDGE_ANGLE_DEG
		var angle_rad: float = deg_to_rad(angle_deg)
		# Position along that angle at the number radius
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		var pos: Vector2 = direction * board_radius * number_radius_multiplier

		# Look up effective value (may differ from original if modifiers applied)
		var effective_value: int = WEDGE_ORDER[wedge_idx]
		var is_modified: bool = false
		if effective_wedge_values.size() == 20:
			effective_value = effective_wedge_values[wedge_idx]
			is_modified = effective_value != WEDGE_ORDER[wedge_idx]

		var number_text: String = str(effective_value)
		# Calculate text offset for centering
		var text_width: float = font.get_string_size(number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, number_font_size).x
		var draw_pos: Vector2 = Vector2(pos.x - text_width / 2.0, pos.y + number_font_size / 2.0)

		# Color-code: modified values show in a highlight color, originals in default
		var text_color: Color = modified_number_color if is_modified else number_color
		draw_string(font, draw_pos, number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, number_font_size, text_color)

	# Draw flash overlay on the hit segment (if active)
	if _flash_alpha > 0.0:
		var flash_col: Color = Color(flash_color, _flash_alpha)
		_draw_flash_segment(flash_col)


## Trigger a flash on the segment at the given global hit position.
## Call this after scoring to highlight where the dart landed.
func flash_segment(global_hit_position: Vector2) -> void:
	var relative: Vector2 = global_hit_position - global_position
	var distance: float = relative.length()
	var normalized_distance: float = distance / board_radius

	# Determine which ring was hit
	if normalized_distance <= RING_DOUBLE_BULL_OUTER:
		_flash_ring_name = "double_bull"
	elif normalized_distance <= RING_SINGLE_BULL_OUTER:
		_flash_ring_name = "single_bull"
	elif normalized_distance <= RING_INNER_SINGLE_OUTER:
		_flash_ring_name = "inner_single"
	elif normalized_distance <= RING_TRIPLE_OUTER:
		_flash_ring_name = "triple"
	elif normalized_distance <= RING_OUTER_SINGLE_OUTER:
		_flash_ring_name = "outer_single"
	elif normalized_distance <= RING_DOUBLE_OUTER:
		_flash_ring_name = "double"
	else:
		# Off board — no flash
		_flash_ring_name = ""
		return

	# Determine which wedge index (not needed for bullseyes)
	if _flash_ring_name != "double_bull" and _flash_ring_name != "single_bull":
		var angle_rad: float = atan2(relative.x, -relative.y)
		var angle_deg: float = rad_to_deg(angle_rad)
		if angle_deg < 0.0:
			angle_deg += 360.0
		angle_deg = fmod(angle_deg - WEDGE_OFFSET_DEG, 360.0)
		if angle_deg < 0.0:
			angle_deg += 360.0
		_flash_wedge_idx = int(angle_deg / WEDGE_ANGLE_DEG) % 20

	# Animate the flash: start bright, tween alpha to 0
	_flash_alpha = flash_color.a
	var tween: Tween = create_tween()
	tween.tween_property(self, "_flash_alpha", 0.0, flash_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(queue_redraw)
	# Redraw every frame during the tween
	set_process(true)


func _process(delta: float) -> void:
	var needs_redraw: bool = false

	if _flash_alpha > 0.0:
		needs_redraw = true

	if _checkout_pulse_active:
		_checkout_pulse_time += delta
		needs_redraw = true

	if _shop_active:
		_shop_pulse_time += delta
		needs_redraw = true

	if needs_redraw:
		queue_redraw()
	elif not _checkout_pulse_active and not _shop_active:
		set_process(false)


## Draw the flash overlay for the currently flashing segment.
func _draw_flash_segment(color: Color) -> void:
	match _flash_ring_name:
		"double_bull":
			draw_circle(Vector2.ZERO, board_radius * RING_DOUBLE_BULL_OUTER, color)
		"single_bull":
			# Draw the single bull ring (donut shape) using the segment helper
			# Approximate as a full circle overlay for simplicity
			draw_circle(Vector2.ZERO, board_radius * RING_SINGLE_BULL_OUTER, color)
		"inner_single":
			var start_deg: float = _flash_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_INNER_SINGLE_OUTER, RING_SINGLE_BULL_OUTER, color)
		"triple":
			var start_deg: float = _flash_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_TRIPLE_OUTER, RING_INNER_SINGLE_OUTER, color)
		"outer_single":
			var start_deg: float = _flash_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_OUTER_SINGLE_OUTER, RING_TRIPLE_OUTER, color)
		"double":
			var start_deg: float = _flash_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER, color)


## Draw a single arc segment (wedge slice of a ring).
func _draw_segment(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float, color: Color) -> void:
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

	draw_colored_polygon(points, color)


## Draw a circular wire line at a given normalized radius.
func _draw_ring_wire(normalized_radius: float) -> void:
	var r: float = board_radius * normalized_radius
	var points: PackedVector2Array = PackedVector2Array()
	var num_points: int = 64
	for i: int in range(num_points + 1):
		var angle: float = TAU * float(i) / float(num_points)
		points.append(Vector2(cos(angle), sin(angle)) * r)
	draw_polyline(points, wire_color, wire_thickness)


## Calculate the score for a dart landing at the given global pixel position.
## Returns an enriched dictionary with: face_value, multiplier, total_score,
## ring_name, wedge_index, segment_color, is_bull.
## Uses effective_wedge_values for face value lookup if available.
## Uses effective_wedge_colors for segment color if available.
func calculate_score(global_hit_position: Vector2) -> Dictionary:
	# Convert to board-relative coordinates
	var relative: Vector2 = global_hit_position - global_position
	var distance: float = relative.length()
	var normalized_distance: float = distance / board_radius

	# Determine ring
	var ring_name: String = ""
	var multiplier: int = 0
	var face_value: int = 0
	var wedge_index: int = -1
	var segment_color: int = -1
	var is_bull: bool = false

	if normalized_distance <= RING_DOUBLE_BULL_OUTER:
		ring_name = "Double Bull"
		face_value = 25
		multiplier = 2
		is_bull = true
		segment_color = ScoringEnums.SegmentColor.RED
	elif normalized_distance <= RING_SINGLE_BULL_OUTER:
		ring_name = "Single Bull"
		face_value = 25
		multiplier = 1
		is_bull = true
		segment_color = ScoringEnums.SegmentColor.GREEN
	elif normalized_distance <= RING_INNER_SINGLE_OUTER:
		ring_name = "Inner Single"
		multiplier = 1
		wedge_index = _get_wedge_index(relative)
		face_value = _lookup_wedge_value(wedge_index)
		segment_color = _lookup_segment_color(wedge_index, false)
	elif normalized_distance <= RING_TRIPLE_OUTER:
		ring_name = "Triple"
		multiplier = 3
		wedge_index = _get_wedge_index(relative)
		face_value = _lookup_wedge_value(wedge_index)
		segment_color = _lookup_segment_color(wedge_index, true)
	elif normalized_distance <= RING_OUTER_SINGLE_OUTER:
		ring_name = "Outer Single"
		multiplier = 1
		wedge_index = _get_wedge_index(relative)
		face_value = _lookup_wedge_value(wedge_index)
		segment_color = _lookup_segment_color(wedge_index, false)
	elif normalized_distance <= RING_DOUBLE_OUTER:
		ring_name = "Double"
		multiplier = 2
		wedge_index = _get_wedge_index(relative)
		face_value = _lookup_wedge_value(wedge_index)
		segment_color = _lookup_segment_color(wedge_index, true)
	else:
		ring_name = "Off Board"
		face_value = 0
		multiplier = 0

	var total_score: int = face_value * multiplier
	return {
		"face_value": face_value,
		"multiplier": multiplier,
		"total_score": total_score,
		"ring_name": ring_name,
		"wedge_index": wedge_index,
		"segment_color": segment_color,
		"is_bull": is_bull,
	}


## Determine which wedge index (0-19) a board-relative position falls in.
## This is the physical position on the board, not the face value.
func _get_wedge_index(relative: Vector2) -> int:
	# atan2(x, -y) gives angle from 12 o'clock, clockwise positive
	var angle_rad: float = atan2(relative.x, -relative.y)
	var angle_deg: float = rad_to_deg(angle_rad)

	# Normalize to 0-360 range
	if angle_deg < 0.0:
		angle_deg += 360.0

	# Apply the 9-degree offset so wedge boundaries align
	angle_deg = fmod(angle_deg - WEDGE_OFFSET_DEG, 360.0)
	if angle_deg < 0.0:
		angle_deg += 360.0

	# Determine wedge index
	return int(angle_deg / WEDGE_ANGLE_DEG) % 20


## Look up the effective face value for a wedge index.
## Uses effective_wedge_values if populated, otherwise falls back to WEDGE_ORDER.
func _lookup_wedge_value(wedge_idx: int) -> int:
	if effective_wedge_values.size() == 20:
		return effective_wedge_values[wedge_idx]
	return WEDGE_ORDER[wedge_idx]


## Map a SegmentColor enum value to the actual render Color used for drawing.
func _segment_color_to_render(seg_color: ScoringEnums.SegmentColor) -> Color:
	match seg_color:
		ScoringEnums.SegmentColor.BLACK:
			return wedge_a_single
		ScoringEnums.SegmentColor.WHITE:
			return wedge_b_single
		ScoringEnums.SegmentColor.RED:
			return wedge_a_multi
		ScoringEnums.SegmentColor.GREEN:
			return wedge_b_multi
	return wedge_a_single


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


## Compute the global-space centroid of a board segment identified by wedge_index and ring_name.
## For bullseyes, returns the board center. For wedge segments, returns the midpoint
## of the arc segment (center angle of the wedge, midpoint radius of the ring).
func get_segment_centroid(wedge_index: int, ring_name: String) -> Vector2:
	if ring_name == "Double Bull" or ring_name == "double_bull":
		return global_position
	if ring_name == "Single Bull" or ring_name == "single_bull":
		return global_position

	# For wedge segments, compute center angle and midpoint radius
	var center_angle_deg: float = wedge_index * WEDGE_ANGLE_DEG
	var center_angle_rad: float = deg_to_rad(center_angle_deg)
	var direction: Vector2 = Vector2(sin(center_angle_rad), -cos(center_angle_rad))

	# Determine inner and outer normalized radius for this ring
	var inner_norm: float = 0.0
	var outer_norm: float = 0.0
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


## Set the declared target segment for visual highlighting.
func set_declared_target(target: Dictionary) -> void:
	declared_target = target
	queue_redraw()


## Clear the declared target highlight.
func clear_declared_target() -> void:
	declared_target = {}
	queue_redraw()


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


## Draw a subtle highlight on the currently hovered segment.
func _draw_hover_segment() -> void:
	match _hover_ring_name:
		"double_bull":
			draw_circle(Vector2.ZERO, board_radius * RING_DOUBLE_BULL_OUTER, hover_highlight_color)
			var points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
			draw_polyline(points, hover_border_color, hover_border_thickness)
		"single_bull":
			draw_circle(Vector2.ZERO, board_radius * RING_SINGLE_BULL_OUTER, hover_highlight_color)
			var outer_points: PackedVector2Array = _make_circle_points(RING_SINGLE_BULL_OUTER)
			draw_polyline(outer_points, hover_border_color, hover_border_thickness)
			var inner_points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
			draw_polyline(inner_points, hover_border_color, hover_border_thickness)
		"inner_single":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_INNER_SINGLE_OUTER, RING_SINGLE_BULL_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_INNER_SINGLE_OUTER, RING_SINGLE_BULL_OUTER, hover_border_color, hover_border_thickness)
		"triple":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_TRIPLE_OUTER, RING_INNER_SINGLE_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_TRIPLE_OUTER, RING_INNER_SINGLE_OUTER, hover_border_color, hover_border_thickness)
		"outer_single":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_OUTER_SINGLE_OUTER, RING_TRIPLE_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_OUTER_SINGLE_OUTER, RING_TRIPLE_OUTER, hover_border_color, hover_border_thickness)
		"double":
			var start_deg: float = _hover_wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment(start_deg, end_deg, RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER, hover_highlight_color)
			_draw_segment_border(start_deg, end_deg, RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER, hover_border_color, hover_border_thickness)


## Draw a highlight on the declared target segment.
func _draw_target_highlight() -> void:
	var ring_name: String = declared_target.get("ring_name", "")
	var is_bull: bool = declared_target.get("is_bull", false)
	var wedge_idx: int = declared_target.get("wedge_index", -1)

	if is_bull:
		if ring_name == "Double Bull":
			draw_circle(Vector2.ZERO, board_radius * RING_DOUBLE_BULL_OUTER, target_highlight_color)
			var points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
			draw_polyline(points, target_highlight_border_color, hover_border_thickness)
		elif ring_name == "Single Bull":
			draw_circle(Vector2.ZERO, board_radius * RING_SINGLE_BULL_OUTER, target_highlight_color)
			var outer_points: PackedVector2Array = _make_circle_points(RING_SINGLE_BULL_OUTER)
			draw_polyline(outer_points, target_highlight_border_color, hover_border_thickness)
			var inner_points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
			draw_polyline(inner_points, target_highlight_border_color, hover_border_thickness)
	elif wedge_idx >= 0:
		var start_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
		var end_deg: float = start_deg + WEDGE_ANGLE_DEG
		var inner_norm: float = 0.0
		var outer_norm: float = 0.0
		match ring_name:
			"Inner Single":
				inner_norm = RING_SINGLE_BULL_OUTER
				outer_norm = RING_INNER_SINGLE_OUTER
			"Triple":
				inner_norm = RING_INNER_SINGLE_OUTER
				outer_norm = RING_TRIPLE_OUTER
			"Outer Single":
				inner_norm = RING_TRIPLE_OUTER
				outer_norm = RING_OUTER_SINGLE_OUTER
			"Double":
				inner_norm = RING_OUTER_SINGLE_OUTER
				outer_norm = RING_DOUBLE_OUTER
		if outer_norm > 0.0:
			_draw_segment(start_deg, end_deg, outer_norm, inner_norm, target_highlight_color)
			_draw_segment_border(start_deg, end_deg, outer_norm, inner_norm, target_highlight_border_color, hover_border_thickness)


## Draw a border outline around a wedge segment.
## Used for hover highlighting and checkout pulse effects.
func _draw_segment_border(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float, color: Color, thickness: float) -> void:
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
	draw_polyline(points, color, thickness)


## Generate circle points for a border at a given normalized radius.
func _make_circle_points(normalized_radius: float) -> PackedVector2Array:
	var r: float = board_radius * normalized_radius
	var points: PackedVector2Array = PackedVector2Array()
	var num_points: int = 64
	for i: int in range(num_points + 1):
		var angle: float = TAU * float(i) / float(num_points)
		points.append(Vector2(cos(angle), sin(angle)) * r)
	return points


## Set which segments should pulse as valid checkouts.
func set_checkout_segments(segments: Array[Dictionary]) -> void:
	_checkout_segments = segments
	_checkout_pulse_active = segments.size() > 0
	if _checkout_pulse_active:
		set_process(true)
	queue_redraw()


## Clear all checkout highlights.
func clear_checkout_segments() -> void:
	_checkout_segments.clear()
	_checkout_pulse_active = false
	queue_redraw()


## Enable/disable picker mode for interactive wedge selection.
func set_picker_mode(enabled: bool) -> void:
	picker_mode = enabled
	_picker_hover_wedge = -1
	_picker_selected_wedges.clear()
	if enabled:
		hover_enabled = false
	queue_redraw()


## Get the wedge index at a global position, or -1 if off the wedge area.
func get_wedge_at_position(global_pos: Vector2) -> int:
	var relative: Vector2 = global_pos - global_position
	var distance: float = relative.length()
	var normalized: float = distance / board_radius
	if normalized > RING_DOUBLE_OUTER or normalized < RING_SINGLE_BULL_OUTER:
		return -1
	return _get_wedge_index(relative)


## Update picker hover and return the hovered wedge index.
func update_picker_hover(global_pos: Vector2) -> int:
	var wedge: int = get_wedge_at_position(global_pos)
	if wedge != _picker_hover_wedge:
		_picker_hover_wedge = wedge
		queue_redraw()
	return wedge


## Set which wedges are visually selected in picker mode.
func set_picker_selected(wedges: Array[int]) -> void:
	_picker_selected_wedges = wedges
	queue_redraw()


## Draw picker highlights — selected wedges and hovered wedge.
func _draw_picker_highlights() -> void:
	for wedge_idx: int in _picker_selected_wedges:
		_draw_full_wedge_highlight(wedge_idx, picker_selected_color, picker_border_color)
	if _picker_hover_wedge >= 0 and _picker_hover_wedge not in _picker_selected_wedges:
		_draw_full_wedge_highlight(_picker_hover_wedge, picker_highlight_color, picker_border_color)


## Draw a highlight overlay covering all rings of a single wedge.
func _draw_full_wedge_highlight(wedge_idx: int, fill_color: Color, border_col: Color) -> void:
	var start_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
	var end_deg: float = start_deg + WEDGE_ANGLE_DEG
	_draw_segment(start_deg, end_deg, RING_DOUBLE_OUTER, RING_SINGLE_BULL_OUTER, fill_color)
	_draw_segment_border(start_deg, end_deg, RING_DOUBLE_OUTER, RING_SINGLE_BULL_OUTER, border_col, hover_border_thickness)


## Draw pulsing border outlines on all valid checkout segments.
func _draw_checkout_pulses() -> void:
	var t: float = sin(_checkout_pulse_time * checkout_pulse_speed)
	var alpha: float = lerpf(checkout_pulse_min_alpha, checkout_pulse_max_alpha, (t + 1.0) / 2.0)
	var pulse_color: Color = Color(checkout_pulse_color, alpha)

	for segment: Dictionary in _checkout_segments:
		var segment_type: String = segment["type"]

		if segment_type == "double_bull":
			var points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
			draw_polyline(points, pulse_color, checkout_border_thickness)
		elif segment_type == "wedge":
			var wedge_idx: int = segment["wedge_idx"]
			var start_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
			var end_deg: float = start_deg + WEDGE_ANGLE_DEG
			_draw_segment_border(start_deg, end_deg, RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER, pulse_color, checkout_border_thickness)


## Set lit spots for the shop. Each entry: {wedge_index, ring_name, rarity, active}.
func set_shop_spots(spots: Array[Dictionary]) -> void:
	_shop_spots = spots
	_shop_active = spots.size() > 0
	_shop_pulse_time = 0.0
	if _shop_active:
		set_process(true)
	queue_redraw()


## Clear all shop lit spots.
func clear_shop_spots() -> void:
	_shop_spots.clear()
	_shop_active = false
	queue_redraw()


## Check if a hit position lands on an active shop spot.
## Returns the spot index if hit, or -1 if no active spot was hit.
func check_shop_hit(global_hit_position: Vector2) -> int:
	var result: Dictionary = calculate_score(global_hit_position)
	var ring_name: String = result.get("ring_name", "")
	var wedge_index: int = result.get("wedge_index", -1)

	for i: int in range(_shop_spots.size()):
		var spot: Dictionary = _shop_spots[i]
		if not spot.get("active", false):
			continue
		if spot["wedge_index"] == wedge_index and spot["ring_name"] == ring_name:
			return i

	return -1


## Deactivate a shop spot after it's been hit.
func deactivate_shop_spot(index: int) -> void:
	if index >= 0 and index < _shop_spots.size():
		_shop_spots[index]["active"] = false
		queue_redraw()


## Draw pulsing filled overlays on all active shop lit spots.
func _draw_shop_spots() -> void:
	var t: float = sin(_shop_pulse_time * shop_pulse_speed)
	var alpha: float = lerpf(shop_pulse_min_alpha, shop_pulse_max_alpha, (t + 1.0) / 2.0)

	for spot: Dictionary in _shop_spots:
		if not spot.get("active", false):
			continue

		var rarity: int = spot.get("rarity", ScoringEnums.Rarity.COMMON)
		var base_color: Color = SHOP_RARITY_COLORS.get(rarity, SHOP_RARITY_COLORS[ScoringEnums.Rarity.COMMON])
		var fill_color: Color = Color(base_color.r, base_color.g, base_color.b, alpha)
		var border_color: Color = Color(base_color.r, base_color.g, base_color.b, minf(alpha + 0.3, 1.0))

		var ring_name: String = spot["ring_name"]
		var wedge_idx: int = spot["wedge_index"]

		if not RING_BOUNDS.has(ring_name):
			continue

		var bounds: Array = RING_BOUNDS[ring_name]
		var inner_norm: float = bounds[0]
		var outer_norm: float = bounds[1]
		var start_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
		var end_deg: float = start_deg + WEDGE_ANGLE_DEG

		_draw_segment(start_deg, end_deg, outer_norm, inner_norm, fill_color)
		_draw_segment_border(start_deg, end_deg, outer_norm, inner_norm, border_color, shop_border_thickness)
