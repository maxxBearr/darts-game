extends Node2D
## Three-stage ellipse-based throw mechanic: place aim ellipse, vertical release,
## then horizontal release. Emits throw_completed with the final pixel position
## when all stages are done.

signal throw_completed(hit_position: Vector2)
signal state_changed(new_state: ThrowState)

enum ThrowState { IDLE, AIMING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, RESOLVING, DONE }

## Controls horizontal range of the aim ellipse. Higher = tighter range.
## 1 = worst (half-width equals max_aim_half_width).
## 100 = best (half-width equals min_aim_half_width).
## Typical gameplay range: 30 to 80.
@export var horizontal_range: float = 8.0

## Maximum aim ellipse half-width in pixels (at horizontal_range = 1). The worst possible horizontal spread.
@export var max_aim_half_width: float = 270.0

## Minimum aim ellipse half-width in pixels (at horizontal_range = 100). The tightest possible horizontal spread.
@export var min_aim_half_width: float = 8.0

## Controls vertical range of the aim ellipse. Higher = tighter range.
## 1 = worst (half-height equals max_aim_half_height).
## 100 = best (half-height equals min_aim_half_height).
## Typical gameplay range: 30 to 70.
@export var vertical_range: float = 5.0

## Maximum aim ellipse half-height in pixels (at vertical_range = 1). The worst possible vertical spread.
@export var max_aim_half_height: float = 270.0

## Minimum aim ellipse half-height in pixels (at vertical_range = 100). The tightest possible vertical spread.
@export var min_aim_half_height: float = 5.0

## Controls vertical marker bounce speed. Higher = slower = easier to time.
## Range ~1.0 (hard) to 5.0 (easy).
@export var vertical_speed: float = 1.5

## Controls vertical accuracy of the release. Higher = more accurate = tighter glow zone.
## 1 = worst (half-height equals max_vertical_accuracy_half).
## 100 = best (half-height equals min_vertical_accuracy_half).
## Typical gameplay range: 30 to 80.
@export var vertical_accuracy: float = 25.0

## Maximum vertical variance half-height in pixels (at vertical_accuracy = 1).
@export var max_vertical_accuracy_half: float = 90.0

## Minimum vertical variance half-height in pixels (at vertical_accuracy = 100).
@export var min_vertical_accuracy_half: float = 5.0

## Controls horizontal accuracy of the final dart landing. Higher = more accurate = tighter zone.
## 1 = worst (half-width equals max_horizontal_accuracy_half).
## 100 = best (half-width equals min_horizontal_accuracy_half).
@export var horizontal_accuracy: float = 25.0

## Maximum horizontal variance half-width in pixels (at horizontal_accuracy = 1).
@export var max_horizontal_accuracy_half: float = 90.0

## Minimum horizontal variance half-width in pixels (at horizontal_accuracy = 100).
@export var min_horizontal_accuracy_half: float = 5.0

## Controls horizontal marker bounce speed. Higher = slower = easier to time.
## Range ~1.0 (hard) to 5.0 (easy).
@export var horizontal_speed: float = 1.5

## Vertical accuracy skew in pixels. Set by DartBuild based on balance.
## Positive = dart lands lower, Negative = dart lands higher.
var accuracy_skew_v: float = 0.0

## Semi-transparent color of the aim ellipse fill.
@export var aim_line_color: Color = Color(0.2, 0.5, 1.0, 0.3)

## Speed at which WASD moves the aim ellipse during AIMING (pixels per second).
@export var window_move_speed: float = 300.0

## Color of the marker circle (shared by vertical and horizontal markers).
@export var marker_color: Color = Color(1.0, 0.3, 0.3, 0.9)

## Size (radius) of the marker circle in pixels (shared by both markers).
@export var marker_size: float = 8.0

## Color of the marker outline ring for visibility against busy backgrounds.
@export var marker_outline_color: Color = Color(1.0, 1.0, 1.0, 0.9)

## Thickness of the marker outline ring in pixels. Set to 0 to disable.
@export var marker_outline_thickness: float = 2.0

## Color of the vertical release glow zone.
@export var vertical_glow_color: Color = Color(1.0, 0.3, 0.3, 0.15)

