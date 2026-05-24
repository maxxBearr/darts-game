class_name AssemblyScreen
extends Control
## Full-screen pre-run overlay where the player assembles their dart from
## three components (barrel, shaft, flight). Shows stat bars, balance meter,
## and a dart preview. Emits run_confirmed when the player clicks Begin Run.

signal run_confirmed
signal play_tutorial_pressed
signal rules_pressed

var dart_build: DartBuild
var registry: DartComponentRegistry
var throw_mechanic: Node2D
var base_stats: Dictionary = {}

# Available parts for each slot (populated from registry)
var _barrels: Array[DartComponent] = []
var _shafts: Array[DartComponent] = []
var _flights: Array[DartComponent] = []

# Current selection index per slot
var _barrel_idx: int = 0
var _shaft_idx: int = 0
var _flight_idx: int = 0

# UI references built in _ready()
var _title_label: Label
var _barrel_name: Label
var _shaft_name: Label
var _flight_name: Label
var _barrel_stats: RichTextLabel
var _shaft_stats: RichTextLabel
var _flight_stats: RichTextLabel
var _barrel_perk: Label
var _shaft_perk: Label
var _flight_perk: Label
var _barrel_preview: ColorRect
var _shaft_preview: ColorRect
var _flight_preview: ColorRect
var _barrel_tex: TextureRect
var _shaft_tex: TextureRect
var _flight_tex: TextureRect
var _stat_bars: Dictionary = {}
var _stat_value_labels: Dictionary = {}
var _balance_bar: Control
var _balance_needle_x: float = 0.0
var _balance_label: Label
var _zone_label: Label
var _begin_button: Button
var _throw_color_panel: VBoxContainer
var _throw_color_toggle: Button
var _throw_color_pickers: Dictionary = {}
var _zone_preview: Control
var _v_bounce_t: float = 0.0
var _h_bounce_t: float = 0.0

# "New Parts!" labels per slot, shown when newly unlocked parts exist
var _barrel_new_label: Label
var _shaft_new_label: Label
var _flight_new_label: Label

# IDs of components unlocked during this session that haven't been viewed yet.
# Populated by the component_unlocked signal, cleared as the player cycles to them.
var _unseen_new_ids: Dictionary = {}

# ── Layout exports ───────────────────────────────────────────────────────────

@export_group("Title")
@export var title_position: Vector2 = Vector2(0.0, 20.0)
@export var title_font_size: int = 32

@export_group("Dart Preview")
@export var dart_preview_position: Vector2 = Vector2(440.0, 70.0)
@export var dart_preview_size: Vector2 = Vector2(400.0, 100.0)
@export var component_preview_height: float = 80.0

## Size of the point sprite in the dart preview.
@export var point_preview_size: Vector2 = Vector2(40.0, 20.0)

## Horizontal offset of the point relative to its default position (pixels).
@export var point_preview_h_offset: float = 0.0

## Vertical offset of the point relative to the barrel (pixels).
@export var point_preview_v_offset: float = 0.0

@export_group("Slot Selectors")
@export var barrel_slot_position: Vector2 = Vector2(100.0, 200.0)
@export var shaft_slot_position: Vector2 = Vector2(490.0, 200.0)
@export var flight_slot_position: Vector2 = Vector2(880.0, 200.0)
@export var slot_selector_size: Vector2 = Vector2(260.0, 200.0)
@export var slot_title_font_size: int = 18
@export var slot_name_font_size: int = 16

@export_group("Stat Bars")
@export var stats_position: Vector2 = Vector2(40.0, 370.0)
@export var stats_size: Vector2 = Vector2(300.0, 200.0)
@export var stat_bar_width: float = 180.0
@export var stat_bar_height: float = 14.0

@export_group("Zone Preview")
@export var zone_preview_position: Vector2 = Vector2(40.0, 510.0)
@export var zone_preview_size: Vector2 = Vector2(300.0, 210.0)
@export var zone_preview_board_radius: float = 80.0
@export var zone_preview_label_offset: float = 0.0

@export_group("Balance")
@export var balance_position: Vector2 = Vector2(400.0, 500.0)
@export var balance_size: Vector2 = Vector2(480.0, 90.0)
@export var balance_bar_width: float = 460.0
@export var balance_bar_height: float = 30.0

@export_group("Throw Colors")
@export var color_ui_position: Vector2 = Vector2(920.0, 420.0)
@export var color_ui_size: Vector2 = Vector2(320.0, 300.0)

@export_group("Begin Button")
@export var begin_button_position: Vector2 = Vector2(540.0, 610.0)
@export var begin_button_size: Vector2 = Vector2(200.0, 50.0)
@export var begin_button_font_size: int = 22

# ── Constants ────────────────────────────────────────────────────────────────

const STAT_KEYS: Array[String] = [
	"horizontal_range", "vertical_range",
	"horizontal_speed", "vertical_speed",
	"horizontal_accuracy", "vertical_accuracy",
]

const STAT_DISPLAY_NAMES: Dictionary = {
	"horizontal_range": "H Range",
	"vertical_range": "V Range",
	"horizontal_speed": "H Speed Control",
	"vertical_speed": "V Speed Control",
	"horizontal_accuracy": "H Accuracy",
	"vertical_accuracy": "V Accuracy",
}

const SLOT_COLORS: Dictionary = {
	"barrel": Color(0.5, 0.4, 0.35),
	"shaft": Color(0.4, 0.45, 0.5),
	"flight": Color(0.35, 0.5, 0.4),
}

const STAT_DESCRIPTIONS: Dictionary = {
	"horizontal_range": "Shrinks the aim ellipse horizontally. Also reduces the distance the horizontal marker travels, making it easier to time.",
	"vertical_range": "Shrinks the aim ellipse vertically. Also reduces the distance the vertical marker travels, making it easier to time.",
	"horizontal_speed": "Slows the horizontal release marker. Higher = easier to time your click.",
	"vertical_speed": "Slows the vertical release marker. Higher = easier to time your click.",
	"horizontal_accuracy": "Tightens horizontal dart landing variance. Higher = dart lands closer to where you clicked.",
	"vertical_accuracy": "Tightens vertical dart landing variance. Higher = dart lands closer to where you clicked.",
}

