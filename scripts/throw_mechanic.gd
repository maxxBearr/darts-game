extends Node2D
## Three-stage crosshair-based throw mechanic: place aim crosshair, vertical release,
## then horizontal release. Emits throw_completed with the final pixel position
## when all stages are done.

signal throw_completed(hit_position: Vector2)
signal state_changed(new_state: ThrowState)

enum ThrowState { IDLE, AIMING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, RESOLVING, DONE }

@export_group("Aim Range")

## Controls horizontal range of the aim crosshair. Higher = tighter range.
## 1 = worst (half-width equals max_aim_half_width).
## 100 = best (half-width equals min_aim_half_width).
## Typical gameplay range: 30 to 80.
@export var horizontal_range: float = 8.0

## Maximum aim crosshair half-width in pixels (at horizontal_range = 1). The worst possible horizontal spread.
@export var max_aim_half_width: float = 270.0

## Minimum aim crosshair half-width in pixels (at horizontal_range = 100). The tightest possible horizontal spread.
@export var min_aim_half_width: float = 8.0

## Controls vertical range of the aim crosshair. Higher = tighter range.
## 1 = worst (half-height equals max_aim_half_height).
## 100 = best (half-height equals min_aim_half_height).
## Typical gameplay range: 30 to 70.
@export var vertical_range: float = 5.0

## Maximum aim crosshair half-height in pixels (at vertical_range = 1). The worst possible vertical spread.
@export var max_aim_half_height: float = 270.0

## Minimum aim crosshair half-height in pixels (at vertical_range = 100). The tightest possible vertical spread.
@export var min_aim_half_height: float = 5.0

@export_group("Speed & Accuracy")

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

@export_group("Throw Visual")

## Color of the vertical crosshair arm during AIMING.
@export var v_arm_color: Color = Color(1.0, 0.3, 0.3, 0.35)

## Color of the vertical crosshair arm during meter phases (dimmed).
@export var v_arm_dimmed_color: Color = Color(1.0, 0.3, 0.3, 0.2)

## Color of the horizontal crosshair arm during AIMING.
@export var h_arm_color: Color = Color(0.2, 0.5, 1.0, 0.35)

## Color of the horizontal crosshair arm during meter phases (dimmed).
@export var h_arm_dimmed_color: Color = Color(0.2, 0.5, 1.0, 0.2)

## Line thickness of the aim crosshair in pixels.
@export var aim_crosshair_thickness: float = 2.0

## Speed at which WASD moves the aim crosshair during AIMING (pixels per second).
@export var window_move_speed: float = 300.0

## Color of the marker circle (shared by vertical and horizontal markers).
@export var marker_color: Color = Color(1.0, 0.3, 0.3, 0.9)

## Size (radius) of the marker circle in pixels (shared by both markers).
@export var marker_size: float = 8.0

## Color of the marker outline ring for visibility against busy backgrounds.
@export var marker_outline_color: Color = Color(1.0, 1.0, 1.0, 0.9)

## Thickness of the marker outline ring in pixels. Set to 0 to disable.
@export var marker_outline_thickness: float = 2.0

## Duration in seconds the resolve preview is shown before the dart lands.
@export var resolve_preview_duration: float = 0.5

## Controls how tightly the Gaussian distribution clusters toward the aim point.
## Lower values = tighter clustering near center (more skill-rewarding).
## Higher values = wider spread (more RNG).
## At 0.4, roughly 95% of throws land in the inner 80% of the accuracy ellipse.
@export_range(0.2, 0.6, 0.01) var gaussian_spread: float = 0.4

@export_group("Accuracy Zones")

## Reference radius for accuracy zone distance normalization (in pixels).
## Distance from the target centroid is divided by this value to get the
## normalized distance. Uses absolute pixel distance — independent of ellipse
## size so that improving range doesn't penalize accuracy zone placement.
@export var accuracy_zone_reference_radius: float = 150.0

## Normalized distance threshold for the green (bonus) zone.
## At or below this distance, the player gets an accuracy bonus.
## With the default 150px reference: green zone = within ~37px of target.
@export_range(0.0, 0.5, 0.01) var green_zone_threshold: float = 0.25

## Normalized distance threshold where the penalty zone begins.
## Between green_threshold and this value is the neutral zone (no change).
## With the default 150px reference: penalty starts at ~90px from target.
@export_range(0.3, 0.8, 0.01) var penalty_zone_threshold: float = 0.6

## Accuracy multiplier at the center of the green zone (best case).
## Values < 1.0 mean the accuracy zone shrinks (tighter grouping).
@export_range(0.5, 1.0, 0.01) var green_zone_multiplier: float = 0.75

## Accuracy multiplier at maximum penalty distance (worst case).
## Values > 1.0 mean the accuracy zone bloats (wider scatter).
@export_range(1.5, 4.0, 0.1) var max_edge_penalty_multiplier: float = 2.5

## Color of the accuracy zone when in the green (bonus) zone.
@export var accuracy_green_color: Color = Color(0.2, 0.85, 0.3, 0.25)

## Color of the accuracy zone in the neutral zone (no bonus or penalty).
@export var accuracy_neutral_color: Color = Color(1.0, 0.9, 0.2, 0.25)

## Color of the accuracy zone when in the red (penalty) zone.
@export var accuracy_red_color: Color = Color(0.9, 0.2, 0.15, 0.25)

@export_group("Debug")

## When true, shows ghost-dart scatter preview during the RESOLVING stage.
@export var live_scatter_preview: bool = false

