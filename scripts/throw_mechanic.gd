extends Node2D
## Two-stage throw mechanic: aim line (horizontal), vertical window positioning,
## then release marker (vertical). Emits throw_completed with the final pixel
## position when all stages are done.

signal throw_completed(hit_position: Vector2)
signal state_changed(new_state: ThrowState)

enum ThrowState { IDLE, AIMING, POSITIONING, RELEASING, RESOLVING, DONE }

## Controls horizontal accuracy of the aim line. Higher = more accurate = thinner line.
## 1 = worst (line half-width equals max_aim_half_width).
## 100 = best (line half-width equals min_aim_half_width).
## Typical gameplay range: 30 to 80.
@export var aim_accuracy: float = 20.0

## Maximum aim line half-width in pixels (at aim_accuracy = 0.0). The worst possible spread.
@export var max_aim_half_width: float = 200.0

## Minimum aim line half-width in pixels (at aim_accuracy = 1.0). The tightest possible spread.
@export var min_aim_half_width: float = 5.0

## Controls how much the vertical window shrinks after aiming.
## Higher value = more shrinkage = tighter window = more accurate.
## Represents the percentage of the full line that gets removed.
## 1 = almost no shrinkage (window stays near full height).
## 100 = shrinks to nearly zero height (extremely tight).
## Typical gameplay range: 30 to 70.
@export var vertical_accuracy: float = 10.0

## Controls marker bounce speed. Higher = slower = easier to time. Range ~1.0 (hard) to 5.0 (easy).
@export var release_speed: float = 3.0

## Controls vertical accuracy of the release. Higher = more accurate = tighter glow zone.
## 1 = worst (glow half-height equals max_release_half_height).
## 100 = best (glow half-height equals min_release_half_height).
## Typical gameplay range: 30 to 80.
@export var release_accuracy: float = 50.0

## Maximum release glow zone half-height in pixels (at release_accuracy = 0.0). The worst vertical spread.
@export var max_release_half_height: float = 60.0

## Minimum release glow zone half-height in pixels (at release_accuracy = 1.0). The tightest vertical spread.
@export var min_release_half_height: float = 5.0

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

## Color of the release marker circle.
@export var release_marker_color: Color = Color(1.0, 0.3, 0.3, 0.9)

## Size (radius) of the release marker in pixels.
@export var release_marker_size: float = 8.0

## Color of the vertical variance glow zone.
@export var glow_zone_color: Color = Color(1.0, 0.3, 0.3, 0.15)

## Duration in seconds the resolve preview is shown before the dart lands.
@export var resolve_preview_duration: float = 0.5

## Color of the resolve preview zone showing where the dart could land.
@export var resolve_preview_color: Color = Color(1.0, 0.9, 0.2, 0.25)

# Internal state
var _state: ThrowState = ThrowState.IDLE
var _board_center: Vector2 = Vector2.ZERO
var _board_radius: float = 300.0
var _aim_x: float = 0.0
var _locked_aim_x: float = 0.0
var _release_y: float = 0.0
var _bounce_direction: float = 1.0
var _bounce_t: float = 0.0

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


func _ready() -> void:
	set_process(false)


## Start a new throw. Call this to begin the aiming phase.
func start_throw(board_center: Vector2, board_radius: float) -> void:
	_board_center = board_center
	_board_radius = board_radius
	_aim_x = _board_center.x
	_state = ThrowState.AIMING
	_bounce_t = 0.0
	_bounce_direction = 1.0
	_is_shrink_complete = false
	set_process(true)
	queue_redraw()


## Returns the current throw state.
func get_throw_state() -> ThrowState:
	return _state


