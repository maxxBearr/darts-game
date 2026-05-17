extends Control
## Draws 3 vertical lines representing darts remaining in the current turn.
## Active darts are bright, used darts are dim.

## Color of active (remaining) dart lines.
@export var active_color: Color = Color(1.0, 1.0, 1.0, 0.9)

## Color of used (spent) dart lines.
@export var spent_color: Color = Color(0.4, 0.4, 0.4, 0.3)

## Width of each dart line in pixels.
@export var line_width: float = 4.0

## Height of each dart line in pixels.
@export var line_height: float = 30.0

## Horizontal spacing between dart lines in pixels.
@export var spacing: float = 12.0

# How many darts are still available (0-3)
var _darts_remaining: int = 3


## Update how many darts are remaining and redraw.
func set_darts_remaining(count: int) -> void:
	_darts_remaining = clampi(count, 0, 3)
	queue_redraw()


func _draw() -> void:
	# Draw 3 vertical lines side by side
	for i: int in range(3):
		var color: Color = active_color if i < _darts_remaining else spent_color
		var x: float = float(i) * spacing
		var start: Vector2 = Vector2(x, 0.0)
		var end: Vector2 = Vector2(x, line_height)
		draw_line(start, end, color, line_width, true)