const STAT_MAX_VALUE: float = 100.0

const THROW_COLOR_ENTRIES: Array = [
	["aim_line_color", "Aim Zone"],
	["resolve_preview_color", "Accuracy Zone"],
	["vertical_glow_color", "V Meter Glow"],
	["horizontal_glow_color", "H Meter Glow"],
	["marker_color", "Marker"],
	["marker_outline_color", "Marker Outline"],
]

# ── Process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not visible or dart_build == null:
		return
	var bonuses: Dictionary = dart_build.get_total_stat_bonuses()
	var v_speed: float = clampf(base_stats.get("vertical_speed", 1.5) + bonuses.get("vertical_speed", 0.0), 1.0, 5.0)
	var h_speed: float = clampf(base_stats.get("horizontal_speed", 1.5) + bonuses.get("horizontal_speed", 0.0), 1.0, 5.0)
	_v_bounce_t += delta * (6.0 - v_speed) * 2.5
	_h_bounce_t += delta * (6.0 - h_speed) * 2.5
	if _zone_preview:
		_zone_preview.queue_redraw()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	PlayerProgress.component_unlocked.connect(_on_component_unlocked)

	# Background overlay
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title
	_title_label = Label.new()
	_title_label.text = "Assemble Your Dart"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = title_position
	_title_label.size = Vector2(1280.0, 40.0)
	_title_label.add_theme_font_size_override("font_size", title_font_size)
	add_child(_title_label)

	# Dart preview area (center-top)
	_build_dart_preview()

	# Part selectors (center row)
	_build_slot_selector("barrel", barrel_slot_position)
	_build_slot_selector("shaft", shaft_slot_position)
	_build_slot_selector("flight", flight_slot_position)

	# Stat bars (left column)
	_build_stat_bars()

	# Zone preview (below stat bars)
	_build_zone_preview()

	# Balance bar (center-bottom)
	_build_balance_bar()

	# Throw color customizer (bottom-right)
	_build_throw_color_ui()

	# Begin Run button
	_begin_button = Button.new()
	_begin_button.text = "Begin Run"
	_begin_button.position = begin_button_position
	_begin_button.size = begin_button_size
	_begin_button.add_theme_font_size_override("font_size", begin_button_font_size)
	_begin_button.pressed.connect(_on_begin_run)
	add_child(_begin_button)

	# Tutorial and Rules replay buttons (below Begin Run)
	var help_row: HBoxContainer = HBoxContainer.new()
	help_row.position = begin_button_position + Vector2(-20.0, begin_button_size.y + 12.0)
	help_row.size = Vector2(begin_button_size.x + 40.0, 32.0)
	help_row.alignment = BoxContainer.ALIGNMENT_CENTER
	help_row.add_theme_constant_override("separation", 12)
	add_child(help_row)

	var tutorial_btn: Button = Button.new()
	tutorial_btn.text = "Play Tutorial"
	tutorial_btn.add_theme_font_size_override("font_size", 13)
	tutorial_btn.flat = true
	tutorial_btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	tutorial_btn.pressed.connect(func() -> void: play_tutorial_pressed.emit())
	help_row.add_child(tutorial_btn)

	var rules_btn: Button = Button.new()
	rules_btn.text = "Rules of Darts"
	rules_btn.add_theme_font_size_override("font_size", 13)
	rules_btn.flat = true
	rules_btn.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
	rules_btn.pressed.connect(func() -> void: rules_pressed.emit())
	help_row.add_child(rules_btn)


func _build_dart_preview() -> void:
	var preview_container: HBoxContainer = HBoxContainer.new()
	preview_container.position = dart_preview_position
	preview_container.size = dart_preview_size
	preview_container.add_theme_constant_override("separation", -3)
	preview_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(preview_container)

	# Point (tip of the dart, to the left of the barrel)
	var point_holder: Control = Control.new()
	point_holder.custom_minimum_size = Vector2(point_preview_size.x, component_preview_height)
	preview_container.add_child(point_holder)

	var point_tex: TextureRect = TextureRect.new()
	point_tex.texture = preload("res://sprites/point.png")
	point_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	point_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	point_tex.size = point_preview_size
	point_tex.position = Vector2(point_preview_h_offset, (component_preview_height - point_preview_size.y) / 2.0 + point_preview_v_offset)
	point_holder.add_child(point_tex)

	# Barrel slot
	var barrel_holder: Control = Control.new()
	barrel_holder.custom_minimum_size = Vector2(140.0, component_preview_height)
	preview_container.add_child(barrel_holder)

	_barrel_preview = ColorRect.new()
	_barrel_preview.color = SLOT_COLORS["barrel"]
	_barrel_preview.size = Vector2(140.0, component_preview_height)
	barrel_holder.add_child(_barrel_preview)

	_barrel_tex = TextureRect.new()
	_barrel_tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_barrel_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_barrel_tex.size = Vector2(140.0, component_preview_height)
	barrel_holder.add_child(_barrel_tex)

	var barrel_slot_label: Label = Label.new()
	barrel_slot_label.text = "Barrel"
	barrel_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	barrel_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	barrel_slot_label.size = Vector2(140.0, component_preview_height)
	barrel_slot_label.add_theme_font_size_override("font_size", 12)
	barrel_slot_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
	barrel_holder.add_child(barrel_slot_label)

	# Shaft slot
	var shaft_holder: Control = Control.new()
	shaft_holder.custom_minimum_size = Vector2(100.0, component_preview_height)
	preview_container.add_child(shaft_holder)

	_shaft_preview = ColorRect.new()
	_shaft_preview.color = SLOT_COLORS["shaft"]
	_shaft_preview.size = Vector2(100.0, component_preview_height)
	shaft_holder.add_child(_shaft_preview)

	_shaft_tex = TextureRect.new()
	_shaft_tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_shaft_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shaft_tex.size = Vector2(100.0, component_preview_height)
	shaft_holder.add_child(_shaft_tex)

	var shaft_slot_label: Label = Label.new()
	shaft_slot_label.text = "Shaft"
	shaft_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shaft_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shaft_slot_label.size = Vector2(100.0, component_preview_height)
	shaft_slot_label.add_theme_font_size_override("font_size", 12)
	shaft_slot_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
	shaft_holder.add_child(shaft_slot_label)

	# Flight slot
	var flight_holder: Control = Control.new()
	flight_holder.custom_minimum_size = Vector2(120.0, component_preview_height)
	preview_container.add_child(flight_holder)

	_flight_preview = ColorRect.new()
	_flight_preview.color = SLOT_COLORS["flight"]
	_flight_preview.size = Vector2(120.0, component_preview_height)
	flight_holder.add_child(_flight_preview)

	_flight_tex = TextureRect.new()
	_flight_tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_flight_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flight_tex.size = Vector2(120.0, component_preview_height)
	flight_holder.add_child(_flight_tex)

	var flight_slot_label: Label = Label.new()
	flight_slot_label.text = "Flight"
	flight_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flight_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flight_slot_label.size = Vector2(120.0, component_preview_height)
	flight_slot_label.add_theme_font_size_override("font_size", 12)
	flight_slot_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
	flight_holder.add_child(flight_slot_label)


