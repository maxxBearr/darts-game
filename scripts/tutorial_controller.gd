class_name TutorialController
extends Node
## Orchestrates the mechanics tutorial: a 3-throw sandbox walkthrough that teaches
## the throw mechanic and stats through demo, guided, and free throws.
## Owns the beat sequence and drives throw_mechanic's scripted mode.
##
## Phase A (shipped): 3-throw walkthrough with freeze-and-explain at accuracy zones.
## Phase B (added): Progressive stat-bar reveals and three interactive slider demos
## (Range, Speed, Accuracy) woven into throw 1. Tutorial uses the player's actual
## build stats — no special tutorial values. Assumes throw_mechanic stats are
## pre-configured by main.gd before the tutorial starts.

signal tutorial_finished(destination: String)

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

## Default callout panel position (right side of screen, vertically centered).
@export var callout_position: Vector2 = Vector2(1020.0, 360.0)

## Callout position for the guided throw banner (top of screen).
@export var banner_position: Vector2 = Vector2(640.0, 80.0)

## Whether the demo throw targets the bullseye (true) or a wedge segment (false).
@export var demo_target_bullseye: bool = true

## Target wedge index for the demo throw (only used if demo_target_bullseye is false).
@export var demo_target_wedge: int = 0

## Target ring for the demo throw (only used if demo_target_bullseye is false).
@export var demo_target_ring: String = "Outer Single"

## Duration of the stat bar fade-in animation in seconds.
@export var stat_reveal_fade_duration: float = 0.4

## Slider demo: H Range min value.
@export var demo_h_range_min: float = 20.0

## Slider demo: H Range max value.
@export var demo_h_range_max: float = 90.0

## Slider demo: H Speed min value.
@export var demo_h_speed_min: float = 1.0

## Slider demo: H Speed max value.
@export var demo_h_speed_max: float = 5.0

## Slider demo: H Accuracy min value.
@export var demo_h_accuracy_min: float = 20.0

## Slider demo: H Accuracy max value.
@export var demo_h_accuracy_max: float = 80.0

## Position of the slider widget on screen.
@export var slider_position: Vector2 = Vector2(1020.0, 540.0)

## Fixed RNG seed for accuracy demo scatter (ensures consistent visual).
@export var accuracy_demo_scatter_seed: int = 99

## Tunable tutorial caption strings. Keyed by beat name.
@export var tutorial_strings: Dictionary = {
	"welcome": "Welcome to the tutorial! We'll walk you through how throwing works — three quick throws and you'll have it down.",
	"intro": "We'll throw at the bullseye.",
	"aim_crosshair": "This is your [b]aim crosshair[/b]. Where your dart can possibly end up after the meters resolve. Bigger crosshair = wider range of outcomes.",
	"reveal_range": "These two stats — [b]H Range[/b] and [b]V Range[/b] — control the size of your aim crosshair. Higher Range = smaller crosshair = more precise aim.",
	"demo_range": "Try it — drag the sliders and watch the crosshair change. Each axis controls one dimension of the crosshair.",
	"ideal_aim": "The center of your target is the ideal spot. Time the meters to land as close to it as possible.",
	"lock_vertical": "First you lock your [b]vertical[/b] position.",
	"reveal_v_speed": "[b]V Speed[/b] controls how fast the vertical marker bounces. Higher = slower = easier to time.",
	"reveal_h_speed": "[b]H Speed[/b] is the same idea for the horizontal marker.",
	"demo_speed": "Drag to feel how speed and range interact. Slower meter = more time to react. Tighter range = less distance to cover.",
	"green_zone": "When timed closer to your chosen target (double bullseye), your scatter shrinks.",
	"reveal_accuracy": "[b]H Accuracy[/b] and [b]V Accuracy[/b] set your base scatter size. Where you lock on the meters then modifies it — closer to the centroid shrinks the scatter, farther bloats it.",
	"orange_zone": "When timed near it, No bonus, no penalty. Default scatter shape.",
	"red_zone": "Far from the chosen target, your dart sprays wider, leaving more up to random chance.",
	"demo_accuracy": "Watch the scatter shrink and grow. Tighter accuracy = your darts land closer together. [b]V Accuracy[/b] does the same for vertical spread.",
	"throw_complete": "That's the full throw. The colored zones on the H meter show you where green / orange / red are.",
	"guided_banner": "Try to lock the H meter in the [b]green[/b] zone.",
	"guided_green": "Green zone — your dart clustered tight!",
	"guided_orange": "Orange zone — neutral scatter.",
	"guided_red": "Red zone — your dart sprayed wider.",
	"free_finish": "That's it. The same loop runs every throw of a real game. Ready to play?",
}