## Color of the horizontal release glow zone.
@export var horizontal_glow_color: Color = Color(0.3, 0.5, 1.0, 0.15)

## Duration in seconds the resolve preview is shown before the dart lands.
@export var resolve_preview_duration: float = 0.5

## Color of the resolve preview zone showing where the dart could land.
@export var resolve_preview_color: Color = Color(1.0, 0.9, 0.2, 0.25)

## Controls how tightly the Gaussian distribution clusters toward the aim point.
## Lower values = tighter clustering near center (more skill-rewarding).
## Higher values = wider spread (more RNG).
## At 0.4, roughly 95% of throws land in the inner 80% of the accuracy ellipse.
@export_range(0.2, 0.6, 0.01) var gaussian_spread: float = 0.4

## Normalized distance threshold for the green (bonus) zone.
## At or below this distance, the player gets an accuracy bonus.
@export_range(0.0, 0.5, 0.01) var green_zone_threshold: float = 0.25

## Normalized distance threshold where the penalty zone begins.
## Between green_threshold and this value is the neutral zone (no change).
@export_range(0.3, 0.8, 0.01) var penalty_zone_threshold: float = 0.6

## Accuracy multiplier at the center of the green zone (best case).
## Values < 1.0 mean the accuracy zone shrinks (tighter grouping).
@export_range(0.5, 1.0, 0.01) var green_zone_multiplier: float = 0.75

## Accuracy multiplier at the ellipse edge (worst case).
## Values > 1.0 mean the accuracy zone bloats (wider scatter).
@export_range(1.5, 4.0, 0.1) var max_edge_penalty_multiplier: float = 2.5

## Color of the accuracy zone when in the green (bonus) zone.
@export var accuracy_green_color: Color = Color(0.2, 0.85, 0.3, 0.25)

## Color of the accuracy zone in the neutral zone (no bonus or penalty).
@export var accuracy_neutral_color: Color = Color(1.0, 0.9, 0.2, 0.25)

## Color of the accuracy zone when in the red (penalty) zone.
@export var accuracy_red_color: Color = Color(0.9, 0.2, 0.15, 0.25)

# Internal state
var _state: ThrowState = ThrowState.IDLE
var _board_center: Vector2 = Vector2.ZERO
var _board_radius: float = 300.0
var _release_y: float = 0.0
var _bounce_t: float = 0.0

# Locked Y after vertical release
var _locked_release_y: float = 0.0

# Horizontal release state
var _horizontal_x: float = 0.0
var _horizontal_bounce_t: float = 0.0

# Animated skew — tweens from 0.0 to accuracy_skew_v during resolve preview
var _current_skew_offset: float = 0.0

## The board segment the player declared as their target when placing the aim zone.
var _declared_target: Dictionary = {}

## The centroid (center point) of the declared target segment in global coordinates.
var _target_centroid: Vector2 = Vector2.ZERO

## The effective half-width for the horizontal meter at the locked Y position.
var _h_meter_half_width: float = 0.0

## Reference to the dartboard node, set by main.gd.
var dartboard: Node2D = null

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

# Track last mouse position to detect mouse movement
var _last_mouse_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	set_process(false)


## Start a new throw. Call this to begin the aiming phase.
func start_throw(board_center: Vector2, board_radius: float) -> void:
	_board_center = board_center
	_board_radius = board_radius
	_aim_center = _board_center
	_mouse_controls_aim = true
	_last_mouse_pos = get_global_mouse_position()
	_state = ThrowState.AIMING
	_bounce_t = 0.0
	_horizontal_bounce_t = 0.0
	set_process(true)
	state_changed.emit(ThrowState.AIMING)
	queue_redraw()


## Returns the current throw state.
func get_throw_state() -> ThrowState:
	return _state


