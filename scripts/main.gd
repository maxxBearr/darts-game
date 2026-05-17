extends Node2D
## Main scene controller. Orchestrates the dartboard, throw mechanic, and HUD.
## Manages game flow: start throw → aim → release → score → repeat.

## Color of placed dart markers on the board.
@export var dart_color: Color = Color(0.9, 0.85, 0.0)

## Radius of placed dart markers in pixels.
@export var dart_size: float = 5.0

@onready var dartboard: Node2D = $Dartboard
@onready var throw_mechanic: Node2D = $ThrowMechanic
@onready var dart_container: Node2D = $DartContainer
@onready var hud: CanvasLayer = $HUD

var _total_score: int = 0


func _ready() -> void:
	# Connect signals
	throw_mechanic.throw_completed.connect(_on_throw_completed)
	throw_mechanic.state_changed.connect(_on_throw_state_changed)
	hud.throw_again_pressed.connect(_on_throw_again)
	hud.clear_board_pressed.connect(_on_clear_board)

	# Center the dartboard on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	dartboard.position = viewport_size / 2.0

	# Start the first throw
	hud.update_total(_total_score)
	_start_new_throw()


func _start_new_throw() -> void:
	hud.hide_score()
	hud.show_instruction("Click or Space to lock aim position")
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)


func _on_throw_completed(hit_position: Vector2) -> void:
	# Score the throw
	var result: Dictionary = dartboard.calculate_score(hit_position)

	# Place a dart marker at the hit position
	_place_dart(hit_position)

	# Update scores and HUD
	_total_score += result["total_score"]
	hud.show_score(result)
	hud.update_total(_total_score)
	hud.show_instruction("Press 'Throw Again' for next dart")


## Create a visual dart marker at the landing position.
func _place_dart(position: Vector2) -> void:
	var dart: Node2D = Node2D.new()
	dart.position = position
	dart.set_script(preload("res://scripts/dart_marker.gd"))
	dart.set("dart_color", dart_color)
	dart.set("dart_size", dart_size)
	dart_container.add_child(dart)


func _on_throw_state_changed(new_state: int) -> void:
	# Reference the ThrowState enum from the throw_mechanic script
	match new_state:
		throw_mechanic.ThrowState.POSITIONING:
			hud.show_instruction("W/S or Up/Down to move window, Enter/Space to lock")
		throw_mechanic.ThrowState.RELEASING:
			hud.show_instruction("Click or Space to release the dart")
		throw_mechanic.ThrowState.RESOLVING:
			hud.show_instruction("Releasing...")


func _on_throw_again() -> void:
	_start_new_throw()


func _on_clear_board() -> void:
	# Remove all dart markers
	for child: Node in dart_container.get_children():
		child.queue_free()
	_total_score = 0
	hud.update_total(_total_score)
	_start_new_throw()
