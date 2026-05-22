class_name GhostDartLayer
extends Node2D
## Renders semi-transparent ghost dart markers to visualize scatter patterns.
## Used by the tutorial to show where darts would land at different accuracy zones,
## and optionally as a live preview during normal gameplay.

## Color of the ghost dart marker fill.
@export var ghost_color: Color = Color(1.0, 1.0, 1.0, 0.35)

## Color of the ghost dart marker outline.
@export var ghost_outline_color: Color = Color(1.0, 1.0, 1.0, 0.5)

## Radius of each ghost dart marker in pixels.
@export var ghost_size: float = 4.0

## Outline thickness of each ghost dart marker in pixels.
@export var ghost_outline_thickness: float = 1.5

## Auto-fade duration in seconds. 0 = stay visible until explicitly cleared.
@export var auto_fade_duration: float = 0.0

## Currently displayed ghost dart positions (global coordinates).
var _scatter_points: Array[Vector2] = []

## Whether ghost markers are currently visible.
var _visible: bool = false

## Current fade alpha (1.0 = fully visible, tweened to 0 during fade).
var _fade_alpha: float = 1.0


## Display ghost dart markers at the given positions.
func show_scatter(points: Array[Vector2]) -> void:
	_scatter_points = points
	_visible = true
	_fade_alpha = 1.0
	queue_redraw()

	if auto_fade_duration > 0.0:
		var tween: Tween = create_tween()
		tween.tween_property(self, "_fade_alpha", 0.0, auto_fade_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(clear_scatter)


## Remove all ghost dart markers.
func clear_scatter() -> void:
	_scatter_points.clear()
	_visible = false
	_fade_alpha = 1.0
	queue_redraw()


func _draw() -> void:
	if not _visible or _scatter_points.is_empty():
		return

	var fill: Color = Color(ghost_color.r, ghost_color.g, ghost_color.b, ghost_color.a * _fade_alpha)
	var outline: Color = Color(ghost_outline_color.r, ghost_outline_color.g, ghost_outline_color.b, ghost_outline_color.a * _fade_alpha)

	for point: Vector2 in _scatter_points:
		var local_pos: Vector2 = point - global_position
		if ghost_outline_thickness > 0.0:
			draw_arc(local_pos, ghost_size + ghost_outline_thickness * 0.5, 0.0, TAU, 32, outline, ghost_outline_thickness)
		draw_circle(local_pos, ghost_size, fill)
