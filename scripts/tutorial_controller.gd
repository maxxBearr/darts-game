class_name TutorialController
extends Node
## Orchestrates the mechanics tutorial using a three-throw structure:
## DISCOVER (guided throw with freeze-and-explain) → DO (free uninterrupted throw) →
## UNDERSTAND (stats walkthrough with live slider demos).
##
## Uses the player's actual build stats — no special tutorial values.
## Slider demos let the player "Set" values they throw with; all stats
## restore to pre-tutorial values when the tutorial ends or is skipped.

signal tutorial_finished(destination: String)
signal request_rules(destination: String)

enum TutorialMode { FULL, STATS_ONLY }

## Reference to the throw mechanic node. Set by main.gd.
var throw_mechanic: Node2D = null

## Reference to the dartboard node. Set by main.gd.
var dartboard: Node2D = null

## Reference to the ghost dart layer. Set by main.gd.
var ghost_dart_layer: GhostDartLayer = null

## Reference to the tutorial callout overlay. Set by main.gd.
var callout: TutorialCallout = null

## Reference to the HUD. Set by main.gd.
var hud: CanvasLayer = null

## Where the player entered the tutorial from ("start_screen" or "assembly").
var entry_source: String = "start_screen"

## Default callout panel position (left side of screen, upper area).
@export var callout_position: Vector2 = Vector2(230.0, 200.0)

## Slider demo: V Range min value.
@export var demo_v_range_min: float = 1.0

## Slider demo: V Range max value.
@export var demo_v_range_max: float = 100.0

## Slider demo: H Range min value.
@export var demo_h_range_min: float = 1.0

## Slider demo: H Range max value.
@export var demo_h_range_max: float = 100.0

## Slider demo: V Speed min (display scale 0-100).
@export var demo_v_speed_min: float = 0.0

## Slider demo: V Speed max (display scale 0-100).
@export var demo_v_speed_max: float = 100.0

## Slider demo: H Speed min (display scale 0-100).
@export var demo_h_speed_min: float = 0.0

## Slider demo: H Speed max (display scale 0-100).
@export var demo_h_speed_max: float = 100.0

## Slider demo: V Accuracy min value.
@export var demo_v_accuracy_min: float = 20.0

## Slider demo: V Accuracy max value.
@export var demo_v_accuracy_max: float = 80.0

## Slider demo: H Accuracy min value.
@export var demo_h_accuracy_min: float = 20.0

## Slider demo: H Accuracy max value.
@export var demo_h_accuracy_max: float = 80.0

## Position of the slider widget on screen (left side, below callout).
@export var slider_position: Vector2 = Vector2(200.0, 520.0)

## Fixed RNG seed for accuracy demo scatter (ensures consistent visual).
@export var accuracy_demo_scatter_seed: int = 99

## Tunable tutorial caption strings. Keyed by beat name.
@export var tutorial_strings: Dictionary = {
	# Throw 1: DISCOVER
	"t1_welcome": "Welcome to the throw mechanic. You'll do three darts, first one we'll walk through together.",
	"t1_aim": "Use your mouse to move your aim, and left-click to select your target. Try it!",
	"t1_aim_placed": "Nice! You selected [b]{target}[/b]. You see this marker moving up and down the vertical arm of the crosshair? To set the height of your throw, left-click or press space to stop the meter at a vertical position.",
	"t1_v_stopped": "Nice. Now that you have set the height of your throw, you have to aim it along the horizontal arm of your crosshair. Stop the meter to set the final alignment of your crosshair.",
	"t1_h_stopped": "This bubble you are seeing is your [b]accuracy zone[/b]. It represents the final area that your dart could wind up.",
	"t1_scatter": "Here is the spread of where 10 darts would wind up in this accuracy zone.",
	# Throw 2: DO
	"t2_intro": "Try an uninterrupted throw!",
	"t2_transition": "Nice throw! Now let's look at how your stats shape what just happened.",
	# Throw 3: UNDERSTAND
	"t3_intro": "One last throw to add some context to these stats you see. First, pick a target.",
	"t3_v_range_speed": "Your [b]V Range[/b] controls how wide the vertical arm of your crosshair spreads, and [b]V Speed[/b] controls how fast the meter bounces. Drag the sliders to see how they work together.",
	"t3_v_meter": "Now time the meter to set your vertical aim.",
	"t3_h_range_speed": "[b]H Range[/b] and [b]H Speed[/b] are the same idea for the horizontal arm. Adjust and set.",
	"t3_h_meter": "Now watch your accuracy zone — as the crosshair sweeps closer to your target, the zone tightens. Farther away, it bloats. Stop the meter when you're aimed where you want.",
	"t3_accuracy": "This is your final accuracy zone — your [b]H Accuracy[/b] and [b]V Accuracy[/b] stats decide how tight or loose your dart's landing scatter is. Drag the sliders to see it change.",
	"t3_complete": "Tutorial complete — you're ready for a real run.",
}

