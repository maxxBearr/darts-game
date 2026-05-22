extends CanvasLayer
## HUD overlay displaying X01 game state, per-dart feedback, upgrade cards, and control buttons.

signal next_dart_pressed
signal next_turn_pressed
signal next_leg_pressed
signal new_run_pressed
signal upgrade_selected(index: int)
signal modifier_selected(index: int)

@onready var score_label: Label = $ScoreLabel
@onready var instruction_label: Label = $InstructionLabel
@onready var remaining_label: Label = $RemainingLabel
@onready var turn_label: Label = $TurnLabel
@onready var dart_label: Label = $DartLabel
@onready var leg_label: Label = $LegLabel
@onready var bust_label: Label = $BustLabel
@onready var next_dart_button: Button = $NextDartButton
@onready var next_turn_button: Button = $NextTurnButton
@onready var next_leg_button: Button = $NextLegButton
@onready var new_run_button: Button = $NewRunButton
@onready var upgrade_container: HBoxContainer = $UpgradeContainer
@onready var upgrade_button_1: Button = $UpgradeContainer/UpgradeButton1
@onready var upgrade_button_2: Button = $UpgradeContainer/UpgradeButton2
@onready var upgrade_button_3: Button = $UpgradeContainer/UpgradeButton3
@onready var dart_indicator: Control = $DartIndicator
@onready var turn_score_label: Label = $TurnScoreLabel
@onready var hover_tooltip: Label = $HoverTooltip
@onready var modifier_tooltip: Label = $ModifierTooltip
@onready var modifier_panel: HBoxContainer = $ModifierPanel

## Size of each modifier square in the relic bar (pixels).
@export var modifier_square_size: int = 40

## Vertical offset above the crosshair for the hover tooltip (pixels).
@export var hover_tooltip_offset_y: float = 50.0

## How many pixels a modifier square lifts during perk-up hover state.
@export var perkup_lift_pixels: float = 8.0

## Duration of the perk-up lift/drop animation in seconds.
@export var perkup_anim_duration: float = 0.15

## Background opacity of upgrade/modifier pick buttons (0 = transparent, 1 = solid).
@export_range(0.0, 1.0, 0.05) var upgrade_button_opacity: float = 0.85

## Corner radius of upgrade/modifier pick buttons in pixels.
@export_range(0.0, 16.0, 1.0) var upgrade_button_corner_radius: float = 6.0

@onready var stats_container: VBoxContainer = $StatsContainer

const STAT_KEYS: Array[String] = [
	"horizontal_range", "vertical_range",
	"horizontal_speed", "vertical_speed",
	"horizontal_accuracy", "vertical_accuracy",
]

const STAT_DISPLAY_NAMES: Dictionary = {
	"horizontal_range": "H Range",
	"vertical_range": "V Range",
	"horizontal_speed": "H Spd Ctrl",
	"vertical_speed": "V Spd Ctrl",
	"horizontal_accuracy": "H Accuracy",
	"vertical_accuracy": "V Accuracy",
}

const STAT_DESCRIPTIONS: Dictionary = {
	"horizontal_range": "Shrinks the aim ellipse horizontally. Also reduces the distance the horizontal marker travels, making it easier to time.",
	"vertical_range": "Shrinks the aim ellipse vertically. Also reduces the distance the vertical marker travels, making it easier to time.",
	"horizontal_speed": "Slows the speed of the horizantal merer.",
	"vertical_speed": "Slows the speed of the vertical meter.",
	"horizontal_accuracy": "Shortens the width of the accruacy zone.",
	"vertical_accuracy": "Shrinks the height of the accuracy zone"
}

const BAR_MAX_WIDTH: float = 120.0
const BAR_HEIGHT: float = 12.0
const STAT_MAX_VALUE: float = 100.0

var _stat_bars: Dictionary = {}
var _stat_value_labels: Dictionary = {}
var _modifier_status_title: Label
var _modifier_rows: Array[Dictionary] = []

## Whether upgrade buttons are in modifier selection mode.
var _modifier_mode: bool = false

## Current upgrades for hover preview (set during accuracy pick phase).
var _preview_upgrades: Array[Dictionary] = []

## Cached current stats for restoring after hover preview.
var _cached_current_stats: Dictionary = {}

## Cached base stats for restoring after hover preview.
var _cached_base_stats: Dictionary = {}

## Color for stat bars showing a previewed upgrade boost.
const PREVIEW_BOOST_COLOR: Color = Color(0.3, 0.8, 1.0)

## Color for stat bars showing a previewed upgrade penalty.
const PREVIEW_PENALTY_COLOR: Color = Color(1.0, 0.5, 0.2)

## Picker header label (created on demand).
var _picker_header: Label
## Picker prompt label (created on demand).
var _picker_prompt: Label