## Number of ghost darts to show during live scatter preview.
@export var live_scatter_sample_count: int = 10

## Whether colored zone bands are drawn on the H meter during HORIZONTAL_RELEASE.
@export var show_h_meter_zone_bands: bool = true

# --- Tutorial scripting hooks ---

## When true, _process() skips its own bounce_t updates. The tutorial advances meters manually.
var _scripted_mode: bool = false

## When true, _process() returns early entirely — markers frozen, no input accepted.
var _paused: bool = false

## When true, the meter keeps bouncing but clicks/keys don't commit. Used by the
## H Speed tutorial demo so the player can see speed changes without locking.
var _input_blocked: bool = false

## Emitted every _process tick during VERTICAL_RELEASE / HORIZONTAL_RELEASE with the current
## normalized bounce_t so the tutorial controller can detect when meters reach freeze points.
signal meter_position_changed(state: ThrowState, normalized_t: float)

# When true, the aim crosshair and accuracy zone previews are drawn more prominently.
var _tutorial_visual_boost: bool = false

# Which element's border should pulse during the tutorial.
# "aim_crosshair", "accuracy_zone", "vertical_band", "marker", or "" (none).
var _tutorial_pulse_target: String = ""

# Pulse animation timer (incremented in _process when a pulse target is active).
var _tutorial_pulse_time: float = 0.0

@export_group("Tutorial Pulse")

## Speed of the tutorial pulse animation.
@export var tutorial_pulse_speed: float = 3.5

## Minimum outline alpha of the pulse cycle.
@export var tutorial_pulse_min_alpha: float = 0.4

## Maximum outline alpha of the pulse cycle.
@export var tutorial_pulse_max_alpha: float = 1.0

## Minimum outline width of the pulse cycle.
@export var tutorial_pulse_min_width: float = 2.0

## Maximum outline width of the pulse cycle.
@export var tutorial_pulse_max_width: float = 5.0

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

## Reference to the dartboard node, set by main.gd.
var dartboard: Node2D = null

## Center of the placed aim crosshair (locked when player confirms placement).
var _placed_center: Vector2 = Vector2.ZERO

## Horizontal arm half-length of the aim crosshair (computed from horizontal_range at placement time).
var _aim_half_width: float = 0.0

## Vertical arm half-length of the aim crosshair (computed from vertical_range at placement time).
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


# ── The Drunkard boss: distorted aim + enforced meter length ──────────────────
# Set by DrunkardBoss.on_leg_start via set_drunk_distortion(); cleared at leg end.
var _drunk_active: bool = false
## Zigzag depth applied to the bounce→position mapping (fraction of the meter half-
## length). Makes the marker wander as it travels — learnable, not random.
var _drunk_warp_amp: float = 0.0
## Number of zigzag lobes along the meter.
var _drunk_freq: float = 3.0
## Visual-only perpendicular squiggle amplitude in px (the drunk "track" the marker rides).
var _drunk_perp_amp: float = 0.0
## Enforced minimum meter half-length: base px plus extra scaled by (100 − range stat).
var _drunk_floor_base: float = 0.0
var _drunk_floor_scale: float = 0.0

## How much the player's Range stat trims the enforced floor back toward their natural
## (un-floored) meter length. 0 = hard floor (old behavior); 1 = floor fully removed at
## max range. Lets a maxed-accuracy player keep some of their investment instead of being
## flattened to a fixed minimum. Kept modest so the floor still bites.
const DRUNK_FLOOR_RANGE_EASE: float = 0.35

## How much of the floor-induced pixel-speed inflation is cancelled by slowing the bounce
## rate. The marker's pixel speed = bounce_rate × meter length, so the floor stretching the
## meter would silently undo Speed Control; this claws part of it back. 0 = none, 1 = pixel
## speed fully tracks the natural meter again.
const DRUNK_SPEED_COMPENSATION: float = 0.5

## Extra Speed-Control bite under the Drunkard. The bounce rate is multiplied by this on
## top of its normal effect, scaled by how much Speed Control is invested: a maxed stat
## slows the Drunkard meter to this fraction, a minimum stat leaves it unchanged. Lower =
## maxed Speed Control slows the meter more. This is what makes the stat meaningfully
## counter the Drunkard rather than being drowned out by the meter-length floor.
const DRUNK_SPEED_STAT_SLOW: float = 0.4
## The vertical-release squiggle's X offset, locked when the player commits the
## vertical meter. The horizontal phase (and the final landing) are shifted by this,
## so the dart respects the curve the player rode on the vertical arm too. 0 = no drunk.
var _drunk_locked_perp_x: float = 0.0


## Configure the drunk distortion (called by DrunkardBoss). All amplitudes scale with
## difficulty tier. Pass clear via clear_drunk_distortion().
func set_drunk_distortion(warp_amp: float, freq: float, perp_amp: float, floor_base: float, floor_scale: float) -> void:
	_drunk_active = true
	_drunk_warp_amp = warp_amp
	_drunk_freq = freq
	_drunk_perp_amp = perp_amp
	_drunk_floor_base = floor_base
	_drunk_floor_scale = floor_scale
	queue_redraw()


## Remove the drunk distortion (called at the Drunkard's leg end).
func clear_drunk_distortion() -> void:
	_drunk_active = false
	_drunk_warp_amp = 0.0
	_drunk_perp_amp = 0.0
	_drunk_floor_base = 0.0
	_drunk_floor_scale = 0.0
	_drunk_locked_perp_x = 0.0
	queue_redraw()