func _build_slot_selector(slot_name: String, pos: Vector2) -> void:
	var container: VBoxContainer = VBoxContainer.new()
	container.position = pos
	container.size = slot_selector_size
	container.add_theme_constant_override("separation", 4)
	add_child(container)

	# "New Parts!" label (hidden by default, shown when new unlocks exist)
	var new_label: Label = Label.new()
	new_label.text = "New Parts!"
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_label.add_theme_font_size_override("font_size", 14)
	new_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	new_label.visible = false
	container.add_child(new_label)

	# Slot title
	var title: Label = Label.new()
	title.text = slot_name.capitalize()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", slot_title_font_size)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	container.add_child(title)

	# Arrow row
	var arrow_row: HBoxContainer = HBoxContainer.new()
	arrow_row.alignment = BoxContainer.ALIGNMENT_CENTER
	arrow_row.add_theme_constant_override("separation", 8)
	container.add_child(arrow_row)

	var left_btn: Button = Button.new()
	left_btn.text = "<"
	left_btn.custom_minimum_size = Vector2(40.0, 30.0)
	left_btn.pressed.connect(_on_arrow_pressed.bind(slot_name, -1))
	arrow_row.add_child(left_btn)

	var name_label: Label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(160.0, 30.0)
	name_label.add_theme_font_size_override("font_size", slot_name_font_size)
	arrow_row.add_child(name_label)

	var right_btn: Button = Button.new()
	right_btn.text = ">"
	right_btn.custom_minimum_size = Vector2(40.0, 30.0)
	right_btn.pressed.connect(_on_arrow_pressed.bind(slot_name, 1))
	arrow_row.add_child(right_btn)

	# Stat tooltip (RichTextLabel for per-line coloring)
	var stats_label: RichTextLabel = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	stats_label.custom_minimum_size = Vector2(slot_selector_size.x, 0.0)
	stats_label.add_theme_font_size_override("normal_font_size", 13)
	container.add_child(stats_label)

	# Perk label (shown below stats when component has a throw modifier)
	var perk_label: Label = Label.new()
	perk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perk_label.custom_minimum_size = Vector2(slot_selector_size.x, 0.0)
	perk_label.add_theme_font_size_override("font_size", 12)
	perk_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	perk_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perk_label.visible = false
	container.add_child(perk_label)

	# Store references
	match slot_name:
		"barrel":
			_barrel_name = name_label
			_barrel_stats = stats_label
			_barrel_perk = perk_label
			_barrel_new_label = new_label
		"shaft":
			_shaft_name = name_label
			_shaft_stats = stats_label
			_shaft_perk = perk_label
			_shaft_new_label = new_label
		"flight":
			_flight_name = name_label
			_flight_stats = stats_label
			_flight_perk = perk_label
			_flight_new_label = new_label


func _build_stat_bars() -> void:
	var stats_container: VBoxContainer = VBoxContainer.new()
	stats_container.position = stats_position
	stats_container.size = stats_size
	stats_container.add_theme_constant_override("separation", 4)
	stats_container.theme = _create_tooltip_theme()
	add_child(stats_container)

	var stats_title: Label = Label.new()
	stats_title.text = "— Final Stats —"
	stats_title.add_theme_font_size_override("font_size", 16)
	stats_title.modulate = Color(0.8, 0.8, 0.6)
	stats_container.add_child(stats_title)

	for key: String in STAT_KEYS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = STAT_DESCRIPTIONS[key]
		stats_container.add_child(row)

		var name_lbl: Label = Label.new()
		name_lbl.text = STAT_DISPLAY_NAMES[key] + ":"
		name_lbl.custom_minimum_size = Vector2(100.0, stat_bar_height + 4.0)
		name_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(name_lbl)

		# Bar background
		var bar_bg: ColorRect = ColorRect.new()
		bar_bg.color = Color(0.15, 0.15, 0.2)
		bar_bg.custom_minimum_size = Vector2(stat_bar_width, stat_bar_height)
		row.add_child(bar_bg)

		# Bar fill (child of bg so it overlays)
		var bar_fill: ColorRect = ColorRect.new()
		bar_fill.color = Color(0.3, 0.7, 0.4)
		bar_fill.size = Vector2(0.0, stat_bar_height)
		bar_bg.add_child(bar_fill)

		# Value label
		var val_lbl: Label = Label.new()
		val_lbl.custom_minimum_size = Vector2(40.0, stat_bar_height + 4.0)
		val_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(val_lbl)

		_stat_bars[key] = bar_fill
		_stat_value_labels[key] = val_lbl