## Total shop darts for the current shop (for "thrown/total" label).
var _shop_total_darts: int = 0


func _ready() -> void:
	# Connect action buttons
	next_dart_button.pressed.connect(func() -> void: next_dart_pressed.emit())
	next_turn_button.pressed.connect(func() -> void: next_turn_pressed.emit())
	next_leg_button.pressed.connect(func() -> void: next_leg_pressed.emit())
	new_run_button.pressed.connect(func() -> void: new_run_pressed.emit())

	# Connect upgrade buttons — each emits upgrade_selected with its index
	upgrade_button_1.pressed.connect(func() -> void: _select_upgrade(0))
	upgrade_button_2.pressed.connect(func() -> void: _select_upgrade(1))
	upgrade_button_3.pressed.connect(func() -> void: _select_upgrade(2))

	# Style upgrade/modifier pick buttons
	_apply_upgrade_button_style(upgrade_button_1)
	_apply_upgrade_button_style(upgrade_button_2)
	_apply_upgrade_button_style(upgrade_button_3)

	# Start with all buttons and optional labels hidden
	hide_all_buttons()
	bust_label.visible = false
	upgrade_container.visible = false
	hover_tooltip.visible = false
	modifier_tooltip.visible = false

	_build_stat_bars()


## Display the result of the current throw (per-dart feedback).
func show_score(result: Dictionary) -> void:
	var ring_name: String = result["ring_name"]
	if ring_name == "Off Board":
		score_label.text = "Off Board — 0 points"
	elif ring_name == "Double Bull":
		score_label.text = "Double Bull — 50 points!"
	elif ring_name == "Single Bull":
		score_label.text = "Single Bull — 25 points"
	else:
		var face: int = result["face_value"]
		var total: int = result["total_score"]
		score_label.text = "%s %d — %d points!" % [ring_name, face, total]


## Update the remaining score display.
func update_remaining(score: int) -> void:
	remaining_label.text = str(score)


## Set the remaining score label to gold when a single-dart checkout exists,
## or back to default when it doesn't. Driven by the same checkout logic
## that highlights finishing spots on the board — single source of truth.
func set_remaining_checkout_available(has_checkout: bool) -> void:
	if has_checkout:
		remaining_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		remaining_label.modulate = Color(1.0, 1.0, 1.0)


## Update the turn counter display.
func update_turn(turn: int, max_turns: int) -> void:
	if turn == max_turns:
		turn_label.text = "Turn %d/%d — LAST TURN!" % [turn, max_turns]
		turn_label.modulate = Color(1.0, 0.4, 0.3)
	else:
		turn_label.text = "Turn %d/%d" % [turn, max_turns]
		turn_label.modulate = Color(1.0, 1.0, 1.0)


## Update the dart counter display and visual indicator.
func update_darts(darts_remaining: int, is_last_turn: bool = false) -> void:
	dart_label.text = "Dart %d/3" % [3 - darts_remaining]
	dart_indicator.set_darts_remaining(darts_remaining)
	if darts_remaining == 1 and is_last_turn:
		dart_label.text = "FINAL DART!"
		dart_label.add_theme_font_size_override("font_size", 28)
		dart_label.modulate = Color(1.0, 0.25, 0.2)
		_shake_label(dart_label)
	elif darts_remaining == 1:
		dart_label.text += " — LAST DART!"
		dart_label.remove_theme_font_size_override("font_size")
		dart_label.modulate = Color(1.0, 1.0, 1.0)
	else:
		dart_label.remove_theme_font_size_override("font_size")
		dart_label.modulate = Color(1.0, 1.0, 1.0)


func _shake_label(label: Label) -> void:
	var original_pos: Vector2 = label.position
	var tween: Tween = create_tween()
	for i: int in range(6):
		var offset: Vector2 = Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0))
		tween.tween_property(label, "position", original_pos + offset, 0.05)
	tween.tween_property(label, "position", original_pos, 0.05)


## Update the leg label display.
func update_leg(leg: int, target: int) -> void:
	leg_label.text = "Leg %d — %d" % [leg, target]


## Show bust message and make the bust label visible.
func show_bust(reason: String) -> void:
	bust_label.text = "BUST! %s" % reason
	bust_label.visible = true