# Internal state
var _active: bool = false
var _current_throw: int = 0
var _waiting_for_next: bool = false
var _waiting_for_throw: bool = false
var _tutorial_mode: TutorialMode = TutorialMode.FULL
var _tutorial_hover_active: bool = false

# H meter click intercept state
var _listening_for_h_click: bool = false
var _h_meter_captured_t: float = 0.0

# Slider demo state
var _active_sliders: Array[TutorialSlider] = []
var _demo_dismiss_remaining: int = 0
var _demo_advance_callback: Callable

# Teardown callbacks for skip cleanup
var _teardown_stack: Array[Callable] = []

# Base stats snapshot — captured at tutorial start, restored on finish/skip
var _base_stats: Dictionary = {}

# Skip Stats Walkthrough button (Phase 3)
var _skip_stats_button: Button = null


## Whether the tutorial is currently active.
func is_active() -> bool:
	return _active


# ── Per-frame hover tooltip ──────────────────────────────────────────

func _process(_delta: float) -> void:
	if not _active or not _tutorial_hover_active:
		return
	if dartboard == null or hud == null:
		return
	var mouse_pos: Vector2 = dartboard.get_global_mouse_position()
	var hover_result: Dictionary = dartboard.update_hover(mouse_pos)
	if hover_result.is_empty():
		hud.hide_hover_tooltip()
	else:
		var empty_streaks: Array[String] = []
		hud.show_hover_tooltip(hover_result, dartboard.WEDGE_ORDER, mouse_pos, false, empty_streaks, false)


# ── Hover helpers ────────────────────────────────────────────────────

func _enable_tutorial_hover() -> void:
	_tutorial_hover_active = true
	dartboard.hover_enabled = true


func _disable_tutorial_hover() -> void:
	_tutorial_hover_active = false
	dartboard.hover_enabled = false
	dartboard.clear_hover()
	hud.hide_hover_tooltip()


# ── Slider helpers ───────────────────────────────────────────────────

## Remove all active sliders from the scene.
func _free_all_sliders() -> void:
	for slider: TutorialSlider in _active_sliders:
		if is_instance_valid(slider):
			slider.queue_free()
	_active_sliders.clear()


## Create a slider for a stat demo, positioned vertically based on index.
## Pass display_initial >= 0 to override the raw stat value shown on the slider
## (used for speed stats which display on a 0-100 scale internally stored as 1-5).
func _create_demo_slider(stat_name: String, stat_property: String, min_val: float, max_val: float, index: int, on_change: Callable, display_initial: float = -1.0) -> TutorialSlider:
	var current: float = throw_mechanic.get(stat_property)
	var slider: TutorialSlider = TutorialSlider.new()
	var y_offset: float = float(index) * 120.0
	slider.widget_position = Vector2(slider_position.x, slider_position.y + y_offset)
	get_parent().get_node("HUD").add_child(slider)
	var initial: float = display_initial if display_initial >= 0.0 else current
	slider.setup(stat_name, initial, min_val, max_val)
	slider.value_changed.connect(on_change)
	slider.dismissed.connect(_on_demo_slider_dismissed.bind(slider))
	_active_sliders.append(slider)
	return slider


