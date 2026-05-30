class_name GameOverScreen
extends Control
## Full-screen overlay shown when the player loses a run.
## Displays run stats and offers navigation to assembly or main menu.

signal return_to_assembly_pressed
signal return_to_level_select_pressed
signal return_to_menu_pressed

## Title text displayed at the top.
@export var title_text: String = "RUN LOST"

## Font size for the title.
@export var title_font_size: int = 56

## Color of the title text.
@export var title_color: Color = Color(0.9, 0.25, 0.2)

## Vertical position of the title.
@export var title_y: float = 120.0

## Font size for stat labels.
@export var stat_font_size: int = 26

## Color of stat labels.
@export var stat_color: Color = Color(0.85, 0.85, 0.9)

## Vertical start position for stat lines.
@export var stats_y: float = 260.0

## Vertical spacing between stat lines.
@export var stat_spacing: float = 44.0

## Font size for buttons.
@export var button_font_size: int = 22

## Width of buttons.
@export var button_width: float = 280.0

## Height of buttons.
@export var button_height: float = 50.0

## Vertical spacing between buttons.
@export var button_spacing: float = 16.0

## Vertical position of the button group center.
@export var buttons_center_y: float = 480.0

## Background color of the overlay.
@export var background_color: Color = Color(0.05, 0.05, 0.08, 0.95)

var _title_label: Label
var _legs_won_label: Label
var _darts_used_label: Label
var _assembly_button: Button
var _level_select_button: Button
var _menu_button: Button
var _background: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	_background = ColorRect.new()
	_background.color = background_color
	_background.position = Vector2.ZERO
	_background.size = viewport_size
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_background)

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

	_legs_won_label = _create_stat_label()
	_legs_won_label.position = Vector2(0.0, stats_y)
	add_child(_legs_won_label)

	_darts_used_label = _create_stat_label()
	_darts_used_label.position = Vector2(0.0, stats_y + stat_spacing)
	add_child(_darts_used_label)

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

	_assembly_button = _create_menu_button("Return to Assembly", Color(0.3, 0.5, 1.0))
	_assembly_button.pressed.connect(func() -> void: return_to_assembly_pressed.emit())
	button_container.add_child(_assembly_button)

	_level_select_button = _create_menu_button("Level Select", Color(0.3, 0.7, 0.4))
	_level_select_button.pressed.connect(func() -> void: return_to_level_select_pressed.emit())
	button_container.add_child(_level_select_button)

	_menu_button = _create_menu_button("Main Menu", Color(0.5, 0.5, 0.55))
	_menu_button.pressed.connect(func() -> void: return_to_menu_pressed.emit())
	button_container.add_child(_menu_button)


func show_results(legs_won: int, total_darts: int) -> void:
	_title_label.text = title_text
	_title_label.add_theme_color_override("font_color", title_color)
	_legs_won_label.text = "Legs Won: %d" % legs_won
	_darts_used_label.text = "Darts Used: %d" % total_darts
	visible = true


## Color of the victory title text.
@export var victory_title_color: Color = Color(1.0, 0.85, 0.2)


## Show a run victory screen with level name and dart count.
func show_victory(level_name: String, total_darts: int, is_new_best: bool) -> void:
	_title_label.text = "RUN WON!"
	_title_label.add_theme_color_override("font_color", victory_title_color)
	_legs_won_label.text = "%s Cleared!" % level_name
	var best_text: String = " (New Best!)" if is_new_best else ""
	_darts_used_label.text = "Darts Used: %d%s" % [total_darts, best_text]
	visible = true


func _create_stat_label() -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", stat_font_size)
	label.add_theme_color_override("font_color", stat_color)
	label.size = Vector2(get_viewport_rect().size.x, 40.0)
	return label


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
