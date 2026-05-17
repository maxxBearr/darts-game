extends CanvasLayer
## HUD overlay displaying score information and control buttons.

signal throw_again_pressed
signal clear_board_pressed

@onready var score_label: Label = $ScoreLabel
@onready var total_score_label: Label = $TotalScoreLabel
@onready var throw_again_button: Button = $ThrowAgainButton
@onready var clear_button: Button = $ClearButton
@onready var instruction_label: Label = $InstructionLabel


func _ready() -> void:
	throw_again_button.pressed.connect(_on_throw_again)
	clear_button.pressed.connect(_on_clear_board)
	# Start with buttons hidden until a throw completes
	throw_again_button.visible = false
	clear_button.visible = false


## Display the result of the current throw.
func show_score(result: Dictionary) -> void:
	var ring_name: String = result["ring_name"]
	var total: int = result["total_score"]
	if ring_name == "Off Board":
		score_label.text = "Off Board — 0 points"
	elif ring_name == "Double Bull":
		score_label.text = "Double Bull — 50 points!"
	elif ring_name == "Single Bull":
		score_label.text = "Single Bull — 25 points"
	else:
		var face: int = result["face_value"]
		score_label.text = "%s %d — %d points!" % [ring_name, face, total]
	throw_again_button.visible = true
	clear_button.visible = true


## Update the running total score display.
func update_total(total: int) -> void:
	total_score_label.text = "Total: %d" % total


## Show instruction text to the player.
func show_instruction(text: String) -> void:
	instruction_label.text = text


## Hide the throw result and buttons (during aiming).
func hide_score() -> void:
	score_label.text = ""
	throw_again_button.visible = false


func _on_throw_again() -> void:
	throw_again_pressed.emit()


func _on_clear_board() -> void:
	clear_board_pressed.emit()