## Show leg complete message with upgrade card choices.
func show_leg_complete_with_upgrades(leg: int, target: int, turns_used: int, upgrades: Array[Dictionary]) -> void:
	score_label.text = "Leg %d Complete! Cleared %d in %d turns" % [leg, target, turns_used]
	_preview_upgrades = upgrades

	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var upgrade: Dictionary = upgrades[i]
		var button_text: String = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
		if upgrade["tradeoff"]:
			button_text += "\n-%d %s" % [upgrade["penalty_amount"], upgrade["penalty_name"]]
		buttons[i].text = button_text
		var color: Color = upgrade["color"]
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = upgrade["description"]
		buttons[i].visible = true

		# Connect hover preview signals (disconnect any previous connections)
		if buttons[i].mouse_entered.is_connected(_on_upgrade_hover):
			buttons[i].mouse_entered.disconnect(_on_upgrade_hover)
		if buttons[i].mouse_exited.is_connected(_on_upgrade_unhover):
			buttons[i].mouse_exited.disconnect(_on_upgrade_unhover)
		buttons[i].mouse_entered.connect(_on_upgrade_hover.bind(i))
		buttons[i].mouse_exited.connect(_on_upgrade_unhover)

	upgrade_container.visible = true
	next_leg_button.visible = false



## Show game over message.
func show_game_over(leg_reached: int, target_reached: int) -> void:
	score_label.text = "Run Over! Reached Leg %d (%d)" % [leg_reached, target_reached]
	new_run_button.visible = true


## Hide all action buttons.
func hide_all_buttons() -> void:
	next_dart_button.visible = false
	next_turn_button.visible = false
	next_leg_button.visible = false
	new_run_button.visible = false


## Hide the bust label.
func reset_bust() -> void:
	bust_label.visible = false


## Show instruction text to the player.
func show_instruction(text: String) -> void:
	instruction_label.text = text


## Hide the per-dart score text and all buttons (called at start of each throw).
func hide_score() -> void:
	score_label.text = ""
	hide_all_buttons()
	reset_bust()
	upgrade_container.visible = false


## Show a fresh set of upgrade choices (for subsequent rounds).
func show_upgrade_choices(upgrades: Array[Dictionary]) -> void:
	score_label.text = "Choose another upgrade!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var upgrade: Dictionary = upgrades[i]
		var button_text: String = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
		if upgrade["tradeoff"]:
			button_text += "\n-%d %s" % [upgrade["penalty_amount"], upgrade["penalty_name"]]
		buttons[i].text = button_text
		var color: Color = upgrade["color"]
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = upgrade["description"]
	upgrade_container.visible = true
	next_leg_button.visible = false


## Update the turn score display.
func update_turn_score(score: int) -> void:
	turn_score_label.text = "Turn Score: %d" % score


## Build stat bar rows inside the StatsContainer, replacing scene-defined labels.
func _build_stat_bars() -> void:
	for child: Node in stats_container.get_children():
		child.queue_free()

	var tooltip_theme: Theme = _create_tooltip_theme()
	stats_container.theme = tooltip_theme

	var title: Label = Label.new()
	title.text = "— Stats —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.8, 0.8, 0.6)
	stats_container.add_child(title)

	for key: String in STAT_KEYS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = STAT_DESCRIPTIONS[key]
		stats_container.add_child(row)

		var name_lbl: Label = Label.new()
		name_lbl.text = STAT_DISPLAY_NAMES[key] + ":"
		name_lbl.custom_minimum_size = Vector2(90.0, BAR_HEIGHT + 2.0)
		name_lbl.size_flags_horizontal = 0
		name_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(name_lbl)

		var bar_bg: ColorRect = ColorRect.new()
		bar_bg.color = Color(0.15, 0.15, 0.2)
		bar_bg.custom_minimum_size = Vector2(BAR_MAX_WIDTH, BAR_HEIGHT)
		bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar_bg)

		var bar_fill: ColorRect = ColorRect.new()
		bar_fill.color = Color(0.3, 0.7, 0.4)
		bar_fill.position = Vector2.ZERO
		bar_fill.size = Vector2(0.0, BAR_HEIGHT)
		bar_bg.add_child(bar_fill)

		var val_lbl: Label = Label.new()
		val_lbl.custom_minimum_size = Vector2(30.0, BAR_HEIGHT + 2.0)
		val_lbl.size_flags_horizontal = 0
		val_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(val_lbl)

		_stat_bars[key] = bar_fill
		_stat_value_labels[key] = val_lbl


## Update the stats panel bars with current values and color coding.
func update_stats(stats: Dictionary, base_stats: Dictionary) -> void:
	for key: String in STAT_KEYS:
		var current: float = stats[key]
		var base: float = base_stats[key]

		if key == "horizontal_speed" or key == "vertical_speed":
			current = float(_speed_to_display(current))
			base = float(_speed_to_display(base))

		var bar_fill: ColorRect = _stat_bars[key]
		var val_label: Label = _stat_value_labels[key]
		var bar_width: float = bar_fill.get_parent().size.x if bar_fill.get_parent().size.x > 0.0 else BAR_MAX_WIDTH

		var fill_fraction: float = clampf(current / STAT_MAX_VALUE, 0.0, 1.0)
		bar_fill.size = Vector2(bar_width * fill_fraction, BAR_HEIGHT)

		if current > base:
			bar_fill.color = Color(0.3, 0.75, 0.4)
		elif current < base:
			bar_fill.color = Color(0.75, 0.35, 0.3)
		else:
			bar_fill.color = Color(0.5, 0.5, 0.5)

		val_label.text = str(roundi(current))