## Base X of the horizontal sweep: the placed centre shifted by the vertical lock's
## squiggle offset, so the horizontal meter and the dart land where the vertical curve
## left off. Equals _placed_center.x when not drunk (offset is 0).
func _drunk_h_base() -> float:
	return _placed_center.x + _drunk_locked_perp_x


## Normalized horizontal-meter position (warped), measured from the shifted base.
func _drunk_u_h() -> float:
	return (_horizontal_x - _drunk_h_base()) / maxf(_aim_half_width, 0.001)


## Warp a normalized meter position (sin(bounce_t), in [-1,1]) into a drunk zigzag.
## Returns the input unchanged when the distortion is inactive.
func _drunk_warp_pos(p: float) -> float:
	if not _drunk_active:
		return p
	return clampf(p + _drunk_warp_amp * sin(p * _drunk_freq * PI), -1.0, 1.0)


## Apply the enforced meter-length floor to a natural half-length, scaled by range stat.
func _apply_drunk_floor(natural_half: float, range_stat: float) -> float:
	if not _drunk_active:
		return natural_half
	var floor_half: float = _drunk_floor_base + _drunk_floor_scale * (100.0 - range_stat) / 99.0
	# Range investment trims the floor toward the player's natural meter (more trim the
	# higher the range), so maxed accuracy isn't simply flattened to the fixed minimum.
	var range_norm: float = clampf((range_stat - 1.0) / 99.0, 0.0, 1.0)
	floor_half = lerpf(floor_half, natural_half, DRUNK_FLOOR_RANGE_EASE * range_norm)
	return maxf(natural_half, floor_half)


