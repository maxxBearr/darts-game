class_name AssemblyScreen
extends Control
## Full-screen pre-run overlay where the player assembles their dart from
## three components (barrel, shaft, flight). Shows stat bars, balance meter,
## and a dart preview. Emits run_confirmed when the player clicks Begin Run.

signal run_confirmed

var dart_build: DartBuild
var registry: DartComponentRegistry
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
	"horizontal_range": "Narrows the horizontal aiming band. Also reduces the distance the horizontal marker travels, making it easier to time.",
	"vertical_range": "Shrinks the vertical positioning window. Also reduces the distance the vertical marker travels, making it easier to time.",
	"horizontal_speed": "Slows the horizontal release marker. Higher = easier to time your click.",
	"vertical_speed": "Slows the vertical release marker. Higher = easier to time your click.",
	"horizontal_accuracy": "Tightens horizontal dart landing variance. Higher = dart lands closer to where you clicked.",
	"vertical_accuracy": "Tightens vertical dart landing variance. Higher = dart lands closer to where you clicked.",
}

const BAR_MAX_WIDTH: float = 180.0
const BAR_HEIGHT: float = 14.0
const STAT_MAX_VALUE: float = 100.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Background overlay
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Title
	_title_label = Label.new()
	_title_label.text = "Assemble Your Dart"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(0.0, 20.0)
	_title_label.size = Vector2(1280.0, 40.0)
	_title_label.add_theme_font_size_override("font_size", 32)
	add_child(_title_label)

	# Dart preview area (center-top)
	_build_dart_preview()

	# Part selectors (center row)
	_build_slot_selector("barrel", 100.0, 200.0)
	_build_slot_selector("shaft", 490.0, 200.0)
	_build_slot_selector("flight", 880.0, 200.0)

	# Stat bars (left column)
	_build_stat_bars()

	# Balance bar (center-bottom)
	_build_balance_bar()

	# Begin Run button
	_begin_button = Button.new()
	_begin_button.text = "Begin Run"
	_begin_button.position = Vector2(540.0, 610.0)
	_begin_button.size = Vector2(200.0, 50.0)
	_begin_button.add_theme_font_size_override("font_size", 22)
	_begin_button.pressed.connect(_on_begin_run)
	add_child(_begin_button)


func _build_dart_preview() -> void:
	var preview_container: HBoxContainer = HBoxContainer.new()
	preview_container.position = Vector2(440.0, 70.0)
	preview_container.size = Vector2(400.0, 100.0)
	preview_container.add_theme_constant_override("separation", -3)
	preview_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(preview_container)

	# Barrel slot
	var barrel_holder: Control = Control.new()
	barrel_holder.custom_minimum_size = Vector2(140.0, 80.0)
	preview_container.add_child(barrel_holder)

	_barrel_preview = ColorRect.new()
	_barrel_preview.color = SLOT_COLORS["barrel"]
	_barrel_preview.size = Vector2(140.0, 80.0)
	barrel_holder.add_child(_barrel_preview)

	_barrel_tex = TextureRect.new()
	_barrel_tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_barrel_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_barrel_tex.size = Vector2(140.0, 80.0)
	barrel_holder.add_child(_barrel_tex)

	var barrel_slot_label: Label = Label.new()
	barrel_slot_label.text = "Barrel"
	barrel_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	barrel_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	barrel_slot_label.size = Vector2(140.0, 80.0)
	barrel_slot_label.add_theme_font_size_override("font_size", 12)
	barrel_slot_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
	barrel_holder.add_child(barrel_slot_label)

	# Shaft slot
	var shaft_holder: Control = Control.new()
	shaft_holder.custom_minimum_size = Vector2(100.0, 80.0)
	preview_container.add_child(shaft_holder)

	_shaft_preview = ColorRect.new()
	_shaft_preview.color = SLOT_COLORS["shaft"]
	_shaft_preview.size = Vector2(100.0, 80.0)
	shaft_holder.add_child(_shaft_preview)

	_shaft_tex = TextureRect.new()
	_shaft_tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_shaft_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shaft_tex.size = Vector2(100.0, 80.0)
	shaft_holder.add_child(_shaft_tex)

	var shaft_slot_label: Label = Label.new()
	shaft_slot_label.text = "Shaft"
	shaft_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shaft_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shaft_slot_label.size = Vector2(100.0, 80.0)
	shaft_slot_label.add_theme_font_size_override("font_size", 12)
	shaft_slot_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
	shaft_holder.add_child(shaft_slot_label)

	# Flight slot
	var flight_holder: Control = Control.new()
	flight_holder.custom_minimum_size = Vector2(120.0, 80.0)
	preview_container.add_child(flight_holder)

	_flight_preview = ColorRect.new()
	_flight_preview.color = SLOT_COLORS["flight"]
	_flight_preview.size = Vector2(120.0, 80.0)
	flight_holder.add_child(_flight_preview)

	_flight_tex = TextureRect.new()
	_flight_tex.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	_flight_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flight_tex.size = Vector2(120.0, 80.0)
	flight_holder.add_child(_flight_tex)

	var flight_slot_label: Label = Label.new()
	flight_slot_label.text = "Flight"
	flight_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flight_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flight_slot_label.size = Vector2(120.0, 80.0)
	flight_slot_label.add_theme_font_size_override("font_size", 12)
	flight_slot_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
	flight_holder.add_child(flight_slot_label)