## Compute the aim ellipse half-width in pixels from the horizontal_range stat (1-100).
func _get_aim_half_width() -> float:
	var normalized: float = clampf((horizontal_range - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_aim_half_width, min_aim_half_width, normalized)


## Compute the aim ellipse half-height in pixels from the vertical_range stat (1-100).
func _get_aim_half_height() -> float:
	var normalized: float = clampf((vertical_range - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_aim_half_height, min_aim_half_height, normalized)


## Compute the vertical accuracy half-height in pixels (1-100 stat).
func _get_vertical_accuracy_half() -> float:
	var normalized: float = clampf((vertical_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_vertical_accuracy_half, min_vertical_accuracy_half, normalized)


## Compute the horizontal accuracy half-width in pixels (1-100 stat).
func _get_horizontal_accuracy_half() -> float:
	var normalized: float = clampf((horizontal_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_horizontal_accuracy_half, min_horizontal_accuracy_half, normalized)


## Compute the vertical marker bounce speed from vertical_speed stat.
func _get_vertical_bounce_speed() -> float:
	return (6.0 - clampf(vertical_speed, 1.0, 5.0)) * 2.5


## Compute the horizontal marker bounce speed from horizontal_speed stat.
func _get_horizontal_bounce_speed() -> float:
	return (6.0 - clampf(horizontal_speed, 1.0, 5.0)) * 2.5


## Compute the ellipse half-width at a given Y position.
## Returns 0.0 if y is outside the ellipse's vertical extent.
func _get_ellipse_half_width_at_y(y: float) -> float:
	var dy: float = (y - _placed_center.y) / _aim_half_height
	if absf(dy) >= 1.0:
		return 0.0
	return _aim_half_width * sqrt(1.0 - dy * dy)


## Compute normalized distance from an arbitrary point to the target centroid,
## scaled relative to the aim ellipse size.
func _get_target_distance_normalized_at(pos: Vector2) -> float:
	if _declared_target.is_empty():
		return 0.5
	var dx: float = pos.x - _target_centroid.x
	var dy: float = pos.y - _target_centroid.y
	var norm_x: float = dx / _aim_half_width if _aim_half_width > 0.0 else 0.0
	var norm_y: float = dy / _aim_half_height if _aim_half_height > 0.0 else 0.0
	return sqrt(norm_x * norm_x + norm_y * norm_y)


## Compute normalized distance from the locked marker position to the target centroid.
func _get_target_distance_normalized() -> float:
	return _get_target_distance_normalized_at(Vector2(_horizontal_x, _locked_release_y))


## Compute the accuracy zone multiplier based on distance from target centroid.
## Returns < 1.0 in green zone (bonus), 1.0 in neutral, > 1.0 in penalty zone.
func _get_accuracy_multiplier(normalized_distance: float) -> float:
	if normalized_distance <= green_zone_threshold:
		var t: float = normalized_distance / green_zone_threshold if green_zone_threshold > 0.0 else 0.0
		return lerpf(green_zone_multiplier, 1.0, t)
	elif normalized_distance <= penalty_zone_threshold:
		return 1.0
	else:
		var t: float = (normalized_distance - penalty_zone_threshold) / (1.0 - penalty_zone_threshold)
		t = clampf(t, 0.0, 1.0)
		return lerpf(1.0, max_edge_penalty_multiplier, t)


## Get the accuracy zone color based on the current accuracy multiplier.
func _get_accuracy_zone_color(accuracy_multiplier: float) -> Color:
	if accuracy_multiplier <= 1.0:
		var t: float = (accuracy_multiplier - green_zone_multiplier) / (1.0 - green_zone_multiplier)
		t = clampf(t, 0.0, 1.0)
		return accuracy_green_color.lerp(accuracy_neutral_color, t)
	else:
		var t: float = (accuracy_multiplier - 1.0) / (max_edge_penalty_multiplier - 1.0)
		t = clampf(t, 0.0, 1.0)
		return accuracy_neutral_color.lerp(accuracy_red_color, t)


## Clamp aim center so it stays within the board circle (ellipse may overhang).
func _clamp_aim_to_board() -> void:
	_aim_center.x = clampf(_aim_center.x,
		_board_center.x - _board_radius,
		_board_center.x + _board_radius)
	_aim_center.y = clampf(_aim_center.y,
		_board_center.y - _board_radius,
		_board_center.y + _board_radius)


func _process(delta: float) -> void:
	match _state:
		ThrowState.AIMING:
			# Check for mouse movement — if mouse moved, reclaim mouse control
			var current_mouse: Vector2 = get_global_mouse_position()
			if current_mouse.distance_to(_last_mouse_pos) > 1.0:
				_mouse_controls_aim = true
			_last_mouse_pos = current_mouse

			if _mouse_controls_aim:
				# Ellipse center tracks mouse position
				_aim_center = current_mouse
			else:
				# WASD / arrow key movement
				var move_dir: Vector2 = Vector2.ZERO
				if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
					move_dir.x -= 1.0
				if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
					move_dir.x += 1.0
				if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
					move_dir.y -= 1.0
				if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
					move_dir.y += 1.0
				if move_dir != Vector2.ZERO:
					_aim_center += move_dir.normalized() * window_move_speed * delta

			_clamp_aim_to_board()
			queue_redraw()

		ThrowState.VERTICAL_RELEASE:
			# Marker bounces vertically across the full height of the placed ellipse
			var bounce_speed: float = _get_vertical_bounce_speed()
			_bounce_t += delta * bounce_speed
			_release_y = _placed_center.y + sin(_bounce_t) * _aim_half_height
			queue_redraw()

		ThrowState.HORIZONTAL_RELEASE:
			# Marker bounces horizontally across the ellipse width at locked Y
			var bounce_speed: float = _get_horizontal_bounce_speed()
			_horizontal_bounce_t += delta * bounce_speed
			_horizontal_x = _placed_center.x + sin(_horizontal_bounce_t) * _h_meter_half_width
			queue_redraw()

		ThrowState.RESOLVING:
			queue_redraw()

		ThrowState.DONE:
			set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	# Detect WASD/arrow presses to switch away from mouse control
	if _state == ThrowState.AIMING and event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed:
			if key.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
				_mouse_controls_aim = false

	# Handle mouse click for all applicable states
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			match _state:
				ThrowState.AIMING:
					_place_aim_ellipse()
					get_viewport().set_input_as_handled()
				ThrowState.VERTICAL_RELEASE:
					_lock_vertical()
					get_viewport().set_input_as_handled()
				ThrowState.HORIZONTAL_RELEASE:
					get_viewport().set_input_as_handled()
					_enter_resolving()

	# Handle Enter/Space key presses for all states
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_SPACE):
			match _state:
				ThrowState.AIMING:
					_place_aim_ellipse()
					get_viewport().set_input_as_handled()
				ThrowState.VERTICAL_RELEASE:
					_lock_vertical()
					get_viewport().set_input_as_handled()
				ThrowState.HORIZONTAL_RELEASE:
					get_viewport().set_input_as_handled()
					_enter_resolving()


## Lock the aim ellipse in place and transition to VERTICAL_RELEASE.
func _place_aim_ellipse() -> void:
	_placed_center = _aim_center
	_aim_half_width = _get_aim_half_width()
	_aim_half_height = _get_aim_half_height()
	_bounce_t = 0.0
	_release_y = _placed_center.y

	# Declare target segment based on where the player placed the ellipse
	if dartboard != null:
		var target_result: Dictionary = dartboard.calculate_score(_placed_center)
		if target_result["ring_name"] == "Off Board":
			_declared_target = {}
			_target_centroid = _placed_center
		else:
			_declared_target = target_result
			_target_centroid = dartboard.get_segment_centroid(
				target_result["wedge_index"], target_result["ring_name"])
	else:
		_declared_target = {}
		_target_centroid = _placed_center

	_state = ThrowState.VERTICAL_RELEASE
	state_changed.emit(ThrowState.VERTICAL_RELEASE)
	queue_redraw()


## Lock the vertical position and transition to HORIZONTAL_RELEASE.
func _lock_vertical() -> void:
	_locked_release_y = _release_y
	_h_meter_half_width = _get_ellipse_half_width_at_y(_locked_release_y)
	_state = ThrowState.HORIZONTAL_RELEASE
	_horizontal_bounce_t = 0.0
	_horizontal_x = _placed_center.x
	state_changed.emit(ThrowState.HORIZONTAL_RELEASE)
	queue_redraw()


## Transition to RESOLVING: freeze the marker, show landing zone preview, start timer.
func _enter_resolving() -> void:
	_state = ThrowState.RESOLVING
	state_changed.emit(ThrowState.RESOLVING)

	_current_skew_offset = 0.0
	if absf(accuracy_skew_v) > 0.1:
		var tween: Tween = create_tween()
		tween.tween_property(self, "_current_skew_offset", accuracy_skew_v, resolve_preview_duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_callback(_on_resolve_timer_finished)
	else:
		get_tree().create_timer(resolve_preview_duration).timeout.connect(_on_resolve_timer_finished)

	set_process(true)
	queue_redraw()


## Called when the resolve preview timer expires — land the dart.
func _on_resolve_timer_finished() -> void:
	_state = ThrowState.DONE
	_resolve_throw()


## Resolve the final dart position using Gaussian sampling with ellipse rejection.
func _resolve_throw() -> void:
	# Apply accuracy scaling based on distance from target centroid
	var dist: float = _get_target_distance_normalized()
	var accuracy_mult: float = _get_accuracy_multiplier(dist)
	var h_half: float = _get_horizontal_accuracy_half() * accuracy_mult
	var v_half: float = _get_vertical_accuracy_half() * accuracy_mult
	var center_x: float = _horizontal_x
	var center_y: float = _locked_release_y + accuracy_skew_v

	# Gaussian sample with ellipse rejection
	var offset_x: float = 0.0
	var offset_y: float = 0.0
	for i: int in range(20):
		offset_x = randfn(0.0, h_half * gaussian_spread)
		offset_y = randfn(0.0, v_half * gaussian_spread)
		# Check if point is inside the accuracy ellipse
		var ellipse_check: float = (offset_x * offset_x) / (h_half * h_half) + (offset_y * offset_y) / (v_half * v_half)
		if ellipse_check <= 1.0:
			break

	var hit_position: Vector2 = Vector2(center_x + offset_x, center_y + offset_y)
	queue_redraw()
	throw_completed.emit(hit_position)


# ── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	match _state:
		ThrowState.AIMING:
			_draw_aiming()
		ThrowState.VERTICAL_RELEASE:
			_draw_vertical_release()
		ThrowState.HORIZONTAL_RELEASE:
			_draw_horizontal_release()
		ThrowState.RESOLVING:
			_draw_resolving()


## Draw a filled ellipse centered at `center` (local coords) with given semi-axes and color.
func _draw_filled_ellipse(center: Vector2, half_w: float, half_h: float, color: Color, segments: int = 64) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * half_w, sin(angle) * half_h))
	draw_colored_polygon(points, color)


## Draw an ellipse outline centered at `center` (local coords).
func _draw_ellipse_outline(center: Vector2, half_w: float, half_h: float, color: Color, width: float = 2.0, segments: int = 64) -> void:
	for i: int in range(segments):
		var angle_a: float = TAU * float(i) / float(segments)
		var angle_b: float = TAU * float(i + 1) / float(segments)
		var point_a: Vector2 = center + Vector2(cos(angle_a) * half_w, sin(angle_a) * half_h)
		var point_b: Vector2 = center + Vector2(cos(angle_b) * half_w, sin(angle_b) * half_h)
		draw_line(point_a, point_b, color, width)


## Draw a horizontal band (y_min to y_max) clipped to the aim ellipse.
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


## Draw a vertical band (x_min to x_max) clipped to the aim ellipse.
func _draw_v_band_clipped(center: Vector2, half_w: float, half_h: float, x_min: float, x_max: float, color: Color, segments: int = 32) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	# Clamp band to ellipse horizontal extent
	x_min = maxf(x_min, center.x - half_w)
	x_max = minf(x_max, center.x + half_w)
	if x_min >= x_max:
		return
	# Bottom edge: left to right
	for i: int in range(segments + 1):
		var x: float = x_min + (x_max - x_min) * float(i) / float(segments)
		var dx: float = (x - center.x) / half_w
		var y_extent: float = half_h * sqrt(maxf(1.0 - dx * dx, 0.0))
		points.append(Vector2(x, center.y + y_extent))
	# Top edge: right to left
	for i: int in range(segments, -1, -1):
		var x: float = x_min + (x_max - x_min) * float(i) / float(segments)
		var dx: float = (x - center.x) / half_w
		var y_extent: float = half_h * sqrt(maxf(1.0 - dx * dx, 0.0))
		points.append(Vector2(x, center.y - y_extent))
	draw_colored_polygon(points, color)


## Draw the intersection of a horizontal band and vertical band clipped to the ellipse.
func _draw_band_intersection(center: Vector2, half_w: float, half_h: float, y_min: float, y_max: float, x_min: float, x_max: float, color: Color, segments: int = 32) -> void:
	# Clamp bands to ellipse extents
	y_min = maxf(y_min, center.y - half_h)
	y_max = minf(y_max, center.y + half_h)
	x_min = maxf(x_min, center.x - half_w)
	x_max = minf(x_max, center.x + half_w)
	if y_min >= y_max or x_min >= x_max:
		return
	# Build polygon: for each y, the x range is intersection of [x_min, x_max] with ellipse width at y
	var points: PackedVector2Array = PackedVector2Array()
	# Right edge: top to bottom
	for i: int in range(segments + 1):
		var y: float = y_min + (y_max - y_min) * float(i) / float(segments)
		var dy: float = (y - center.y) / half_h
		var ellipse_x: float = half_w * sqrt(maxf(1.0 - dy * dy, 0.0))
		var right: float = minf(x_max, center.x + ellipse_x)
		points.append(Vector2(right, y))
	# Left edge: bottom to top
	for i: int in range(segments, -1, -1):
		var y: float = y_min + (y_max - y_min) * float(i) / float(segments)
		var dy: float = (y - center.y) / half_h
		var ellipse_x: float = half_w * sqrt(maxf(1.0 - dy * dy, 0.0))
		var left: float = maxf(x_min, center.x - ellipse_x)
		points.append(Vector2(left, y))
	if points.size() >= 3:
		draw_colored_polygon(points, color)


## Draw a small crosshair at the given position (local coords).
func _draw_crosshair(pos: Vector2, color: Color, size: float = 6.0, width: float = 1.5) -> void:
	draw_line(pos + Vector2(-size, 0), pos + Vector2(size, 0), color, width)
	draw_line(pos + Vector2(0, -size), pos + Vector2(0, size), color, width)


## Draw the bouncing marker dot with optional outline ring for visibility.
func _draw_marker(pos: Vector2) -> void:
	if marker_outline_thickness > 0.0:
		draw_arc(pos, marker_size + marker_outline_thickness * 0.5, 0.0, TAU, 64, marker_outline_color, marker_outline_thickness)
	draw_circle(pos, marker_size, marker_color)


## Draw the AIMING state: filled ellipse following cursor with crosshair.
func _draw_aiming() -> void:
	var half_w: float = _get_aim_half_width()
	var half_h: float = _get_aim_half_height()
	var center: Vector2 = _aim_center - global_position

	# Filled semi-transparent ellipse
	_draw_filled_ellipse(center, half_w, half_h, aim_line_color)
	# Ellipse outline (slightly more opaque)
	_draw_ellipse_outline(center, half_w, half_h, Color(aim_line_color, minf(aim_line_color.a + 0.3, 1.0)))
	# Crosshair at center
	_draw_crosshair(center, Color(0.2, 0.5, 1.0, 0.7))


## Draw the VERTICAL_RELEASE state: dimmed ellipse + ghost preview + vertical accuracy band + bouncing marker.
func _draw_vertical_release() -> void:
	var center: Vector2 = _placed_center - global_position

	# Dimmed placed ellipse outline
	_draw_ellipse_outline(center, _aim_half_width, _aim_half_height, Color(aim_line_color, 0.2), 1.5)

	# Ghost accuracy preview at current marker position
	var preview_pos: Vector2 = Vector2(_placed_center.x, _release_y)
	var ghost_dist: float = _get_target_distance_normalized_at(preview_pos)
	var ghost_mult: float = _get_accuracy_multiplier(ghost_dist)
	var ghost_h_half: float = _get_horizontal_accuracy_half() * ghost_mult
	var ghost_v_half: float = _get_vertical_accuracy_half() * ghost_mult
	var ghost_color: Color = _get_accuracy_zone_color(ghost_mult)
	ghost_color.a *= 0.5
	var ghost_local: Vector2 = preview_pos - global_position
	_draw_filled_ellipse(ghost_local, ghost_h_half, ghost_v_half, ghost_color)
	_draw_ellipse_outline(ghost_local, ghost_h_half, ghost_v_half,
		Color(ghost_color, ghost_color.a * 2.0), 1.5)

	# Vertical accuracy glow band clipped to ellipse
	var v_half: float = _get_vertical_accuracy_half()
	var glow_y_min: float = _release_y - global_position.y - v_half
	var glow_y_max: float = _release_y - global_position.y + v_half
	_draw_h_band_clipped(center, _aim_half_width, _aim_half_height, glow_y_min, glow_y_max, vertical_glow_color)

	# Bouncing marker dot
	var marker_pos: Vector2 = Vector2(_placed_center.x, _release_y) - global_position
	_draw_marker(marker_pos)


## Draw the HORIZONTAL_RELEASE state: dimmed ellipse + ghost preview + locked V band + H band + intersection + marker.
func _draw_horizontal_release() -> void:
	var center: Vector2 = _placed_center - global_position

	# Dimmed placed ellipse outline
	_draw_ellipse_outline(center, _aim_half_width, _aim_half_height, Color(aim_line_color, 0.2), 1.5)

	# Ghost accuracy preview at current marker position
	var preview_pos: Vector2 = Vector2(_horizontal_x, _locked_release_y)
	var ghost_dist: float = _get_target_distance_normalized_at(preview_pos)
	var ghost_mult: float = _get_accuracy_multiplier(ghost_dist)
	var ghost_h_half: float = _get_horizontal_accuracy_half() * ghost_mult
	var ghost_v_half: float = _get_vertical_accuracy_half() * ghost_mult
	var ghost_color: Color = _get_accuracy_zone_color(ghost_mult)
	ghost_color.a *= 0.5
	var ghost_local: Vector2 = preview_pos - global_position
	_draw_filled_ellipse(ghost_local, ghost_h_half, ghost_v_half, ghost_color)
	_draw_ellipse_outline(ghost_local, ghost_h_half, ghost_v_half,
		Color(ghost_color, ghost_color.a * 2.0), 1.5)

	# Locked vertical accuracy band (dimmed, from V release)
	var v_half: float = _get_vertical_accuracy_half()
	var v_y_min: float = _locked_release_y - global_position.y - v_half
	var v_y_max: float = _locked_release_y - global_position.y + v_half
	_draw_h_band_clipped(center, _aim_half_width, _aim_half_height, v_y_min, v_y_max, Color(vertical_glow_color, vertical_glow_color.a * 0.5))

	# Horizontal accuracy glow band clipped to ellipse
	var h_half: float = _get_horizontal_accuracy_half()
	var h_x_min: float = _horizontal_x - global_position.x - h_half
	var h_x_max: float = _horizontal_x - global_position.x + h_half
	_draw_v_band_clipped(center, _aim_half_width, _aim_half_height, h_x_min, h_x_max, horizontal_glow_color)

	# Intersection region highlighted
	_draw_band_intersection(center, _aim_half_width, _aim_half_height, v_y_min, v_y_max, h_x_min, h_x_max, resolve_preview_color)

	# Bouncing marker dot at intersection with locked Y
	var marker_pos: Vector2 = Vector2(_horizontal_x, _locked_release_y) - global_position
	_draw_marker(marker_pos)


## Draw the RESOLVING state: dimmed ellipse + accuracy-scaled ellipse with color feedback + frozen marker.
func _draw_resolving() -> void:
	var center: Vector2 = _placed_center - global_position

	# Dimmed placed ellipse outline
	_draw_ellipse_outline(center, _aim_half_width, _aim_half_height, Color(aim_line_color, 0.2), 1.5)

	# Accuracy ellipse at the locked point with skew offset, scaled by target distance
	var dist: float = _get_target_distance_normalized()
	var accuracy_mult: float = _get_accuracy_multiplier(dist)
	var h_half: float = _get_horizontal_accuracy_half() * accuracy_mult
	var v_half: float = _get_vertical_accuracy_half() * accuracy_mult
	var zone_color: Color = _get_accuracy_zone_color(accuracy_mult)
	var skewed_center: Vector2 = Vector2(_horizontal_x, _locked_release_y + _current_skew_offset) - global_position

	_draw_filled_ellipse(skewed_center, h_half, v_half, zone_color)
	_draw_ellipse_outline(skewed_center, h_half, v_half, Color(zone_color, minf(zone_color.a + 0.3, 1.0)), 1.5)

	# Frozen marker dot at accuracy ellipse center
	_draw_marker(skewed_center)