## Natural (un-floored) aim half-width from the horizontal_range stat (1-100).
func _natural_aim_half_width() -> float:
	var normalized: float = clampf((horizontal_range - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_aim_half_width, min_aim_half_width, normalized)


## Natural (un-floored) aim half-height from the vertical_range stat (1-100).
func _natural_aim_half_height() -> float:
	var normalized: float = clampf((vertical_range - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_aim_half_height, min_aim_half_height, normalized)


## Compute the aim crosshair half-width in pixels from the horizontal_range stat (1-100).
func _get_aim_half_width() -> float:
	return _apply_drunk_floor(_natural_aim_half_width(), horizontal_range)


## Compute the aim crosshair half-height in pixels from the vertical_range stat (1-100).
func _get_aim_half_height() -> float:
	return _apply_drunk_floor(_natural_aim_half_height(), vertical_range)


## Compute the vertical accuracy half-height in pixels (1-100 stat).
func _get_vertical_accuracy_half() -> float:
	var normalized: float = clampf((vertical_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_vertical_accuracy_half, min_vertical_accuracy_half, normalized)


## Compute the horizontal accuracy half-width in pixels (1-100 stat).
func _get_horizontal_accuracy_half() -> float:
	var normalized: float = clampf((horizontal_accuracy - 1.0) / 99.0, 0.0, 1.0)
	return lerpf(max_horizontal_accuracy_half, min_horizontal_accuracy_half, normalized)


## Combined Drunkard slowdown applied to the bounce rate. Two stacking effects, both 1.0
## (no change) when not drunk:
##   • Speed-Control bite — the more Speed Control invested, the slower the meter, scaled
##     toward DRUNK_SPEED_STAT_SLOW at max stat. This is the dominant lever.
##   • Length compensation — cancels part of the pixel-speed inflation from the meter-length
##     floor, so a long floored meter doesn't read as fast (DRUNK_SPEED_COMPENSATION).
func _drunk_bounce_factor(speed_stat: float, natural_half: float, floored_half: float) -> float:
	if not _drunk_active:
		return 1.0
	var speed_norm: float = clampf((clampf(speed_stat, 1.0, 5.0) - 1.0) / 4.0, 0.0, 1.0)
	var stat_factor: float = lerpf(1.0, DRUNK_SPEED_STAT_SLOW, speed_norm)
	var stretch_factor: float = 1.0
	if natural_half > 0.001 and floored_half > natural_half:
		var stretch: float = floored_half / natural_half
		stretch_factor = lerpf(1.0, 1.0 / stretch, DRUNK_SPEED_COMPENSATION)
	return stat_factor * stretch_factor


## Compute the vertical marker bounce speed from vertical_speed stat.
func _get_vertical_bounce_speed() -> float:
	var base_speed: float = (6.0 - clampf(vertical_speed, 1.0, 5.0)) * 2.5
	return base_speed * _drunk_bounce_factor(vertical_speed, _natural_aim_half_height(), _get_aim_half_height())


## Compute the horizontal marker bounce speed from horizontal_speed stat.
func _get_horizontal_bounce_speed() -> float:
	var base_speed: float = (6.0 - clampf(horizontal_speed, 1.0, 5.0)) * 2.5
	return base_speed * _drunk_bounce_factor(horizontal_speed, _natural_aim_half_width(), _get_aim_half_width())


## Compute normalized distance from an arbitrary point to the target centroid.
## Uses absolute pixel distance divided by accuracy_zone_reference_radius,
## so the zone boundaries are fixed in space regardless of ellipse size.
func _get_target_distance_normalized_at(pos: Vector2) -> float:
	if _declared_target.is_empty():
		return 0.5
	var distance: float = pos.distance_to(_target_centroid)
	return distance / accuracy_zone_reference_radius if accuracy_zone_reference_radius > 0.0 else 0.5


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
	# Advance tutorial pulse even while paused so the glow animates during freeze beats
	if _tutorial_pulse_target != "":
		_tutorial_pulse_time += delta

	# Tutorial pause — freeze everything except the pulse
	if _paused:
		if _tutorial_pulse_target != "":
			queue_redraw()
		return

	match _state:
		ThrowState.AIMING:
			if _scripted_mode:
				queue_redraw()
				return
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
			if not _scripted_mode:
				var bounce_speed: float = _get_vertical_bounce_speed()
				_bounce_t += delta * bounce_speed
				_release_y = _placed_center.y + _drunk_warp_pos(sin(_bounce_t)) * _aim_half_height
			# Emit normalized position for tutorial controller
			var normalized_v: float = sin(_bounce_t)
			meter_position_changed.emit(ThrowState.VERTICAL_RELEASE, normalized_v)
			queue_redraw()

		ThrowState.HORIZONTAL_RELEASE:
			if not _scripted_mode:
				var bounce_speed: float = _get_horizontal_bounce_speed()
				_horizontal_bounce_t += delta * bounce_speed
				_horizontal_x = _drunk_h_base() + _drunk_warp_pos(sin(_horizontal_bounce_t)) * _aim_half_width
			# Emit normalized position for tutorial controller
			var normalized_h: float = sin(_horizontal_bounce_t)
			meter_position_changed.emit(ThrowState.HORIZONTAL_RELEASE, normalized_h)
			queue_redraw()

		ThrowState.RESOLVING:
			queue_redraw()

		ThrowState.DONE:
			set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	# Block all input while paused, scripted, or input-blocked
	if _paused or _scripted_mode or _input_blocked:
		return

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
					_place_aim_crosshair()
					get_viewport().set_input_as_handled()
				ThrowState.VERTICAL_RELEASE:
					_lock_vertical()
					get_viewport().set_input_as_handled()
				ThrowState.HORIZONTAL_RELEASE:
					get_viewport().set_input_as_handled()
					_enter_resolving()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if _state == ThrowState.VERTICAL_RELEASE:
				_cancel_to_aiming()
				get_viewport().set_input_as_handled()

	# Handle Enter/Space key presses for all states
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_SPACE):
			match _state:
				ThrowState.AIMING:
					_place_aim_crosshair()
					get_viewport().set_input_as_handled()
				ThrowState.VERTICAL_RELEASE:
					_lock_vertical()
					get_viewport().set_input_as_handled()
				ThrowState.HORIZONTAL_RELEASE:
					get_viewport().set_input_as_handled()
					_enter_resolving()
		elif key.pressed and key.keycode == KEY_ESCAPE and _state == ThrowState.VERTICAL_RELEASE:
			_cancel_to_aiming()
			get_viewport().set_input_as_handled()


## Lock the aim crosshair in place and transition to VERTICAL_RELEASE.
func _place_aim_crosshair() -> void:
	# Reject clicks outside the surround — prevents accidental throws from UI areas
	if dartboard != null:
		var offset: Vector2 = _aim_center - dartboard.global_position
		var surround_radius: float = dartboard.board_radius * dartboard.surround_outer_multiplier
		if offset.length() > surround_radius:
			return

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


## Cancel the vertical meter and return to the AIMING state.
func _cancel_to_aiming() -> void:
	_aim_center = _placed_center
	_declared_target = {}
	_target_centroid = _aim_center
	_bounce_t = 0.0
	_mouse_controls_aim = false
	_last_mouse_pos = get_global_mouse_position()
	_state = ThrowState.AIMING
	state_changed.emit(ThrowState.AIMING)
	queue_redraw()


## Lock the vertical position and transition to HORIZONTAL_RELEASE.
func _lock_vertical() -> void:
	_locked_release_y = _release_y
	# Lock the vertical squiggle's X offset (the marker's perpendicular position when
	# committed) so the horizontal phase and the landing respect that curve too.
	if _drunk_active:
		var u_v: float = (_locked_release_y - _placed_center.y) / maxf(_aim_half_height, 0.001)
		_drunk_locked_perp_x = _drunk_perp_offset(u_v)
	else:
		_drunk_locked_perp_x = 0.0
	_state = ThrowState.HORIZONTAL_RELEASE
	_horizontal_bounce_t = 0.0
	_horizontal_x = _drunk_h_base()
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
	var center_y: float = _locked_release_y + accuracy_skew_v + _drunk_landing_perp_y()

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


## The aim center used as the accuracy-ellipse center when the dart resolved — the
## point the player actually locked onto. The anticipation fly-in starts the large
## dart here; it then drifts to the RNG landing point, so the drift distance is a
## direct visualization of the accuracy miss. Valid immediately after a resolve.
func get_resolve_center() -> Vector2:
	return Vector2(_horizontal_x, _locked_release_y + accuracy_skew_v + _drunk_landing_perp_y())


## The perpendicular squiggle offset the horizontal-release marker visibly rode, in
## Y (its travel is along X). Folded into the committed landing so the dart lands on
## the drunk path the player saw, not the straight line under it. 0 when not drunk.
## Mirrors the marker math in _draw_horizontal_release.
func _drunk_landing_perp_y() -> float:
	if not _drunk_active:
		return 0.0
	return _drunk_perp_offset(_drunk_u_h())


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


## Draw the aim crosshair with independent arm lengths, per-arm colors, and optional tick marks.
func _draw_aim_crosshair(center: Vector2, h_arm_half: float, v_arm_half: float,
		h_color: Color, v_color: Color, width: float = 2.0, tick_size: float = 4.0) -> void:
	draw_line(center + Vector2(-h_arm_half, 0.0), center + Vector2(h_arm_half, 0.0), h_color, width)
	draw_line(center + Vector2(0.0, -v_arm_half), center + Vector2(0.0, v_arm_half), v_color, width)
	if tick_size > 0.0:
		for x_sign: float in [-1.0, 1.0]:
			var tip: Vector2 = center + Vector2(x_sign * h_arm_half, 0.0)
			draw_line(tip + Vector2(0.0, -tick_size), tip + Vector2(0.0, tick_size), h_color, width)
		for y_sign: float in [-1.0, 1.0]:
			var tip: Vector2 = center + Vector2(0.0, y_sign * v_arm_half)
			draw_line(tip + Vector2(-tick_size, 0.0), tip + Vector2(tick_size, 0.0), v_color, width)


## Draw the drunk "track" — the squiggly path the release marker rides (visual only).
## `vertical` selects the meter axis; `center_local` is the arm centre in local coords.
func _draw_drunk_track(vertical: bool, center_local: Vector2, half_w: float, half_h: float) -> void:
	if not _drunk_active or _drunk_perp_amp <= 0.0:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 48
	for i: int in range(steps + 1):
		var u: float = lerpf(-1.0, 1.0, float(i) / float(steps))
		var perp: float = _drunk_perp_amp * sin(u * _drunk_freq * PI)
		if vertical:
			pts.append(center_local + Vector2(perp, u * half_h))
		else:
			pts.append(center_local + Vector2(u * half_w, perp))
	var col: Color = Color(v_arm_color, 0.45) if vertical else Color(h_arm_color, 0.45)
	draw_polyline(pts, col, 2.0)


## Perpendicular squiggle offset (px) for the marker at a warped normalized position.
func _drunk_perp_offset(normalized_pos: float) -> float:
	if not _drunk_active:
		return 0.0
	return _drunk_perp_amp * sin(normalized_pos * _drunk_freq * PI)


## Draw the bouncing marker dot with optional outline ring for visibility.
func _draw_marker(pos: Vector2) -> void:
	if marker_outline_thickness > 0.0:
		draw_arc(pos, marker_size + marker_outline_thickness * 0.5, 0.0, TAU, 64, marker_outline_color, marker_outline_thickness)
	draw_circle(pos, marker_size, marker_color)


## Draw the AIMING state: crosshair following cursor showing aim range.
func _draw_aiming() -> void:
	var half_w: float = _get_aim_half_width()
	var half_h: float = _get_aim_half_height()
	var center: Vector2 = _aim_center - global_position

	_draw_aim_crosshair(center, half_w, half_h, h_arm_color, v_arm_color, aim_crosshair_thickness)
	_draw_aim_crosshair(center, half_w, half_h,
		Color(h_arm_color, minf(h_arm_color.a + 0.3, 1.0)),
		Color(v_arm_color, minf(v_arm_color.a + 0.3, 1.0)),
		maxf(aim_crosshair_thickness - 1.0, 1.0), 0.0)


## Draw the VERTICAL_RELEASE state: dimmed crosshair + ghost preview + vertical accuracy band + bouncing marker.
func _draw_vertical_release() -> void:
	var center: Vector2 = _placed_center - global_position
	var pulse: Dictionary = _get_pulse_values()

	# Aim crosshair — H arm follows the bouncing marker's Y, always full width
	var dimmed_w: float = maxf(aim_crosshair_thickness * 0.75, 1.0)
	var marker_y_local: float = _release_y - global_position.y
	var h_arm_center: Vector2 = Vector2(center.x, marker_y_local)
	if _tutorial_visual_boost:
		var aim_outline_a: float = 0.5
		var aim_outline_w: float = aim_crosshair_thickness + 1.0
		if _tutorial_pulse_target == "aim_crosshair":
			aim_outline_a = pulse["alpha"]
			aim_outline_w = pulse["width"] + 1.0
		var vc: Color = Color(v_arm_color, aim_outline_a)
		var hc: Color = Color(h_arm_color, aim_outline_a)
		draw_line(center + Vector2(0.0, -_aim_half_height), center + Vector2(0.0, _aim_half_height), vc, aim_outline_w)
		draw_line(h_arm_center + Vector2(-_aim_half_width, 0.0), h_arm_center + Vector2(_aim_half_width, 0.0), hc, aim_outline_w)
	else:
		draw_line(center + Vector2(0.0, -_aim_half_height), center + Vector2(0.0, _aim_half_height), v_arm_dimmed_color, dimmed_w)
		draw_line(h_arm_center + Vector2(-_aim_half_width, 0.0), h_arm_center + Vector2(_aim_half_width, 0.0), h_arm_dimmed_color, dimmed_w)
		var tick: float = 3.0
		for y_sign: float in [-1.0, 1.0]:
			var tip: Vector2 = center + Vector2(0.0, y_sign * _aim_half_height)
			draw_line(tip + Vector2(-tick, 0.0), tip + Vector2(tick, 0.0), v_arm_dimmed_color, dimmed_w)
		for x_sign: float in [-1.0, 1.0]:
			var tip: Vector2 = h_arm_center + Vector2(x_sign * _aim_half_width, 0.0)
			draw_line(tip + Vector2(0.0, -tick), tip + Vector2(0.0, tick), h_arm_dimmed_color, dimmed_w)

	# Ghost accuracy preview at current marker position
	var preview_pos: Vector2 = Vector2(_placed_center.x, _release_y)
	var ghost_dist: float = _get_target_distance_normalized_at(preview_pos)
	var ghost_mult: float = _get_accuracy_multiplier(ghost_dist)
	var ghost_h_half: float = _get_horizontal_accuracy_half() * ghost_mult
	var ghost_v_half: float = _get_vertical_accuracy_half() * ghost_mult
	var ghost_color: Color = _get_accuracy_zone_color(ghost_mult)
	var fill_alpha: float = 0.7 if _tutorial_visual_boost else 0.5
	var outline_alpha: float = 0.8 if _tutorial_visual_boost else ghost_color.a
	var outline_width: float = 2.5 if _tutorial_visual_boost else 1.5
	if _tutorial_pulse_target == "accuracy_zone":
		fill_alpha = 0.8
		outline_alpha = pulse["alpha"]
		outline_width = pulse["width"]
	ghost_color.a *= fill_alpha
	var ghost_local: Vector2 = preview_pos - global_position
	_draw_filled_ellipse(ghost_local, ghost_h_half, ghost_v_half, ghost_color)
	_draw_ellipse_outline(ghost_local, ghost_h_half, ghost_v_half,
		Color(ghost_color.r, ghost_color.g, ghost_color.b, outline_alpha), outline_width)

	# Bouncing marker dot (rides the drunk squiggle track when distorted)
	var marker_x: float = _placed_center.x
	if _drunk_active:
		_draw_drunk_track(true, center, _aim_half_width, _aim_half_height)
		var u_v: float = (_release_y - _placed_center.y) / maxf(_aim_half_height, 0.001)
		marker_x += _drunk_perp_offset(u_v)
	var marker_pos: Vector2 = Vector2(marker_x, _release_y) - global_position
	_draw_marker(marker_pos)


## Draw the HORIZONTAL_RELEASE state: dimmed crosshair (H arm at locked Y) + ghost preview + marker.
func _draw_horizontal_release() -> void:
	# X is the drunk-shifted base (the vertical lock's squiggle offset) so the whole
	# horizontal crosshair lines up with where the dart will actually land. Equal to
	# _placed_center.x when not drunk.
	var center: Vector2 = Vector2(_drunk_h_base(), _placed_center.y) - global_position
	var locked_y_local: float = _locked_release_y - global_position.y
	var h_arm_center: Vector2 = Vector2(center.x, locked_y_local)
	var pulse: Dictionary = _get_pulse_values()

	# Aim crosshair — V arm at center, H arm at locked Y
	var dimmed_w: float = maxf(aim_crosshair_thickness * 0.75, 1.0)
	if _tutorial_visual_boost:
		var aim_outline_a: float = 0.5
		var aim_outline_w: float = aim_crosshair_thickness + 1.0
		if _tutorial_pulse_target == "aim_crosshair":
			aim_outline_a = pulse["alpha"]
			aim_outline_w = pulse["width"] + 1.0
		var vc: Color = Color(v_arm_color, aim_outline_a)
		var hc: Color = Color(h_arm_color, aim_outline_a)
		draw_line(center + Vector2(0.0, -_aim_half_height), center + Vector2(0.0, _aim_half_height), vc, aim_outline_w)
		draw_line(h_arm_center + Vector2(-_aim_half_width, 0.0), h_arm_center + Vector2(_aim_half_width, 0.0), hc, aim_outline_w)
	else:
		draw_line(center + Vector2(0.0, -_aim_half_height), center + Vector2(0.0, _aim_half_height), v_arm_dimmed_color, dimmed_w)
		draw_line(h_arm_center + Vector2(-_aim_half_width, 0.0), h_arm_center + Vector2(_aim_half_width, 0.0), h_arm_dimmed_color, dimmed_w)
		var tick: float = 3.0
		for y_sign: float in [-1.0, 1.0]:
			var tip: Vector2 = center + Vector2(0.0, y_sign * _aim_half_height)
			draw_line(tip + Vector2(-tick, 0.0), tip + Vector2(tick, 0.0), v_arm_dimmed_color, dimmed_w)
		for x_sign: float in [-1.0, 1.0]:
			var tip: Vector2 = h_arm_center + Vector2(x_sign * _aim_half_width, 0.0)
			draw_line(tip + Vector2(0.0, -tick), tip + Vector2(0.0, tick), h_arm_dimmed_color, dimmed_w)

	# Ghost accuracy preview at current marker position (incl. the drunk perp-Y)
	var preview_pos: Vector2 = Vector2(_horizontal_x, _locked_release_y + _drunk_landing_perp_y())
	var ghost_dist: float = _get_target_distance_normalized_at(preview_pos)
	var ghost_mult: float = _get_accuracy_multiplier(ghost_dist)
	var ghost_h_half: float = _get_horizontal_accuracy_half() * ghost_mult
	var ghost_v_half: float = _get_vertical_accuracy_half() * ghost_mult
	var ghost_color: Color = _get_accuracy_zone_color(ghost_mult)
	var fill_alpha: float = 0.7 if _tutorial_visual_boost else 0.5
	var outline_alpha: float = 0.8 if _tutorial_visual_boost else ghost_color.a
	var outline_width: float = 2.5 if _tutorial_visual_boost else 1.5
	if _tutorial_pulse_target == "accuracy_zone":
		fill_alpha = 0.8
		outline_alpha = pulse["alpha"]
		outline_width = pulse["width"]
	ghost_color.a *= fill_alpha
	var ghost_local: Vector2 = preview_pos - global_position
	_draw_filled_ellipse(ghost_local, ghost_h_half, ghost_v_half, ghost_color)
	_draw_ellipse_outline(ghost_local, ghost_h_half, ghost_v_half,
		Color(ghost_color.r, ghost_color.g, ghost_color.b, outline_alpha), outline_width)

	# Bouncing marker dot at locked Y (rides the drunk squiggle track when distorted)
	var marker_y: float = _locked_release_y
	if _drunk_active:
		_draw_drunk_track(false, h_arm_center, _aim_half_width, _aim_half_height)
		marker_y += _drunk_perp_offset(_drunk_u_h())
	var marker_pos: Vector2 = Vector2(_horizontal_x, marker_y) - global_position
	_draw_marker(marker_pos)


# ── Tutorial scripting API ──────────────────────────────────────────────────

## Enable or disable tutorial visual boost. When active, the aim crosshair is drawn
## thicker and the accuracy zone preview is more opaque, making zone colors clearly
## readable during the tutorial walkthrough.
func set_tutorial_visual_boost(enabled: bool) -> void:
	_tutorial_visual_boost = enabled
	queue_redraw()


## Set which element's border should pulse. Pass "" to stop pulsing.
## Valid targets: "aim_crosshair", "accuracy_zone", "vertical_band", "marker".
func set_tutorial_pulse_target(target: String) -> void:
	_tutorial_pulse_target = target
	_tutorial_pulse_time = 0.0
	queue_redraw()


## Compute the current pulse alpha and width for the active pulse target.
## Returns {alpha: float, width: float}. Only meaningful when a target is set.
func _get_pulse_values() -> Dictionary:
	var t: float = (sin(_tutorial_pulse_time * tutorial_pulse_speed) + 1.0) / 2.0
	return {
		"alpha": lerpf(tutorial_pulse_min_alpha, tutorial_pulse_max_alpha, t),
		"width": lerpf(tutorial_pulse_min_width, tutorial_pulse_max_width, t),
	}


## Set paused state — when paused, _process returns early and no input is accepted.
func set_paused(paused: bool) -> void:
	_paused = paused


## Block/unblock player input without stopping the meter animation.
## Used by the H Speed demo so the marker keeps bouncing but clicks don't commit.
func set_input_blocked(blocked: bool) -> void:
	_input_blocked = blocked


## Recompute the cached aim crosshair dimensions and all dependent values from
## the current range stats. Called by the tutorial Range slider demo so the
## crosshair, marker position, and meter range all update live.
func recompute_aim_dimensions() -> void:
	_aim_half_width = _get_aim_half_width()
	_aim_half_height = _get_aim_half_height()
	_release_y = _placed_center.y + sin(_bounce_t) * _aim_half_height
	_horizontal_x = _placed_center.x + sin(_horizontal_bounce_t) * _aim_half_width
	queue_redraw()


## Enable or disable scripted mode. When scripted, _process skips bounce_t updates
## and input is blocked — the tutorial controller drives the meters manually.
func set_scripted_mode(enabled: bool) -> void:
	_scripted_mode = enabled


## Set the vertical bounce parameter directly (0-TAU range). Used by tutorial controller.
func set_bounce_t(value: float) -> void:
	_bounce_t = value
	_release_y = _placed_center.y + sin(_bounce_t) * _aim_half_height
	queue_redraw()


## Set the horizontal bounce parameter directly (0-TAU range). Used by tutorial controller.
func set_horizontal_bounce_t(value: float) -> void:
	_horizontal_bounce_t = value
	_horizontal_x = _placed_center.x + sin(_horizontal_bounce_t) * _aim_half_width
	queue_redraw()


## Programmatically lock the AIM stage at a given position with a declared target.
## Bypasses player input. Used by tutorial to auto-place the aim crosshair.
func force_lock_aim(global_pos: Vector2, target: Dictionary) -> void:
	_aim_center = global_pos
	_placed_center = global_pos
	_aim_half_width = _get_aim_half_width()
	_aim_half_height = _get_aim_half_height()
	_bounce_t = 0.0
	_release_y = _placed_center.y

	_declared_target = target
	if target.is_empty():
		_target_centroid = _placed_center
	elif dartboard != null:
		_target_centroid = dartboard.get_segment_centroid(
			target["wedge_index"], target["ring_name"])
	else:
		_target_centroid = _placed_center

	_state = ThrowState.VERTICAL_RELEASE
	state_changed.emit(ThrowState.VERTICAL_RELEASE)
	set_process(true)
	queue_redraw()


## Programmatically lock the vertical release at a given bounce_t value (0-1 maps to sin).
## Transitions to HORIZONTAL_RELEASE. Used by tutorial.
func force_lock_vertical(t: float) -> void:
	_bounce_t = asin(clampf(t, -1.0, 1.0))
	_release_y = _placed_center.y + sin(_bounce_t) * _aim_half_height
	_lock_vertical()


## Programmatically lock the horizontal release at a given bounce_t value.
## Triggers normal resolve. Used by tutorial.
func force_lock_horizontal(t: float) -> void:
	_horizontal_bounce_t = asin(clampf(t, -1.0, 1.0))
	_horizontal_x = _placed_center.x + sin(_horizontal_bounce_t) * _aim_half_width
	_enter_resolving()


## Compute zone boundary H positions for the given locked Y.
## Returns the screen-space X positions where the green, orange, and red zones
## begin and end on the H meter. Used by tutorial freeze beats and zone band drawing.
func get_zone_boundary_h_positions(locked_y: float) -> Dictionary:
	var h_half: float = _aim_half_width
	if h_half <= 0.0:
		return {"green_min": _placed_center.x, "green_max": _placed_center.x,
				"orange_max": _placed_center.x, "red_max": _placed_center.x}

	# Sample H positions across the meter to find zone boundaries
	var green_min_x: float = _placed_center.x
	var green_max_x: float = _placed_center.x
	var orange_max_x: float = _placed_center.x
	var red_max_x: float = _placed_center.x + h_half
	var found_green_start: bool = false

	var sample_count: int = 100
	for i: int in range(sample_count + 1):
		var frac: float = float(i) / float(sample_count)
		var x: float = _placed_center.x + (frac * 2.0 - 1.0) * h_half
		var dist: float = _get_target_distance_normalized_at(Vector2(x, locked_y))

		if dist <= green_zone_threshold:
			if not found_green_start:
				green_min_x = x
				found_green_start = true
			green_max_x = x
		elif dist <= penalty_zone_threshold:
			orange_max_x = x

	# Ensure ordering makes sense
	if not found_green_start:
		green_min_x = _placed_center.x
		green_max_x = _placed_center.x

	return {
		"green_min": green_min_x,
		"green_max": green_max_x,
		"orange_max": orange_max_x,
		"red_max": red_max_x,
	}


## Get the midpoint X position of a given zone on the H meter.
## zone_name: "green", "orange", or "red".
func get_zone_midpoint_x(locked_y: float, zone_name: String) -> float:
	var bounds: Dictionary = get_zone_boundary_h_positions(locked_y)
	match zone_name:
		"green":
			return (bounds["green_min"] + bounds["green_max"]) / 2.0
		"orange":
			return (bounds["green_max"] + bounds["orange_max"]) / 2.0
		"red":
			return (bounds["orange_max"] + bounds["red_max"]) / 2.0
	return _placed_center.x


## Sample scatter points using the same gaussian + accuracy zone math as the live throw.
## Returns an array of global positions where darts would land from the given release position.
## rng_seed >= 0 uses a deterministic RNG (for tutorial consistency). -1 = global RNG.
func sample_scatter_points(locked_release_pos: Vector2, sample_count: int = 10, rng_seed: int = -1) -> Array[Vector2]:
	var dist: float = _get_target_distance_normalized_at(locked_release_pos)
	var accuracy_mult: float = _get_accuracy_multiplier(dist)
	var h_half: float = _get_horizontal_accuracy_half() * accuracy_mult
	var v_half: float = _get_vertical_accuracy_half() * accuracy_mult
	var center_x: float = locked_release_pos.x
	var center_y: float = locked_release_pos.y + accuracy_skew_v

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if rng_seed >= 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	var points: Array[Vector2] = []
	for _i: int in range(sample_count):
		var offset_x: float = rng.randfn(0.0, h_half * gaussian_spread)
		var offset_y: float = rng.randfn(0.0, v_half * gaussian_spread)
		# Ellipse rejection — resample if outside the accuracy ellipse
		var ellipse_check: float = (offset_x * offset_x) / (h_half * h_half + 0.001) + (offset_y * offset_y) / (v_half * v_half + 0.001)
		if ellipse_check > 1.0:
			offset_x *= 0.7
			offset_y *= 0.7
		points.append(Vector2(center_x + offset_x, center_y + offset_y))

	return points


## Draw the RESOLVING state: dimmed crosshair + accuracy-scaled ellipse with color feedback + frozen marker.
func _draw_resolving() -> void:
	# Crosshair X uses the drunk-shifted base so it lines up with the landing point.
	var center: Vector2 = Vector2(_drunk_h_base(), _placed_center.y) - global_position

	# Dimmed crosshair — V arm at center, H arm at locked Y
	var dimmed_w: float = maxf(aim_crosshair_thickness * 0.75, 1.0)
	var locked_y_local: float = _locked_release_y - global_position.y
	var h_arm_center: Vector2 = Vector2(center.x, locked_y_local)
	draw_line(center + Vector2(0.0, -_aim_half_height), center + Vector2(0.0, _aim_half_height), v_arm_dimmed_color, dimmed_w)
	draw_line(h_arm_center + Vector2(-_aim_half_width, 0.0), h_arm_center + Vector2(_aim_half_width, 0.0), h_arm_dimmed_color, dimmed_w)
	var tick: float = 3.0
	for y_sign: float in [-1.0, 1.0]:
		var tip: Vector2 = center + Vector2(0.0, y_sign * _aim_half_height)
		draw_line(tip + Vector2(-tick, 0.0), tip + Vector2(tick, 0.0), v_arm_dimmed_color, dimmed_w)
	for x_sign: float in [-1.0, 1.0]:
		var tip: Vector2 = h_arm_center + Vector2(x_sign * _aim_half_width, 0.0)
		draw_line(tip + Vector2(0.0, -tick), tip + Vector2(0.0, tick), h_arm_dimmed_color, dimmed_w)

	# Accuracy ellipse at the locked point with skew offset, scaled by target distance
	var dist: float = _get_target_distance_normalized()
	var accuracy_mult: float = _get_accuracy_multiplier(dist)
	var h_half: float = _get_horizontal_accuracy_half() * accuracy_mult
	var v_half: float = _get_vertical_accuracy_half() * accuracy_mult
	var zone_color: Color = _get_accuracy_zone_color(accuracy_mult)
	var skewed_center: Vector2 = Vector2(_horizontal_x, _locked_release_y + _current_skew_offset + _drunk_landing_perp_y()) - global_position

	_draw_filled_ellipse(skewed_center, h_half, v_half, zone_color)
	_draw_ellipse_outline(skewed_center, h_half, v_half, Color(zone_color, minf(zone_color.a + 0.3, 1.0)), 1.5)

	# Frozen marker dot at accuracy ellipse center
	_draw_marker(skewed_center)
