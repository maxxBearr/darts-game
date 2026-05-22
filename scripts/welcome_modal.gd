class_name WelcomeModal
extends Control
## First-run welcome prompt shown once on first launch.
## Asks the player if they want a tutorial walkthrough or to jump straight in.

signal tutorial_chosen
signal skip_chosen

## Title text for the welcome modal.
@export var title_text: String = "Welcome!"

## Body text for the welcome modal.
@export var body_text: String = "Looks like this is your first time.\nWant a walkthrough?"

## Font size for the title.
@export var title_font_size: int = 32

## Font size for the body text.
@export var body_font_size: int = 18

## Font size for the choice buttons.
@export var button_font_size: int = 16

## Background color of the modal scrim.
@export var scrim_color: Color = Color(0.0, 0.0, 0.0, 0.7)

## Background color of the modal panel.
@export var panel_color: Color = Color(0.08, 0.08, 0.12, 0.95)

## Border color of the modal panel.
@export var panel_border_color: Color = Color(0.4, 0.4, 0.5, 0.6)

## Width of the modal panel in pixels.
@export var panel_width: float = 400.0

## Accent color for the "Yes" button.
@export var yes_button_color: Color = Color(0.3, 0.5, 1.0)

## Accent color for the "No thanks" button.
@export var no_button_color: Color = Color(0.5, 0.5, 0.5)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	visible = false


## Show the welcome modal.
func show_modal() -> void:
	visible = true


## Hide the welcome modal.
func hide_modal() -> void:
	visible = false


func _build_ui() -> void:
	var viewport_size: Vector2 = Vector2(1280.0, 720.0)

	# Full-screen scrim
	var scrim: ColorRect = ColorRect.new()
	scrim.color = scrim_color
	scrim.size = viewport_size
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	# Center panel
	var panel: Panel = Panel.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = panel_border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.size = Vector2(panel_width, 240.0)
	panel.position = (viewport_size - panel.size) / 2.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	# Content
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(24.0, 24.0)
	vbox.size = Vector2(panel_width - 48.0, 200.0)
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", title_font_size)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	vbox.add_child(title)

	# Body
	var body: Label = Label.new()
	body.text = body_text
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", body_font_size)
	body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	# Button row
	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)

	# Yes button
	var yes_button: Button = _create_choice_button("Yes, show me", yes_button_color)
	yes_button.pressed.connect(func() -> void:
		SettingsStore.set_tutorial_seen(true)
		hide_modal()
		tutorial_chosen.emit()
	)
	button_row.add_child(yes_button)

	# No button
	var no_button: Button = _create_choice_button("No thanks", no_button_color)
	no_button.pressed.connect(func() -> void:
		SettingsStore.set_tutorial_seen(true)
		hide_modal()
		skip_chosen.emit()
	)
	button_row.add_child(no_button)


## Create a styled choice button with accent color.
func _create_choice_button(text: String, accent: Color) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", button_font_size)
	button.custom_minimum_size = Vector2(150.0, 40.0)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.85)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(accent.r * 0.4, accent.g * 0.4, accent.b * 0.4, 0.9)
	button.add_theme_stylebox_override("hover", hover_style)

	return button
