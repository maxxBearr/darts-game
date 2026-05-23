class_name ModifierIcon
extends Control
## Custom-drawn icon for a scoring modifier. Renders the modifier's category
## shape (circle / square / triangle / sector), fill, category outline, and
## rarity outline based on a single ScoringModifier resource reference.

## The modifier resource this icon represents. Setting this triggers a redraw.
@export var modifier: Resource = null:
	set(value):
		modifier = value
		queue_redraw()

## Outline width of the rarity ring in pixels.
@export var rarity_outline_width: float = 2.0

## Outline width of the inner category ring (parity modifiers only).
@export var category_outline_width: float = 2.0

## Gap in pixels between the inner category outline and the outer rarity outline.
@export var outline_gap: float = 1.0

## Inset from the Control's bounds before drawing — leaves room for outlines.
@export var draw_inset: float = 2.0

## Color used as the neutral fill on parity and wedge shapes.
@export var neutral_fill_color: Color = Color(0.18, 0.18, 0.22)

## Segment color mapping — matches the dartboard's actual segment colors.
@export var color_red: Color = Color(0.85, 0.2, 0.15)
@export var color_green: Color = Color(0.1, 0.6, 0.2)
@export var color_black: Color = Color(0.12, 0.12, 0.15)
@export var color_white: Color = Color(0.92, 0.88, 0.78)

## Inner category outline colors for parity modifiers.
@export var even_outline_color: Color = Color(0.85, 0.2, 0.15)
@export var odd_outline_color: Color = Color(0.1, 0.6, 0.2)


func _draw() -> void:
	if modifier == null:
		return
	if not modifier is ScoringModifier:
		return
	var mod: ScoringModifier = modifier as ScoringModifier
	if mod.kind == ScoringEnums.ModifierKind.BOARD_MUTATION:
		return

	var shape: ScoringEnums.IconShape = mod.get_icon_shape()
	if shape == ScoringEnums.IconShape.NONE:
		return

	var rarity_color: Color = mod.rarity_color
	var area: Rect2 = Rect2(Vector2(draw_inset, draw_inset), size - Vector2(draw_inset * 2.0, draw_inset * 2.0))

	match shape:
		ScoringEnums.IconShape.COLOR_CIRCLE:
			_draw_color_circle(area, mod, rarity_color)
		ScoringEnums.IconShape.EVEN_SQUARE:
			_draw_even_square(area, rarity_color)
		ScoringEnums.IconShape.ODD_TRIANGLE:
			_draw_odd_triangle(area, rarity_color)
		ScoringEnums.IconShape.WEDGE_SECTOR:
			_draw_wedge_sector(area, rarity_color)


func _get_segment_color(segment_color: ScoringEnums.SegmentColor) -> Color:
	match segment_color:
		ScoringEnums.SegmentColor.RED:
			return color_red
		ScoringEnums.SegmentColor.GREEN:
			return color_green
		ScoringEnums.SegmentColor.BLACK:
			return color_black
		ScoringEnums.SegmentColor.WHITE:
			return color_white
	return color_white


func _draw_color_circle(area: Rect2, mod: ScoringModifier, rarity_color: Color) -> void:
	var center: Vector2 = area.get_center()
	var radius: float = minf(area.size.x, area.size.y) / 2.0

	# Determine fill color from target_color
	var fill_color: Color = neutral_fill_color
	if mod.has_method("get_icon_shape"):
		if "target_color" in mod:
			fill_color = _get_segment_color(mod.target_color)

	# Fill
	draw_circle(center, radius - rarity_outline_width, fill_color)
	# Rarity outline
	draw_arc(center, radius - rarity_outline_width / 2.0, 0.0, TAU, 64, rarity_color, rarity_outline_width)


func _draw_even_square(area: Rect2, rarity_color: Color) -> void:
	var total_outline: float = rarity_outline_width + outline_gap + category_outline_width
	var inner_rect: Rect2 = area.grow(-total_outline)

	# Fill
	draw_rect(inner_rect, neutral_fill_color)
	# Inner category outline (red for even)
	var cat_rect: Rect2 = inner_rect.grow(category_outline_width)
	draw_rect(cat_rect, even_outline_color, false, category_outline_width)
	# Outer rarity outline
	var rarity_rect: Rect2 = cat_rect.grow(outline_gap + rarity_outline_width)
	draw_rect(rarity_rect, rarity_color, false, rarity_outline_width)


func _draw_odd_triangle(area: Rect2, rarity_color: Color) -> void:
	var total_outline: float = rarity_outline_width + outline_gap + category_outline_width
	var cx: float = area.get_center().x
	var top: float = area.position.y + total_outline
	var bottom: float = area.end.y - total_outline
	var left: float = area.position.x + total_outline
	var right: float = area.end.x - total_outline

	var inner_points: PackedVector2Array = PackedVector2Array([
		Vector2(cx, top),
		Vector2(right, bottom),
		Vector2(left, bottom),
	])

	# Fill
	draw_colored_polygon(inner_points, neutral_fill_color)

	# Inner category outline (green for odd)
	var cat_points: PackedVector2Array = _offset_triangle(inner_points, category_outline_width)
	_draw_triangle_outline(cat_points, odd_outline_color, category_outline_width)

	# Outer rarity outline
	var rarity_points: PackedVector2Array = _offset_triangle(cat_points, outline_gap + rarity_outline_width)
	_draw_triangle_outline(rarity_points, rarity_color, rarity_outline_width)


func _offset_triangle(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var cx: float = (points[0].x + points[1].x + points[2].x) / 3.0
	var cy: float = (points[0].y + points[1].y + points[2].y) / 3.0
	var center: Vector2 = Vector2(cx, cy)
	var result: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in points:
		var dir: Vector2 = (p - center).normalized()
		result.append(p + dir * amount)
	return result


func _draw_triangle_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for i: int in range(3):
		draw_line(points[i], points[(i + 1) % 3], color, width)


func _draw_wedge_sector(area: Rect2, rarity_color: Color) -> void:
	var center: Vector2 = Vector2(area.position.x + area.size.x * 0.3, area.end.y)
	var radius: float = minf(area.size.x, area.size.y) * 0.85
	var start_angle: float = -PI * 0.7
	var end_angle: float = -PI * 0.3

	# Fill sector
	var fill_points: PackedVector2Array = PackedVector2Array()
	fill_points.append(center)
	var segments: int = 24
	for i: int in range(segments + 1):
		var angle: float = start_angle + (end_angle - start_angle) * float(i) / float(segments)
		var fill_radius: float = radius - rarity_outline_width
		fill_points.append(center + Vector2(cos(angle), sin(angle)) * fill_radius)
	draw_colored_polygon(fill_points, neutral_fill_color)

	# Rarity outline arc
	draw_arc(center, radius - rarity_outline_width / 2.0, start_angle, end_angle, 24, rarity_color, rarity_outline_width)
	# Rarity outline radial lines
	var r_inner: float = 0.0
	var r_outer: float = radius - rarity_outline_width / 2.0
	draw_line(center + Vector2(cos(start_angle), sin(start_angle)) * r_inner,
		center + Vector2(cos(start_angle), sin(start_angle)) * r_outer,
		rarity_color, rarity_outline_width)
	draw_line(center + Vector2(cos(end_angle), sin(end_angle)) * r_inner,
		center + Vector2(cos(end_angle), sin(end_angle)) * r_outer,
		rarity_color, rarity_outline_width)
