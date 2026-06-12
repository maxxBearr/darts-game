class_name RecordsScreen
extends Control
## Full-screen benchmark records view (run-consolidation spec 2026-06-12). Replaces the old
## level-select surface: now that one continuous run is the only mode, this screen displays the
## persistent benchmarks instead of launching levels. Two blocks — the best run reached so far
## (furthest act/node + cumulative darts), and a per-tier high-score table (times each x01 tier
## was cleared + the fewest cumulative darts to clear it). Reads PlayerProgress directly via
## refresh(); persists across runs.

signal back_pressed

## Title text at the top of the screen.
@export var title_text: String = "RECORDS"

## Font size for the title.
@export var title_font_size: int = 48

## Color of the title text.
@export var title_color: Color = Color(1.0, 0.95, 0.85)

## Vertical position of the title from the top of the screen.
@export var title_y: float = 70.0

## Font size for section headers ("Best Run", "Tier Clears").
@export var header_font_size: int = 26

## Color of section headers.
@export var header_color: Color = Color(0.7, 0.85, 1.0)

## Font size for the record value lines.
@export var line_font_size: int = 22

## Color of a record line that HAS a value.
@export var value_color: Color = Color(0.9, 0.9, 0.95)

## Color of a record line that is still empty ("not yet" / "no runs yet").
@export var empty_color: Color = Color(0.5, 0.5, 0.55)

## Vertical position of the Back button.
@export var back_button_y: float = 600.0

## Font size for the Back button.
@export var back_button_font_size: int = 18

## Background color of the screen overlay.
@export var background_color: Color = Color(0.05, 0.05, 0.08, 0.95)

var _background: ColorRect
var _title_label: Label
var _content: VBoxContainer

## The act-ceiling tiers to display, set by main before refresh() (e.g. [501, 1001, 1501]).
var tiers: Array[int] = []


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
	_title_label.size = Vector2(viewport_size.x, 70.0)
	_title_label.position = Vector2(0.0, title_y)
	add_child(_title_label)

	# Centered content column — rebuilt each refresh() so it always reflects live progress.
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_BEGIN
	_content.add_theme_constant_override("separation", 10)
	_content.size = Vector2(560.0, 0.0)
	_content.position = Vector2((viewport_size.x - 560.0) / 2.0, 180.0)
	add_child(_content)

	var back_button: Button = _create_nav_button("Back")
	back_button.position = Vector2((viewport_size.x - 160.0) / 2.0, back_button_y)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back_button)


## Rebuild the records display from the live PlayerProgress benchmarks. Call before showing.
func refresh() -> void:
	if _content == null:
		return
	for child: Node in _content.get_children():
		child.queue_free()

	_add_header("Best Run")
	var best: Dictionary = PlayerProgress.get_best_run()
	if best.is_empty():
		_add_line("No runs yet", true)
	else:
		var act: int = int(best.get("act", 0))
		var darts: int = int(best.get("darts", 0))
		# Map the furthest act onto its tier label (act-major depth resolves "how deep").
		var tier_label: String = "%d" % tiers[act] if act < tiers.size() else "?"
		var act_total: int = maxi(tiers.size(), act + 1)
		_add_line("Reached Act %d/%d (%s) — %d darts" % [act + 1, act_total, tier_label, darts], false)

	_add_spacer()
	_add_header("Tier Clears")
	if tiers.is_empty():
		_add_line("No tiers configured", true)
	for tier: int in tiers:
		var rec: Dictionary = PlayerProgress.get_tier_record(tier)
		var clears: int = int(rec.get("clears", 0))
		if clears > 0:
			var fewest: int = int(rec.get("fewest_darts", 0))
			_add_line("%d  ×%d — best %d darts" % [tier, clears, fewest], false)
		else:
			_add_line("%d  — not yet" % tier, true)


func _add_header(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", header_font_size)
	label.add_theme_color_override("font_color", header_color)
	_content.add_child(label)


func _add_line(text: String, is_empty: bool) -> void:
	var label: Label = Label.new()
	label.text = "   " + text
	label.add_theme_font_size_override("font_size", line_font_size)
	label.add_theme_color_override("font_color", empty_color if is_empty else value_color)
	_content.add_child(label)


func _add_spacer() -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 16.0)
	_content.add_child(spacer)


func _create_nav_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", back_button_font_size)
	button.custom_minimum_size = Vector2(160.0, 40.0)

	var accent: Color = Color(0.5, 0.5, 0.55)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.8)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, 0.9)
	hover_style.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style: StyleBoxFlat = style.duplicate()
	pressed_style.bg_color = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.8)
	button.add_theme_stylebox_override("pressed", pressed_style)

	return button