func _build_balance_bar() -> void:
	var balance_container: VBoxContainer = VBoxContainer.new()
	balance_container.position = balance_position
	balance_container.size = balance_size
	balance_container.add_theme_constant_override("separation", 4)
	add_child(balance_container)

	var balance_title: Label = Label.new()
	balance_title.text = "— Balance —"
	balance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance_title.add_theme_font_size_override("font_size", 16)
	balance_title.modulate = Color(0.8, 0.8, 0.6)
	balance_container.add_child(balance_title)

	_balance_bar = Control.new()
	_balance_bar.custom_minimum_size = Vector2(balance_bar_width, balance_bar_height)
	_balance_bar.draw.connect(_draw_balance_bar)
	balance_container.add_child(_balance_bar)

	var info_row: HBoxContainer = HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.add_theme_constant_override("separation", 20)
	balance_container.add_child(info_row)

	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", 14)
	info_row.add_child(_balance_label)

	_zone_label = Label.new()
	_zone_label.add_theme_font_size_override("font_size", 14)
	info_row.add_child(_zone_label)


func _draw_balance_bar() -> void:
	if _balance_bar == null:
		return
	var w: float = _balance_bar.size.x
	var h: float = _balance_bar.size.y
	var half_w: float = w / 2.0

	# Zone boundaries in pixels from center
	var perfect_px: float = (dart_build.perfect_threshold / 1.5) * half_w if dart_build else half_w * 0.05
	var green_px: float = (dart_build.green_threshold / 1.5) * half_w if dart_build else half_w * 0.17
	var orange_px: float = (dart_build.orange_threshold / 1.5) * half_w if dart_build else half_w * 0.33

	# Transition sub-zone boundaries
	var orange_zone_px: float = orange_px - green_px
	var go_trans_px: float = orange_zone_px * (dart_build.green_orange_transition_width if dart_build else 0.4)
	var or_trans_px: float = orange_zone_px * (dart_build.orange_red_transition_width if dart_build else 0.4)

	# Zone colors
	var perfect_color: Color = Color(0.15, 0.85, 0.4, 0.7)
	var green_color: Color = Color(0.2, 0.7, 0.3, 0.6)
	var go_trans_color: Color = Color(0.5, 0.7, 0.25, 0.6)
	var orange_color: Color = Color(0.8, 0.6, 0.2, 0.6)
	var or_trans_color: Color = Color(0.75, 0.4, 0.2, 0.6)
	var red_color: Color = Color(0.7, 0.2, 0.2, 0.6)

	# Draw gradient using thin vertical slices across the full bar width
	var num_slices: int = int(w)
	for i: int in range(num_slices):
		var x: float = float(i)
		var dist_from_center: float = absf(x - half_w)

		# Determine which zone this pixel falls in and interpolate color
		var color: Color
		if dist_from_center <= perfect_px:
			color = perfect_color
		elif dist_from_center <= green_px:
			# Blend from perfect into green
			var t: float = (dist_from_center - perfect_px) / (green_px - perfect_px) if green_px > perfect_px else 1.0
			color = perfect_color.lerp(green_color, t)
		elif dist_from_center <= green_px + go_trans_px:
			# Green→orange transition
			var t: float = (dist_from_center - green_px) / go_trans_px if go_trans_px > 0.0 else 1.0
			color = green_color.lerp(go_trans_color, t)
		elif dist_from_center <= orange_px - or_trans_px:
			# Pure orange zone
			var pure_start: float = green_px + go_trans_px
			var pure_end: float = orange_px - or_trans_px
			var t: float = (dist_from_center - pure_start) / (pure_end - pure_start) if pure_end > pure_start else 0.5
			color = go_trans_color.lerp(orange_color, t)
		elif dist_from_center <= orange_px:
			# Orange→red transition
			var t: float = (dist_from_center - (orange_px - or_trans_px)) / or_trans_px if or_trans_px > 0.0 else 1.0
			color = orange_color.lerp(or_trans_color, t)
		else:
			# Red zone
			var red_extent: float = half_w - orange_px
			var into_red: float = dist_from_center - orange_px
			var t: float = clampf(into_red / red_extent, 0.0, 1.0) if red_extent > 0.0 else 1.0
			color = or_trans_color.lerp(red_color, t)

		_balance_bar.draw_rect(Rect2(x, 0.0, 1.0, h), color)

	# Needle
	var balance: float = dart_build.get_balance_value() if dart_build else 0.0
	var needle_x: float = half_w + (balance / 1.5) * half_w
	needle_x = clampf(needle_x, 4.0, w - 4.0)
	_balance_bar.draw_rect(Rect2(needle_x - 2.0, -2.0, 4.0, h + 4.0), Color(1.0, 1.0, 1.0, 0.95))

	# Border
	_balance_bar.draw_rect(Rect2(0.0, 0.0, w, h), Color(0.5, 0.5, 0.5, 0.6), false, 1.0)


func _build_throw_color_ui() -> void:
	var container: VBoxContainer = VBoxContainer.new()
	container.position = color_ui_position
	container.size = color_ui_size
	container.add_theme_constant_override("separation", 6)
	add_child(container)

	_throw_color_toggle = Button.new()
	_throw_color_toggle.text = "Customize Throw Colors"
	_throw_color_toggle.add_theme_font_size_override("font_size", 14)
	_throw_color_toggle.pressed.connect(func() -> void: _throw_color_panel.visible = not _throw_color_panel.visible)
	container.add_child(_throw_color_toggle)

	_throw_color_panel = VBoxContainer.new()
	_throw_color_panel.add_theme_constant_override("separation", 4)
	_throw_color_panel.visible = false
	container.add_child(_throw_color_panel)

	for entry: Array in THROW_COLOR_ENTRIES:
		var prop: String = entry[0]
		var display_name: String = entry[1]

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_throw_color_panel.add_child(row)

		var lbl: Label = Label.new()
		lbl.text = display_name + ":"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.custom_minimum_size = Vector2(110.0, 0.0)
		row.add_child(lbl)

		var picker: ColorPickerButton = ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(80.0, 28.0)
		picker.edit_alpha = true
		picker.color = throw_mechanic.get(prop) if throw_mechanic else Color.WHITE
		picker.color_changed.connect(_on_throw_color_changed.bind(prop))
		row.add_child(picker)

		_throw_color_pickers[prop] = picker


