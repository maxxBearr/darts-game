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

	# Populate upgrade buttons with rarity, name, and value
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var upgrade: Dictionary = upgrades[i]
		buttons[i].text = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
		# Tint button to rarity color at full opacity so it stays readable
		var color: Color = upgrade["color"]
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		# Set tooltip with description for hover feedback
		buttons[i].tooltip_text = upgrade["description"]

	# Show upgrade container, hide NextLegButton until they pick
	upgrade_container.visible = true
	next_leg_button.visible = false


## Show a new set of upgrade choices (for subsequent rounds after the first).
func show_upgrade_choices(upgrades: Array[Dictionary]) -> void:
	score_label.text = "Choose another upgrade!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var upgrade: Dictionary = upgrades[i]
		buttons[i].text = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
		var color: Color = upgrade["color"]
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = upgrade["description"]
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


## Handle upgrade button selection — emit signal, let main.gd decide what to show next.
func _select_upgrade(index: int) -> void:
	upgrade_container.visible = false
	upgrade_selected.emit(index)
