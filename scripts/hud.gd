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
	"horizontal_range": "Narrows the horizontal aiming band. Also reduces the distance the horizontal marker travels, making it easier to time.",
	"vertical_range": "Shrinks the vertical positioning window. Also reduces the distance the vertical marker travels, making it easier to time.",
	"horizontal_speed": "Slows the horizontal release marker. Higher = easier to time your click.",
	"vertical_speed": "Slows the vertical release marker. Higher = easier to time your click.",
	"horizontal_accuracy": "Tightens horizontal dart landing variance. Higher = dart lands closer to where you clicked.",
	"vertical_accuracy": "Tightens vertical dart landing variance. Higher = dart lands closer to where you clicked.",
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

## Picker header label (created on demand).
var _picker_header: Label
## Picker prompt label (created on demand).
var _picker_prompt: Label


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

	# Populate upgrade buttons with rarity, name, value, and tradeoff penalty
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var upgrade: Dictionary = upgrades[i]
		var button_text: String = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
		if upgrade["tradeoff"]:
			button_text += "\n-%d %s" % [upgrade["penalty_amount"], upgrade["penalty_name"]]
		buttons[i].text = button_text
		# Tint button to rarity color at full opacity so it stays readable
		var color: Color = upgrade["color"]
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		# Tooltip description on hover
		buttons[i].tooltip_text = upgrade["description"]

	# Show upgrade container, hide NextLegButton until they pick
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


## Convert internal speed (1.0-5.0) to a display value (0-100).
func _speed_to_display(speed: float) -> int:
	return roundi((speed - 1.0) / 4.0 * 100.0)


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


## Show hover tooltip with score info for the hovered segment.
## Displays the base score, then any modifier effects with highlights.
func show_hover_tooltip(result: Dictionary, original_wedge_order: Array[int]) -> void:
	if result.is_empty():
		hover_tooltip.visible = false
		return

	var ring_name: String = result["ring_name"]
	var face_value: int = result["face_value"]
	var total_score: int = result["total_score"]
	var multiplier: int = result["multiplier"]
	var wedge_index: int = result.get("wedge_index", -1)
	var is_bull: bool = result.get("is_bull", false)

	if ring_name == "Off Board":
		hover_tooltip.visible = false
		return

	var lines: PackedStringArray = PackedStringArray()

	# Line 1: Segment name
	if is_bull:
		lines.append(ring_name)
	else:
		var original_value: int = original_wedge_order[wedge_index] if wedge_index >= 0 and wedge_index < original_wedge_order.size() else face_value
		if face_value != original_value:
			lines.append("%s %d (was %d)" % [ring_name, face_value, original_value])
		else:
			lines.append("%s %d" % [ring_name, face_value])

	var modifications: Array = result.get("modifications", [])

	if modifications.size() > 0:
		# Show each modifier effect, then final total
		for mod: Dictionary in modifications:
			var field: String = mod["field"]
			var source: String = mod["source_name"]
			if field == "multiplier":
				lines.append("%s x%d -> x%d" % [source, mod["old_value"], mod["new_value"]])
			elif field == "total_score":
				lines.append("%s +%d" % [source, int(mod["new_value"]) - int(mod["old_value"])])
			else:
				lines.append("%s: %s -> %s" % [source, str(mod["old_value"]), str(mod["new_value"])])
		lines.append("= %d pts" % total_score)
	else:
		# No modifiers — just show base score
		lines.append("%d x%d = %d" % [face_value, multiplier, total_score])

	hover_tooltip.text = "\n".join(lines)
	hover_tooltip.visible = true


## Hide the hover tooltip.
func hide_hover_tooltip() -> void:
	hover_tooltip.visible = false


## Add a modifier square to the panel. Called when a scoring modifier is acquired.
func add_modifier_to_panel(modifier: Resource) -> void:
	var square: ColorRect = ColorRect.new()
	square.custom_minimum_size = Vector2(modifier_square_size, modifier_square_size)
	# Tint by rarity color
	square.color = modifier.rarity_color
	# Store modifier reference for tooltip lookup
	square.set_meta("modifier", modifier)
	# Connect mouse signals for hover tooltip
	square.mouse_entered.connect(_on_modifier_hover.bind(square))
	square.mouse_exited.connect(_on_modifier_unhover)
	# Make sure it accepts mouse events
	square.mouse_filter = Control.MOUSE_FILTER_STOP
	modifier_panel.add_child(square)


## Clear all modifier squares from the panel. Called on new run.
func clear_modifier_panel() -> void:
	for child: Node in modifier_panel.get_children():
		child.queue_free()
	modifier_tooltip.visible = false


## Called when the mouse enters a modifier square.
func _on_modifier_hover(square: ColorRect) -> void:
	var modifier: Resource = square.get_meta("modifier")
	if modifier:
		modifier_tooltip.text = "%s\n%s" % [modifier.modifier_name, modifier.description]
		modifier_tooltip.visible = true


## Called when the mouse exits a modifier square.
func _on_modifier_unhover() -> void:
	modifier_tooltip.visible = false


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
	_modifier_mode = true
	score_label.text = "Choose a scoring modifier!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var modifier: Resource = modifiers[i]
		var button_text: String = "%s\n%s\n%s" % [modifier.rarity, modifier.modifier_name, modifier.description]
		buttons[i].text = button_text
		var color: Color = modifier.rarity_color
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = modifier.description
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