func _on_throw_color_changed(color: Color, property: String) -> void:
	if throw_mechanic:
		throw_mechanic.set(property, color)


func _sync_throw_color_pickers() -> void:
	if throw_mechanic == null:
		return
	for prop: String in _throw_color_pickers:
		_throw_color_pickers[prop].color = throw_mechanic.get(prop)


## Show the assembly screen with the given base stats for bar display.
## Preserves the player's previous dart build when returning between runs.
func show_assembly(p_base_stats: Dictionary) -> void:
	base_stats = p_base_stats

	if registry:
		_barrels = registry.barrels.duplicate()
		_shafts = registry.shafts.duplicate()
		_flights = registry.flights.duplicate()

	if dart_build:
		_barrel_idx = _find_component_index(_barrels, dart_build.equipped_barrel)
		_shaft_idx = _find_component_index(_shafts, dart_build.equipped_shaft)
		_flight_idx = _find_component_index(_flights, dart_build.equipped_flight)

		# Skip past any locked component at the resolved index so the initial
		# equip never targets a locked part (e.g., if a locked component ended
		# up at array index 0).
		_barrel_idx = _skip_locked(_barrels, _barrel_idx)
		_shaft_idx = _skip_locked(_shafts, _shaft_idx)
		_flight_idx = _skip_locked(_flights, _flight_idx)

		if _barrels.size() > 0:
			dart_build.equip_barrel(_barrels[_barrel_idx])
		if _shafts.size() > 0:
			dart_build.equip_shaft(_shafts[_shaft_idx])
		if _flights.size() > 0:
			dart_build.equip_flight(_flights[_flight_idx])

	_refresh_new_parts()
	_sync_throw_color_pickers()
	_refresh_all()
	visible = true


## Find the index of a component in a list, defaulting to 0 if not found.
func _find_component_index(parts: Array[DartComponent], current: DartComponent) -> int:
	if current != null:
		for i: int in range(parts.size()):
			if parts[i] == current:
				return i
	return 0


## Advance an index forward (with wrap) until landing on an unlocked component.
## Returns the original index unchanged if every part is locked, which only
## happens if the registry contains nothing default-unlocked — an authoring
## mistake the registry validator will already have flagged.
func _skip_locked(parts: Array[DartComponent], idx: int) -> int:
	if parts.size() == 0:
		return idx
	var start: int = idx
	for _i: int in range(parts.size()):
		if PlayerProgress.is_unlocked(parts[idx]):
			return idx
		idx = (idx + 1) % parts.size()
		if idx == start:
			break
	return idx


func _on_arrow_pressed(slot_name: String, direction: int) -> void:
	match slot_name:
		"barrel":
			if _barrels.size() == 0:
				return
			_barrel_idx = wrapi(_barrel_idx + direction, 0, _barrels.size())
			if dart_build and PlayerProgress.is_unlocked(_barrels[_barrel_idx]):
				dart_build.equip_barrel(_barrels[_barrel_idx])
		"shaft":
			if _shafts.size() == 0:
				return
			_shaft_idx = wrapi(_shaft_idx + direction, 0, _shafts.size())
			if dart_build and PlayerProgress.is_unlocked(_shafts[_shaft_idx]):
				dart_build.equip_shaft(_shafts[_shaft_idx])
		"flight":
			if _flights.size() == 0:
				return
			_flight_idx = wrapi(_flight_idx + direction, 0, _flights.size())
			if dart_build and PlayerProgress.is_unlocked(_flights[_flight_idx]):
				dart_build.equip_flight(_flights[_flight_idx])
	_mark_current_seen()
	_refresh_all()


func _refresh_all() -> void:
	_refresh_slot("barrel")
	_refresh_slot("shaft")
	_refresh_slot("flight")
	_refresh_stat_bars()
	_refresh_balance()
	_refresh_begin_button()
	if _zone_preview:
		_zone_preview.queue_redraw()


func _refresh_begin_button() -> void:
	var barrel: DartComponent = _barrels[_barrel_idx] if _barrel_idx < _barrels.size() else null
	var shaft: DartComponent = _shafts[_shaft_idx] if _shaft_idx < _shafts.size() else null
	var flight: DartComponent = _flights[_flight_idx] if _flight_idx < _flights.size() else null
	var any_locked: bool = (
		(barrel != null and not PlayerProgress.is_unlocked(barrel))
		or (shaft != null and not PlayerProgress.is_unlocked(shaft))
		or (flight != null and not PlayerProgress.is_unlocked(flight))
	)
	_begin_button.disabled = any_locked
	_begin_button.modulate = Color(0.4, 0.4, 0.4) if any_locked else Color(1.0, 1.0, 1.0)


## Called when a component is unlocked during play.
func _on_component_unlocked(component: DartComponent) -> void:
	if component.id != &"":
		_unseen_new_ids[component.id] = true


## Mark currently viewed components as seen and refresh the labels.
func _refresh_new_parts() -> void:
	_mark_current_seen()
	_update_new_labels()


## Mark the currently viewed component in each slot as seen.
func _mark_current_seen() -> void:
	if _barrel_idx < _barrels.size():
		_unseen_new_ids.erase(_barrels[_barrel_idx].id)
	if _shaft_idx < _shafts.size():
		_unseen_new_ids.erase(_shafts[_shaft_idx].id)
	if _flight_idx < _flights.size():
		_unseen_new_ids.erase(_flights[_flight_idx].id)
	_update_new_labels()