# Internal state
var _active: bool = false
var _current_throw: int = 0
var _waiting_for_next: bool = false
var _waiting_for_throw: bool = false
var _h_freeze_queue: Array[String] = []
var _h_freeze_index: int = 0
var _guided_mode: bool = false
var _free_mode: bool = false

# B3: active slider widgets (empty when no demo is running)
var _active_sliders: Array[TutorialSlider] = []

# B3: how many slider "Got it" dismissals remain before advancing
var _demo_dismiss_remaining: int = 0

# B3: callback to run when all sliders in a demo are dismissed
var _demo_advance_callback: Callable

# B4: teardown callbacks for skip cleanup
var _teardown_stack: Array[Callable] = []

# B1: stat snapshots for slider demos {stat_name: saved_value}
var _demo_snapshots: Dictionary = {}


## Whether the tutorial is currently active.
func is_active() -> bool:
	return _active


# ── B1: Stat snapshot/restore ─────────────────────────────────────────────

## Snapshot a single throw_mechanic stat before a slider demo mutates it.
func _snapshot_stat(stat_name: String) -> float:
	var value: float = throw_mechanic.get(stat_name)
	_demo_snapshots[stat_name] = value
	return value


## Restore a previously snapshotted stat on throw_mechanic.
func _restore_stat(stat_name: String, value: float) -> void:
	throw_mechanic.set(stat_name, value)
	throw_mechanic.queue_redraw()


## Restore all snapshotted stats and clear the snapshot dict.
func _restore_all_snapshots() -> void:
	for stat_name: String in _demo_snapshots:
		throw_mechanic.set(stat_name, _demo_snapshots[stat_name])
	_demo_snapshots.clear()
	throw_mechanic.recompute_aim_dimensions()
	throw_mechanic.queue_redraw()


## Remove all active sliders from the scene.
func _free_all_sliders() -> void:
	for slider: TutorialSlider in _active_sliders:
		if is_instance_valid(slider):
			slider.queue_free()
	_active_sliders.clear()


## Create a slider for a stat demo, positioned vertically based on index.
## Returns the slider instance. Connects value_changed to the given callback.
## Vertical spacing: first slider at slider_position.y, subsequent ones offset by 120px.
func _create_demo_slider(stat_name: String, stat_property: String, min_val: float, max_val: float, index: int, on_change: Callable) -> TutorialSlider:
	var saved: float = _snapshot_stat(stat_property)
	var slider: TutorialSlider = TutorialSlider.new()
	var y_offset: float = float(index) * 120.0
	slider.widget_position = Vector2(slider_position.x, slider_position.y + y_offset)
	get_parent().get_node("HUD").add_child(slider)
	slider.setup(stat_name, saved, min_val, max_val)
	slider.value_changed.connect(on_change)
	slider.dismissed.connect(_on_demo_slider_dismissed.bind(slider))
	_active_sliders.append(slider)
	return slider


## Called when any demo slider's "Got it" is clicked. Hides that slider
## and advances the tutorial when all sliders in the demo have been dismissed.
func _on_demo_slider_dismissed(which: TutorialSlider) -> void:
	if is_instance_valid(which):
		which.visible = false
	_demo_dismiss_remaining -= 1
	if _demo_dismiss_remaining <= 0:
		_restore_all_snapshots()
		_pop_teardown()
		_free_all_sliders()
		if _demo_advance_callback.is_valid():
			_demo_advance_callback.call()


# ── B4: Teardown stack for skip cleanup ───────────────────────────────────

## Register a teardown callback to run if the player skips mid-demo.
func _push_teardown(callback: Callable) -> void:
	_teardown_stack.append(callback)


