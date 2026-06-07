extends Node2D
## Board-rule reminder studs, drawn on the dartboard surround ring. One stud per active GEOMETRY
## rule (dynamic board laws need a persistent "this law is active" display, and its home is the
## surround — the effect is spatial, so the reminder should be too). Placeholder glyph art
## (EventFamilyIcons-fallback style: labelled colored shapes); hover shows the rule name + live
## effect summary.
##
## A child of the Dartboard (shares its coordinate space). main pushes the active rules via
## dartboard.set_geometry_studs() on every geometry change. Architected generically around an
## {icon, tooltip} entry so Mirror Zone + future board-level relics can migrate into studs later.

## Normalized radius (× the dartboard's board_radius) at which the studs sit on the surround.
## Kept clear of the number track (number_radius_multiplier ≈ 0.93) so studs don't collide with
## the wedge numbers or the boss flash.
@export var stud_radius_norm: float = 1.07

## Stud glyph radius in pixels.
@export var stud_size: float = 16.0

## Angular spacing between studs, in degrees along the surround.
@export var stud_spacing_deg: float = 16.0

## Angle (deg from top, clockwise) of the FIRST stud. 120° = the 4 o'clock position on screen
## (12 = top, 90 = 3 o'clock, 120 = 4 o'clock), in the right surround clear of the top-of-board
## number track and boss banners. NOTE the projection (Vector2(sin, -cos) below) and the dartboard
## carry no extra rotation — the Rotation boss's board_rotation_offset is folded into the wedge-angle
## math, never the dartboard node transform, so the studs (a child Node2D) never rotate with it.
## Subsequent studs walk COUNTERCLOCKWISE from here (up toward 3 o'clock); see _stud_center.
@export var stud_start_deg: float = 120.0

## Stud backing + outline + label colors (high-contrast so they survive recolor + boss overlay).
@export var stud_fill_color: Color = Color(0.12, 0.12, 0.14, 0.95)
@export var stud_outline_color: Color = Color(0.95, 0.9, 0.5, 0.95)
@export var stud_outline_thickness: float = 2.0
@export var stud_label_color: Color = Color(0.97, 0.97, 0.92)
@export var stud_label_font_size: int = 13

## Per-family glyph tint (matches EventFamilyIcons' geometry green; each rule kind gets a hue so
## the three geometry mechanics read apart at a glance).
@export var ring_trade_color: Color = Color(0.55, 0.80, 0.55)
@export var color_territory_color: Color = Color(0.85, 0.55, 0.45)
@export var parity_shift_color: Color = Color(0.55, 0.65, 0.90)

## Tooltip box styling.
@export var tooltip_bg_color: Color = Color(0.08, 0.08, 0.10, 0.95)
@export var tooltip_text_color: Color = Color(0.97, 0.97, 0.92)
@export var tooltip_font_size: int = 13

## board_radius mirror, set by the parent dartboard so the studs scale with the board.
var _board_radius: float = 300.0

## Active rule entries: {name, summary, modifier}. Drawn left-to-right along the surround.
var _rules: Array[Dictionary] = []

## Index of the stud the mouse is over (-1 = none).
var _hover_idx: int = -1


func _ready() -> void:
	# Draw above the board body but the studs/tooltip are small; process hover each frame.
	z_index = 2
	set_process(true)
	var parent: Node = get_parent()
	if parent != null and "board_radius" in parent:
		_board_radius = parent.board_radius


## Set the active board rules (one stud each). Each entry: {name, summary} plus EITHER a geometry
## `modifier` (glyph/color derived from its class) OR an explicit `glyph` + `color` (the generic
## form non-geometry laws like Parity Out use). See ScoringModifierManager.get_active_board_rules.
func set_rules(rules: Array[Dictionary]) -> void:
	_rules = rules
	queue_redraw()


func _process(_delta: float) -> void:
	if _rules.is_empty():
		if _hover_idx != -1:
			_hover_idx = -1
			queue_redraw()
		return
	var mouse: Vector2 = get_local_mouse_position()
	var new_hover: int = -1
	for i: int in range(_rules.size()):
		if mouse.distance_to(_stud_center(i)) <= stud_size:
			new_hover = i
			break
	if new_hover != _hover_idx:
		_hover_idx = new_hover
		queue_redraw()