## Called when any demo slider's "Set" is clicked. Player keeps the value.
func _on_demo_slider_dismissed(which: TutorialSlider) -> void:
	if is_instance_valid(which):
		which.visible = false
	_demo_dismiss_remaining -= 1
	if _demo_dismiss_remaining <= 0:
		_update_tutorial_stats_display()
		_pop_teardown()
		_free_all_sliders()
		if _demo_advance_callback.is_valid():
			_demo_advance_callback.call()


# ── Stats display helpers ────────────────────────────────────────────

## Convert internal speed (1.0-5.0) to display value (0-100).
func _speed_to_display(speed: float) -> int:
	return roundi((speed - 1.0) / 4.0 * 100.0)


## Push current throw_mechanic stats to the HUD stat bars.
func _update_tutorial_stats_display() -> void:
	var current: Dictionary = {
		"horizontal_range": throw_mechanic.horizontal_range,
		"vertical_range": throw_mechanic.vertical_range,
		"vertical_accuracy": throw_mechanic.vertical_accuracy,
		"horizontal_accuracy": throw_mechanic.horizontal_accuracy,
		"vertical_speed": throw_mechanic.vertical_speed,
		"horizontal_speed": throw_mechanic.horizontal_speed,
	}
	hud.update_stats(current, _base_stats)


## Restore all stats to their pre-tutorial values from the base snapshot.
func _restore_base_stats() -> void:
	if throw_mechanic == null or _base_stats.is_empty():
		return
	for stat_name: String in _base_stats:
		throw_mechanic.set(stat_name, _base_stats[stat_name])
	throw_mechanic.recompute_aim_dimensions()
	throw_mechanic.queue_redraw()


# ── Teardown stack for skip cleanup ───────────────────────────────────

func _push_teardown(callback: Callable) -> void:
	_teardown_stack.append(callback)


func _pop_teardown() -> void:
	if _teardown_stack.size() > 0:
		_teardown_stack.pop_back()


func _run_all_teardowns() -> void:
	for callback: Callable in _teardown_stack:
		if callback.is_valid():
			callback.call()
	_teardown_stack.clear()


# ── Start / Stop ──────────────────────────────────────────────────────

## Start the mechanics tutorial from the given entry source.
func start_mechanics_tutorial(source: String, mode: TutorialMode = TutorialMode.FULL) -> void:
	entry_source = source
	_tutorial_mode = mode
	_active = true
	_current_throw = 0
	_waiting_for_next = false
	_waiting_for_throw = false
	_listening_for_h_click = false
	_tutorial_hover_active = false
	_teardown_stack.clear()

	if callout != null:
		if not callout.next_pressed.is_connected(_on_next_pressed):
			callout.next_pressed.connect(_on_next_pressed)
		if not callout.skip_pressed.is_connected(_on_skip):
			callout.skip_pressed.connect(_on_skip)
		if not callout.secondary_pressed.is_connected(_on_secondary_pressed):
			callout.secondary_pressed.connect(_on_secondary_pressed)

	if throw_mechanic != null:
		throw_mechanic.set_tutorial_visual_boost(true)
		if not throw_mechanic.throw_completed.is_connected(_on_tutorial_throw_completed):
			throw_mechanic.throw_completed.connect(_on_tutorial_throw_completed)
		if not throw_mechanic.state_changed.is_connected(_on_state_changed_tutorial):
			throw_mechanic.state_changed.connect(_on_state_changed_tutorial)

	# Snapshot base stats for HUD bar coloring and end-of-tutorial restore
	_base_stats = {
		"horizontal_range": throw_mechanic.horizontal_range,
		"vertical_range": throw_mechanic.vertical_range,
		"vertical_accuracy": throw_mechanic.vertical_accuracy,
		"horizontal_accuracy": throw_mechanic.horizontal_accuracy,
		"vertical_speed": throw_mechanic.vertical_speed,
		"horizontal_speed": throw_mechanic.horizontal_speed,
	}

	# Stats container + bars visible from the start
	if hud != null:
		hud.stats_container.visible = true
		hud.show_all_stat_bars()
		_update_tutorial_stats_display()

	if mode == TutorialMode.STATS_ONLY:
		_show_skip_stats_button()
		_t3_intro()
	else:
		_build_and_run_throw_1()