func _build_slot_selector(slot_name: String, x: float, y: float) -> void:
	var container: VBoxContainer = VBoxContainer.new()
	container.position = Vector2(x, y)
	container.size = Vector2(260.0, 200.0)
	container.add_theme_constant_override("separation", 4)
	add_child(container)

	# Slot title
	var title: Label = Label.new()
	title.text = slot_name.capitalize()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
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
	name_label.add_theme_font_size_override("font_size", 16)
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
	stats_label.custom_minimum_size = Vector2(260.0, 0.0)
	stats_label.add_theme_font_size_override("normal_font_size", 13)
	container.add_child(stats_label)

	# Perk label (shown below stats when component has a throw modifier)
	var perk_label: Label = Label.new()
	perk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perk_label.custom_minimum_size = Vector2(260.0, 0.0)
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
		"shaft":
			_shaft_name = name_label
			_shaft_stats = stats_label
			_shaft_perk = perk_label
		"flight":
			_flight_name = name_label
			_flight_stats = stats_label
			_flight_perk = perk_label


func _build_stat_bars() -> void:
	var stats_container: VBoxContainer = VBoxContainer.new()
	stats_container.position = Vector2(40.0, 430.0)
	stats_container.size = Vector2(300.0, 200.0)
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
		name_lbl.custom_minimum_size = Vector2(100.0, BAR_HEIGHT + 4.0)
		name_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(name_lbl)

		# Bar background
		var bar_bg: ColorRect = ColorRect.new()
		bar_bg.color = Color(0.15, 0.15, 0.2)
		bar_bg.custom_minimum_size = Vector2(BAR_MAX_WIDTH, BAR_HEIGHT)
		row.add_child(bar_bg)

		# Bar fill (child of bg so it overlays)
		var bar_fill: ColorRect = ColorRect.new()
		bar_fill.color = Color(0.3, 0.7, 0.4)
		bar_fill.size = Vector2(0.0, BAR_HEIGHT)
		bar_bg.add_child(bar_fill)

		# Value label
		var val_lbl: Label = Label.new()
		val_lbl.custom_minimum_size = Vector2(40.0, BAR_HEIGHT + 4.0)
		val_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(val_lbl)

		_stat_bars[key] = bar_fill
		_stat_value_labels[key] = val_lbl


