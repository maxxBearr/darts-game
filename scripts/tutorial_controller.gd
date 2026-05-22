class_name TutorialController
extends Node
## Orchestrates the mechanics tutorial: a 3-throw sandbox walkthrough that teaches
## the throw mechanic through demo, guided, and free throws.
## Owns the beat sequence and drives throw_mechanic's scripted mode.

signal tutorial_finished(destination: String)

## Reference to the throw mechanic node. Set by main.gd.
var throw_mechanic: Node2D = null

## Reference to the dartboard node. Set by main.gd.
var dartboard: Node2D = null

## Reference to the ghost dart layer. Set by main.gd.
var ghost_dart_layer: GhostDartLayer = null

## Reference to the tutorial callout overlay. Set by main.gd.
var callout: TutorialCallout = null

## Where the player entered the tutorial from ("start_screen" or "assembly").
var entry_source: String = "start_screen"

## Default callout panel position (right side of screen, vertically centered).
## Keeps the panel clear of the dartboard at screen center.
@export var callout_position: Vector2 = Vector2(1020.0, 360.0)

## Callout position for the guided throw banner (top of screen).
@export var banner_position: Vector2 = Vector2(640.0, 80.0)

## Whether the demo throw targets the bullseye (true) or a wedge segment (false).
@export var demo_target_bullseye: bool = true

## Target wedge index for the demo throw (only used if demo_target_bullseye is false).
@export var demo_target_wedge: int = 0

## Target ring for the demo throw (only used if demo_target_bullseye is false).
@export var demo_target_ring: String = "Outer Single"

## Tunable tutorial caption strings. Keyed by beat name.
@export var tutorial_strings: Dictionary = {
	"welcome": "Welcome to the tutorial! We'll walk you through how throwing works — three quick throws and you'll have it down.",
	"intro": "We'll throw at the bullseye.",
	"aim_ellipse": "This is your [b]aim ellipse[/b]. Where your dart can possibly end up after the meters resolve. Bigger ellipse = wider range of outcomes.",
	"ideal_aim": "The center of your target is the ideal spot. Time the meters to land as close to it as possible.",
	"lock_vertical": "First you lock your [b]vertical[/b] position.",
	"green_zone": "When timed closer to your chosen target (double bullseye), your scatter shrinks.",
	"orange_zone": "When timed near it, No bonus, no penalty. Default scatter shape.",
	"red_zone": "Far from the chosen target, your dart sprays wider, leaving more up to randome chance.",
	"throw_complete": "That's the full throw. The colored zones on the H meter show you where green / orange / red are.",
	"guided_banner": "Try to lock the H meter in the [b]green[/b] zone.",
	"guided_green": "Green zone — your dart clustered tight!",
	"guided_orange": "Orange zone — neutral scatter.",
	"guided_red": "Red zone — your dart sprayed wider.",
	"free_finish": "That's it. The same loop runs every throw of a real game. Ready to play?",
}

# Internal state
var _active: bool = false
var _beats: Array[Dictionary] = []
var _current_beat: int = 0
var _current_throw: int = 0
var _waiting_for_next: bool = false
var _waiting_for_throw: bool = false
var _h_freeze_queue: Array[String] = []
var _h_freeze_index: int = 0
var _guided_mode: bool = false
var _free_mode: bool = false


## Whether the tutorial is currently active.
func is_active() -> bool:
	return _active


## Start the mechanics tutorial from the given entry source.
func start_mechanics_tutorial(source: String) -> void:
	entry_source = source
	_active = true
	_current_throw = 0
	_current_beat = 0
	_waiting_for_next = false
	_waiting_for_throw = false
	_guided_mode = false
	_free_mode = false

	# Connect signals
	if callout != null:
		if not callout.next_pressed.is_connected(_on_next_pressed):
			callout.next_pressed.connect(_on_next_pressed)
		if not callout.skip_pressed.is_connected(_on_skip):
			callout.skip_pressed.connect(_on_skip)

	if throw_mechanic != null:
		throw_mechanic.set_tutorial_visual_boost(true)
		if not throw_mechanic.throw_completed.is_connected(_on_tutorial_throw_completed):
			throw_mechanic.throw_completed.connect(_on_tutorial_throw_completed)

	_build_and_run_throw_1()


## Stop the tutorial and clean up.
func stop_tutorial() -> void:
	_active = false
	_waiting_for_next = false
	_waiting_for_throw = false
	_guided_mode = false
	_free_mode = false

	if throw_mechanic != null:
		throw_mechanic.set_scripted_mode(false)
		throw_mechanic.set_paused(false)
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


# ── Throw 1: Demo (autopilot with freeze-and-explain) ────────────────────