## Stop the tutorial and clean up.
func stop_tutorial() -> void:
	_active = false
	_waiting_for_next = false
	_waiting_for_throw = false
	_listening_for_h_click = false
	_disable_tutorial_hover()

	_run_all_teardowns()
	_free_all_sliders()
	_hide_skip_stats_button()

	# Restore stats to pre-tutorial values
	_restore_base_stats()

	if throw_mechanic != null:
		throw_mechanic.set_scripted_mode(false)
		throw_mechanic.set_paused(false)
		throw_mechanic.set_input_blocked(false)
		throw_mechanic.set_tutorial_visual_boost(false)
		throw_mechanic.set_tutorial_pulse_target("")
		if throw_mechanic.throw_completed.is_connected(_on_tutorial_throw_completed):
			throw_mechanic.throw_completed.disconnect(_on_tutorial_throw_completed)
		if throw_mechanic.state_changed.is_connected(_on_state_changed_tutorial):
			throw_mechanic.state_changed.disconnect(_on_state_changed_tutorial)

	if callout != null:
		callout.hide_callout()
		callout.set_secondary_action("", false)
		callout.show_skip_button = true
		if callout.next_pressed.is_connected(_on_next_pressed):
			callout.next_pressed.disconnect(_on_next_pressed)
		if callout.skip_pressed.is_connected(_on_skip):
			callout.skip_pressed.disconnect(_on_skip)
		if callout.secondary_pressed.is_connected(_on_secondary_pressed):
			callout.secondary_pressed.disconnect(_on_secondary_pressed)

	if ghost_dart_layer != null:
		ghost_dart_layer.clear_scatter()

	if dartboard != null:
		dartboard.clear_tutorial_highlight()
		dartboard.clear_declared_target()

	if hud != null:
		hud.show_all_stat_bars()


# ── Beat navigation ──────────────────────────────────────────────────

func _set_beat_after_next(beat_name: String) -> void:
	set_meta("_next_beat", beat_name)


func _on_next_pressed() -> void:
	if not _waiting_for_next:
		return
	_waiting_for_next = false

	var beat_name: String = get_meta("_next_beat") if has_meta("_next_beat") else ""
	match beat_name:
		# Throw 1: DISCOVER
		"t1_aim_phase":
			_t1_aim_phase()
		"t1_v_active":
			_t1_v_active()
		"t1_h_active":
			_t1_h_active()
		"t1_scatter":
			_t1_scatter()
		"t1_resolve":
			_t1_resolve()
		# Throw 2: DO
		"t2_free":
			_t2_free()
		# Throw 3: UNDERSTAND (intro reached via Next from transition)
		"t3_intro":
			_t3_intro()
		# Rules hand-off
		"request_rules":
			_request_rules()
		# Finish
		"finish":
			_finish()


# ── Throw mechanic state change handler ──────────────────────────────

func _on_state_changed_tutorial(new_state: int) -> void:
	if not _active:
		return

	# Disable hover tooltip when aim is placed (all throws)
	if new_state == throw_mechanic.ThrowState.VERTICAL_RELEASE:
		_disable_tutorial_hover()

	if _current_throw == 1:
		match new_state:
			throw_mechanic.ThrowState.VERTICAL_RELEASE:
				# Don't pause — let V meter bounce visibly during explanation
				throw_mechanic.set_input_blocked(true)
				_t1_aim_placed()
			throw_mechanic.ThrowState.HORIZONTAL_RELEASE:
				# Don't pause — let H meter bounce visibly during explanation
				throw_mechanic.set_input_blocked(true)
				_t1_v_stopped()

	elif _current_throw == 2:
		if new_state == throw_mechanic.ThrowState.VERTICAL_RELEASE:
			var target: Dictionary = throw_mechanic._declared_target
			if not target.is_empty():
				dartboard.set_declared_target(target)

	elif _current_throw == 3:
		match new_state:
			throw_mechanic.ThrowState.VERTICAL_RELEASE:
				_t3_target_selected()
			throw_mechanic.ThrowState.HORIZONTAL_RELEASE:
				throw_mechanic.set_paused(true)
				_t3_v_stopped()