func _build_balance_bar() -> void:
	var balance_container: VBoxContainer = VBoxContainer.new()
	balance_container.position = Vector2(400.0, 500.0)
	balance_container.size = Vector2(480.0, 90.0)
	balance_container.add_theme_constant_override("separation", 4)
	add_child(balance_container)

	var balance_title: Label = Label.new()
	balance_title.text = "— Balance —"
	balance_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	balance_title.add_theme_font_size_override("font_size", 16)
	balance_title.modulate = Color(0.8, 0.8, 0.6)
	balance_container.add_child(balance_title)

	_balance_bar = Control.new()
	_balance_bar.custom_minimum_size = Vector2(460.0, 30.0)
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
	var green_px: float = (dart_build.green_threshold / 1.5) * half_w if dart_build else half_w * 0.17
	var orange_px: float = (dart_build.orange_threshold / 1.5) * half_w if dart_build else half_w * 0.33

	# Red zones (outer)
	_balance_bar.draw_rect(Rect2(0.0, 0.0, w, h), Color(0.7, 0.2, 0.2, 0.6))

	# Orange zones
	_balance_bar.draw_rect(Rect2(half_w - orange_px, 0.0, orange_px * 2.0, h), Color(0.8, 0.6, 0.2, 0.6))

	# Green zone (center)
	_balance_bar.draw_rect(Rect2(half_w - green_px, 0.0, green_px * 2.0, h), Color(0.2, 0.7, 0.3, 0.6))

	# Needle
	var balance: float = dart_build.get_balance_value() if dart_build else 0.0
	var needle_x: float = half_w + (balance / 1.5) * half_w
	needle_x = clampf(needle_x, 4.0, w - 4.0)
	_balance_bar.draw_rect(Rect2(needle_x - 2.0, -2.0, 4.0, h + 4.0), Color(1.0, 1.0, 1.0, 0.95))

	# Border
	_balance_bar.draw_rect(Rect2(0.0, 0.0, w, h), Color(0.5, 0.5, 0.5, 0.6), false, 1.0)


## Show the assembly screen with the given base stats for bar display.
## Preserves the player's previous dart build when returning between runs.
func show_assembly(p_base_stats: Dictionary) -> void:
	base_stats = p_base_stats

	if registry:
		_barrels = registry.get_unlocked_barrels()
		_shafts = registry.get_unlocked_shafts()
		_flights = registry.get_unlocked_flights()

	if dart_build:
		_barrel_idx = _find_component_index(_barrels, dart_build.equipped_barrel)
		_shaft_idx = _find_component_index(_shafts, dart_build.equipped_shaft)
		_flight_idx = _find_component_index(_flights, dart_build.equipped_flight)

		if _barrels.size() > 0:
			dart_build.equip_barrel(_barrels[_barrel_idx])
		if _shafts.size() > 0:
			dart_build.equip_shaft(_shafts[_shaft_idx])
		if _flights.size() > 0:
			dart_build.equip_flight(_flights[_flight_idx])

	_refresh_all()
	visible = true


## Find the index of a component in a list, defaulting to 0 if not found.
func _find_component_index(parts: Array[DartComponent], current: DartComponent) -> int:
	if current != null:
		for i: int in range(parts.size()):
			if parts[i] == current:
				return i
	return 0


func _on_arrow_pressed(slot_name: String, direction: int) -> void:
	match slot_name:
		"barrel":
			if _barrels.size() == 0:
				return
			_barrel_idx = wrapi(_barrel_idx + direction, 0, _barrels.size())
			if dart_build:
				dart_build.equip_barrel(_barrels[_barrel_idx])
		"shaft":
			if _shafts.size() == 0:
				return
			_shaft_idx = wrapi(_shaft_idx + direction, 0, _shafts.size())
			if dart_build:
				dart_build.equip_shaft(_shafts[_shaft_idx])
		"flight":
			if _flights.size() == 0:
				return
			_flight_idx = wrapi(_flight_idx + direction, 0, _flights.size())
			if dart_build:
				dart_build.equip_flight(_flights[_flight_idx])
	_refresh_all()


func _refresh_all() -> void:
	_refresh_slot("barrel")
	_refresh_slot("shaft")
	_refresh_slot("flight")
	_refresh_stat_bars()
	_refresh_balance()


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

	if name_label:
		name_label.text = part.component_name

	if stats_label:
		stats_label.text = "[center]" + part.get_bbcode_tooltip() + "[/center]"

	_update_perk_display(part, perk_label)

	# Update preview texture or placeholder
	if tex_rect:
		if part.texture:
			tex_rect.texture = part.texture
			tex_rect.visible = true
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
		bar_fill.size = Vector2(BAR_MAX_WIDTH * fill_fraction, BAR_HEIGHT)

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
	var zone: String = dart_build.get_balance_zone()

	_balance_label.text = "Balance: %+.2f" % balance

	match zone:
		"green":
			_zone_label.text = "GREEN (+%.0f all stats)" % dart_build.green_bonus
			_zone_label.modulate = Color(0.3, 1.0, 0.4)
		"orange":
			_zone_label.text = "ORANGE (neutral)"
			_zone_label.modulate = Color(1.0, 0.8, 0.3)
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


func _on_begin_run() -> void:
	visible = false
	run_confirmed.emit()
