extends Node2D
## Main scene controller. Orchestrates the dartboard, throw mechanic, X01 game logic, and HUD.
## Manages game flow: X01 run → legs → turns → darts → score → upgrades → repeat.

## Color of placed dart markers on the board.
@export var dart_color: Color = Color(0.9, 0.85, 0.0)

## Radius of placed dart markers in pixels.
@export var dart_size: float = 5.0

@onready var dartboard: Node2D = $Dartboard
@onready var throw_mechanic: Node2D = $ThrowMechanic
@onready var dart_container: Node2D = $DartContainer
@onready var hud: CanvasLayer = $HUD
@onready var x01_game: Node = $X01Game

# Upgrade type definitions — 4 pure buffs, 2 tradeoffs (consistency stats penalize each other)
const UPGRADE_TYPES: Array[Dictionary] = [
	{
		"name": "Horizontal Range",
		"property": "horizontal_range",
		"scale": "direct",
		"tradeoff": false,
		"description": "Narrows the horizontal aiming band",
	},
	{
		"name": "Vertical Range",
		"property": "vertical_range",
		"scale": "direct",
		"tradeoff": false,
		"description": "Shrinks the vertical positioning window",
	},
	{
		"name": "Vertical Speed",
		"property": "vertical_speed",
		"scale": "speed",
		"tradeoff": false,
		"description": "Slows the vertical release marker",
	},
	{
		"name": "Horizontal Speed",
		"property": "horizontal_speed",
		"scale": "speed",
		"tradeoff": false,
		"description": "Slows the horizontal release marker",
	},
	{
		"name": "Vertical Accuracy",
		"property": "vertical_accuracy",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "horizontal_accuracy",
		"penalty_name": "Horizontal Accuracy",
		"penalty_amount": 3,
		"description": "Tightens vertical variance, but widens horizontal",
	},
	{
		"name": "Horizontal Accuracy",
		"property": "horizontal_accuracy",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "vertical_accuracy",
		"penalty_name": "Vertical Accuracy",
		"penalty_amount": 3,
		"description": "Tightens horizontal variance, but widens vertical",
	},
]

# Rarity tiers for standard (direct 1-100) stats
const STANDARD_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 5, "max_value": 8, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 9, "max_value": 12, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 13, "max_value": 15, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Rarity tiers for speed stats (1.0-5.0 internal scale)
const SPEED_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 2, "max_value": 4, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 5, "max_value": 7, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 8, "max_value": 10, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Rarity tiers for consistency stats (tradeoff upgrades — higher values to offset the penalty)
const CONSISTENCY_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 8, "max_value": 12, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 13, "max_value": 16, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 17, "max_value": 20, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Flow state — tracks what the game is waiting for between throws
var _awaiting_next_dart: bool = false
var _awaiting_next_turn: bool = false
var _awaiting_next_leg: bool = false
var _run_over: bool = false

# Base stats snapshot — saved at run start, restored on new run
var _base_horizontal_range: float = 0.0
var _base_vertical_range: float = 0.0
var _base_vertical_accuracy: float = 0.0
var _base_horizontal_accuracy: float = 0.0
var _base_vertical_speed: float = 0.0
var _base_horizontal_speed: float = 0.0

# The 3 generated upgrade choices for the current leg-complete screen
var _current_upgrades: Array[Dictionary] = []

# How many upgrade selection rounds remain before advancing to the next leg
var _upgrade_rounds_remaining: int = 0

# Cumulative score for the current turn (resets each turn)
var _turn_score: int = 0


func _ready() -> void:
	# Connect throw mechanic signals
	throw_mechanic.throw_completed.connect(_on_throw_completed)
	throw_mechanic.state_changed.connect(_on_throw_state_changed)

	# Connect HUD button signals
	hud.next_dart_pressed.connect(_on_next_dart)
	hud.next_turn_pressed.connect(_on_next_turn)
	hud.next_leg_pressed.connect(_on_next_leg)
	hud.new_run_pressed.connect(_on_new_run)
	hud.upgrade_selected.connect(_on_upgrade_selected)

	# Center the dartboard on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	dartboard.position = viewport_size / 2.0

	# Snapshot base stats before first run so colors are correct
	_snapshot_base_stats()

	# Start the first run
	x01_game.start_run()
	_update_all_hud()
	_start_new_throw()


## Start a new throw (single dart).
func _start_new_throw() -> void:
	hud.hide_score()
	# Update dart counter to show which dart we're on
	var darts_remaining: int = 3 - x01_game.darts_this_turn
	hud.update_darts(darts_remaining)
	hud.show_instruction("Click or Space to lock aim position")
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)