## Centre position (local) of stud i along the surround arc. Studs walk COUNTERCLOCKWISE from
## stud_start_deg (4 o'clock) — i.e. SUBTRACT the spacing so later studs climb up the right side
## toward 3 o'clock. (A clockwise walk would march them down toward 6 o'clock, the cluttered bottom
## of the surround.) Vector2(sin, -cos) maps deg-from-top-clockwise to screen space: 0 = top,
## 90 = right, 120 = lower-right (4 o'clock).
func _stud_center(i: int) -> Vector2:
	var deg: float = stud_start_deg - float(i) * stud_spacing_deg
	var rad: float = deg_to_rad(deg)
	return Vector2(sin(rad), -cos(rad)) * _board_radius * stud_radius_norm


## Glyph tint for a rule. An entry may carry an explicit "color" (the generic {glyph, color}
## form non-geometry rules like Parity Out use); otherwise it falls back to per-modifier-class
## dispatch for the geometry rules.
func _rule_color(entry: Dictionary) -> Color:
	if entry.get("color", null) is Color:
		return entry["color"]
	var m: Variant = entry.get("modifier", null)
	if m is RingTradeModifier:
		return ring_trade_color
	if m is ColorTerritoryModifier:
		return color_territory_color
	if m is ParityShiftModifier:
		return parity_shift_color
	return stud_outline_color


## Short glyph label for a rule (ASCII-safe, EventFamilyIcons-fallback style). Honors an explicit
## "glyph" on the entry (generic form), else dispatches on the geometry modifier class.
func _rule_glyph(entry: Dictionary) -> String:
	var explicit: String = str(entry.get("glyph", ""))
	if explicit != "":
		return explicit
	var m: Variant = entry.get("modifier", null)
	if m is RingTradeModifier:
		return "T" if (m as RingTradeModifier).triple_shift >= 0.0 else "D"
	if m is ColorTerritoryModifier:
		return (m as ColorTerritoryModifier).get_color_name().substr(0, 1)
	if m is ParityShiftModifier:
		return "E" if (m as ParityShiftModifier).grow_even else "O"
	return "?"


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for i: int in range(_rules.size()):
		var center: Vector2 = _stud_center(i)
		var tint: Color = _rule_color(_rules[i])
		# Backing disc + colored ring so each stud reads as a persistent law marker.
		draw_circle(center, stud_size, stud_fill_color)
		draw_arc(center, stud_size, 0.0, TAU, 24, tint, stud_outline_thickness)
		var glyph: String = _rule_glyph(_rules[i])
		var gsize: Vector2 = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, stud_label_font_size)
		draw_string(font, center - Vector2(gsize.x * 0.5, -gsize.y * 0.25), glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, stud_label_font_size, stud_label_color)

	# Hover tooltip: rule name + live effect summary.
	if _hover_idx >= 0 and _hover_idx < _rules.size():
		_draw_tooltip(font, _rules[_hover_idx], _stud_center(_hover_idx))


func _draw_tooltip(font: Font, entry: Dictionary, anchor: Vector2) -> void:
	var name_text: String = str(entry.get("name", ""))
	var summary_text: String = str(entry.get("summary", ""))
	var name_size: Vector2 = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size)
	var summary_size: Vector2 = font.get_string_size(summary_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size)
	var pad: float = 6.0
	var w: float = maxf(name_size.x, summary_size.x) + pad * 2.0
	var h: float = name_size.y + summary_size.y + pad * 3.0
	var origin: Vector2 = anchor + Vector2(stud_size + 4.0, -h * 0.5)
	draw_rect(Rect2(origin, Vector2(w, h)), tooltip_bg_color)
	draw_rect(Rect2(origin, Vector2(w, h)), stud_outline_color, false, 1.0)
	var line1: Vector2 = origin + Vector2(pad, pad + name_size.y * 0.8)
	draw_string(font, line1, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size, tooltip_text_color)
	var line2: Vector2 = line1 + Vector2(0.0, name_size.y + pad)
	draw_string(font, line2, summary_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tooltip_font_size, tooltip_text_color)
