class_name TutorialSlider
extends Control
## Transient interactive slider widget for tutorial stat demos.
## Shows a stat name, current value, draggable slider, and "Got it" button.
## Instantiated by the tutorial controller, freed when dismissed.

signal value_changed(value: float)
signal dismissed

## Label text shown above the slider (e.g., "H Range").
@export var label_text: String = "Stat"

## Font size for the stat label.
@export var label_font_size: int = 18

## Font size for the value display.
@export var value_font_size: int = 16

## Font size for the dismiss button.
@export var button_font_size: int = 14

## Width of the slider widget in pixels.
@export var slider_width: float = 240.0

## Position of the widget on screen.
@export var widget_position: Vector2 = Vector2(1020.0, 520.0)

## Background color of the widget panel.
@export var panel_color: Color = Color(0.08, 0.08, 0.12, 0.92)

## Border color of the widget panel.
@export var panel_border_color: Color = Color(0.4, 0.4, 0.5, 0.7)

var _label: Label
var _value_label: Label
var _slider: HSlider
var _button: Button
var _panel: Panel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


## Configure the slider range and initial value. Call after adding to the scene tree.
func setup(stat_name: String, current_value: float, min_value: float, max_value: float) -> void:
	label_text = stat_name
	_label.text = stat_name
	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.step = 0.1
	_slider.value = current_value
	_value_label.text = str(roundi(current_value))


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = panel_border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.size = Vector2(slider_width + 32.0, 130.0)
	_panel.position = widget_position - _panel.size / 2.0
	add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(16.0, 12.0)
	vbox.size = Vector2(slider_width, 110.0)
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# Stat name + value row
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	_label = Label.new()
	_label.text = label_text
	_label.add_theme_font_size_override("font_size", label_font_size)
	_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_label)

	_value_label = Label.new()
	_value_label.text = "0"
	_value_label.add_theme_font_size_override("font_size", value_font_size)
	_value_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_value_label)

	# Slider
	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(slider_width, 20.0)
	_slider.min_value = 0.0
	_slider.max_value = 100.0
	_slider.step = 0.1
	_slider.value_changed.connect(_on_slider_changed)
	vbox.add_child(_slider)

	# Got it button
	_button = Button.new()
	_button.text = "Got it"
	_button.add_theme_font_size_override("font_size", button_font_size)
	_button.custom_minimum_size = Vector2(80.0, 30.0)
	_button.pressed.connect(func() -> void: dismissed.emit())
	vbox.add_child(_button)


func _on_slider_changed(new_value: float) -> void:
	_value_label.text = str(roundi(new_value))
	value_changed.emit(new_value)
