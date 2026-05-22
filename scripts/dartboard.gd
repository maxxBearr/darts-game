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

@export_group("Tutorial Highlights")

## Fill color for tutorial-highlighted segments. Bright yellow to distinguish from other highlights.
@export var tutorial_highlight_color: Color = Color(1.0, 0.85, 0.2, 0.4)

## Border color for tutorial-highlighted segments.
@export var tutorial_highlight_border_color: Color = Color(1.0, 1.0, 1.0, 0.7)

## Border thickness for tutorial highlight outlines in pixels.
@export var tutorial_highlight_thickness: float = 2.5

@export_group("Shop Spots — Shader")

## How fast the swirl pattern flows across lit spots.
@export_range(0.1, 3.0, 0.05) var shop_swirl_speed: float = 0.6

## Scale of the noise pattern — lower = larger swirls, higher = finer detail.
@export_range(1.0, 30.0, 0.5) var shop_noise_scale: float = 8.0

## How much domain warping distorts the pattern (more = swirly-er).
@export_range(0.0, 2.0, 0.05) var shop_distortion: float = 0.8

## How much brightness varies across the swirl pattern.
@export_range(0.0, 1.0, 0.05) var shop_contrast: float = 0.5

## Extra glow intensity at bright spots in the pattern.
@export_range(0.0, 2.0, 0.1) var shop_glow_strength: float = 0.8

@export_group("Shop Spots — Colors")

## Fill color for common lit spots.
@export var shop_color_common: Color = Color(0.95, 0.88, 0.65, 0.8)

## Fill color for uncommon lit spots.
@export var shop_color_uncommon: Color = Color(0.3, 0.5, 1.0, 0.8)

## Fill color for rare lit spots.
@export var shop_color_rare: Color = Color(0.7, 0.3, 0.9, 0.8)

## Base fill opacity for lit spot segments (before shader processing).
@export_range(0.3, 1.0, 0.05) var shop_fill_alpha: float = 0.7

## Border opacity for lit spot outlines.
@export_range(0.3, 1.0, 0.05) var shop_border_alpha: float = 0.9

## Border thickness for shop lit-spot outlines.
@export var shop_border_thickness: float = 2.5

@export_group("")

# Tutorial highlight state — segments to highlight during rules slideshow
var _tutorial_highlights: Array[Dictionary] = []
var _tutorial_highlight_active: bool = false

# Shop lit-spot state
var _shop_spots: Array[Dictionary] = []
var _shop_active: bool = false

## Ring name to inner/outer normalized radii mapping for segment drawing.
const RING_BOUNDS: Dictionary = {
	"Inner Single": [RING_SINGLE_BULL_OUTER, RING_INNER_SINGLE_OUTER],
	"Triple": [RING_INNER_SINGLE_OUTER, RING_TRIPLE_OUTER],
	"Outer Single": [RING_TRIPLE_OUTER, RING_OUTER_SINGLE_OUTER],
	"Double": [RING_OUTER_SINGLE_OUTER, RING_DOUBLE_OUTER],
}

## Child node for shop spot rendering — lets a shader apply to just the spots.
var _shop_overlay: Node2D


func _ready() -> void:
	_shop_overlay = Node2D.new()
	_shop_overlay.draw.connect(_draw_shop_overlay)
	var shader: Shader = load("res://shaders/shop_spot.gdshader")
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	_sync_shop_shader(mat)
	_shop_overlay.material = mat
	add_child(_shop_overlay)


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

	# Draw tutorial highlights (rules slideshow / tutorial callouts)
	if _tutorial_highlight_active:
		_draw_tutorial_highlights()

	# Shop spots are drawn on the overlay child (shader handles animation)

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

	if needs_redraw:
		queue_redraw()
	elif not _checkout_pulse_active:
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


# ── Tutorial highlight API ──────────────────────────────────────────────────

## Set tutorial highlight segments. Each entry specifies a highlight type:
## {type: "all_wedges_ring", ring_name: "Triple"} — highlight that ring on every wedge.
## {type: "single_wedge_all", wedge_index: 0} — highlight every ring of a single wedge.
## {type: "single_segment", wedge_index: 0, ring_name: "Triple"} — highlight one segment.
## {type: "bullseye", which: "inner"|"outer"|"both"} — highlight bullseye region(s).
func set_tutorial_highlight(highlights: Array[Dictionary]) -> void:
	_tutorial_highlights = highlights
	_tutorial_highlight_active = highlights.size() > 0
	queue_redraw()


## Clear all tutorial highlights.
func clear_tutorial_highlight() -> void:
	_tutorial_highlights.clear()
	_tutorial_highlight_active = false
	queue_redraw()