## Show or hide the "New Parts!" label for each slot based on unseen parts.
func _update_new_labels() -> void:
	if _barrel_new_label:
		_barrel_new_label.visible = _slot_has_unseen(_barrels)
	if _shaft_new_label:
		_shaft_new_label.visible = _slot_has_unseen(_shafts)
	if _flight_new_label:
		_flight_new_label.visible = _slot_has_unseen(_flights)


func _slot_has_unseen(parts: Array[DartComponent]) -> bool:
	for part: DartComponent in parts:
		if part != null and _unseen_new_ids.has(part.id):
			return true
	return false


func _refresh_slot(slot_name: String) -> void:
	var part: DartComponent = null
	var name_label: Label = null
	var stats_label: RichTextLabel = null
	var preview: ColorRect = null
	var tex_rect: TextureRect = null
	var perk_label: Label = null

	match slot_name:
		"barrel":
			part = _barrels[_barrel_idx] if _barrel_idx < _barrels.size() else null
			name_label = _barrel_name
			stats_label = _barrel_stats
			preview = _barrel_preview
			tex_rect = _barrel_tex
			perk_label = _barrel_perk
		"shaft":
			part = _shafts[_shaft_idx] if _shaft_idx < _shafts.size() else null
			name_label = _shaft_name
			stats_label = _shaft_stats
			preview = _shaft_preview
			tex_rect = _shaft_tex
			perk_label = _shaft_perk
		"flight":
			part = _flights[_flight_idx] if _flight_idx < _flights.size() else null
			name_label = _flight_name
			stats_label = _flight_stats
			preview = _flight_preview
			tex_rect = _flight_tex
			perk_label = _flight_perk

	if part == null:
		if name_label:
			name_label.text = "(none)"
		if stats_label:
			stats_label.text = ""
		_update_perk_display(null, perk_label)
		return

	var is_locked: bool = not PlayerProgress.is_unlocked(part)

	if name_label:
		if is_locked:
			name_label.text = "[Locked]"
			name_label.modulate = Color(0.5, 0.5, 0.5)
		else:
			name_label.text = part.component_name
			name_label.modulate = Color(1.0, 1.0, 1.0)

	if stats_label:
		if is_locked:
			var hint: String = ""
			if part.unlock_condition != null and part.unlock_condition.description != "":
				hint = part.unlock_condition.description
			else:
				hint = "???"
			stats_label.text = "[center][color=#888888]%s[/color][/center]" % hint
		else:
			stats_label.text = "[center]" + part.get_bbcode_tooltip() + "[/center]"

	if is_locked:
		_update_perk_display(null, perk_label)
	else:
		_update_perk_display(part, perk_label)

	if tex_rect:
		if part.texture and not is_locked:
			tex_rect.texture = part.texture
			tex_rect.visible = true
			tex_rect.modulate = Color(1.0, 1.0, 1.0)
			if preview:
				preview.visible = false
		elif part.texture and is_locked:
			tex_rect.texture = part.texture
			tex_rect.visible = true
			tex_rect.modulate = Color(0.08, 0.08, 0.08)
			if preview:
				preview.visible = false
		else:
			tex_rect.texture = null
			tex_rect.visible = false
			if preview:
				preview.visible = true


func _refresh_stat_bars() -> void:
	if dart_build == null:
		return
	var bonuses: Dictionary = dart_build.get_total_stat_bonuses()

	for key: String in STAT_KEYS:
		var base_val: float = base_stats.get(key, 0.0)
		var total: float = base_val + bonuses[key]
		var bar_fill: ColorRect = _stat_bars[key]
		var val_label: Label = _stat_value_labels[key]

		var fill_fraction: float = clampf(total / STAT_MAX_VALUE, 0.0, 1.0)
		bar_fill.size = Vector2(stat_bar_width * fill_fraction, stat_bar_height)

		# Color based on bonus direction
		if bonuses[key] > 0.0:
			bar_fill.color = Color(0.3, 0.75, 0.4)
		elif bonuses[key] < 0.0:
			bar_fill.color = Color(0.75, 0.35, 0.3)
		else:
			bar_fill.color = Color(0.5, 0.5, 0.5)

		val_label.text = str(roundi(total))


func _refresh_balance() -> void:
	if dart_build == null:
		return

	var balance: float = dart_build.get_balance_value()
	var zone: String = dart_build.get_balance_zone_detailed()

	_balance_label.text = "Balance: %+.2f" % balance

	match zone:
		"perfect":
			var total_bonus: float = dart_build.green_bonus + dart_build.perfect_bonus
			_zone_label.text = "PERFECT (+%.0f all stats)" % total_bonus
			_zone_label.modulate = Color(0.2, 1.0, 0.5)
		"green":
			_zone_label.text = "GREEN (+%.0f all stats)" % dart_build.green_bonus
			_zone_label.modulate = Color(0.3, 1.0, 0.4)
		"green_orange":
			_zone_label.text = "TRANSITION (+%.1f all stats)" % dart_build.green_orange_transition_bonus
			_zone_label.modulate = Color(0.6, 0.9, 0.35)
		"orange":
			_zone_label.text = "ORANGE (neutral)"
			_zone_label.modulate = Color(1.0, 0.8, 0.3)
		"orange_red":
			var skew: float = dart_build.get_accuracy_skew()
			_zone_label.text = "TRANSITION (skew: %+.1f px)" % skew
			_zone_label.modulate = Color(0.9, 0.55, 0.3)
		"red":
			var skew: float = dart_build.get_accuracy_skew()
			_zone_label.text = "RED (skew: %+.1f px)" % skew
			_zone_label.modulate = Color(1.0, 0.4, 0.3)

	if _balance_bar:
		_balance_bar.queue_redraw()