## Cache current stats so hover preview can restore them.
func cache_stats(stats: Dictionary, base_stats: Dictionary) -> void:
	_cached_current_stats = stats.duplicate()
	_cached_base_stats = base_stats.duplicate()


## Show a preview of what stats would look like if an upgrade were picked.
## Highlights the affected bar(s) in preview colors.
func _show_stat_preview(upgrade: Dictionary) -> void:
	if _cached_current_stats.is_empty():
		return

	var preview_stats: Dictionary = _cached_current_stats.duplicate()
	var property: String = upgrade["property"]
	var value: int = upgrade["value"]
	var scale: String = upgrade["scale"]

	# Apply the boost
	if scale == "direct":
		preview_stats[property] = minf(preview_stats[property] + float(value), 100.0)
	elif scale == "speed":
		var internal_boost: float = float(value) * (4.0 / 40.0)
		preview_stats[property] = minf(preview_stats[property] + internal_boost, 5.0)

	# Apply tradeoff penalty
	if upgrade["tradeoff"]:
		var penalty_prop: String = upgrade["penalty_property"]
		var penalty_amount: int = upgrade["penalty_amount"]
		preview_stats[penalty_prop] = preview_stats[penalty_prop] - float(penalty_amount)

	# Update bars with preview coloring
	for key: String in STAT_KEYS:
		var current: float = preview_stats[key]
		var base_val: float = _cached_current_stats[key]

		if key == "horizontal_speed" or key == "vertical_speed":
			current = float(_speed_to_display(current))
			base_val = float(_speed_to_display(base_val))

		var bar_fill: ColorRect = _stat_bars[key]
		var val_label: Label = _stat_value_labels[key]
		var bar_width: float = bar_fill.get_parent().size.x if bar_fill.get_parent().size.x > 0.0 else BAR_MAX_WIDTH

		var fill_fraction: float = clampf(current / STAT_MAX_VALUE, 0.0, 1.0)
		bar_fill.size = Vector2(bar_width * fill_fraction, BAR_HEIGHT)

		if current > base_val:
			bar_fill.color = PREVIEW_BOOST_COLOR
		elif current < base_val:
			bar_fill.color = PREVIEW_PENALTY_COLOR
		else:
			var cached_base: float = _cached_base_stats[key]
			if key == "horizontal_speed" or key == "vertical_speed":
				cached_base = float(_speed_to_display(cached_base))
			if base_val > cached_base:
				bar_fill.color = Color(0.3, 0.75, 0.4)
			elif base_val < cached_base:
				bar_fill.color = Color(0.75, 0.35, 0.3)
			else:
				bar_fill.color = Color(0.5, 0.5, 0.5)

		val_label.text = str(roundi(current))


## Called when the mouse enters an upgrade button — show stat preview.
## Only previews if the item at this index is an accuracy upgrade (not a modifier).
func _on_upgrade_hover(index: int) -> void:
	if index >= _preview_upgrades.size():
		return
	var upgrade: Dictionary = _preview_upgrades[index]
	if upgrade.is_empty():
		return
	_show_stat_preview(upgrade)


## Called when the mouse exits an upgrade button — restore real stats.
func _on_upgrade_unhover() -> void:
	if _cached_current_stats.is_empty():
		return
	update_stats(_cached_current_stats, _cached_base_stats)


## Convert internal speed (1.0-5.0) to a display value (0-100).
func _speed_to_display(speed: float) -> int:
	return roundi((speed - 1.0) / 4.0 * 100.0)


## Apply a StyleBoxFlat to an upgrade button for controllable opacity and corners.
func _apply_upgrade_button_style(button: Button) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, upgrade_button_opacity)
	style.set_corner_radius_all(int(upgrade_button_corner_radius))
	style.set_content_margin_all(8)
	style.border_color = Color(0.4, 0.4, 0.5, upgrade_button_opacity)
	style.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(0.2, 0.2, 0.28, minf(upgrade_button_opacity + 0.1, 1.0))
	hover_style.border_color = Color(0.5, 0.5, 0.6, minf(upgrade_button_opacity + 0.1, 1.0))
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style: StyleBoxFlat = style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.1, 0.15, upgrade_button_opacity)
	button.add_theme_stylebox_override("pressed", pressed_style)


## Create a Theme with opaque tooltip styling for readability.
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