## Pop and discard the most recent teardown (called on normal demo dismiss).
func _pop_teardown() -> void:
	if _teardown_stack.size() > 0:
		_teardown_stack.pop_back()


## Run all teardown callbacks (called on skip).
func _run_all_teardowns() -> void:
	for callback: Callable in _teardown_stack:
		if callback.is_valid():
			callback.call()
	_teardown_stack.clear()


# ── Start / Stop ──────────────────────────────────────────────────────────

## Start the mechanics tutorial from the given entry source.
func start_mechanics_tutorial(source: String) -> void:
	entry_source = source
	_active = true
	_current_throw = 0
	_waiting_for_next = false
	_waiting_for_throw = false
	_guided_mode = false
	_free_mode = false
	_teardown_stack.clear()

	if callout != null:
		if not callout.next_pressed.is_connected(_on_next_pressed):
			callout.next_pressed.connect(_on_next_pressed)
		if not callout.skip_pressed.is_connected(_on_skip):
			callout.skip_pressed.connect(_on_skip)

	if throw_mechanic != null:
		throw_mechanic.set_tutorial_visual_boost(true)
		if not throw_mechanic.throw_completed.is_connected(_on_tutorial_throw_completed):
			throw_mechanic.throw_completed.connect(_on_tutorial_throw_completed)

	# B2: hide all stat bars at start — they'll be revealed progressively
	if hud != null:
		var all_keys: Array[String] = ["horizontal_range", "vertical_range", "horizontal_speed", "vertical_speed", "horizontal_accuracy", "vertical_accuracy"]
		hud.set_stat_bar_visibility(all_keys, false)
		hud.set_stats_title_visible(false)

	_build_and_run_throw_1()


## Stop the tutorial and clean up.
func stop_tutorial() -> void:
	_active = false
	_waiting_for_next = false
	_waiting_for_throw = false
	_guided_mode = false
	_free_mode = false

	# B4: run any pending teardowns (slider cleanup, stat restore)
	_run_all_teardowns()

	# Remove active sliders
	_free_all_sliders()

	if throw_mechanic != null:
		throw_mechanic.set_scripted_mode(false)
		throw_mechanic.set_paused(false)
		throw_mechanic.set_input_blocked(false)
		throw_mechanic.set_tutorial_visual_boost(false)
		throw_mechanic.set_tutorial_pulse_target("")
		if throw_mechanic.throw_completed.is_connected(_on_tutorial_throw_completed):
			throw_mechanic.throw_completed.disconnect(_on_tutorial_throw_completed)

	if callout != null:
		callout.hide_callout()
		if callout.next_pressed.is_connected(_on_next_pressed):
			callout.next_pressed.disconnect(_on_next_pressed)
		if callout.skip_pressed.is_connected(_on_skip):
			callout.skip_pressed.disconnect(_on_skip)

	if ghost_dart_layer != null:
		ghost_dart_layer.clear_scatter()

	if dartboard != null:
		dartboard.clear_tutorial_highlight()
		dartboard.clear_declared_target()

	# B2: restore all stat bars on exit
	if hud != null:
		hud.show_all_stat_bars()


# ── Beat navigation ──────────────────────────────────────────────────────

func _set_beat_after_next(beat_name: String) -> void:
	set_meta("_next_beat", beat_name)


func _on_next_pressed() -> void:
	if not _waiting_for_next:
		return
	_waiting_for_next = false

	var beat_name: String = get_meta("_next_beat") if has_meta("_next_beat") else ""
	match beat_name:
		# Phase A beats
		"intro_target":
			_show_intro_target()
		"aim_place":
			_throw1_place_aim()
		"aim_explain":
			_throw1_explain_ideal()
		"vertical_lock":
			_throw1_lock_vertical()
		"h_freeze_start":
			_throw1_start_h_freezes()
		"h_freeze_next":
			_throw1_next_h_freeze()
		"h_resume":
			_throw1_resume_h()
		"guided_start":
			_start_throw_2_guided()
		"free_start":
			_start_throw_3_free()
		"finish_play":
			_finish_to_assembly()
		"finish_start":
			_finish_to_start()
		# Phase B beats
		"reveal_range":
			_beat_reveal_range()
		"demo_range":
			_beat_demo_range()
		"reveal_v_speed":
			_beat_reveal_v_speed()
		"reveal_h_speed":
			_beat_reveal_h_speed()
		"demo_speed":
			_beat_demo_speed()
		"reveal_accuracy":
			_beat_reveal_accuracy()
		"demo_accuracy":
			_beat_demo_accuracy()