func _update_perk_display(part: DartComponent, perk_label: Label) -> void:
	if perk_label == null:
		return
	if part == null or part.throw_modifier == null:
		perk_label.visible = false
		return

	perk_label.visible = true
	var modifier: ThrowModifier = part.throw_modifier
	var lines: String = "── PERK ──\n"
	lines += '"%s"\n' % modifier.modifier_name

	var bonus_parts: Array[String] = []
	if modifier.h_range_bonus != 0.0:
		bonus_parts.append("H Range %+.0f" % modifier.h_range_bonus)
	if modifier.v_range_bonus != 0.0:
		bonus_parts.append("V Range %+.0f" % modifier.v_range_bonus)
	if modifier.h_speed_bonus != 0.0:
		bonus_parts.append("H Speed Control %+.0f" % modifier.h_speed_bonus)
	if modifier.v_speed_bonus != 0.0:
		bonus_parts.append("V Speed Control %+.0f" % modifier.v_speed_bonus)
	if modifier.h_accuracy_bonus != 0.0:
		bonus_parts.append("H Accuracy %+.0f" % modifier.h_accuracy_bonus)
	if modifier.v_accuracy_bonus != 0.0:
		bonus_parts.append("V Accuracy %+.0f" % modifier.v_accuracy_bonus)
	if modifier.gaussian_spread_override > 0.0:
		bonus_parts.append("Precision → %.2f" % modifier.gaussian_spread_override)

	if bonus_parts.size() > 0:
		lines += ", ".join(bonus_parts) + "\n"

	lines += modifier.description
	perk_label.text = lines


func _create_tooltip_theme() -> Theme:
	var t: Theme = Theme.new()
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8)
	panel_style.border_color = Color(0.4, 0.4, 0.5, 0.6)
	panel_style.set_border_width_all(1)
	t.set_stylebox("panel", "TooltipPanel", panel_style)
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "TooltipLabel", Color(0.9, 0.9, 0.9))
	return t


# ── Zone Preview ─────────────────────────────────────────────────────────────

func _build_zone_preview() -> void:
	var preview_title: Label = Label.new()
	preview_title.text = "— Zone Preview —"
	preview_title.position = zone_preview_position + Vector2(0.0, zone_preview_label_offset)
	preview_title.size = Vector2(zone_preview_size.x, 20.0)
	preview_title.add_theme_font_size_override("font_size", 14)
	preview_title.modulate = Color(0.8, 0.8, 0.6)
	add_child(preview_title)

	_zone_preview = Control.new()
	_zone_preview.position = zone_preview_position + Vector2(0.0, 22.0)
	_zone_preview.size = Vector2(zone_preview_size.x - 20.0, zone_preview_size.y - 22.0)
	_zone_preview.draw.connect(_draw_zone_preview)
	add_child(_zone_preview)


func _draw_zone_preview() -> void:
	if dart_build == null or _zone_preview == null:
		return

	var preview_ratio: float = zone_preview_board_radius / 300.0

	var bonuses: Dictionary = dart_build.get_total_stat_bonuses()
	var h_range: float = base_stats.get("horizontal_range", 20.0) + bonuses.get("horizontal_range", 0.0)
	var v_range: float = base_stats.get("vertical_range", 20.0) + bonuses.get("vertical_range", 0.0)
	var h_acc: float = base_stats.get("horizontal_accuracy", 25.0) + bonuses.get("horizontal_accuracy", 0.0)
	var v_acc: float = base_stats.get("vertical_accuracy", 25.0) + bonuses.get("vertical_accuracy", 0.0)

	## Map stats to pixel sizes — using in-game max/min values scaled by preview_ratio
	var h_range_n: float = clampf((h_range - 1.0) / 99.0, 0.0, 1.0)
	var v_range_n: float = clampf((v_range - 1.0) / 99.0, 0.0, 1.0)
	var h_acc_n: float = clampf((h_acc - 1.0) / 99.0, 0.0, 1.0)
	var v_acc_n: float = clampf((v_acc - 1.0) / 99.0, 0.0, 1.0)

	var aim_half_w: float = lerpf(270.0, 8.0, h_range_n) * preview_ratio
	var aim_half_h: float = lerpf(270.0, 5.0, v_range_n) * preview_ratio
	var acc_half_w: float = lerpf(80.0, 5.0, h_acc_n) * preview_ratio
	var acc_half_h: float = lerpf(90.0, 5.0, v_acc_n) * preview_ratio

	var center: Vector2 = Vector2(_zone_preview.size.x / 2.0, _zone_preview.size.y / 2.0)

	## Mini dartboard (background reference)
	_draw_preview_dartboard(center)

	## Read colors from throw_mechanic (with fallback defaults)
	var aim_base: Color = throw_mechanic.aim_line_color if throw_mechanic else Color(0.2, 0.5, 1.0, 0.3)
	var acc_base: Color = throw_mechanic.resolve_preview_color if throw_mechanic else Color(1.0, 0.9, 0.2, 0.25)
	var v_glow: Color = throw_mechanic.vertical_glow_color if throw_mechanic else Color(1.0, 0.3, 0.3, 0.15)
	var h_glow: Color = throw_mechanic.horizontal_glow_color if throw_mechanic else Color(0.3, 0.5, 1.0, 0.15)

	## Aim ellipse (outer)
	var aim_outline_color: Color = Color(aim_base.r, aim_base.g, aim_base.b, minf(aim_base.a + 0.3, 1.0))
	_draw_preview_ellipse_filled(center, aim_half_w, aim_half_h, aim_base)
	_draw_preview_ellipse_outline(center, aim_half_w, aim_half_h, aim_outline_color)

	## Accuracy ellipse (inner)
	var acc_outline_color: Color = Color(acc_base.r, acc_base.g, acc_base.b, minf(acc_base.a + 0.3, 1.0))
	_draw_preview_ellipse_filled(center, acc_half_w, acc_half_h, acc_base)
	_draw_preview_ellipse_outline(center, acc_half_w, acc_half_h, acc_outline_color)

	## V speed line — horizontal line bouncing up and down, clipped to aim ellipse
	var v_offset: float = sin(_v_bounce_t) * aim_half_h
	var v_line_y: float = center.y + v_offset
	var v_dy: float = v_offset / aim_half_h if aim_half_h > 0.0 else 0.0
	var v_x_extent: float = aim_half_w * sqrt(maxf(1.0 - v_dy * v_dy, 0.0))
	var v_line_color: Color = Color(v_glow.r, v_glow.g, v_glow.b, 0.7)
	_zone_preview.draw_line(Vector2(center.x - v_x_extent, v_line_y), Vector2(center.x + v_x_extent, v_line_y), v_line_color, 1.5)

	## H speed line — vertical line bouncing left and right, clipped to aim ellipse
	var h_offset: float = sin(_h_bounce_t) * aim_half_w
	var h_line_x: float = center.x + h_offset
	var h_dx: float = h_offset / aim_half_w if aim_half_w > 0.0 else 0.0
	var h_y_extent: float = aim_half_h * sqrt(maxf(1.0 - h_dx * h_dx, 0.0))
	var h_line_color: Color = Color(h_glow.r, h_glow.g, h_glow.b, 0.7)
	_zone_preview.draw_line(Vector2(h_line_x, center.y - h_y_extent), Vector2(h_line_x, center.y + h_y_extent), h_line_color, 1.5)

	## Crosshair at center
	var cross_color: Color = Color(1.0, 1.0, 1.0, 0.4)
	_zone_preview.draw_line(center + Vector2(-5.0, 0.0), center + Vector2(5.0, 0.0), cross_color, 1.0)
	_zone_preview.draw_line(center + Vector2(0.0, -5.0), center + Vector2(0.0, 5.0), cross_color, 1.0)

	## Labels
	var aim_label_pos: Vector2 = center + Vector2(aim_half_w + 4.0, -8.0)
	var acc_label_pos: Vector2 = center + Vector2(acc_half_w + 4.0, 4.0)
	_zone_preview.draw_string(ThemeDB.fallback_font, aim_label_pos, "aim", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, aim_outline_color)
	_zone_preview.draw_string(ThemeDB.fallback_font, acc_label_pos, "accuracy", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, acc_outline_color)


