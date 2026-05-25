class_name UnlockNotificationQueue
extends Control
## Displays toast notifications when a component is unlocked.
## Connects to PlayerProgress.component_unlocked and queues multiple unlocks.

## Duration (seconds) each notification stays on screen before sliding out.
@export var display_duration: float = 2.0

## Slide-in / slide-out animation duration in seconds.
@export var slide_duration: float = 0.3

## Position offset from the top-right screen edge.
@export var screen_margin: Vector2 = Vector2(18.0, 24.0)

## Background color of the notification panel.
@export var background_color: Color = Color(0.1, 0.1, 0.12, 0.95)

## Accent color for the header text.
@export var accent_color: Color = Color(1.0, 0.85, 0.2)

## Size of the notification panel.
@export var panel_size: Vector2 = Vector2(320.0, 80.0)

var _queue: Array[DartComponent] = []
var _showing: bool = false
var _panel: PanelContainer
var _icon: TextureRect
var _header_label: Label
var _name_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	PlayerProgress.component_unlocked.connect(_on_component_unlocked)
	_build_panel()



func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = panel_size
	_panel.size = panel_size
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = accent_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(hbox)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_END
	hbox.add_child(_icon)

	_header_label = Label.new()
	_header_label.text = "NEW COMPONENT\nUNLOCKED"
	_header_label.add_theme_font_size_override("font_size", 11)
	_header_label.add_theme_color_override("font_color", accent_color)
	_header_label.clip_text = true
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_header_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_name_label.clip_text = true
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_name_label)

	var viewport_w: float = 1280.0
	_panel.position = Vector2(viewport_w, screen_margin.y)
	_panel.visible = false
	add_child(_panel)


func _on_component_unlocked(component: DartComponent) -> void:
	_queue.append(component)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return

	_showing = true
	var component: DartComponent = _queue.pop_front()

	_name_label.text = component.component_name
	if component.texture:
		_icon.texture = component.texture
		_icon.visible = true
	else:
		_icon.visible = false

	var viewport_w: float = 1280.0
	var on_x: float = viewport_w - panel_size.x - screen_margin.x
	var off_x: float = viewport_w

	_panel.position = Vector2(off_x, screen_margin.y)
	_panel.visible = true

	var tween: Tween = create_tween()
	tween.tween_property(_panel, "position:x", on_x, slide_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(display_duration)
	tween.tween_property(_panel, "position:x", off_x, slide_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_on_slide_out_finished)


func _on_slide_out_finished() -> void:
	_panel.visible = false
	_show_next()