## Draw all active tutorial highlights.
func _draw_tutorial_highlights() -> void:
	for spec: Dictionary in _tutorial_highlights:
		var highlight_type: String = spec.get("type", "")
		match highlight_type:
			"all_wedges_ring":
				var ring_name: String = spec.get("ring_name", "")
				if RING_BOUNDS.has(ring_name):
					var bounds: Array = RING_BOUNDS[ring_name]
					for wedge_idx: int in range(20):
						var start_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
						var end_deg: float = start_deg + WEDGE_ANGLE_DEG
						_draw_segment(start_deg, end_deg, bounds[1], bounds[0], tutorial_highlight_color)
						_draw_segment_border(start_deg, end_deg, bounds[1], bounds[0], tutorial_highlight_border_color, tutorial_highlight_thickness)

			"single_wedge_all":
				var wedge_idx: int = spec.get("wedge_index", 0)
				_draw_full_wedge_highlight(wedge_idx, tutorial_highlight_color, tutorial_highlight_border_color)

			"single_segment":
				var wedge_idx: int = spec.get("wedge_index", 0)
				var ring_name: String = spec.get("ring_name", "")
				if RING_BOUNDS.has(ring_name):
					var bounds: Array = RING_BOUNDS[ring_name]
					var start_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
					var end_deg: float = start_deg + WEDGE_ANGLE_DEG
					_draw_segment(start_deg, end_deg, bounds[1], bounds[0], tutorial_highlight_color)
					_draw_segment_border(start_deg, end_deg, bounds[1], bounds[0], tutorial_highlight_border_color, tutorial_highlight_thickness)

			"bullseye":
				var which: String = spec.get("which", "both")
				if which == "inner" or which == "both":
					draw_circle(Vector2.ZERO, board_radius * RING_DOUBLE_BULL_OUTER, tutorial_highlight_color)
					var inner_points: PackedVector2Array = _make_circle_points(RING_DOUBLE_BULL_OUTER)
					draw_polyline(inner_points, tutorial_highlight_border_color, tutorial_highlight_thickness)
				if which == "outer" or which == "both":
					draw_circle(Vector2.ZERO, board_radius * RING_SINGLE_BULL_OUTER, tutorial_highlight_color)
					var outer_points: PackedVector2Array = _make_circle_points(RING_SINGLE_BULL_OUTER)
					draw_polyline(outer_points, tutorial_highlight_border_color, tutorial_highlight_thickness)


## Push exported shader values into the ShaderMaterial.
func _sync_shop_shader(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("board_radius", board_radius)
	mat.set_shader_parameter("speed", shop_swirl_speed)
	mat.set_shader_parameter("noise_scale", shop_noise_scale)
	mat.set_shader_parameter("distortion", shop_distortion)
	mat.set_shader_parameter("contrast", shop_contrast)
	mat.set_shader_parameter("glow_strength", shop_glow_strength)


## Look up the exported rarity color for a shop spot.
func _get_shop_rarity_color(rarity: int) -> Color:
	match rarity:
		ScoringEnums.Rarity.UNCOMMON:
			return shop_color_uncommon
		ScoringEnums.Rarity.RARE:
			return shop_color_rare
		_:
			return shop_color_common


## Set lit spots for the shop. Each entry: {wedge_index, ring_name, rarity, active}.
func set_shop_spots(spots: Array[Dictionary]) -> void:
	_shop_spots = spots
	_shop_active = spots.size() > 0
	# Re-sync shader params in case exports were tweaked in the inspector
	if _shop_overlay.material is ShaderMaterial:
		_sync_shop_shader(_shop_overlay.material as ShaderMaterial)
	_shop_overlay.queue_redraw()
	queue_redraw()


## Clear all shop lit spots.
func clear_shop_spots() -> void:
	_shop_spots.clear()
	_shop_active = false
	_shop_overlay.queue_redraw()
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
		_shop_overlay.queue_redraw()


## Draw shop spot segments on the overlay child (shader applies to this geometry).
func _draw_shop_overlay() -> void:
	for spot: Dictionary in _shop_spots:
		if not spot.get("active", false):
			continue

		var rarity: int = spot.get("rarity", ScoringEnums.Rarity.COMMON)
		var base_color: Color = _get_shop_rarity_color(rarity)
		var fill_color: Color = Color(base_color.r, base_color.g, base_color.b, shop_fill_alpha)
		var border_color: Color = Color(base_color.r, base_color.g, base_color.b, shop_border_alpha)

		var ring_name: String = spot["ring_name"]
		var wedge_idx: int = spot["wedge_index"]

		if not RING_BOUNDS.has(ring_name):
			continue

		var bounds: Array = RING_BOUNDS[ring_name]
		var inner_norm: float = bounds[0]
		var outer_norm: float = bounds[1]
		var start_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
		var end_deg: float = start_deg + WEDGE_ANGLE_DEG

		# Build segment polygon and draw on the overlay
		var points: PackedVector2Array = _build_segment_points(start_deg, end_deg, outer_norm, inner_norm)
		_shop_overlay.draw_colored_polygon(points, fill_color)

		# Border
		var border_points: PackedVector2Array = _build_segment_border_points(start_deg, end_deg, outer_norm, inner_norm)
		_shop_overlay.draw_polyline(border_points, border_color, shop_border_thickness)


## Build a segment polygon (same geometry as _draw_segment but returns points).
func _build_segment_points(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_r: float = board_radius * outer_norm
	var inner_r: float = board_radius * inner_norm

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * outer_r)

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * inner_r)

	return points


## Build a segment border polyline (closed loop).
func _build_segment_border_points(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_r: float = board_radius * outer_norm
	var inner_r: float = board_radius * inner_norm

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * outer_r)

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * inner_r)

	points.append(points[0])
	return points