func _draw_preview_dartboard(center: Vector2) -> void:
	var r: float = zone_preview_board_radius

	# Surround
	_zone_preview.draw_circle(center, r * 0.93, Color(0.12, 0.12, 0.12))

	# Wedge colors (muted so overlays stay readable)
	var single_a: Color = Color(0.06, 0.06, 0.06)
	var multi_a: Color = Color(0.35, 0.05, 0.05)
	var single_b: Color = Color(0.4, 0.38, 0.32)
	var multi_b: Color = Color(0.0, 0.22, 0.06)

	for wedge_idx: int in range(20):
		var start_deg: float = wedge_idx * 18.0 - 9.0
		var end_deg: float = start_deg + 18.0
		var is_even: bool = wedge_idx % 2 == 0
		var sc: Color = single_a if is_even else single_b
		var mc: Color = multi_a if is_even else multi_b

		_draw_board_segment(center, start_deg, end_deg, r * 0.83, r * 0.76, mc)
		_draw_board_segment(center, start_deg, end_deg, r * 0.76, r * 0.53, sc)
		_draw_board_segment(center, start_deg, end_deg, r * 0.53, r * 0.48, mc)
		_draw_board_segment(center, start_deg, end_deg, r * 0.48, r * 0.08, sc)

	# Bull
	_zone_preview.draw_circle(center, r * 0.08, Color(0.0, 0.22, 0.06))
	_zone_preview.draw_circle(center, r * 0.032, Color(0.35, 0.05, 0.05))

	# Wire rings
	var wire: Color = Color(0.4, 0.4, 0.4, 0.4)
	for ring_r: float in [0.032, 0.08, 0.48, 0.53, 0.76, 0.83]:
		_draw_board_ring(center, r * ring_r, wire)

	# Wedge boundary wires
	for wedge_idx: int in range(20):
		var angle_rad: float = deg_to_rad(wedge_idx * 18.0 - 9.0)
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		_zone_preview.draw_line(center + direction * r * 0.08, center + direction * r * 0.83, wire, 1.0)


func _draw_board_segment(center: Vector2, start_deg: float, end_deg: float, outer_r: float, inner_r: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var arc_pts: int = 6
	for i: int in range(arc_pts + 1):
		var t: float = float(i) / float(arc_pts)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(center + direction * outer_r)
	for i: int in range(arc_pts + 1):
		var t: float = float(i) / float(arc_pts)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(center + direction * inner_r)
	_zone_preview.draw_colored_polygon(points, color)


func _draw_board_ring(center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var num_pts: int = 48
	for i: int in range(num_pts + 1):
		var angle: float = TAU * float(i) / float(num_pts)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_zone_preview.draw_polyline(points, color, 1.0)


func _draw_preview_ellipse_filled(center: Vector2, half_w: float, half_h: float, color: Color, segments: int = 48) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * half_w, sin(angle) * half_h))
	_zone_preview.draw_colored_polygon(points, color)


func _draw_preview_ellipse_outline(center: Vector2, half_w: float, half_h: float, color: Color, segments: int = 48) -> void:
	for i: int in range(segments):
		var angle_a: float = TAU * float(i) / float(segments)
		var angle_b: float = TAU * float(i + 1) / float(segments)
		var point_a: Vector2 = center + Vector2(cos(angle_a) * half_w, sin(angle_a) * half_h)
		var point_b: Vector2 = center + Vector2(cos(angle_b) * half_w, sin(angle_b) * half_h)
		_zone_preview.draw_line(point_a, point_b, color, 1.5)


func _on_begin_run() -> void:
	visible = false
	run_confirmed.emit()