## Compute the actual aim line half-width in pixels from the aim_accuracy stat (1–100).
## Higher aim_accuracy → smaller half-width → more accurate.
func _get_aim_half_width() -> float:
	var normalized: float = clampf((aim_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_aim_half_width, min_aim_half_width, normalized)


## Compute the actual release glow zone half-height in pixels from the release_accuracy stat (1–100).
## Higher release_accuracy → smaller half-height → more accurate.
func _get_release_half_height() -> float:
	var normalized: float = clampf((release_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_release_half_height, min_release_half_height, normalized)


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

		ThrowState.RELEASING:
			# Marker bounces up and down within the locked window only
			# Higher release_speed stat means slower (easier) bouncing
			var bounce_speed: float = (6.0 - clampf(release_speed, 1.0, 5.0)) * 2.5
			_bounce_t += delta * bounce_speed
			# Bounce within window bounds using sine wave
			_release_y = _window_center_y + sin(_bounce_t) * (_window_height / 2.0)
			queue_redraw()

		ThrowState.DONE:
			set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			match _state:
				ThrowState.AIMING:
					# Lock the aim line and transition to POSITIONING
					_locked_aim_x = _aim_x
					_state = ThrowState.POSITIONING
					get_viewport().set_input_as_handled()
					_enter_positioning()
				ThrowState.RELEASING:
					# Freeze the marker and enter resolve preview
					get_viewport().set_input_as_handled()
					_enter_resolving()

	# Handle Enter/Space key presses for all states
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_SPACE):
			match _state:
				ThrowState.AIMING:
					# Lock the aim line and transition to POSITIONING
					_locked_aim_x = _aim_x
					_state = ThrowState.POSITIONING
					get_viewport().set_input_as_handled()
					_enter_positioning()
				ThrowState.POSITIONING:
					if _is_shrink_complete:
						# Lock window and transition to RELEASING
						_state = ThrowState.RELEASING
						_bounce_t = 0.0
						_release_y = _window_center_y
						get_viewport().set_input_as_handled()
						state_changed.emit(ThrowState.RELEASING)
						queue_redraw()
				ThrowState.RELEASING:
					# Freeze the marker and enter resolve preview
					get_viewport().set_input_as_handled()
					_enter_resolving()


## Set up the POSITIONING state: record bounds, calculate target height, start shrink tween.
func _enter_positioning() -> void:
	# Record the full line bounds
	_full_line_top = _board_center.y - _board_radius
	_full_line_bottom = _board_center.y + _board_radius
	_full_line_height = _full_line_bottom - _full_line_top

	# Calculate target window height based on vertical_accuracy (1–100 → normalized fraction)
	var vertical_fraction: float = clampf((vertical_accuracy - 1.0) / 99.0, 0.0, 1.0)
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
	# Snap window edges to final calculated values
	_window_top = _window_center_y - _window_height / 2.0
	_window_bottom = _window_center_y + _window_height / 2.0


## Transition to RESOLVING: freeze the marker, show landing zone preview, start timer.
func _enter_resolving() -> void:
	_state = ThrowState.RESOLVING
	set_process(false)
	state_changed.emit(ThrowState.RESOLVING)
	queue_redraw()

	# Start a timer for the resolve preview duration, then land the dart
	get_tree().create_timer(resolve_preview_duration).timeout.connect(_on_resolve_timer_finished)


## Called when the resolve preview timer expires — land the dart.
func _on_resolve_timer_finished() -> void:
	_state = ThrowState.DONE
	_resolve_throw()


## Resolve the final dart position from locked aim and release values with variance.
func _resolve_throw() -> void:
	# Horizontal position: random within aim line width, centered on locked x
	var aim_half_w: float = _get_aim_half_width()
	var horizontal_offset: float = randf_range(-aim_half_w, aim_half_w)
	var final_x: float = _locked_aim_x + horizontal_offset

	# Vertical position: marker position plus random variance within glow zone
	var release_half_h: float = _get_release_half_height()
	var vertical_offset: float = randf_range(-release_half_h, release_half_h)
	var final_y: float = _release_y + vertical_offset

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

		ThrowState.RELEASING:
			_draw_releasing()

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

	# Draw window border for clarity
	draw_rect(window_rect, window_border_color, false, 2.0)


## Draw the RELEASING state: dimmed aim band + locked window + bouncing marker.
func _draw_releasing() -> void:
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

	# Draw the locked vertical window
	var window_rect: Rect2 = Rect2(
		Vector2(band_left, _window_top) - global_position,
		Vector2(band_width, _window_bottom - _window_top)
	)
	draw_rect(window_rect, window_color)
	draw_rect(window_rect, window_border_color, false, 2.0)

	# Draw glow zone around marker, clipped to window bounds
	var release_half_h: float = _get_release_half_height()
	var glow_top: float = maxf(_release_y - release_half_h, _window_top)
	var glow_bottom: float = minf(_release_y + release_half_h, _window_bottom)
	var glow_rect: Rect2 = Rect2(
		Vector2(band_left, glow_top) - global_position,
		Vector2(band_width, glow_bottom - glow_top)
	)
	draw_rect(glow_rect, glow_zone_color)

	# Draw the bouncing marker
	var marker_pos: Vector2 = Vector2(_locked_aim_x, _release_y) - global_position
	draw_circle(marker_pos, release_marker_size, release_marker_color)


## Draw the RESOLVING state: frozen marker + full landing zone preview.
func _draw_resolving() -> void:
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

	# Draw the locked vertical window
	var window_rect: Rect2 = Rect2(
		Vector2(band_left, _window_top) - global_position,
		Vector2(band_width, _window_bottom - _window_top)
	)
	draw_rect(window_rect, window_color)
	draw_rect(window_rect, window_border_color, false, 2.0)

	# Draw the resolve preview rectangle (full landing zone), clipped to window bounds
	var release_half_h: float = _get_release_half_height()
	var preview_top: float = maxf(_release_y - release_half_h, _window_top)
	var preview_bottom: float = minf(_release_y + release_half_h, _window_bottom)
	var preview_rect: Rect2 = Rect2(
		Vector2(band_left, preview_top) - global_position,
		Vector2(band_width, preview_bottom - preview_top)
	)
	draw_rect(preview_rect, resolve_preview_color)

	# Draw the frozen marker at its stopped position
	var marker_pos: Vector2 = Vector2(_locked_aim_x, _release_y) - global_position
	draw_circle(marker_pos, release_marker_size, release_marker_color)
