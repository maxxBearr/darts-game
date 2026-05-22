class_name RulesSlideshow
extends Control
## Modal slideshow walking through x01 dart rules and board layout.
## Includes standard text/highlight slides and one interactive doubles-checkout drill.

signal slideshow_closed

## Background color of the modal scrim.
@export var scrim_color: Color = Color(0.0, 0.0, 0.0, 0.75)

## Background color of the slide panel.
@export var panel_color: Color = Color(0.08, 0.08, 0.12, 0.95)

## Border color of the slide panel.
@export var panel_border_color: Color = Color(0.4, 0.4, 0.5, 0.6)

## Width of the slide panel in pixels.
@export var panel_width: float = 520.0

## Maximum height of the slide panel in pixels.
@export var panel_max_height: float = 420.0

## Font size for slide titles.
@export var title_font_size: int = 24

## Color of slide titles.
@export var title_color: Color = Color(1.0, 0.95, 0.85)

## Font size for slide body text.
@export var body_font_size: int = 15

## Color of slide body text.
@export var body_color: Color = Color(0.88, 0.88, 0.88)

## Font size for navigation buttons.
@export var nav_font_size: int = 14

## Font size for drill answer buttons.
@export var drill_font_size: int = 16

## Color for correct drill answer feedback.
@export var drill_correct_color: Color = Color(0.2, 0.85, 0.3)

## Color for wrong drill answer feedback.
@export var drill_wrong_color: Color = Color(0.9, 0.25, 0.2)

## Slide data — built in _build_slides(). Each entry has type, title, body, and optional fields.
var _slides: Array[Dictionary] = []

## Current slide index.
var _current_slide: int = 0

## Reference to the dartboard for tutorial highlights. Set by the tutorial controller / main.
var dartboard: Node2D = null

# UI references
var _scrim: ColorRect
var _panel: Panel
var _title_label: Label
var _body_label: RichTextLabel
var _prev_button: Button
var _next_button: Button
var _close_button: Button
var _skip_link: Button
var _slide_counter: Label
var _drill_container: VBoxContainer
var _drill_feedback: Label
var _drill_answered_correctly: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_slides()
	_build_ui()
	visible = false


## Show the slideshow starting from slide 0.
func show_slideshow() -> void:
	_current_slide = 0
	_drill_answered_correctly = false
	visible = true
	_display_current_slide()


## Hide the slideshow and clean up highlights.
func hide_slideshow() -> void:
	visible = false
	if dartboard != null:
		dartboard.clear_tutorial_highlight()


func _build_slides() -> void:
	_slides = [
		{
			"type": "text",
			"title": "The Board",
			"body": "20 wedges, numbered 1-20, arranged in a specific order to punish missing your target. Standard around the world.",
			"highlight": [],
		},
		{
			"type": "text",
			"title": "Wedges and Rings",
			"body": "Each wedge has the same number value, but different rings on it score differently.",
			"highlight": [{"type": "single_wedge_all", "wedge_index": 0}],
		},
		{
			"type": "text",
			"title": "Singles",
			"body": "The big body of a wedge is a single — face value x 1. A single 20 = 20 points.",
			"highlight": [
				{"type": "all_wedges_ring", "ring_name": "Inner Single"},
				{"type": "all_wedges_ring", "ring_name": "Outer Single"},
			],
		},
		{
			"type": "text",
			"title": "Doubles",
			"body": "The thin outer ring is the double — face value x 2. A double 20 = 40 points. [b]Important — you'll need this in a moment.[/b]",
			"highlight": [{"type": "all_wedges_ring", "ring_name": "Double"}],
		},
		{
			"type": "text",
			"title": "Triples",
			"body": "The thin inner ring is the triple — face value x 3. A triple 20 = 60 points. [b]The highest single-dart score is triple 20.[/b]",
			"highlight": [{"type": "all_wedges_ring", "ring_name": "Triple"}],
		},
		{
			"type": "text",
			"title": "The Bullseye",
			"body": "Outer bull = 25 points. Inner bull (double bull) = 50 points. [b]Double bull counts as a double[/b] for checkout purposes.",
			"highlight": [{"type": "bullseye", "which": "both"}],
		},
		{
			"type": "text",
			"title": "x01 Scoring",
			"body": "You start each leg at a target score (101, 201, 301, etc.). Every dart subtracts its score from your remaining. Get to exactly 0 to win the leg.",
			"highlight": [],
		},
		{
			"type": "text",
			"title": "The Doubles Rule",
			"body": "There's a catch — your [b]last dart[/b] has to land on a [b]double[/b] (or the double bull). Hitting 0 with anything else = [b]bust[/b]. Going below 0 = [b]bust[/b]. Leaving 1 remaining = [b]bust[/b] (because no double sums to 1).",
			"highlight": [{"type": "all_wedges_ring", "ring_name": "Double"}],
		},
		{
			"type": "drill",
			"title": "Quick Check",
			"body": "You have 32 remaining. Which dart wins the leg?",
			"options": ["Double 16", "Single 16", "Triple 10 + Double 1"],
			"correct_index": 0,
			"correct_text": "Correct! 32 = double 16.",
			"wrong_text": "Not quite — remember, the last dart must be a double.",
			"highlight": [],
		},
		{
			"type": "text",
			"title": "That's the Basics",
			"body": "The game throws scoring modifiers and dart customization on top, but the throwing and counting always work this way.",
			"highlight": [],
		},
	]