# ── H meter click intercept ─────────────────────────────────────────
# During throws 1 and 3, the H meter runs with input_blocked so normal
# clicks don't trigger a resolve. Instead we catch clicks here, record
# the meter position, pause, and show the explanation before resolving.

func _unhandled_input(event: InputEvent) -> void:
	if not _active or not _listening_for_h_click:
		return
	var is_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var is_space: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE
	if is_click or is_space:
		_capture_h_meter()
		get_viewport().set_input_as_handled()


func _capture_h_meter() -> void:
	_h_meter_captured_t = throw_mechanic._horizontal_bounce_t
	_listening_for_h_click = false
	throw_mechanic.set_paused(true)
	throw_mechanic.set_input_blocked(false)

	if _current_throw == 1:
		_t1_h_stopped()
	elif _current_throw == 3:
		_t3_h_stopped()


# ── Throw completed handler ──────────────────────────────────────────

func _on_tutorial_throw_completed(hit_position: Vector2) -> void:
	if not _active:
		return
	# Route through main's shared anticipation fly-in so tutorial throws match the real
	# game. The tutorial marker is yellow (see _place_tutorial_dart), so the flyer uses
	# the same colors for a seamless hand-off. on_landed runs the rest at impact.
	var main: Node = get_parent()
	if main != null and main.has_method("play_throw_anticipation"):
		main.play_throw_anticipation(hit_position, Color(0.9, 0.85, 0.0), Color(0.2, 0.2, 0.2), _resolve_tutorial_throw.bind(hit_position))
	else:
		_resolve_tutorial_throw(hit_position)


## Tutorial landing flow: place the marker, then advance the tutorial beat.
func _resolve_tutorial_throw(hit_position: Vector2) -> void:
	_place_tutorial_dart(hit_position)

	if _current_throw == 1:
		_on_throw_1_completed()
	elif _current_throw == 2:
		_on_throw_2_completed()
	elif _current_throw == 3:
		_on_throw_3_completed()


# ── Throw 1: DISCOVER ────────────────────────────────────────────────
# The player makes their first throw with freeze-and-explain at each
# stage transition. Meters bounce live during explanations so the player
# can see the marker moving while they read.

func _build_and_run_throw_1() -> void:
	_current_throw = 1
	callout.show_callout(tutorial_strings["t1_welcome"], callout_position)
	callout.set_next_text("Let's go")
	_waiting_for_next = true
	_set_beat_after_next("t1_aim_phase")


func _t1_aim_phase() -> void:
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
	_enable_tutorial_hover()
	callout.show_callout(tutorial_strings["t1_aim"], callout_position)
	callout.set_next_visible(false)
	# Player clicks to place aim → state_changed(VERTICAL_RELEASE) → _t1_aim_placed


func _t1_aim_placed() -> void:
	var target: Dictionary = throw_mechanic._declared_target
	dartboard.set_declared_target(target)
	# V meter is already bouncing (state handler didn't pause), input is blocked
	var target_name: String = _get_target_display_name(target)
	var text: String = tutorial_strings["t1_aim_placed"].format({"target": target_name})
	callout.show_callout(text, callout_position)
	callout.set_next_visible(true)
	callout.set_next_text("Next")
	_waiting_for_next = true
	_set_beat_after_next("t1_v_active")


func _t1_v_active() -> void:
	# Meter is already bouncing — just unblock input so the player can stop it
	throw_mechanic.set_input_blocked(false)
	callout.hide_callout()
	# V meter bounces, player clicks → state_changed(HORIZONTAL_RELEASE) → _t1_v_stopped


func _t1_v_stopped() -> void:
	# H meter is already bouncing (state handler didn't pause), input is blocked
	callout.show_callout(tutorial_strings["t1_v_stopped"], callout_position)
	callout.set_next_visible(true)
	callout.set_next_text("Next")
	_waiting_for_next = true
	_set_beat_after_next("t1_h_active")


