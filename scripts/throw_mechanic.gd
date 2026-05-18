extends Node2D
## Four-stage throw mechanic: aim line (horizontal), vertical window positioning,
## vertical release, then horizontal release. Emits throw_completed with the final
## pixel position when all stages are done.

signal throw_completed(hit_position: Vector2)
signal state_changed(new_state: ThrowState)

enum ThrowState { IDLE, AIMING, POSITIONING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, RESOLVING, DONE }

## Controls horizontal range of the aim line. Higher = tighter range.
## 1 = worst (line half-width equals max_aim_half_width).
## 100 = best (line half-width equals min_aim_half_width).
## Typical gameplay range: 30 to 80.
@export var horizontal_range: float = 20.0

## Maximum aim line half-width in pixels (at horizontal_range = 1). The worst possible spread.
@export var max_aim_half_width: float = 200.0

## Minimum aim line half-width in pixels (at horizontal_range = 100). The tightest possible spread.
@export var min_aim_half_width: float = 5.0

## Controls vertical range of the positioning window. Higher = tighter range.
## 1 = almost no shrinkage (window stays near full height).
## 100 = shrinks to nearly zero height (extremely tight).
## Typical gameplay range: 30 to 70.
@export var vertical_range: float = 20.0

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
@export var max_horizontal_accuracy_half: float = 80.0

## Minimum horizontal variance half-width in pixels (at horizontal_accuracy = 100).
@export var min_horizontal_accuracy_half: float = 5.0

## Controls horizontal marker bounce speed. Higher = slower = easier to time.
## Range ~1.0 (hard) to 5.0 (easy).
@export var horizontal_speed: float = 1.5

## Vertical accuracy skew in pixels. Set by DartBuild based on balance.
## Positive = dart lands lower, Negative = dart lands higher.
var accuracy_skew_v: float = 0.0

## Semi-transparent color of the aim line band.
@export var aim_line_color: Color = Color(0.2, 0.5, 1.0, 0.3)

## Color of the vertical window segment during positioning.
@export var window_color: Color = Color(0.2, 0.8, 0.4, 0.3)

## Color of the vertical window border/outline.
@export var window_border_color: Color = Color(0.2, 0.8, 0.4, 0.7)

## Speed at which the player can move the window up/down (pixels per second).
@export var window_move_speed: float = 300.0

## Duration of the shrink tween in seconds.
@export var shrink_tween_duration: float = 0.4

## Color of the marker circle (shared by vertical and horizontal markers).
@export var marker_color: Color = Color(1.0, 0.3, 0.3, 0.9)

## Size (radius) of the marker circle in pixels (shared by both markers).
@export var marker_size: float = 8.0

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
## At 0.4, roughly 95% of throws land in the inner 80% of the variance box.
@export_range(0.2, 0.6, 0.01) var gaussian_spread: float = 0.4

# Internal state
var _state: ThrowState = ThrowState.IDLE
var _board_center: Vector2 = Vector2.ZERO
var _board_radius: float = 300.0
var _aim_x: float = 0.0
var _locked_aim_x: float = 0.0
var _release_y: float = 0.0
var _bounce_t: float = 0.0

# Locked Y after vertical release
var _locked_release_y: float = 0.0

# Horizontal release state
var _horizontal_x: float = 0.0
var _horizontal_bounce_t: float = 0.0

# Full line bounds (recorded when entering POSITIONING)
var _full_line_top: float = 0.0
var _full_line_bottom: float = 0.0
var _full_line_height: float = 0.0

# Vertical window state
var _window_top: float = 0.0
var _window_bottom: float = 0.0
var _window_height: float = 0.0
var _window_center_y: float = 0.0
var _is_shrink_complete: bool = false

# Animated skew — tweens from 0.0 to accuracy_skew_v during resolve preview
var _current_skew_offset: float = 0.0


func _ready() -> void:
	set_process(false)


