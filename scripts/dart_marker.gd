extends Node2D
## A simple visual marker representing a dart stuck in the board.

## Color of this dart marker.
var dart_color: Color = Color(0.9, 0.85, 0.0)

## Radius of this dart marker in pixels.
var dart_size: float = 5.0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	# Outer ring
	draw_circle(Vector2.ZERO, dart_size, dart_color)
	# Inner dark center for visibility
	draw_circle(Vector2.ZERO, dart_size * 0.4, Color(0.2, 0.2, 0.2))