func _t1_h_active() -> void:
	# Meter is already bouncing and input is already blocked — redirect clicks to our interceptor
	_listening_for_h_click = true
	callout.hide_callout()
	# H meter bounces with input blocked; player click intercepted → _capture_h_meter → _t1_h_stopped


func _t1_h_stopped() -> void:
	throw_mechanic.set_tutorial_pulse_target("accuracy_zone")
	callout.show_callout(tutorial_strings["t1_h_stopped"], callout_position)
	callout.set_next_visible(true)
	callout.set_next_text("Next")
	_waiting_for_next = true
	_set_beat_after_next("t1_scatter")


func _t1_scatter() -> void:
	var locked_y: float = throw_mechanic._locked_release_y
	var h_x: float = throw_mechanic._horizontal_x
	var release_pos: Vector2 = Vector2(h_x, locked_y)
	var points: Array[Vector2] = throw_mechanic.sample_scatter_points(release_pos, 10, 42)
	ghost_dart_layer.show_scatter(points)
	callout.show_callout(tutorial_strings["t1_scatter"], callout_position)
	callout.set_next_visible(true)
	callout.set_next_text("Next")
	_waiting_for_next = true
	_set_beat_after_next("t1_resolve")


func _t1_resolve() -> void:
	ghost_dart_layer.clear_scatter()
	throw_mechanic.set_tutorial_pulse_target("")
	callout.hide_callout()
	throw_mechanic.set_paused(false)
	throw_mechanic.force_lock_horizontal(sin(_h_meter_captured_t))
	# throw_completed fires → _on_tutorial_throw_completed → _on_throw_1_completed


func _on_throw_1_completed() -> void:
	dartboard.clear_declared_target()
	get_tree().create_timer(0.8).timeout.connect(_start_throw_2)


# ── Throw 2: DO ──────────────────────────────────────────────────────
# The player throws without interruption.

func _start_throw_2() -> void:
	_current_throw = 2
	callout.show_callout(tutorial_strings["t2_intro"], callout_position)
	callout.set_next_text("I've got it")
	callout.set_next_visible(true)
	_waiting_for_next = true
	_set_beat_after_next("t2_free")


func _t2_free() -> void:
	callout.hide_callout()
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
	_enable_tutorial_hover()
	_waiting_for_throw = true
	# No intercepts — throw completes normally → _on_throw_2_completed


func _on_throw_2_completed() -> void:
	_waiting_for_throw = false
	dartboard.clear_declared_target()
	_t2_transition()


func _t2_transition() -> void:
	_show_skip_stats_button()
	callout.show_skip_button = false
	callout.show_callout(tutorial_strings["t2_transition"], callout_position)
	callout.set_next_text("Continue")
	callout.set_next_visible(true)
	_waiting_for_next = true
	_set_beat_after_next("t3_intro")


# ── Throw 3: UNDERSTAND ──────────────────────────────────────────────
# The stats walkthrough. Slider demos let the player set stat values
# they'll actually throw with. Stats restore on tutorial finish/skip.

func _t3_intro() -> void:
	_current_throw = 3
	callout.show_skip_button = false
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
	_enable_tutorial_hover()
	callout.show_callout(tutorial_strings["t3_intro"], callout_position)
	callout.set_next_visible(false)
	# Player clicks to place aim → state_changed(VERTICAL_RELEASE) → _t3_target_selected


func _t3_target_selected() -> void:
	var target: Dictionary = throw_mechanic._declared_target
	dartboard.set_declared_target(target)

	# V Range + V Speed slider demo — V meter bounces live so the player
	# can see range and speed interact in real time
	throw_mechanic.set_input_blocked(true)
	callout.show_callout(tutorial_strings["t3_v_range_speed"], callout_position)
	callout.set_next_visible(false)

	_create_demo_slider("V Range", "vertical_range", demo_v_range_min, demo_v_range_max, 0,
		func(val: float) -> void:
			throw_mechanic.vertical_range = val
			throw_mechanic.recompute_aim_dimensions()
			throw_mechanic.queue_redraw()
			_update_tutorial_stats_display()
	)
	_create_demo_slider("V Speed", "vertical_speed", demo_v_speed_min, demo_v_speed_max, 1,
		func(val: float) -> void:
			throw_mechanic.vertical_speed = val / 100.0 * 4.0 + 1.0
			_update_tutorial_stats_display(),
		float(_speed_to_display(throw_mechanic.vertical_speed))
	)

	_demo_dismiss_remaining = 2
	_demo_advance_callback = func() -> void:
		_t3_v_active()

	_push_teardown(func() -> void:
		_free_all_sliders()
		throw_mechanic.set_input_blocked(false)
	)