# ── Throw 1: Demo with progressive stat reveals and slider demos ─────────
# Beat order: welcome → intro → aim_place → reveal_range → demo_range →
# explain ideal → lock vertical → reveal_v_speed → reveal_h_speed + demo_speed →
# h_freeze(green) → reveal_accuracy → h_freeze(orange) → h_freeze(red) →
# demo_accuracy → resume_h → throw_complete

func _build_and_run_throw_1() -> void:
	_current_throw = 1
	callout.show_callout(tutorial_strings["welcome"], callout_position)
	callout.set_next_text("Let's go")
	_waiting_for_next = true
	_set_beat_after_next("intro_target")


func _show_intro_target() -> void:
	var target_centroid: Vector2 = _get_demo_centroid()
	callout.show_callout(tutorial_strings["intro"], callout_position, target_centroid)
	callout.set_next_text("Next")
	_waiting_for_next = true
	_set_beat_after_next("aim_place")


func _get_demo_centroid() -> Vector2:
	if demo_target_bullseye:
		return dartboard.global_position
	return dartboard.get_segment_centroid(demo_target_wedge, demo_target_ring)


func _get_demo_target_result() -> Dictionary:
	if demo_target_bullseye:
		return dartboard.calculate_score(dartboard.global_position)
	var centroid: Vector2 = dartboard.get_segment_centroid(demo_target_wedge, demo_target_ring)
	return dartboard.calculate_score(centroid)


func _throw1_place_aim() -> void:
	var target_centroid: Vector2 = _get_demo_centroid()
	var target_result: Dictionary = _get_demo_target_result()

	throw_mechanic.set_scripted_mode(true)
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
	throw_mechanic.force_lock_aim(target_centroid, target_result)
	throw_mechanic.set_paused(true)
	throw_mechanic.set_tutorial_pulse_target("aim_crosshair")

	dartboard.set_declared_target(target_result)

	callout.show_callout(tutorial_strings["aim_crosshair"], callout_position)
	_waiting_for_next = true
	# Phase B: next beat reveals range stats instead of going straight to explain ideal
	_set_beat_after_next("reveal_range")


# ── B2: Range reveal + B3: Range demo ────────────────────────────────────

func _beat_reveal_range() -> void:
	# Show stats title and range bars
	if hud != null:
		hud.set_stats_title_visible(true)
		var range_keys: Array[String] = ["horizontal_range", "vertical_range"]
		hud.fade_in_stat_bars(range_keys, stat_reveal_fade_duration)

	callout.show_callout(tutorial_strings["reveal_range"], callout_position)
	_waiting_for_next = true
	_set_beat_after_next("demo_range")


func _beat_demo_range() -> void:
	_create_demo_slider("H Range", "horizontal_range", demo_h_range_min, demo_h_range_max, 0,
		func(val: float) -> void:
			throw_mechanic.horizontal_range = val
			throw_mechanic.recompute_aim_dimensions()
	)
	_create_demo_slider("V Range", "vertical_range", demo_h_range_min, demo_h_range_max, 1,
		func(val: float) -> void:
			throw_mechanic.vertical_range = val
			throw_mechanic.recompute_aim_dimensions()
	)

	_demo_dismiss_remaining = 2
	_demo_advance_callback = func() -> void:
		_waiting_for_next = true
		_set_beat_after_next("aim_explain")
		_on_next_pressed()

	_push_teardown(func() -> void:
		_restore_all_snapshots()
		_free_all_sliders()
	)

	callout.show_callout(tutorial_strings["demo_range"], callout_position)
	callout.set_next_visible(false)


# ── Continue Phase A beats ────────────────────────────────────────────────

