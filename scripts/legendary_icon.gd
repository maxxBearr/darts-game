class_name LegendaryIcon
extends Control
## Gold diamond-shaped icon for a legendary (boss reward) in the HUD panel.

## The reward this icon represents.
var reward: RuleModifierReward = null

## Gold tint color for the diamond background.
var tint_color: Color = Color(1.0, 0.85, 0.2, 1.0)

## Outline width in pixels.
var outline_width: float = 2.0

## Inset from the Control's bounds before drawing.
var draw_inset: float = 4.0

## Font size for the monogram letter.
var monogram_font_size: int = 16


func _draw() -> void:
	if reward == null:
		return

	var cx: float = size.x / 2.0
	var cy: float = size.y / 2.0
	var half: float = minf(size.x, size.y) / 2.0 - draw_inset

	# Diamond shape (45-degree rotated square)
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(cx, cy - half),
		Vector2(cx + half, cy),
		Vector2(cx, cy + half),
		Vector2(cx - half, cy),
	])

	# Fill
	var fill_color: Color = Color(tint_color.r * 0.25, tint_color.g * 0.25, tint_color.b * 0.25, 0.85)
	draw_colored_polygon(points, fill_color)

	# Outline
	for i: int in range(4):
		draw_line(points[i], points[(i + 1) % 4], tint_color, outline_width)

	# Monogram letter
	var letter: String = reward.display_name.substr(0, 1).to_upper() if reward.display_name.length() > 0 else "?"
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, monogram_font_size)
	var text_pos: Vector2 = Vector2(cx - text_size.x / 2.0, cy + text_size.y / 4.0)
	draw_string(font, text_pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, monogram_font_size, tint_color)