func _t3_v_active() -> void:
	# Meter is already bouncing — just unblock input so the player can stop it
	throw_mechanic.set_input_blocked(false)
	callout.show_callout(tutorial_strings["t3_v_meter"], callout_position)
	callout.set_next_visible(false)
	# V meter bounces, player clicks → state_changed(HORIZONTAL_RELEASE) → _t3_v_stopped


func _t3_v_stopped() -> void:
	# H Range + H Speed slider demo — H meter bounces live
	throw_mechanic.set_paused(false)
	throw_mechanic.set_input_blocked(true)
	callout.show_callout(tutorial_strings["t3_h_range_speed"], callout_position)
	callout.set_next_visible(false)

	_create_demo_slider("H Range", "horizontal_range", demo_h_range_min, demo_h_range_max, 0,
		func(val: float) -> void:
			throw_mechanic.horizontal_range = val
			throw_mechanic.recompute_aim_dimensions()
			throw_mechanic.queue_redraw()
			_update_tutorial_stats_display()
	)
	_create_demo_slider("H Speed", "horizontal_speed", demo_h_speed_min, demo_h_speed_max, 1,
		func(val: float) -> void:
			throw_mechanic.horizontal_speed = val / 100.0 * 4.0 + 1.0
			_update_tutorial_stats_display(),
		float(_speed_to_display(throw_mechanic.horizontal_speed))
	)

	_demo_dismiss_remaining = 2
	_demo_advance_callback = func() -> void:
		_t3_h_active()

	_push_teardown(func() -> void:
		_free_all_sliders()
		throw_mechanic.set_input_blocked(false)
	)


func _t3_h_active() -> void:
	# Meter is already bouncing and input is already blocked from the H demo
	_listening_for_h_click = true
	callout.show_callout(tutorial_strings["t3_h_meter"], callout_position)
	callout.set_next_visible(false)
	# H meter bounces with input blocked; accuracy zone breathes as meter sweeps.
	# Player click intercepted → _capture_h_meter → _t3_h_stopped


func _t3_h_stopped() -> void:
	throw_mechanic.set_tutorial_pulse_target("accuracy_zone")

	var locked_y: float = throw_mechanic._locked_release_y
	var h_x: float = throw_mechanic._horizontal_x
	var release_pos: Vector2 = Vector2(h_x, locked_y)

	# V Accuracy + H Accuracy sliders with live scatter
	var initial_points: Array[Vector2] = throw_mechanic.sample_scatter_points(release_pos, 10, accuracy_demo_scatter_seed)
	ghost_dart_layer.show_scatter(initial_points)

	callout.show_callout(tutorial_strings["t3_accuracy"], callout_position)
	callout.set_next_visible(false)

	_create_demo_slider("V Accuracy", "vertical_accuracy", demo_v_accuracy_min, demo_v_accuracy_max, 0,
		func(val: float) -> void:
			throw_mechanic.vertical_accuracy = val
			var new_points: Array[Vector2] = throw_mechanic.sample_scatter_points(release_pos, 10, accuracy_demo_scatter_seed)
			ghost_dart_layer.show_scatter(new_points)
			throw_mechanic.queue_redraw()
			_update_tutorial_stats_display()
	)
	_create_demo_slider("H Accuracy", "horizontal_accuracy", demo_h_accuracy_min, demo_h_accuracy_max, 1,
		func(val: float) -> void:
			throw_mechanic.horizontal_accuracy = val
			var new_points: Array[Vector2] = throw_mechanic.sample_scatter_points(release_pos, 10, accuracy_demo_scatter_seed)
			ghost_dart_layer.show_scatter(new_points)
			throw_mechanic.queue_redraw()
			_update_tutorial_stats_display()
	)

	_demo_dismiss_remaining = 2
	_demo_advance_callback = func() -> void:
		ghost_dart_layer.clear_scatter()
		throw_mechanic.set_tutorial_pulse_target("")
		_t3_resolve()

	_push_teardown(func() -> void:
		ghost_dart_layer.clear_scatter()
		_free_all_sliders()
	)


