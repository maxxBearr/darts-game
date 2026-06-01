class_name TutorialCallout
extends Control
## Reusable overlay widget for tutorial captions with optional pointer arrows.
## Renders a semi-transparent rounded panel with text, a "Next" button,
## and an optional arrow pointing to a screen-space target.

signal next_pressed
signal skip_pressed
signal secondary_pressed

## Background color of the callout panel.
@export var panel_color: Color = Color(0.08, 0.08, 0.12, 0.92)

## Border color of the callout panel.
@export var panel_border_color: Color = Color(0.4, 0.4, 0.5, 0.7)

## Corner radius of the callout panel in pixels.
@export var panel_corner_radius: float = 8.0

## Padding inside the callout panel in pixels.
@export var panel_padding: float = 16.0

## Font size for the callout body text.
@export var body_font_size: int = 20

## Font color for the callout body text.
@export var body_font_color: Color = Color(0.92, 0.92, 0.92)

## Font size for the Next button.
@export var button_font_size: int = 14

## Font size for the Skip button.
@export var skip_font_size: int = 12

## Color of the arrow line pointing to the target.
@export var arrow_color: Color = Color(1.0, 0.85, 0.2, 0.8)

## Thickness of the arrow line in pixels.
@export var arrow_thickness: float = 2.5

## Size of the arrowhead in pixels.
@export var arrowhead_size: float = 10.0

## Maximum width of the callout panel in pixels.
@export var max_panel_width: float = 420.0

## Position of the callout panel center on screen.
@export var panel_position: Vector2 = Vector2(640.0, 580.0)

## Whether the Next button is visible (some beats auto-advance).
@export var show_next_button: bool = true

## Whether the Skip button is visible.
@export var show_skip_button: bool = true

var _body_label: RichTextLabel
var _next_button: Button
var _skip_button: Button
var _secondary_button: Button
var _panel: Panel
var _arrow_target: Vector2 = Vector2.ZERO
var _show_arrow: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false


## Show a callout with the given text and optional arrow pointing to a target.
func show_callout(text: String, anchor_pos: Vector2 = Vector2.ZERO, arrow_target: Vector2 = Vector2.ZERO) -> void:
	_body_label.text = text
	if anchor_pos != Vector2.ZERO:
		panel_position = anchor_pos
	_panel.position = panel_position - _panel.size / 2.0

	_show_arrow = arrow_target != Vector2.ZERO
	_arrow_target = arrow_target
	_next_button.visible = show_next_button
	_skip_button.visible = show_skip_button
	_secondary_button.visible = false
	visible = true
	queue_redraw()


## Hide the callout.
func hide_callout() -> void:
	visible = false
	_show_arrow = false


## Update just the text without changing position or arrow.
func update_text(text: String) -> void:
	_body_label.text = text


## Set whether the Next button is visible for this beat.
func set_next_visible(show: bool) -> void:
	show_next_button = show
	if _next_button != null:
		_next_button.visible = show


## Set the Next button label text.
func set_next_text(text: String) -> void:
	if _next_button != null:
		_next_button.text = text


## Show or hide the secondary action button with the given label.
func set_secondary_action(text: String, show: bool) -> void:
	if _secondary_button != null:
		_secondary_button.text = text
		_secondary_button.visible = show


func _build_ui() -> void:
	# Scrim (semi-transparent background that blocks interaction with the game)
	# Not used here — the tutorial controller manages input blocking

	# Panel
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(max_panel_width, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = panel_border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(panel_corner_radius))
	style.set_content_margin_all(panel_padding)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# Content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(panel_padding, panel_padding)
	vbox.size = Vector2(max_panel_width - panel_padding * 2.0, 0.0)
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# Body text (RichTextLabel for bold/formatting support)
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size = Vector2(max_panel_width - panel_padding * 2.0, 0.0)
	_body_label.add_theme_font_size_override("normal_font_size", body_font_size)
	_body_label.add_theme_font_size_override("bold_font_size", body_font_size)
	_body_label.add_theme_color_override("default_color", body_font_color)
	_body_label.add_theme_constant_override("outline_size", 4)
	_body_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_body_label)

	# Button row
	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.add_theme_font_size_override("font_size", button_font_size)
	_next_button.custom_minimum_size = Vector2(80.0, 32.0)
	_next_button.pressed.connect(func() -> void: next_pressed.emit())
	button_row.add_child(_next_button)

	# Secondary action button (hidden by default — used for tutorial hand-off choice)
	_secondary_button = Button.new()
	_secondary_button.add_theme_font_size_override("font_size", button_font_size)
	_secondary_button.custom_minimum_size = Vector2(80.0, 32.0)
	_secondary_button.modulate = Color(0.7, 0.7, 0.7)
	_secondary_button.pressed.connect(func() -> void: secondary_pressed.emit())
	_secondary_button.visible = false
	button_row.add_child(_secondary_button)

	# Skip button (top-right of the panel)
	_skip_button = Button.new()
	_skip_button.text = "Skip Tutorial"
	_skip_button.add_theme_font_size_override("font_size", skip_font_size)
	_skip_button.modulate = Color(0.7, 0.7, 0.7)
	_skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	button_row.add_child(_skip_button)

	# Size the panel after content is laid out
	_panel.size = Vector2(max_panel_width, 0.0)
	_panel.position = panel_position - Vector2(max_panel_width / 2.0, 0.0)


func _draw() -> void:
	if not visible or not _show_arrow:
		return

	# Draw arrow from panel edge to target
	var panel_center: Vector2 = _panel.position + _panel.size / 2.0
	var direction: Vector2 = (_arrow_target - panel_center).normalized()
	var start: Vector2 = panel_center + direction * 20.0
	var end: Vector2 = _arrow_target

	draw_line(start, end, arrow_color, arrow_thickness)

	# Arrowhead
	var perp: Vector2 = Vector2(-direction.y, direction.x)
	var head_base: Vector2 = end - direction * arrowhead_size
	var head_left: Vector2 = head_base + perp * arrowhead_size * 0.5
	var head_right: Vector2 = head_base - perp * arrowhead_size * 0.5
	draw_colored_polygon(PackedVector2Array([end, head_left, head_right]), arrow_color)