## Populate the throw perk status section below stat bars.
func setup_modifier_status(modifiers: Array[Dictionary]) -> void:
	clear_modifier_status()
	if modifiers.is_empty():
		return

	_modifier_status_title = Label.new()
	_modifier_status_title.text = "— Throw Perks —"
	_modifier_status_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_status_title.add_theme_font_size_override("font_size", 14)
	_modifier_status_title.modulate = Color(0.8, 0.8, 0.6)
	stats_container.add_child(_modifier_status_title)

	for mod: Dictionary in modifiers:
		var row_container: VBoxContainer = VBoxContainer.new()
		row_container.add_theme_constant_override("separation", 1)
		stats_container.add_child(row_container)

		var name_label: Label = Label.new()
		name_label.text = "%s: Inactive" % mod["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.modulate = Color(0.5, 0.5, 0.5)
		row_container.add_child(name_label)

		var desc_label: Label = Label.new()
		desc_label.text = mod["description"]
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.modulate = Color(0.6, 0.8, 1.0, 0.0)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(280.0, 0.0)
		row_container.add_child(desc_label)

		_modifier_rows.append({
			"name": mod["name"],
			"active_color": mod.get("active_color", Color(0.3, 1.0, 0.4)),
			"name_label": name_label,
			"desc_label": desc_label,
		})


## Update throw perk active/inactive state each throw.
func update_modifier_status(active_names: Array[String]) -> void:
	for row: Dictionary in _modifier_rows:
		var is_active: bool = row["name"] in active_names
		var name_label: Label = row["name_label"]
		var desc_label: Label = row["desc_label"]
		var color: Color = row["active_color"]
		if is_active:
			name_label.text = "%s: Active" % row["name"]
			name_label.modulate = color
			desc_label.modulate = Color(color.r, color.g, color.b, 0.8)
		else:
			name_label.text = "%s: Inactive" % row["name"]
			name_label.modulate = Color(0.5, 0.5, 0.5)
			desc_label.modulate = Color(color.r, color.g, color.b, 0.0)


## Remove all throw perk status rows.
func clear_modifier_status() -> void:
	for row: Dictionary in _modifier_rows:
		(row["name_label"] as Label).get_parent().queue_free()
	_modifier_rows.clear()
	if _modifier_status_title != null:
		_modifier_status_title.queue_free()
		_modifier_status_title = null


## Show hover tooltip above the crosshair with simplified score readout.
## Positioned directly above the aim point for in-focus feedback during aiming.
## Format: "Target: D7 ×3 = 35" (with modifier), or "Target: D7 = 14" (without).
## Turns gold when hovering a segment that would win the leg in one dart.
## streak_lines: current streak display strings appended after the score readout.
func show_hover_tooltip(result: Dictionary, original_wedge_order: Array[int], screen_pos: Vector2 = Vector2.ZERO, is_checkout: bool = false, streak_lines: Array[String] = [], would_bust: bool = false) -> void:
	if result.is_empty():
		hover_tooltip.visible = false
		return

	var ring_name: String = result["ring_name"]
	var face_value: int = result["face_value"]
	var total_score: int = result["total_score"]
	var multiplier: int = result["multiplier"]
	var is_bull: bool = result.get("is_bull", false)

	if ring_name == "Off Board":
		hover_tooltip.visible = false
		return

	# Build simplified prefix (S/D/T/SB/DB)
	var prefix: String = _get_hover_prefix(ring_name)

	# Build the compact tooltip text
	var text: String
	var base_multiplier: int = _get_base_multiplier(ring_name)
	var bonus_mult: int = multiplier - base_multiplier
	if bonus_mult > 0:
		text = "Target: %s%d ×%d = %d" % [prefix, face_value, multiplier, total_score]
	else:
		text = "Target: %s%d = %d" % [prefix, face_value, total_score]

	# Append bust warning or streak info
	if would_bust:
		text += " | ⚠ BUST"
	else:
		for line: String in streak_lines:
			text += " | " + line

	hover_tooltip.text = text
	hover_tooltip.visible = true

	# Color: red for bust, gold for checkout, white otherwise
	if would_bust:
		hover_tooltip.modulate = Color(1.0, 0.3, 0.25)
	elif is_checkout:
		hover_tooltip.modulate = Color(1.0, 0.85, 0.2)
	else:
		hover_tooltip.modulate = Color(1.0, 1.0, 1.0)

	# Position above the crosshair
	if screen_pos != Vector2.ZERO:
		hover_tooltip.position = Vector2(
			screen_pos.x - hover_tooltip.size.x / 2.0,
			screen_pos.y - hover_tooltip_offset_y - hover_tooltip.size.y
		)


## Get the ring prefix abbreviation for the simplified tooltip.
func _get_hover_prefix(ring_name: String) -> String:
	match ring_name:
		"Inner Single", "Outer Single":
			return "S"
		"Double":
			return "D"
		"Triple":
			return "T"
		"Single Bull":
			return "SB"
		"Double Bull":
			return "DB"
	return ""


## Get the base multiplier for a ring type (before modifier effects).
func _get_base_multiplier(ring_name: String) -> int:
	match ring_name:
		"Double", "Double Bull":
			return 2
		"Triple":
			return 3
	return 1


## Hide the hover tooltip.
func hide_hover_tooltip() -> void:
	hover_tooltip.visible = false


## Show streak info during a throw (replaces the full target tooltip).
## Only displays active streak lines near the crosshair.
func show_streak_info(streak_lines: Array[String]) -> void:
	var text: String = ""
	for i: int in range(streak_lines.size()):
		if i > 0:
			text += " | "
		text += streak_lines[i]
	hover_tooltip.text = text
	hover_tooltip.visible = true


## Hide the target tooltip (when throw completes or new run starts).
func hide_target_tooltip() -> void:
	hover_tooltip.visible = false


## Highlight modifier squares whose modifiers triggered on the hovered segment.
## triggered_names: modifier_name strings that appeared in the modifications array.
## Uses absolute rest/perked positions to avoid drift from overlapping tweens.
func set_modifier_perkup(triggered_names: Array[String]) -> void:
	for child: Node in modifier_panel.get_children():
		if not child.has_meta("modifier") or not child.has_meta("rest_y"):
			continue
		var modifier: Resource = child.get_meta("modifier")
		var rest_y: float = child.get_meta("rest_y")
		var should_perkup: bool = modifier.modifier_name in triggered_names
		var is_perked: bool = child.get_meta("perked_up")

		if should_perkup and not is_perked:
			child.set_meta("perked_up", true)
			var tween: Tween = create_tween()
			tween.tween_property(child, "position:y", rest_y - perkup_lift_pixels, perkup_anim_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			child.modulate = Color(1.3, 1.3, 1.3, 1.0)
		elif not should_perkup and is_perked:
			child.set_meta("perked_up", false)
			var tween: Tween = create_tween()
			tween.tween_property(child, "position:y", rest_y, perkup_anim_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			_update_modifier_square_visual(child as Panel)


## Clear all perk-up states on modifier squares.
func clear_modifier_perkup() -> void:
	for child: Node in modifier_panel.get_children():
		if not child.has_meta("perked_up") or not child.get_meta("perked_up"):
			continue
		child.set_meta("perked_up", false)
		if child.has_meta("rest_y"):
			var rest_y: float = child.get_meta("rest_y")
			var tween: Tween = create_tween()
			tween.tween_property(child, "position:y", rest_y, perkup_anim_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_update_modifier_square_visual(child as Panel)


## Add a modifier square to the panel. Called when a scoring modifier is acquired.
func add_modifier_to_panel(modifier: Resource) -> void:
	var square: Panel = Panel.new()
	square.custom_minimum_size = Vector2(modifier_square_size, modifier_square_size)
	square.set_meta("modifier", modifier)
	square.set_meta("perked_up", false)
	square.mouse_entered.connect(_on_modifier_hover.bind(square))
	square.mouse_exited.connect(_on_modifier_unhover)
	square.gui_input.connect(_on_modifier_clicked.bind(square))
	square.mouse_filter = Control.MOUSE_FILTER_STOP
	modifier_panel.add_child(square)
	_update_modifier_square_visual(square)
	# Store rest position after layout settles (deferred so container positions it first)
	square.ready.connect(func() -> void: square.set_meta("rest_y", square.position.y))


## Remove a modifier square from the panel by matching the modifier reference.
## Called when a streak modifier is replaced by a new one in the same category.
func remove_modifier_from_panel(modifier: Resource) -> void:
	for child: Node in modifier_panel.get_children():
		if child.has_meta("modifier") and child.get_meta("modifier") == modifier:
			child.queue_free()
			break


## Clear all modifier squares from the panel. Called on new run.
func clear_modifier_panel() -> void:
	for child: Node in modifier_panel.get_children():
		child.queue_free()
	modifier_tooltip.visible = false


## Called when the mouse enters a modifier square.
func _on_modifier_hover(square: Panel) -> void:
	var modifier: Resource = square.get_meta("modifier")
	if modifier:
		var status: String = "ON" if modifier.enabled else "OFF"
		modifier_tooltip.text = "%s [%s]\n%s\nClick to toggle" % [modifier.modifier_name, status, modifier.description]
		modifier_tooltip.visible = true


## Called when the mouse exits a modifier square.
func _on_modifier_unhover() -> void:
	modifier_tooltip.visible = false


## Toggle modifier on click.
func _on_modifier_clicked(event: InputEvent, square: Panel) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var modifier: Resource = square.get_meta("modifier")
		if modifier:
			modifier.enabled = not modifier.enabled
			_update_modifier_square_visual(square)
			# Refresh tooltip to show new state
			_on_modifier_hover(square)


## Update the visual appearance of a modifier square based on enabled state.
func _update_modifier_square_visual(square: Panel) -> void:
	var modifier: Resource = square.get_meta("modifier")
	if not modifier:
		return
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = modifier.rarity_color
	style.set_corner_radius_all(3)
	if modifier.enabled:
		style.border_color = Color(1.0, 1.0, 1.0, 0.9)
		style.set_border_width_all(2)
		square.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		style.set_border_width_all(0)
		square.modulate = Color(0.3, 0.3, 0.3, 0.6)
	square.add_theme_stylebox_override("panel", style)


## Handle upgrade button selection — hide cards, let main.gd decide what shows next.
func _select_upgrade(index: int) -> void:
	upgrade_container.visible = false
	if _modifier_mode:
		_modifier_mode = false
		modifier_selected.emit(index)
	else:
		upgrade_selected.emit(index)


## Show 3 modifier cards for the player to pick from.
func show_modifier_choices(modifiers: Array) -> void:
	var empty_info: Array[String] = ["", "", ""]
	show_modifier_choices_with_replacement(modifiers, empty_info)


## Show 3 modifier cards with optional replacement warnings.
## replacement_info is an Array[String] of length 3. Empty string = no warning.
## Non-empty string = warning text shown on the card (e.g., "Replaces: Wedge Streak").
func show_modifier_choices_with_replacement(modifiers: Array, replacement_info: Array[String]) -> void:
	_modifier_mode = true
	score_label.text = "Choose a scoring modifier!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var modifier: Resource = modifiers[i]
		var button_text: String = "%s\n%s\n%s" % [modifier.rarity, modifier.modifier_name, modifier.description]
		if replacement_info[i] != "":
			button_text += "\n⚠ %s" % replacement_info[i]
		buttons[i].text = button_text
		var color: Color = modifier.rarity_color
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = modifier.description
		buttons[i].visible = true
	upgrade_container.visible = true
	next_leg_button.visible = false


## Show the wedge picker header text.
func show_picker_header(text: String) -> void:
	if _picker_header == null:
		_picker_header = Label.new()
		_picker_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_picker_header.add_theme_font_size_override("font_size", 24)
		_picker_header.modulate = Color(1.0, 0.9, 0.5)
		_picker_header.anchors_preset = Control.PRESET_CENTER_TOP
		_picker_header.anchor_top = 0.03
		_picker_header.anchor_bottom = 0.03
		_picker_header.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_picker_header.offset_left = -300.0
		_picker_header.offset_right = 300.0
		add_child(_picker_header)
	_picker_header.text = text
	_picker_header.visible = true


## Show a picker confirmation prompt below the header.
func show_picker_prompt(text: String) -> void:
	if _picker_prompt == null:
		_picker_prompt = Label.new()
		_picker_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_picker_prompt.add_theme_font_size_override("font_size", 16)
		_picker_prompt.modulate = Color(0.85, 0.85, 0.85)
		_picker_prompt.anchors_preset = Control.PRESET_CENTER_TOP
		_picker_prompt.anchor_top = 0.08
		_picker_prompt.anchor_bottom = 0.08
		_picker_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_picker_prompt.offset_left = -400.0
		_picker_prompt.offset_right = 400.0
		add_child(_picker_prompt)
	_picker_prompt.text = text
	_picker_prompt.visible = true


## Hide picker UI elements.
func hide_picker() -> void:
	if _picker_header != null:
		_picker_header.visible = false
	if _picker_prompt != null:
		_picker_prompt.visible = false


# --- Shop UI ---

## Enter shop mode — hide leg-specific HUD elements, show shop dart indicator.
func enter_shop_mode(saved_darts: int) -> void:
	remaining_label.visible = false
	turn_label.visible = false
	turn_score_label.visible = false
	leg_label.visible = false
	bust_label.visible = false
	_shop_total_darts = saved_darts
	dart_label.text = "Thrown: 0 / %d" % saved_darts
	dart_label.remove_theme_font_size_override("font_size")
	dart_label.modulate = Color(1.0, 1.0, 1.0)
	dart_indicator.set_shop_darts(saved_darts, saved_darts)


## Exit shop mode — restore leg-specific HUD elements and normal dart display.
func exit_shop_mode() -> void:
	remaining_label.visible = true
	turn_label.visible = true
	turn_score_label.visible = true
	leg_label.visible = true
	remaining_label.modulate = Color(1.0, 1.0, 1.0)
	dart_indicator.restore_normal_darts()
	reset_next_leg_button()


## Show the shop entry screen after completing a shop leg.
func show_shop_entry(leg: int, target: int, turns_used: int, saved_darts: int) -> void:
	score_label.text = "Leg %d Complete! Cleared %d in %d turns" % [leg, target, turns_used]
	upgrade_container.visible = false
	next_leg_button.text = "Enter Shop (%d dart%s saved)" % [saved_darts, "" if saved_darts == 1 else "s"]
	next_leg_button.visible = true


## Show the shop header with remaining dart count and update indicator.
func show_shop_header(darts_remaining: int) -> void:
	upgrade_container.visible = false
	next_leg_button.visible = false
	var thrown: int = _shop_total_darts - darts_remaining
	dart_label.text = "Thrown: %d / %d" % [thrown, _shop_total_darts]
	dart_indicator.set_darts_remaining(darts_remaining)
	if darts_remaining > 0:
		score_label.text = "SHOP — Throw at the lit spots!"
	else:
		score_label.text = "SHOP — No darts left!"


## Show the zero-dart shop acknowledgment.
func show_shop_zero_darts() -> void:
	upgrade_container.visible = false
	next_leg_button.visible = false
	score_label.text = "Oh dear... you didn't save any darts. Oh well!"


## Show the shop's 2-of-2 mixed item pick (modifiers and/or accuracy upgrades).
## items is an Array[Dictionary] with {type: "modifier"|"upgrade", data: ...}.
func show_shop_pick_items(items: Array[Dictionary], darts_remaining: int, replacement_info: Array[String] = []) -> void:
	_modifier_mode = true
	score_label.text = "You hit a spot! Pick one (%d dart%s left)" % [darts_remaining, "" if darts_remaining == 1 else "s"]

	# Build preview data — upgrade dicts for accuracy items, empty for modifiers
	_preview_upgrades = []
	for item: Dictionary in items:
		if item["type"] == "upgrade":
			_preview_upgrades.append(item["data"])
		else:
			_preview_upgrades.append({})

	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(mini(items.size(), 2)):
		var item: Dictionary = items[i]
		var button_text: String
		var button_color: Color

		if item["type"] == "modifier":
			var modifier: Resource = item["data"]
			button_text = "%s\n%s\n%s" % [modifier.rarity, modifier.modifier_name, modifier.description]
			button_color = modifier.rarity_color
			buttons[i].tooltip_text = modifier.description
		else:
			var upgrade: Dictionary = item["data"]
			button_text = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
			if upgrade["tradeoff"]:
				button_text += "\n-%d %s" % [upgrade["penalty_amount"], upgrade["penalty_name"]]
			button_color = upgrade["color"]
			buttons[i].tooltip_text = upgrade["description"]

		if i < replacement_info.size() and replacement_info[i] != "":
			button_text += "\n⚠ %s" % replacement_info[i]

		buttons[i].text = button_text
		buttons[i].self_modulate = Color(button_color.r, button_color.g, button_color.b, 1.0)
		buttons[i].visible = true

		# Connect hover preview signals
		if buttons[i].mouse_entered.is_connected(_on_upgrade_hover):
			buttons[i].mouse_entered.disconnect(_on_upgrade_hover)
		if buttons[i].mouse_exited.is_connected(_on_upgrade_unhover):
			buttons[i].mouse_exited.disconnect(_on_upgrade_unhover)
		buttons[i].mouse_entered.connect(_on_upgrade_hover.bind(i))
		buttons[i].mouse_exited.connect(_on_upgrade_unhover)

	# Hide the third button for 2-of-2 pick
	buttons[2].visible = false
	upgrade_container.visible = true
	next_leg_button.visible = false


## Show the shop hover tooltip above the crosshair with rarity info.
func show_shop_hover_tooltip(rarity_text: String, screen_pos: Vector2) -> void:
	hover_tooltip.text = "Target: %s" % rarity_text
	hover_tooltip.visible = true
	if rarity_text == "Nothing":
		hover_tooltip.modulate = Color(0.6, 0.6, 0.6)
	elif "Rare" in rarity_text:
		hover_tooltip.modulate = Color(0.7, 0.3, 0.9)
	elif "Uncommon" in rarity_text:
		hover_tooltip.modulate = Color(0.3, 0.5, 1.0)
	else:
		hover_tooltip.modulate = Color(1.0, 1.0, 1.0)
	hover_tooltip.position = Vector2(
		screen_pos.x - hover_tooltip.size.x / 2.0,
		screen_pos.y - hover_tooltip_offset_y - hover_tooltip.size.y
	)


## Show the shop complete message with a button to advance.
func show_shop_complete() -> void:
	upgrade_container.visible = false
	score_label.text = "Shop complete!"
	next_leg_button.text = "Next Leg"
	next_leg_button.visible = true


## Reset the next leg button text to default.
func reset_next_leg_button() -> void:
	next_leg_button.text = "Next Leg"