func _build_ui() -> void:
	var viewport_size: Vector2 = Vector2(1280.0, 720.0)

	# Scrim
	_scrim = ColorRect.new()
	_scrim.color = scrim_color
	_scrim.size = viewport_size
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	# Panel
	_panel = Panel.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = panel_border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.size = Vector2(panel_width, panel_max_height)
	_panel.position = (viewport_size - _panel.size) / 2.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.position = Vector2(24.0, 24.0)
	content.size = Vector2(panel_width - 48.0, panel_max_height - 48.0)
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)

	# Title
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", title_font_size)
	_title_label.add_theme_color_override("font_color", title_color)
	content.add_child(_title_label)

	# Body (RichTextLabel for bold support)
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size = Vector2(panel_width - 48.0, 60.0)
	_body_label.add_theme_font_size_override("normal_font_size", body_font_size)
	_body_label.add_theme_font_size_override("bold_font_size", body_font_size)
	_body_label.add_theme_color_override("default_color", body_color)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_body_label)

	# Drill container (hidden by default)
	_drill_container = VBoxContainer.new()
	_drill_container.add_theme_constant_override("separation", 8)
	_drill_container.visible = false
	content.add_child(_drill_container)

	# Drill feedback
	_drill_feedback = Label.new()
	_drill_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drill_feedback.add_theme_font_size_override("font_size", 14)
	_drill_feedback.visible = false
	content.add_child(_drill_feedback)

	# Navigation row
	var nav_row: HBoxContainer = HBoxContainer.new()
	nav_row.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_row.add_theme_constant_override("separation", 12)
	content.add_child(nav_row)

	_prev_button = Button.new()
	_prev_button.text = "Previous"
	_prev_button.add_theme_font_size_override("font_size", nav_font_size)
	_prev_button.custom_minimum_size = Vector2(90.0, 32.0)
	_prev_button.pressed.connect(_go_previous)
	nav_row.add_child(_prev_button)

	_slide_counter = Label.new()
	_slide_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slide_counter.add_theme_font_size_override("font_size", 12)
	_slide_counter.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_slide_counter.custom_minimum_size = Vector2(60.0, 0.0)
	nav_row.add_child(_slide_counter)

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.add_theme_font_size_override("font_size", nav_font_size)
	_next_button.custom_minimum_size = Vector2(90.0, 32.0)
	_next_button.pressed.connect(_go_next)
	nav_row.add_child(_next_button)

	# Skip link (top-right corner)
	_skip_link = Button.new()
	_skip_link.text = "Skip to end"
	_skip_link.flat = true
	_skip_link.add_theme_font_size_override("font_size", 11)
	_skip_link.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_skip_link.position = Vector2(panel_width - 100.0, 4.0)
	_skip_link.pressed.connect(_go_to_last)
	_panel.add_child(_skip_link)

	# Close button (shown on last slide)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.add_theme_font_size_override("font_size", nav_font_size)
	_close_button.custom_minimum_size = Vector2(90.0, 32.0)
	_close_button.pressed.connect(_close)
	_close_button.visible = false
	nav_row.add_child(_close_button)


