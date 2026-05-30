class_name StartScreen
extends Control
## Full-screen start menu shown before the assembly screen.
## Provides entry points to Start Game, Play Tutorial, and Rules of Darts.

signal start_game_pressed
signal play_tutorial_pressed
signal stats_walkthrough_pressed
signal rules_pressed
signal stats_reference_pressed

## Title text displayed at the top of the start screen.
@export var title_text: String = "DARTS"

## Font size for the title.
@export var title_font_size: int = 64

## Color of the title text.
@export var title_color: Color = Color(1.0, 0.95, 0.85)

## Vertical position of the title from the top of the screen.
@export var title_y: float = 140.0

## Font size for the main menu buttons.
@export var button_font_size: int = 22

## Minimum width of the main menu buttons in pixels.
@export var button_width: float = 280.0

## Height of each main menu button in pixels.
@export var button_height: float = 50.0

## Vertical spacing between menu buttons in pixels.
@export var button_spacing: float = 16.0

## Vertical position of the first button (center of the button group).
@export var buttons_center_y: float = 380.0

## Background color of the start screen overlay.
@export var background_color: Color = Color(0.05, 0.05, 0.08, 0.95)

## Font size for the secondary Stats Reference button.
@export var stats_button_font_size: int = 14

## Color of the secondary Stats Reference button text.
@export var stats_button_color: Color = Color(0.6, 0.6, 0.7)

var _title_label: Label
var _start_button: Button
var _tutorial_button: Button
var _rules_button: Button
var _stats_button: Button
var _background: ColorRect
var _chooser_panel: Panel = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	# Full-screen background
	_background = ColorRect.new()
	_background.color = background_color
	_background.position = Vector2.ZERO
	_background.size = viewport_size
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_background)

	# Title
	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", title_font_size)
	_title_label.add_theme_color_override("font_color", title_color)
	_title_label.add_theme_constant_override("outline_size", 4)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	_title_label.size = Vector2(viewport_size.x, 80.0)
	_title_label.position = Vector2(0.0, title_y)
	add_child(_title_label)

	# Button container
	var button_container: VBoxContainer = VBoxContainer.new()
	button_container.add_theme_constant_override("separation", int(button_spacing))
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	var total_button_height: float = button_height * 3.0 + button_spacing * 2.0
	button_container.position = Vector2(
		(viewport_size.x - button_width) / 2.0,
		buttons_center_y - total_button_height / 2.0
	)
	button_container.size = Vector2(button_width, total_button_height)
	add_child(button_container)

	# Start Game button
	_start_button = _create_menu_button("Start Game", Color(0.2, 0.7, 0.3))
	_start_button.pressed.connect(func() -> void: start_game_pressed.emit())
	button_container.add_child(_start_button)

	# Play Tutorial button — opens a sub-menu chooser
	_tutorial_button = _create_menu_button("Play Tutorial", Color(0.3, 0.5, 1.0))
	_tutorial_button.pressed.connect(_show_tutorial_chooser)
	button_container.add_child(_tutorial_button)

	# Rules of Darts button
	_rules_button = _create_menu_button("Rules of Darts", Color(0.7, 0.6, 0.3))
	_rules_button.pressed.connect(func() -> void: rules_pressed.emit())
	button_container.add_child(_rules_button)

	# Stats Reference button (secondary, smaller)
	_stats_button = Button.new()
	_stats_button.text = "? Stats Reference"
	_stats_button.add_theme_font_size_override("font_size", stats_button_font_size)
	_stats_button.add_theme_color_override("font_color", stats_button_color)
	_stats_button.flat = true
	_stats_button.custom_minimum_size = Vector2(0.0, 30.0)
	_stats_button.pressed.connect(func() -> void: stats_reference_pressed.emit())
	button_container.add_child(_stats_button)


## Create a styled menu button with the given text and accent color.
func _create_menu_button(text: String, accent: Color) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", button_font_size)
	button.custom_minimum_size = Vector2(button_width, button_height)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.85)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	button.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(accent.r * 0.4, accent.g * 0.4, accent.b * 0.4, 0.9)
	hover_style.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style: StyleBoxFlat = style.duplicate()
	pressed_style.bg_color = Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2, 0.85)
	button.add_theme_stylebox_override("pressed", pressed_style)

	return button


func _show_tutorial_chooser() -> void:
	if _chooser_panel == null:
		_build_chooser()
	_chooser_panel.visible = true


func _hide_tutorial_chooser() -> void:
	if _chooser_panel != null:
		_chooser_panel.visible = false


func _build_chooser() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	_chooser_panel = Panel.new()
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.1, 0.96)
	panel_style.border_color = Color(0.4, 0.45, 0.6, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(20)
	_chooser_panel.add_theme_stylebox_override("panel", panel_style)
	_chooser_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(button_spacing))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.position = Vector2(20.0, 20.0)
	vbox.size = Vector2(button_width, 0.0)
	_chooser_panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Choose Tutorial"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	title.custom_minimum_size = Vector2(button_width, 30.0)
	vbox.add_child(title)

	var full_btn: Button = _create_menu_button("Full Tutorial", Color(0.3, 0.5, 1.0))
	full_btn.pressed.connect(func() -> void:
		_hide_tutorial_chooser()
		play_tutorial_pressed.emit()
	)
	vbox.add_child(full_btn)

	var stats_btn: Button = _create_menu_button("Stats Walkthrough Only", Color(0.5, 0.4, 0.8))
	stats_btn.pressed.connect(func() -> void:
		_hide_tutorial_chooser()
		stats_walkthrough_pressed.emit()
	)
	vbox.add_child(stats_btn)

	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	back_btn.flat = true
	back_btn.custom_minimum_size = Vector2(0.0, 30.0)
	back_btn.pressed.connect(_hide_tutorial_chooser)
	vbox.add_child(back_btn)

	var panel_width: float = button_width + 40.0
	var panel_height: float = 30.0 + (button_height + button_spacing) * 2.0 + 30.0 + 40.0
	_chooser_panel.size = Vector2(panel_width, panel_height)
	_chooser_panel.position = Vector2(
		(viewport_size.x - panel_width) / 2.0,
		buttons_center_y - panel_height / 2.0
	)
	_chooser_panel.visible = false
	add_child(_chooser_panel)
