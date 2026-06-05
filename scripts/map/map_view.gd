class_name MapView
extends Control
## Code-built run-map overlay (no .tscn this slice — follows the LevelSelectScreen
## instantiation pattern). One grey-rect Button per MapNode, positioned by
## (depth, lane); edges drawn between centres in _draw(). Type-only: it never reads
## a node's target/darts (the "type on map, params on arrival" rule, §4). The art
## reskin later swaps this widget layer without touching MapGraph.

signal node_chosen(node: MapNode)

## Header text shown at the top of the overlay.
@export var title_text: String = "CHOOSE YOUR PATH"

## Font size for the header.
@export var title_font_size: int = 36

## Size of each node widget in pixels.
@export var node_size: Vector2 = Vector2(72.0, 48.0)

## Outer margin (x = left/right padding for the depth axis, y = top padding).
@export var margin: Vector2 = Vector2(110.0, 130.0)

## Vertical spacing between lane rows.
@export var lane_spacing: float = 120.0

## Full-screen backdrop colour.
@export var background_color: Color = Color(0.05, 0.06, 0.09, 0.97)

## Colour of normal (non-pickable-now) edges.
@export var edge_color: Color = Color(0.32, 0.35, 0.42, 0.7)

## Colour of edges leaving the current node (the legal next moves).
@export var edge_reachable_color: Color = Color(0.95, 0.85, 0.45, 0.95)

# --- Type palette (flat grey-rect placeholders; reskinned later) ---
@export var color_leg: Color = Color(0.45, 0.48, 0.55)
@export var color_shop: Color = Color(0.30, 0.55, 0.45)
@export var color_boss: Color = Color(0.62, 0.30, 0.33)
@export var color_offbranch: Color = Color(0.42, 0.42, 0.60)
## Challenge ("Trial") node — the post-boss-1 off-branch wager race (Phase 02).
@export var color_challenge: Color = Color(0.62, 0.50, 0.28)

var graph: MapGraph

var _buttons: Dictionary = {}     ## id -> Button
var _positions: Dictionary = {}   ## id -> Vector2 (widget centre)
var _title: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Build/refresh the widgets from the graph and show the overlay.
func display(g: MapGraph) -> void:
	graph = g
	_rebuild()


func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	_buttons.clear()
	_positions.clear()

	size = get_viewport_rect().size

	_title = Label.new()
	_title.text = title_text
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", title_font_size)
	_title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
	_title.size = Vector2(size.x, 50.0)
	_title.position = Vector2(0.0, 50.0)
	add_child(_title)

	_layout()
	_build_widgets()
	_refresh_reachability()
	queue_redraw()


## x = depth * column spacing (auto-fit to width); y = lane row, centred. Columns
## that hold a single node (act entries, bosses) are vertically centred — those are
## the funnel chokepoints.
func _layout() -> void:
	var max_depth: int = 0
	var max_row: int = 0
	var per_depth_count: Dictionary = {}
	for id: int in graph.nodes:
		var n: MapNode = graph.nodes[id]
		max_depth = maxi(max_depth, n.depth)
		max_row = maxi(max_row, n.lane)
		per_depth_count[n.depth] = per_depth_count.get(n.depth, 0) + 1

	var avail_w: float = size.x - margin.x * 2.0
	var col_spacing: float = avail_w / float(maxi(max_depth, 1))
	var center_y: float = size.y / 2.0 + 30.0
	var rows: int = max_row + 1

	for id: int in graph.nodes:
		var n: MapNode = graph.nodes[id]
		var x: float = margin.x + float(n.depth) * col_spacing
		var y: float
		if per_depth_count[n.depth] == 1:
			y = center_y
		else:
			y = center_y + (float(n.lane) - float(rows - 1) / 2.0) * lane_spacing
		_positions[id] = Vector2(x, y)


func _build_widgets() -> void:
	for id: int in graph.nodes:
		var n: MapNode = graph.nodes[id]
		var btn: Button = Button.new()
		btn.custom_minimum_size = node_size
		btn.size = node_size
		btn.position = _positions[id] - node_size / 2.0
		btn.text = _label_for(n)
		btn.add_theme_font_size_override("font_size", 13)
		btn.clip_text = true
		var nid: int = id
		btn.pressed.connect(func() -> void: _on_node_pressed(nid))
		add_child(btn)
		_buttons[id] = btn


func _on_node_pressed(id: int) -> void:
	var n: MapNode = graph.get_node_by_id(id)
	if n == null or not n.reachable:
		return
	node_chosen.emit(n)


## Enable only the reachable next picks; dim everything else. Marks the current
## node and visited history so the player can read where they are.
func _refresh_reachability() -> void:
	var reach: Array[int] = graph.reachable_from(graph.current_id)
	for id: int in _buttons:
		var btn: Button = _buttons[id]
		var n: MapNode = graph.nodes[id]
		var is_reach: bool = reach.has(id)
		btn.disabled = not is_reach
		_style_button(btn, n, is_reach, id == graph.current_id)
	queue_redraw()


func _style_button(btn: Button, n: MapNode, is_reach: bool, is_current: bool) -> void:
	var base: Color = _color_for(n)
	if not is_reach and not is_current:
		base = Color(base.r * 0.45, base.g * 0.45, base.b * 0.45, 0.85)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = base
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	if is_current:
		style.border_color = Color(1.0, 0.95, 0.6)
		style.set_border_width_all(3)
	elif is_reach:
		style.border_color = Color(0.95, 0.85, 0.45)
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.2, 0.2, 0.24, 0.6)
		style.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = Color(minf(base.r + 0.1, 1.0), minf(base.g + 0.1, 1.0), minf(base.b + 0.1, 1.0), base.a)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95 if (is_reach or is_current) else 0.6))


func _color_for(n: MapNode) -> Color:
	match n.type:
		MapNode.Type.SHOP:
			return color_shop
		MapNode.Type.BOSS:
			return color_boss
		MapNode.Type.CHALLENGE:
			return color_challenge
		_:
			return color_offbranch if n.is_off_branch else color_leg


func _label_for(n: MapNode) -> String:
	match n.type:
		MapNode.Type.SHOP:
			return "Shop"
		MapNode.Type.BOSS:
			return "BOSS"
		MapNode.Type.CHALLENGE:
			return "Trial"
		MapNode.Type.EVENT:
			return "Event"
		_:
			return "Leg"


func _draw() -> void:
	# Backdrop first (drawn under child widgets), then edges, then the Buttons
	# (children) render on top.
	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)
	if graph == null:
		return
	for id: int in graph.nodes:
		var n: MapNode = graph.nodes[id]
		if not _positions.has(id):
			continue
		var from: Vector2 = _positions[id]
		var from_current: bool = id == graph.current_id
		for nid: int in n.next_ids:
			if not _positions.has(nid):
				continue
			var to: Vector2 = _positions[nid]
			var col: Color = edge_reachable_color if from_current else edge_color
			var width: float = 4.0 if from_current else 2.5
			draw_line(from, to, col, width)