## Start a new throw. Call this to begin the aiming phase.
func start_throw(board_center: Vector2, board_radius: float) -> void:
	_board_center = board_center
	_board_radius = board_radius
	_aim_x = _board_center.x
	_state = ThrowState.AIMING
	_bounce_t = 0.0
	_horizontal_bounce_t = 0.0
	_is_shrink_complete = false
	set_process(true)
	state_changed.emit(ThrowState.AIMING)
	queue_redraw()


## Returns the current throw state.
func get_throw_state() -> ThrowState:
	return _state


## Compute the actual aim line half-width in pixels from the horizontal_range stat (1–100).
func _get_aim_half_width() -> float:
	var normalized: float = clampf((horizontal_range - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_aim_half_width, min_aim_half_width, normalized)


## Compute the vertical accuracy half-height in pixels (1–100 stat).
func _get_vertical_accuracy_half() -> float:
	var normalized: float = clampf((vertical_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_vertical_accuracy_half, min_vertical_accuracy_half, normalized)


## Compute the horizontal accuracy half-width in pixels (1–100 stat).
func _get_horizontal_accuracy_half() -> float:
	var normalized: float = clampf((horizontal_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_horizontal_accuracy_half, min_horizontal_accuracy_half, normalized)


## Compute the vertical marker bounce speed from vertical_speed stat.
func _get_vertical_bounce_speed() -> float:
	return (6.0 - clampf(vertical_speed, 1.0, 5.0)) * 2.5


## Compute the horizontal marker bounce speed from horizontal_speed stat.
func _get_horizontal_bounce_speed() -> float:
	return (6.0 - clampf(horizontal_speed, 1.0, 5.0)) * 2.5


func _process(delta: float) -> void:
	match _state:
		ThrowState.AIMING:
			# Aim line follows horizontal mouse position
			_aim_x = get_global_mouse_position().x
			queue_redraw()

		ThrowState.POSITIONING:
			# Handle keyboard input for moving the window up/down (W/S or Up/Down)
			if _is_shrink_complete:
				if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
					_window_center_y -= window_move_speed * delta
				if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
					_window_center_y += window_move_speed * delta

				# Clamp so window stays within original full line bounds
				var half_height: float = _window_height / 2.0
				_window_center_y = clampf(_window_center_y,
					_full_line_top + half_height,
					_full_line_bottom - half_height)

				# Update window edges from center
				_window_top = _window_center_y - half_height
				_window_bottom = _window_center_y + half_height
			queue_redraw()

		ThrowState.VERTICAL_RELEASE:
			# Marker bounces vertically within the locked window
			var bounce_speed: float = _get_vertical_bounce_speed()
			_bounce_t += delta * bounce_speed
			_release_y = _window_center_y + sin(_bounce_t) * (_window_height / 2.0)
			queue_redraw()

		ThrowState.HORIZONTAL_RELEASE:
			# Marker bounces horizontally across the aim band width
			var bounce_speed: float = _get_horizontal_bounce_speed()
			_horizontal_bounce_t += delta * bounce_speed
			var aim_half_w: float = _get_aim_half_width()
			_horizontal_x = _locked_aim_x + sin(_horizontal_bounce_t) * aim_half_w
			queue_redraw()

		ThrowState.RESOLVING:
			queue_redraw()

		ThrowState.DONE:
			set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			match _state:
				ThrowState.AIMING:
					_locked_aim_x = _aim_x
					_state = ThrowState.POSITIONING
					get_viewport().set_input_as_handled()
					_enter_positioning()
				ThrowState.VERTICAL_RELEASE:
					# Lock vertical position, transition to horizontal release
					_locked_release_y = _release_y
					_state = ThrowState.HORIZONTAL_RELEASE
					_horizontal_bounce_t = 0.0
					_horizontal_x = _locked_aim_x
					get_viewport().set_input_as_handled()
					state_changed.emit(ThrowState.HORIZONTAL_RELEASE)
					queue_redraw()
				ThrowState.HORIZONTAL_RELEASE:
					# Freeze horizontal and enter resolve preview
					get_viewport().set_input_as_handled()
					_enter_resolving()

	# Handle Enter/Space key presses for all states
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_SPACE):
			match _state:
				ThrowState.AIMING:
					_locked_aim_x = _aim_x
					_state = ThrowState.POSITIONING
					get_viewport().set_input_as_handled()
					_enter_positioning()
				ThrowState.POSITIONING:
					if _is_shrink_complete:
						# Lock window and transition to VERTICAL_RELEASE
						_state = ThrowState.VERTICAL_RELEASE
						_bounce_t = 0.0
						_release_y = _window_center_y
						get_viewport().set_input_as_handled()
						state_changed.emit(ThrowState.VERTICAL_RELEASE)
						queue_redraw()
				ThrowState.VERTICAL_RELEASE:
					# Lock vertical position, transition to horizontal release
					_locked_release_y = _release_y
					_state = ThrowState.HORIZONTAL_RELEASE
					_horizontal_bounce_t = 0.0
					_horizontal_x = _locked_aim_x
					get_viewport().set_input_as_handled()
					state_changed.emit(ThrowState.HORIZONTAL_RELEASE)
					queue_redraw()
				ThrowState.HORIZONTAL_RELEASE:
					# Freeze horizontal and enter resolve preview
					get_viewport().set_input_as_handled()
					_enter_resolving()


## Set up the POSITIONING state: record bounds, calculate target height, start shrink tween.
func _enter_positioning() -> void:
	# Record the full line bounds
	_full_line_top = _board_center.y - _board_radius
	_full_line_bottom = _board_center.y + _board_radius
	_full_line_height = _full_line_bottom - _full_line_top

	# Calculate target window height based on vertical_range (1–100 → normalized fraction)
	var vertical_fraction: float = clampf((vertical_range - 1.0) / 99.0, 0.0, 1.0)
	_window_height = _full_line_height * (1.0 - vertical_fraction)
	_window_height = maxf(_window_height, 20.0)

	# Start with full line bounds (pre-tween)
	_window_top = _full_line_top
	_window_bottom = _full_line_bottom
	_window_center_y = _board_center.y
	_is_shrink_complete = false

	# Start the shrink tween: animate window edges inward to target height
	var target_top: float = _board_center.y - _window_height / 2.0
	var target_bottom: float = _board_center.y + _window_height / 2.0

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "_window_top", target_top, shrink_tween_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_window_bottom", target_bottom, shrink_tween_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(false)
	tween.tween_callback(_on_shrink_complete)

	# Emit state change signal
	state_changed.emit(ThrowState.POSITIONING)


## Called when the shrink tween finishes.
func _on_shrink_complete() -> void:
	_is_shrink_complete = true
	_window_top = _window_center_y - _window_height / 2.0
	_window_bottom = _window_center_y + _window_height / 2.0


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


## Resolve the final dart position using Gaussian-weighted variance zones.
## Darts are most likely to land near the aimed position, with probability
## falling off toward the edges of the variance box.
func _resolve_throw() -> void:
	# Horizontal: Gaussian-weighted within horizontal consistency zone
	var h_half: float = _get_horizontal_accuracy_half()
	var horizontal_offset: float = clampf(
		randfn(0.0, h_half * gaussian_spread),
		-h_half,
		h_half
	)
	var final_x: float = _horizontal_x + horizontal_offset

	# Vertical: Gaussian-weighted within vertical consistency zone
	var v_half: float = _get_vertical_accuracy_half()
	var vertical_offset: float = clampf(
		randfn(0.0, v_half * gaussian_spread),
		-v_half,
		v_half
	)
	var final_y: float = _locked_release_y + vertical_offset + accuracy_skew_v

	var hit_position: Vector2 = Vector2(final_x, final_y)
	queue_redraw()
	throw_completed.emit(hit_position)


func _draw() -> void:
	match _state:
		ThrowState.AIMING:
			# Draw the semi-transparent aim band
			var top: float = _board_center.y - _board_radius
			var bottom: float = _board_center.y + _board_radius
			var half_w: float = _get_aim_half_width()
			var rect: Rect2 = Rect2(
				Vector2(_aim_x - half_w, top) - global_position,
				Vector2(half_w * 2.0, bottom - top)
			)
			draw_rect(rect, aim_line_color)
			# Draw center line
			var center_top: Vector2 = Vector2(_aim_x, top) - global_position
			var center_bottom: Vector2 = Vector2(_aim_x, bottom) - global_position
			draw_line(center_top, center_bottom, Color(0.2, 0.5, 1.0, 0.7), 2.0)

		ThrowState.POSITIONING:
			_draw_positioning()

		ThrowState.VERTICAL_RELEASE:
			_draw_vertical_release()

		ThrowState.HORIZONTAL_RELEASE:
			_draw_horizontal_release()

		ThrowState.RESOLVING:
			_draw_resolving()


## Draw the POSITIONING state: dimmed aim band + highlighted vertical window.
func _draw_positioning() -> void:
	var top: float = _board_center.y - _board_radius
	var bottom: float = _board_center.y + _board_radius
	var half_w: float = _get_aim_half_width()
	var band_left: float = _locked_aim_x - half_w
	var band_width: float = half_w * 2.0

	# Draw the full dimmed aim band (background)
	var full_rect: Rect2 = Rect2(
		Vector2(band_left, top) - global_position,
		Vector2(band_width, bottom - top)
	)
	draw_rect(full_rect, Color(aim_line_color, 0.15))

	# Draw the vertical window (highlighted active zone)
	var window_rect: Rect2 = Rect2(
		Vector2(band_left, _window_top) - global_position,
		Vector2(band_width, _window_bottom - _window_top)
	)
	draw_rect(window_rect, window_color)
	draw_rect(window_rect, window_border_color, false, 2.0)


## Draw the VERTICAL_RELEASE state: dimmed band + window + bouncing marker with glow strip.
func _draw_vertical_release() -> void:
	var top: float = _board_center.y - _board_radius
	var bottom: float = _board_center.y + _board_radius
	var half_w: float = _get_aim_half_width()
	var band_left: float = _locked_aim_x - half_w
	var band_width: float = half_w * 2.0

	# Dimmed aim band background
	var full_rect: Rect2 = Rect2(
		Vector2(band_left, top) - global_position,
		Vector2(band_width, bottom - top)
	)
	draw_rect(full_rect, Color(aim_line_color, 0.15))

	# Locked window outline
	var window_rect: Rect2 = Rect2(
		Vector2(band_left, _window_top) - global_position,
		Vector2(band_width, _window_bottom - _window_top)
	)
	draw_rect(window_rect, window_color)
	draw_rect(window_rect, window_border_color, false, 2.0)

	# Vertical consistency glow strip around the marker, clipped to window bounds
	var v_half: float = _get_vertical_accuracy_half()
	var glow_top: float = maxf(_release_y - v_half, _window_top)
	var glow_bottom: float = minf(_release_y + v_half, _window_bottom)
	var glow_rect: Rect2 = Rect2(
		Vector2(band_left, glow_top) - global_position,
		Vector2(band_width, glow_bottom - glow_top)
	)
	draw_rect(glow_rect, vertical_glow_color)

	# Bouncing marker dot
	var marker_pos: Vector2 = Vector2(_locked_aim_x, _release_y) - global_position
	draw_circle(marker_pos, marker_size, marker_color)


## Draw the HORIZONTAL_RELEASE state: locked vertical strip + bouncing horizontal marker.
func _draw_horizontal_release() -> void:
	var top: float = _board_center.y - _board_radius
	var bottom: float = _board_center.y + _board_radius
	var half_w: float = _get_aim_half_width()
	var band_left: float = _locked_aim_x - half_w
	var band_width: float = half_w * 2.0

	# Dimmed aim band background
	var full_rect: Rect2 = Rect2(
		Vector2(band_left, top) - global_position,
		Vector2(band_width, bottom - top)
	)
	draw_rect(full_rect, Color(aim_line_color, 0.15))

	# Locked window outline (dimmed)
	var window_rect: Rect2 = Rect2(
		Vector2(band_left, _window_top) - global_position,
		Vector2(band_width, _window_bottom - _window_top)
	)
	draw_rect(window_rect, Color(window_color, 0.15))
	draw_rect(window_rect, Color(window_border_color, 0.3), false, 1.5)

	# Static vertical consistency strip at locked release position (no skew yet)
	var v_half: float = _get_vertical_accuracy_half()
	var strip_top: float = maxf(_locked_release_y - v_half, _window_top)
	var strip_bottom: float = minf(_locked_release_y + v_half, _window_bottom)
	var strip_rect: Rect2 = Rect2(
		Vector2(band_left, strip_top) - global_position,
		Vector2(band_width, strip_bottom - strip_top)
	)
	draw_rect(strip_rect, vertical_glow_color)

	# Horizontal consistency glow: vertical band at _horizontal_x, clipped to aim band
	var h_half: float = _get_horizontal_accuracy_half()
	var glow_left: float = maxf(_horizontal_x - h_half, band_left)
	var glow_right: float = minf(_horizontal_x + h_half, band_left + band_width)
	var glow_rect: Rect2 = Rect2(
		Vector2(glow_left, strip_top) - global_position,
		Vector2(glow_right - glow_left, strip_bottom - strip_top)
	)
	draw_rect(glow_rect, horizontal_glow_color)

	# Bouncing marker dot at the intersection
	var marker_pos: Vector2 = Vector2(_horizontal_x, _locked_release_y) - global_position
	draw_circle(marker_pos, marker_size, marker_color)


## Draw the RESOLVING state: final variance box + frozen marker.
func _draw_resolving() -> void:
	var top: float = _board_center.y - _board_radius
	var bottom: float = _board_center.y + _board_radius
	var half_w: float = _get_aim_half_width()
	var band_left: float = _locked_aim_x - half_w
	var band_width: float = half_w * 2.0

	# Dimmed aim band background
	var full_rect: Rect2 = Rect2(
		Vector2(band_left, top) - global_position,
		Vector2(band_width, bottom - top)
	)
	draw_rect(full_rect, Color(aim_line_color, 0.15))

	# Locked window outline (dimmed)
	var window_rect: Rect2 = Rect2(
		Vector2(band_left, _window_top) - global_position,
		Vector2(band_width, _window_bottom - _window_top)
	)
	draw_rect(window_rect, Color(window_color, 0.15))
	draw_rect(window_rect, Color(window_border_color, 0.3), false, 1.5)

	# Final variance box — drifts by _current_skew_offset (animated during resolve)
	var h_half: float = _get_horizontal_accuracy_half()
	var v_half: float = _get_vertical_accuracy_half()
	var skewed_center_y: float = _locked_release_y + _current_skew_offset
	var box_left: float = maxf(_horizontal_x - h_half, band_left)
	var box_right: float = minf(_horizontal_x + h_half, band_left + band_width)
	var box_top: float = maxf(skewed_center_y - v_half, _window_top)
	var box_bottom: float = minf(skewed_center_y + v_half, _window_bottom)
	var preview_rect: Rect2 = Rect2(
		Vector2(box_left, box_top) - global_position,
		Vector2(box_right - box_left, box_bottom - box_top)
	)
	draw_rect(preview_rect, resolve_preview_color)

	# Frozen marker dot — drifts with the skew
	var marker_pos: Vector2 = Vector2(_horizontal_x, skewed_center_y) - global_position
	draw_circle(marker_pos, marker_size, marker_color)