func _build_and_run_throw_1() -> void:
	_current_throw = 1

	# Show welcome beat first
	callout.show_callout(tutorial_strings["welcome"], callout_position)
	callout.set_next_text("Let's go")
	_waiting_for_next = true
	_set_beat_after_next("intro_target")


func _show_intro_target() -> void:
	var target_centroid: Vector2 = _get_demo_centroid()

	# Show intro callout pointing at the target
	callout.show_callout(tutorial_strings["intro"], callout_position, target_centroid)
	callout.set_next_text("Next")
	_waiting_for_next = true
	_set_beat_after_next("aim_place")


## Get the centroid of the demo target (bullseye or wedge segment).
func _get_demo_centroid() -> Vector2:
	if demo_target_bullseye:
		return dartboard.global_position
	return dartboard.get_segment_centroid(demo_target_wedge, demo_target_ring)


## Get the score result for the demo target.
func _get_demo_target_result() -> Dictionary:
	if demo_target_bullseye:
		return dartboard.calculate_score(dartboard.global_position)
	var centroid: Vector2 = dartboard.get_segment_centroid(demo_target_wedge, demo_target_ring)
	return dartboard.calculate_score(centroid)


func _set_beat_after_next(beat_name: String) -> void:
	# Store what happens when "Next" is clicked
	set_meta("_next_beat", beat_name)


func _on_next_pressed() -> void:
	if not _waiting_for_next:
		return
	_waiting_for_next = false

	var beat_name: String = get_meta("_next_beat") if has_meta("_next_beat") else ""
	match beat_name:
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
		_:
			pass


func _throw1_place_aim() -> void:
	var target_centroid: Vector2 = _get_demo_centroid()
	var target_result: Dictionary = _get_demo_target_result()

	throw_mechanic.set_scripted_mode(true)
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
	throw_mechanic.force_lock_aim(target_centroid, target_result)
	throw_mechanic.set_paused(true)
	throw_mechanic.set_tutorial_pulse_target("aim_ellipse")

	dartboard.set_declared_target(target_result)

	callout.show_callout(tutorial_strings["aim_ellipse"], callout_position, target_centroid)
	_waiting_for_next = true
	_set_beat_after_next("aim_explain")


func _throw1_explain_ideal() -> void:
	throw_mechanic.set_tutorial_pulse_target("")
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
	_set_beat_after_next("h_freeze_start")


func _throw1_start_h_freezes() -> void:
	_h_freeze_queue = ["green", "orange", "red"]
	_h_freeze_index = 0
	throw_mechanic.set_tutorial_pulse_target("accuracy_zone")
	_throw1_show_h_freeze()


func _throw1_show_h_freeze() -> void:
	if _h_freeze_index >= _h_freeze_queue.size():
		_throw1_resume_h()
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
	if _h_freeze_index < _h_freeze_queue.size():
		_set_beat_after_next("h_freeze_next")
	else:
		_set_beat_after_next("h_resume")


func _throw1_next_h_freeze() -> void:
	ghost_dart_layer.clear_scatter()
	_throw1_show_h_freeze()


func _throw1_resume_h() -> void:
	ghost_dart_layer.clear_scatter()
	throw_mechanic.set_tutorial_pulse_target("")

	# Resume the throw — lock H at the orange zone for an honest neutral result
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

	# Wait for throw to complete
	_waiting_for_throw = true
	callout.hide_callout()


func _on_tutorial_throw_completed(hit_position: Vector2) -> void:
	if not _active:
		return

	# Place a dart marker
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

	# Determine which zone the player landed in
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

	# Replace skip with "Back to start"
	_build_end_buttons()


func _build_end_buttons() -> void:
	# Set Next to go to assembly, and repurpose Skip as "Back to start"
	callout.show_skip_button = true
	_waiting_for_next = true
	_set_beat_after_next("finish_play")

	# Reconnect skip to go back to start screen instead of skipping
	if callout.skip_pressed.is_connected(_on_skip):
		callout.skip_pressed.disconnect(_on_skip)
	callout.skip_pressed.connect(_finish_to_start, CONNECT_ONE_SHOT)

	# Relabel the skip button
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


## Place a visual dart marker during the tutorial (without X01 game logic).
func _place_tutorial_dart(hit_position: Vector2) -> void:
	var dart: Node2D = Node2D.new()
	dart.position = hit_position
	dart.set_script(preload("res://scripts/dart_marker.gd"))
	dart.set("dart_color", Color(0.9, 0.85, 0.0))
	dart.set("dart_inner_color", Color(0.2, 0.2, 0.2))
	dart.set("dart_size", 5.0)
	# Add to the dart container (sibling of this node in the main scene)
	var dart_container: Node2D = get_parent().get_node_or_null("DartContainer")
	if dart_container != null:
		dart_container.add_child(dart)