func _t3_resolve() -> void:
	callout.hide_callout()
	throw_mechanic.set_paused(false)
	throw_mechanic.force_lock_horizontal(sin(_h_meter_captured_t))
	# throw_completed fires → _on_tutorial_throw_completed → _on_throw_3_completed


func _on_throw_3_completed() -> void:
	dartboard.clear_declared_target()
	_t3_complete()


func _t3_complete() -> void:
	_hide_skip_stats_button()
	callout.show_callout(tutorial_strings["t3_complete"], callout_position)
	callout.set_next_text("Learn the rules")
	callout.set_next_visible(true)
	callout.set_secondary_action("Play", true)
	callout.show_skip_button = false
	_waiting_for_next = true
	_set_beat_after_next("request_rules")


# ── Finish / Skip ────────────────────────────────────────────────────

func _finish() -> void:
	stop_tutorial()
	if entry_source == "assembly":
		tutorial_finished.emit("assembly")
	else:
		tutorial_finished.emit("start_screen")


func _on_skip() -> void:
	stop_tutorial()
	if entry_source == "assembly":
		tutorial_finished.emit("assembly")
	else:
		tutorial_finished.emit("start_screen")


func _on_secondary_pressed() -> void:
	if not _waiting_for_next:
		return
	_waiting_for_next = false
	_finish()


func _request_rules() -> void:
	var dest: String = "assembly" if entry_source == "assembly" else "start_screen"
	stop_tutorial()
	request_rules.emit(dest)


# ── Skip Stats Walkthrough button (Phase 3) ──────────────────────────

func _show_skip_stats_button() -> void:
	if _skip_stats_button != null:
		_skip_stats_button.visible = true
		return
	_skip_stats_button = Button.new()
	_skip_stats_button.text = "Skip Stats Walkthrough"
	_skip_stats_button.add_theme_font_size_override("font_size", 14)
	_skip_stats_button.position = Vector2(16.0, 16.0)
	_skip_stats_button.custom_minimum_size = Vector2(200.0, 32.0)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.85)
	style.border_color = Color(0.5, 0.5, 0.6, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	_skip_stats_button.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(0.2, 0.2, 0.28, 0.9)
	hover_style.border_color = Color(0.6, 0.6, 0.7, 0.8)
	_skip_stats_button.add_theme_stylebox_override("hover", hover_style)

	_skip_stats_button.pressed.connect(_on_skip_stats)
	get_parent().get_node("HUD").add_child(_skip_stats_button)


func _hide_skip_stats_button() -> void:
	if _skip_stats_button != null:
		_skip_stats_button.visible = false


func _on_skip_stats() -> void:
	stop_tutorial()
	if entry_source == "assembly":
		tutorial_finished.emit("assembly")
	else:
		tutorial_finished.emit("start_screen")


# ── Helpers ──────────────────────────────────────────────────────────

func _get_target_display_name(target: Dictionary) -> String:
	if target.is_empty():
		return "the board"
	var ring: String = target.get("ring_name", "")
	if target.get("is_bull", false):
		return ring
	var face: int = target.get("face_value", 0)
	return "%s %d" % [ring, face]


func _place_tutorial_dart(hit_position: Vector2) -> void:
	AuidoManager.play_dart_thunk()
	var dart: Node2D = Node2D.new()
	dart.position = hit_position
	dart.set_script(preload("res://scripts/dart_marker.gd"))
	dart.set("dart_color", Color(0.9, 0.85, 0.0))
	dart.set("dart_inner_color", Color(0.2, 0.2, 0.2))
	dart.set("dart_size", 5.0)
	var dart_container: Node2D = get_parent().get_node_or_null("DartContainer")
	if dart_container != null:
		dart_container.add_child(dart)