## Called when a dart lands — process through X01 logic and update state.
func _on_throw_completed(hit_position: Vector2) -> void:
	# Score the throw
	var result: Dictionary = dartboard.calculate_score(hit_position)

	# Place a dart marker at the hit position
	_place_dart(hit_position)

	# Flash the hit segment for visual feedback
	dartboard.flash_segment(hit_position)

	# Show per-dart score feedback
	hud.show_score(result)

	# Process through X01 game logic
	var response: Dictionary = x01_game.process_throw(result)

	# Accumulate turn score
	_turn_score += result["total_score"]
	hud.update_turn_score(_turn_score)

	# Update remaining score display
	hud.update_remaining(response["remaining_score"])

	# Branch on what happened
	if response["is_bust"]:
		hud.show_bust(response["bust_reason"])
		if response["is_game_over"]:
			# Run is over
			_run_over = true
			hud.show_game_over(response["current_leg"], response["target_score"])
		else:
			# Turn lost to bust, but run continues
			hud.next_turn_button.visible = true
			_awaiting_next_turn = true
	elif response["is_leg_won"]:
		# Leg complete — offer 2 rounds of upgrade selection
		_upgrade_rounds_remaining = 2
		_current_upgrades = _generate_upgrades()
		hud.show_leg_complete_with_upgrades(
			response["current_leg"],
			response["target_score"],
			response["current_turn"],
			_current_upgrades
		)
		_awaiting_next_leg = true
	elif response["is_turn_over"]:
		# Used all 3 darts without bust or win
		if response["is_game_over"]:
			_run_over = true
			hud.show_game_over(response["current_leg"], response["target_score"])
		else:
			hud.next_turn_button.visible = true
			_awaiting_next_turn = true
	else:
		# Darts remaining this turn — continue throwing
		hud.next_dart_button.visible = true
		_awaiting_next_dart = true

	# Update dart counter
	hud.update_darts(response["darts_remaining"])


## Player presses "Next Dart" — throw another dart in the same turn.
func _on_next_dart() -> void:
	_awaiting_next_dart = false
	_start_new_throw()


## Player presses "Next Turn" — advance to next turn after bust or using all darts.
func _on_next_turn() -> void:
	_awaiting_next_turn = false
	_turn_score = 0
	hud.update_turn_score(0)
	_clear_darts()
	x01_game.end_turn()
	x01_game.start_turn()
	hud.update_turn(x01_game.current_turn, x01_game.max_turns)
	_start_new_throw()


## Player presses "Next Leg" — advance to next leg after picking an upgrade.
func _on_next_leg() -> void:
	_awaiting_next_leg = false
	_turn_score = 0
	hud.update_turn_score(0)
	_clear_darts()
	x01_game.advance_leg()
	_update_all_hud()
	_start_new_throw()


## Player presses "New Run" — start fresh after game over.
func _on_new_run() -> void:
	_run_over = false
	_turn_score = 0
	hud.update_turn_score(0)
	_clear_darts()
	_restore_base_stats()
	x01_game.start_run()
	_update_all_hud()
	_start_new_throw()


## Player picks an upgrade card (index 0, 1, or 2).
func _on_upgrade_selected(index: int) -> void:
	_apply_upgrade(_current_upgrades[index])
	_update_stats_display()
	_upgrade_rounds_remaining -= 1

	if _upgrade_rounds_remaining > 0:
		# Generate and show another round of upgrade choices
		_current_upgrades = _generate_upgrades()
		hud.show_upgrade_choices(_current_upgrades)
	else:
		# All rounds done — show Next Leg button
		hud.next_leg_button.visible = true


## Save throw_mechanic stats at the start of a run for later restoration.
func _snapshot_base_stats() -> void:
	_base_horizontal_range = throw_mechanic.horizontal_range
	_base_vertical_range = throw_mechanic.vertical_range
	_base_vertical_accuracy = throw_mechanic.vertical_accuracy
	_base_horizontal_accuracy = throw_mechanic.horizontal_accuracy
	_base_vertical_speed = throw_mechanic.vertical_speed
	_base_horizontal_speed = throw_mechanic.horizontal_speed


## Restore throw_mechanic stats to their initial values (on new run).
func _restore_base_stats() -> void:
	throw_mechanic.horizontal_range = _base_horizontal_range
	throw_mechanic.vertical_range = _base_vertical_range
	throw_mechanic.vertical_accuracy = _base_vertical_accuracy
	throw_mechanic.horizontal_accuracy = _base_horizontal_accuracy
	throw_mechanic.vertical_speed = _base_vertical_speed
	throw_mechanic.horizontal_speed = _base_horizontal_speed