func _display_current_slide() -> void:
	var slide: Dictionary = _slides[_current_slide]
	_title_label.text = slide["title"]
	_body_label.text = slide["body"]

	# Navigation
	_prev_button.visible = _current_slide > 0
	var is_last: bool = _current_slide == _slides.size() - 1
	var is_drill: bool = slide["type"] == "drill"

	# On drill slides, Next is disabled until answered correctly
	if is_drill:
		_next_button.visible = not is_last
		_next_button.disabled = not _drill_answered_correctly
	else:
		_next_button.visible = not is_last
		_next_button.disabled = false

	_close_button.visible = is_last
	_slide_counter.text = "%d / %d" % [_current_slide + 1, _slides.size()]

	# Drill UI
	_drill_container.visible = is_drill
	_drill_feedback.visible = false
	_drill_answered_correctly = false

	# Clear and rebuild drill buttons if needed
	for child: Node in _drill_container.get_children():
		child.queue_free()

	if is_drill:
		var options: Array = slide["options"]
		for i: int in range(options.size()):
			var option_text: String = options[i]
			var btn: Button = Button.new()
			btn.text = option_text
			btn.add_theme_font_size_override("font_size", drill_font_size)
			btn.custom_minimum_size = Vector2(panel_width - 96.0, 36.0)
			btn.pressed.connect(_on_drill_answer.bind(i))
			_drill_container.add_child(btn)

	# Board highlights
	if dartboard != null:
		var highlights: Array = slide.get("highlight", [])
		if highlights.size() > 0:
			var typed_highlights: Array[Dictionary] = []
			for h: Dictionary in highlights:
				typed_highlights.append(h)
			dartboard.set_tutorial_highlight(typed_highlights)
		else:
			dartboard.clear_tutorial_highlight()


func _on_drill_answer(index: int) -> void:
	var slide: Dictionary = _slides[_current_slide]
	var correct_index: int = slide["correct_index"]

	if index == correct_index:
		_drill_answered_correctly = true
		_drill_feedback.text = slide["correct_text"]
		_drill_feedback.add_theme_color_override("font_color", drill_correct_color)
		_drill_feedback.visible = true
		_next_button.disabled = false

		# Highlight correct button
		var btn: Button = _drill_container.get_child(index) as Button
		if btn != null:
			var correct_style: StyleBoxFlat = StyleBoxFlat.new()
			correct_style.bg_color = Color(0.1, 0.35, 0.15, 0.9)
			correct_style.border_color = drill_correct_color
			correct_style.set_border_width_all(2)
			correct_style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", correct_style)
	else:
		_drill_feedback.text = slide["wrong_text"]
		_drill_feedback.add_theme_color_override("font_color", drill_wrong_color)
		_drill_feedback.visible = true

		# Highlight wrong button
		var btn: Button = _drill_container.get_child(index) as Button
		if btn != null:
			var wrong_style: StyleBoxFlat = StyleBoxFlat.new()
			wrong_style.bg_color = Color(0.35, 0.1, 0.1, 0.9)
			wrong_style.border_color = drill_wrong_color
			wrong_style.set_border_width_all(2)
			wrong_style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", wrong_style)


func _go_next() -> void:
	if _current_slide < _slides.size() - 1:
		_current_slide += 1
		_display_current_slide()


func _go_previous() -> void:
	if _current_slide > 0:
		_current_slide -= 1
		_display_current_slide()


func _go_to_last() -> void:
	_current_slide = _slides.size() - 1
	_display_current_slide()


func _close() -> void:
	hide_slideshow()
	slideshow_closed.emit()


func _on_scrim_input(event: InputEvent) -> void:
	# Absorb clicks on scrim so they don't pass through
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_RIGHT, KEY_SPACE:
				_go_next()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_go_previous()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_close()
				get_viewport().set_input_as_handled()
