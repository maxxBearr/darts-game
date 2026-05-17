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


func _draw() -> void:
	# Draw surround ring (off-board area)
	draw_circle(Vector2.ZERO, board_radius * surround_outer_multiplier, surround_color)

	# Draw each wedge's rings from outermost to innermost
	for wedge_idx: int in range(20):
		var start_angle_deg: float = wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG
		var end_angle_deg: float = start_angle_deg + WEDGE_ANGLE_DEG
		var is_even: bool = wedge_idx % 2 == 0

		# Double ring
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_DOUBLE_OUTER, RING_OUTER_SINGLE_OUTER,
			wedge_a_multi if is_even else wedge_b_multi)

		# Outer single
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_OUTER_SINGLE_OUTER, RING_TRIPLE_OUTER,
			wedge_a_single if is_even else wedge_b_single)

		# Triple ring
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_TRIPLE_OUTER, RING_INNER_SINGLE_OUTER,
			wedge_a_multi if is_even else wedge_b_multi)

		# Inner single
		_draw_segment(start_angle_deg, end_angle_deg,
			RING_INNER_SINGLE_OUTER, RING_SINGLE_BULL_OUTER,
			wedge_a_single if is_even else wedge_b_single)

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
## Returns a dictionary with: face_value, multiplier, total_score, ring_name.
func calculate_score(global_hit_position: Vector2) -> Dictionary:
	# Convert to board-relative coordinates
	var relative: Vector2 = global_hit_position - global_position
	var distance: float = relative.length()
	var normalized_distance: float = distance / board_radius

	# Determine ring
	var ring_name: String = ""
	var multiplier: int = 0
	var face_value: int = 0

	if normalized_distance <= RING_DOUBLE_BULL_OUTER:
		ring_name = "Double Bull"
		face_value = 25
		multiplier = 2
	elif normalized_distance <= RING_SINGLE_BULL_OUTER:
		ring_name = "Single Bull"
		face_value = 25
		multiplier = 1
	elif normalized_distance <= RING_INNER_SINGLE_OUTER:
		ring_name = "Single"
		multiplier = 1
		face_value = _get_wedge_value(relative)
	elif normalized_distance <= RING_TRIPLE_OUTER:
		ring_name = "Triple"
		multiplier = 3
		face_value = _get_wedge_value(relative)
	elif normalized_distance <= RING_OUTER_SINGLE_OUTER:
		ring_name = "Single"
		multiplier = 1
		face_value = _get_wedge_value(relative)
	elif normalized_distance <= RING_DOUBLE_OUTER:
		ring_name = "Double"
		multiplier = 2
		face_value = _get_wedge_value(relative)
	else:
		ring_name = "Off Board"
		face_value = 0
		multiplier = 0

	var total_score: int = face_value * multiplier
	return {
		"face_value": face_value,
		"multiplier": multiplier,
		"total_score": total_score,
		"ring_name": ring_name
	}


## Determine which wedge number a relative position falls in.
func _get_wedge_value(relative: Vector2) -> int:
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
	var wedge_idx: int = int(angle_deg / WEDGE_ANGLE_DEG) % 20
	return WEDGE_ORDER[wedge_idx]