## Generate 3 distinct upgrade cards with random rarities and values.
func _generate_upgrades() -> Array[Dictionary]:
	# Pick 3 distinct upgrade types from the 6 available
	var indices: Array[int] = [0, 1, 2, 3, 4, 5]
	indices.shuffle()
	var chosen_indices: Array[int] = [indices[0], indices[1], indices[2]]

	var upgrades: Array[Dictionary] = []
	for idx: int in chosen_indices:
		var upgrade_type: Dictionary = UPGRADE_TYPES[idx]

		# Select rarity table based on stat type
		var rarity_table: Array[Dictionary]
		if upgrade_type["tradeoff"]:
			rarity_table = CONSISTENCY_RARITY_TABLE
		elif upgrade_type["scale"] == "speed":
			rarity_table = SPEED_RARITY_TABLE
		else:
			rarity_table = STANDARD_RARITY_TABLE

		# Roll rarity using weighted random (1-100 roll)
		var roll: int = randi_range(1, 100)
		var rarity: Dictionary
		if roll <= 65:
			rarity = rarity_table[0]
		elif roll <= 90:
			rarity = rarity_table[1]
		else:
			rarity = rarity_table[2]

		# Roll value within the rarity's range
		var value: int = randi_range(rarity["min_value"], rarity["max_value"])

		upgrades.append({
			"name": upgrade_type["name"],
			"property": upgrade_type["property"],
			"scale": upgrade_type["scale"],
			"description": upgrade_type["description"],
			"rarity": rarity["name"],
			"color": rarity["color"],
			"value": value,
			"tradeoff": upgrade_type["tradeoff"],
			"penalty_property": upgrade_type.get("penalty_property", ""),
			"penalty_name": upgrade_type.get("penalty_name", ""),
			"penalty_amount": upgrade_type.get("penalty_amount", 0),
		})

	return upgrades


## Apply a chosen upgrade to the throw_mechanic.
func _apply_upgrade(upgrade: Dictionary) -> void:
	# Apply the main boost
	if upgrade["scale"] == "direct":
		var current: float = throw_mechanic.get(upgrade["property"])
		var new_value: float = minf(current + float(upgrade["value"]), 100.0)
		throw_mechanic.set(upgrade["property"], new_value)
	elif upgrade["scale"] == "speed":
		var internal_boost: float = float(upgrade["value"]) * (4.0 / 15.0)
		var current: float = throw_mechanic.get(upgrade["property"])
		var new_value: float = minf(current + internal_boost, 5.0)
		throw_mechanic.set(upgrade["property"], new_value)

	# Apply tradeoff penalty if applicable
	if upgrade["tradeoff"]:
		var penalty_current: float = throw_mechanic.get(upgrade["penalty_property"])
		var new_penalty_value: float = penalty_current - float(upgrade["penalty_amount"])
		throw_mechanic.set(upgrade["penalty_property"], new_penalty_value)


## Update all HUD elements to reflect current game state.
func _update_all_hud() -> void:
	hud.update_leg(x01_game.current_leg, x01_game.target_score)
	hud.update_turn(x01_game.current_turn, x01_game.max_turns)
	hud.update_remaining(x01_game.remaining_score)
	hud.update_darts(3 - x01_game.darts_this_turn)
	_update_stats_display()


## Refresh the stats panel on the HUD with current throw_mechanic values.
func _update_stats_display() -> void:
	var current_stats: Dictionary = {
		"horizontal_range": throw_mechanic.horizontal_range,
		"vertical_range": throw_mechanic.vertical_range,
		"vertical_accuracy": throw_mechanic.vertical_accuracy,
		"horizontal_accuracy": throw_mechanic.horizontal_accuracy,
		"vertical_speed": throw_mechanic.vertical_speed,
		"horizontal_speed": throw_mechanic.horizontal_speed,
	}
	var base_stats: Dictionary = {
		"horizontal_range": _base_horizontal_range,
		"vertical_range": _base_vertical_range,
		"vertical_accuracy": _base_vertical_accuracy,
		"horizontal_accuracy": _base_horizontal_accuracy,
		"vertical_speed": _base_vertical_speed,
		"horizontal_speed": _base_horizontal_speed,
	}
	hud.update_stats(current_stats, base_stats)


## Remove all dart markers from the board.
func _clear_darts() -> void:
	for child: Node in dart_container.get_children():
		child.queue_free()


## Create a visual dart marker at the landing position.
func _place_dart(position: Vector2) -> void:
	var dart: Node2D = Node2D.new()
	dart.position = position
	dart.set_script(preload("res://scripts/dart_marker.gd"))
	dart.set("dart_color", dart_color)
	dart.set("dart_size", dart_size)
	dart_container.add_child(dart)


func _on_throw_state_changed(new_state: int) -> void:
	match new_state:
		throw_mechanic.ThrowState.POSITIONING:
			hud.show_instruction("W/S or Up/Down to move window, Enter/Space to lock")
		throw_mechanic.ThrowState.VERTICAL_RELEASE:
			hud.show_instruction("Click or Space to lock vertical position")
		throw_mechanic.ThrowState.HORIZONTAL_RELEASE:
			hud.show_instruction("Click or Space to lock horizontal position")
		throw_mechanic.ThrowState.RESOLVING:
			hud.show_instruction("Releasing...")