func _throw1_explain_ideal() -> void:
	throw_mechanic.set_tutorial_pulse_target("")
	callout.set_next_visible(true)
	var target_centroid: Vector2 = _get_demo_centroid()
	callout.show_callout(tutorial_strings["ideal_aim"], callout_position, target_centroid)
	_waiting_for_next = true
	_set_beat_after_next("vertical_lock")


func _throw1_lock_vertical() -> void:
	throw_mechanic.set_paused(false)
	throw_mechanic.force_lock_vertical(0.1)
	throw_mechanic.set_paused(true)
	throw_mechanic.set_tutorial_pulse_target("vertical_band")

	callout.show_callout(tutorial_strings["lock_vertical"], callout_position)
	_waiting_for_next = true
	# Phase B: reveal V Speed next
	_set_beat_after_next("reveal_v_speed")


# ── B2: V Speed reveal ───────────────────────────────────────────────────

func _beat_reveal_v_speed() -> void:
	throw_mechanic.set_tutorial_pulse_target("")
	if hud != null:
		var v_speed_keys: Array[String] = ["vertical_speed"]
		hud.fade_in_stat_bars(v_speed_keys, stat_reveal_fade_duration)

	callout.show_callout(tutorial_strings["reveal_v_speed"], callout_position)
	_waiting_for_next = true
	# Phase B: reveal H Speed + demo next (before starting H freezes)
	_set_beat_after_next("reveal_h_speed")


# ── B2: H Speed reveal + B3: Speed demo ──────────────────────────────────

func _beat_reveal_h_speed() -> void:
	if hud != null:
		var h_speed_keys: Array[String] = ["horizontal_speed"]
		hud.fade_in_stat_bars(h_speed_keys, stat_reveal_fade_duration)

	callout.show_callout(tutorial_strings["reveal_h_speed"], callout_position)
	_waiting_for_next = true
	_set_beat_after_next("demo_speed")


func _beat_demo_speed() -> void:
	# Unpause the H meter so the marker bounces, but block player commits
	throw_mechanic.set_paused(false)
	throw_mechanic.set_scripted_mode(false)
	throw_mechanic.set_input_blocked(true)

	_create_demo_slider("H Speed", "horizontal_speed", demo_h_speed_min, demo_h_speed_max, 0,
		func(val: float) -> void:
			throw_mechanic.horizontal_speed = val
	)
	_create_demo_slider("H Range", "horizontal_range", demo_h_range_min, demo_h_range_max, 1,
		func(val: float) -> void:
			throw_mechanic.horizontal_range = val
			throw_mechanic.recompute_aim_dimensions()
	)

	_demo_dismiss_remaining = 2
	_demo_advance_callback = func() -> void:
		throw_mechanic.set_input_blocked(false)
		throw_mechanic.set_scripted_mode(true)
		throw_mechanic.set_paused(true)
		_throw1_start_h_freezes()

	_push_teardown(func() -> void:
		_restore_all_snapshots()
		throw_mechanic.set_input_blocked(false)
		_free_all_sliders()
	)

	callout.show_callout(tutorial_strings["demo_speed"], callout_position)
	callout.set_next_visible(false)


# ── H meter freeze sequence (Phase A, with B2 accuracy reveal inserted) ──

func _throw1_start_h_freezes() -> void:
	_h_freeze_queue = ["green", "orange", "red"]
	_h_freeze_index = 0
	throw_mechanic.set_tutorial_pulse_target("accuracy_zone")
	callout.set_next_visible(true)
	_throw1_show_h_freeze()


