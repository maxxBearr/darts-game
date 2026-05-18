extends CanvasLayer
## HUD overlay displaying X01 game state, per-dart feedback, upgrade cards, and control buttons.

signal next_dart_pressed
signal next_turn_pressed
signal next_leg_pressed
signal new_run_pressed
signal upgrade_selected(index: int)

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
@onready var horizontal_range_label: Label = $StatsContainer/HorizontalRangeLabel
@onready var vertical_range_label: Label = $StatsContainer/VerticalRangeLabel
@onready var vertical_accuracy_label: Label = $StatsContainer/VerticalAccuracyLabel
@onready var horizontal_accuracy_label: Label = $StatsContainer/HorizontalAccuracyLabel
@onready var vertical_speed_label: Label = $StatsContainer/VerticalSpeedLabel
@onready var horizontal_speed_label: Label = $StatsContainer/HorizontalSpeedLabel


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
	turn_label.text = "Turn %d/%d" % [turn, max_turns]


## Update the dart counter display and visual indicator.
func update_darts(darts_remaining: int) -> void:
	dart_label.text = "Dart %d/3" % [3 - darts_remaining]
	dart_indicator.set_darts_remaining(darts_remaining)


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
		# Speed upgrades show "-" to indicate slowing down the marker
		var sign: String = "-" if upgrade["scale"] == "speed" else "+"
		var button_text: String = "%s\n%s\n%s%d" % [upgrade["rarity"], upgrade["name"], sign, upgrade["value"]]
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
		var sign: String = "-" if upgrade["scale"] == "speed" else "+"
		var button_text: String = "%s\n%s\n%s%d" % [upgrade["rarity"], upgrade["name"], sign, upgrade["value"]]
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


## Update the stats panel with current values and color coding.
## base_stats is a Dictionary with keys matching stat names, values are the defaults.
## Speed is displayed as an interpreted 0-100 value (internal 1.0-5.0 mapped to 0-100).
func update_stats(stats: Dictionary, base_stats: Dictionary) -> void:
	_update_stat_label(horizontal_range_label, "Horizontal Range", stats["horizontal_range"], base_stats["horizontal_range"])
	_update_stat_label(vertical_range_label, "Vertical Range", stats["vertical_range"], base_stats["vertical_range"])
	_update_stat_label(vertical_accuracy_label, "Vertical Accuracy", stats["vertical_accuracy"], base_stats["vertical_accuracy"])
	_update_stat_label(horizontal_accuracy_label, "Horizontal Accuracy", stats["horizontal_accuracy"], base_stats["horizontal_accuracy"])
	# Speed stats: convert 1.0-5.0 to 0-100 for display (higher internal = better)
	var v_speed_display: int = _speed_to_display(stats["vertical_speed"])
	var v_speed_base: int = _speed_to_display(base_stats["vertical_speed"])
	_update_stat_label(vertical_speed_label, "Vertical Speed", float(v_speed_display), float(v_speed_base))
	var h_speed_display: int = _speed_to_display(stats["horizontal_speed"])
	var h_speed_base: int = _speed_to_display(base_stats["horizontal_speed"])
	_update_stat_label(horizontal_speed_label, "Horizontal Speed", float(h_speed_display), float(h_speed_base))


## Convert internal speed (1.0-5.0) to a display value (0-100).
func _speed_to_display(speed: float) -> int:
	return roundi((speed - 1.0) / 4.0 * 100.0)


## Update a single stat label with value and color based on comparison to base.
func _update_stat_label(label: Label, stat_name: String, current: float, base: float) -> void:
	label.text = "%s: %d" % [stat_name, roundi(current)]
	if current > base:
		label.modulate = Color(0.4, 1.0, 0.4)
	elif current < base:
		label.modulate = Color(1.0, 0.5, 0.5)
	else:
		label.modulate = Color(1.0, 1.0, 1.0)


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
	upgrade_selected.emit(index)