func _throw1_show_h_freeze() -> void:
	if _h_freeze_index >= _h_freeze_queue.size():
		# All three zones shown — go to accuracy demo
		_set_beat_after_next("demo_accuracy")
		_waiting_for_next = true
		callout.show_callout(tutorial_strings["demo_accuracy"], callout_position)
		callout.set_next_visible(false)
		_beat_demo_accuracy()
		return

	var zone: String = _h_freeze_queue[_h_freeze_index]
	var locked_y: float = throw_mechanic._locked_release_y
	var zone_x: float = throw_mechanic.get_zone_midpoint_x(locked_y, zone)

	# Position the H meter at this zone
	var h_half: float = throw_mechanic._h_meter_half_width
	if h_half > 0.0:
		var relative_x: float = (zone_x - throw_mechanic._placed_center.x) / h_half
		relative_x = clampf(relative_x, -1.0, 1.0)
		throw_mechanic.set_horizontal_bounce_t(asin(relative_x))

	# Show ghost dart scatter at this position
	var release_pos: Vector2 = Vector2(zone_x, locked_y)
	var scatter_seed: int = 42 + _h_freeze_index
	var points: Array[Vector2] = throw_mechanic.sample_scatter_points(release_pos, 10, scatter_seed)
	ghost_dart_layer.show_scatter(points)

	# Show the zone-specific caption
	var caption_key: String = zone + "_zone"
	var caption: String = tutorial_strings.get(caption_key, "")
	callout.show_callout(caption, callout_position, Vector2(zone_x, locked_y))
	_waiting_for_next = true

	_h_freeze_index += 1

	# B2: insert accuracy reveal after the green zone beat
	if _h_freeze_index == 1:
		_set_beat_after_next("reveal_accuracy")
	elif _h_freeze_index < _h_freeze_queue.size():
		_set_beat_after_next("h_freeze_next")
	else:
		_set_beat_after_next("h_freeze_next")


# ── B2: Accuracy reveal ──────────────────────────────────────────────────

func _beat_reveal_accuracy() -> void:
	if hud != null:
		var acc_keys: Array[String] = ["horizontal_accuracy", "vertical_accuracy"]
		hud.fade_in_stat_bars(acc_keys, stat_reveal_fade_duration)

	callout.show_callout(tutorial_strings["reveal_accuracy"], callout_position)
	_waiting_for_next = true
	_set_beat_after_next("h_freeze_next")


func _throw1_next_h_freeze() -> void:
	ghost_dart_layer.clear_scatter()
	_throw1_show_h_freeze()


# ── B3: Accuracy demo ────────────────────────────────────────────────────

func _beat_demo_accuracy() -> void:
	ghost_dart_layer.clear_scatter()
	throw_mechanic.set_tutorial_pulse_target("accuracy_zone")

	var locked_y: float = throw_mechanic._locked_release_y
	var demo_x: float = throw_mechanic._horizontal_x
	var release_pos: Vector2 = Vector2(demo_x, locked_y)

	# Show initial scatter
	var initial_points: Array[Vector2] = throw_mechanic.sample_scatter_points(release_pos, 10, accuracy_demo_scatter_seed)
	ghost_dart_layer.show_scatter(initial_points)

	_create_demo_slider("H Accuracy", "horizontal_accuracy", demo_h_accuracy_min, demo_h_accuracy_max, 0,
		func(val: float) -> void:
			throw_mechanic.horizontal_accuracy = val
			var new_points: Array[Vector2] = throw_mechanic.sample_scatter_points(release_pos, 10, accuracy_demo_scatter_seed)
			ghost_dart_layer.show_scatter(new_points)
			throw_mechanic.queue_redraw()
	)

	_demo_dismiss_remaining = 1
	_demo_advance_callback = func() -> void:
		ghost_dart_layer.clear_scatter()
		throw_mechanic.queue_redraw()
		_throw1_resume_h()

	_push_teardown(func() -> void:
		_restore_all_snapshots()
		ghost_dart_layer.clear_scatter()
		_free_all_sliders()
	)

	callout.show_callout(tutorial_strings["demo_accuracy"], callout_position)
	callout.set_next_visible(false)


# ── Resume and complete throw 1 ──────────────────────────────────────────

func _throw1_resume_h() -> void:
	ghost_dart_layer.clear_scatter()
	throw_mechanic.set_tutorial_pulse_target("")

	var locked_y: float = throw_mechanic._locked_release_y
	var orange_x: float = throw_mechanic.get_zone_midpoint_x(locked_y, "orange")
	var h_half: float = throw_mechanic._h_meter_half_width
	if h_half > 0.0:
		var relative_x: float = (orange_x - throw_mechanic._placed_center.x) / h_half
		relative_x = clampf(relative_x, -1.0, 1.0)
		throw_mechanic.set_horizontal_bounce_t(asin(relative_x))

	throw_mechanic.set_paused(false)
	throw_mechanic.set_scripted_mode(false)
	throw_mechanic.force_lock_horizontal(sin(throw_mechanic._horizontal_bounce_t))

	_waiting_for_throw = true
	callout.hide_callout()


func _on_tutorial_throw_completed(hit_position: Vector2) -> void:
	if not _active:
		return
	_place_tutorial_dart(hit_position)

	if _current_throw == 1:
		_on_throw_1_completed()
	elif _current_throw == 2:
		_on_throw_2_completed()
	elif _current_throw == 3:
		_on_throw_3_completed()


func _on_throw_1_completed() -> void:
	_waiting_for_throw = false
	dartboard.clear_declared_target()

	callout.show_callout(tutorial_strings["throw_complete"], callout_position)
	callout.set_next_visible(true)
	_waiting_for_next = true
	_set_beat_after_next("guided_start")


# ── Throw 2: Guided ──────────────────────────────────────────────────────

func _start_throw_2_guided() -> void:
	_current_throw = 2
	_guided_mode = true

	callout.show_callout(tutorial_strings["guided_banner"], banner_position)
	callout.set_next_visible(false)

	throw_mechanic.set_scripted_mode(false)
	throw_mechanic.set_paused(false)
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
	_waiting_for_throw = true


func _on_throw_2_completed() -> void:
	_waiting_for_throw = false
	_guided_mode = false
	dartboard.clear_declared_target()

	var dist: float = throw_mechanic._get_target_distance_normalized()
	var zone_key: String
	if dist <= throw_mechanic.green_zone_threshold:
		zone_key = "guided_green"
	elif dist <= throw_mechanic.penalty_zone_threshold:
		zone_key = "guided_orange"
	else:
		zone_key = "guided_red"

	var caption: String = tutorial_strings.get(zone_key, "")
	callout.show_callout(caption, callout_position)
	callout.set_next_visible(true)
	callout.set_next_text("Next")
	_waiting_for_next = true
	_set_beat_after_next("free_start")


# ── Throw 3: Free ────────────────────────────────────────────────────────

func _start_throw_3_free() -> void:
	_current_throw = 3
	_free_mode = true

	callout.hide_callout()
	throw_mechanic.set_scripted_mode(false)
	throw_mechanic.set_paused(false)
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
	_waiting_for_throw = true


func _on_throw_3_completed() -> void:
	_waiting_for_throw = false
	_free_mode = false
	dartboard.clear_declared_target()

	callout.show_callout(tutorial_strings["free_finish"], callout_position)
	callout.set_next_visible(true)
	callout.set_next_text("Play a real game")
	callout.show_skip_button = false

	_build_end_buttons()


func _build_end_buttons() -> void:
	callout.show_skip_button = true
	_waiting_for_next = true
	_set_beat_after_next("finish_play")

	if callout.skip_pressed.is_connected(_on_skip):
		callout.skip_pressed.disconnect(_on_skip)
	callout.skip_pressed.connect(_finish_to_start, CONNECT_ONE_SHOT)

	if callout._skip_button != null:
		callout._skip_button.text = "Back to start"
		callout._skip_button.modulate = Color(1.0, 1.0, 1.0)


func _finish_to_assembly() -> void:
	stop_tutorial()
	tutorial_finished.emit("assembly")


func _finish_to_start() -> void:
	stop_tutorial()
	tutorial_finished.emit("start_screen")


func _on_skip() -> void:
	stop_tutorial()
	if entry_source == "assembly":
		tutorial_finished.emit("assembly")
	else:
		tutorial_finished.emit("start_screen")


func _place_tutorial_dart(hit_position: Vector2) -> void:
	var dart: Node2D = Node2D.new()
	dart.position = hit_position
	dart.set_script(preload("res://scripts/dart_marker.gd"))
	dart.set("dart_color", Color(0.9, 0.85, 0.0))
	dart.set("dart_inner_color", Color(0.2, 0.2, 0.2))
	dart.set("dart_size", 5.0)
	var dart_container: Node2D = get_parent().get_node_or_null("DartContainer")
	if dart_container != null:
		dart_container.add_child(dart)
