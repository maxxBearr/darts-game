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
## Icon-bearing nodes (event/trial) stack title-over-icon: px reserved at the top for the title.
@export var icon_node_title_height: float = 18.0
## Breathing room between the title band and the family icon below it (px).
@export var icon_node_gap: float = 3.0
## Bottom inset under the family icon (px), so it doesn't kiss the button edge.
@export var icon_node_bottom_inset: float = 3.0

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

## Seconds for one full pulse cycle (dim → bright → dim) of the selectable next nodes. The
## reachable picks pulse so it reads which widgets are clickable; current/visited/locked stay static.
@export var pulse_period: float = 1.4

## Modulate multiplier at the DIM end of the pulse — slightly below the default 1.0 so the trough
## reads as a dip, not the resting state.
@export var pulse_dim: float = 0.72

## Modulate multiplier at the BRIGHT end of the pulse — above the default 1.0 to draw the eye to
## the clickable next nodes.
@export var pulse_bright: float = 1.30

# --- Type palette (flat grey-rect placeholders; reskinned later) ---
@export var color_leg: Color = Color(0.45, 0.48, 0.55)
@export var color_shop: Color = Color(0.30, 0.55, 0.45)
@export var color_boss: Color = Color(0.62, 0.30, 0.33)
@export var color_offbranch: Color = Color(0.42, 0.42, 0.60)
## Challenge ("Trial") node — the post-boss-1 off-branch wager race (Phase 02).
@export var color_challenge: Color = Color(0.62, 0.50, 0.28)

## Event-family glyph scaffold (Phase 03). The clear place Max drops art later; until then
## EVENT nodes render a per-family placeholder label + tint from this resource. Shared with
## the typed-shop ring. Lazily created in _ready if left unset.
@export var family_icons: EventFamilyIcons

var graph: MapGraph

var _buttons: Dictionary = {}     ## id -> Button
var _positions: Dictionary = {}   ## id -> Vector2 (widget centre)
var _title: Label
var _display_act: int = 0         ## the act currently drawn (incremental gen renders one act)

## Looping tween that pulses the selectable next nodes, plus the buttons it drives. Rebuilt from
## scratch every _refresh_reachability so stale tweens never stack or touch freed widgets.
var _pulse_tween: Tween = null
var _pulse_buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if family_icons == null:
		family_icons = EventFamilyIcons.new()


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

	_display_act = _current_display_act()
	_layout()
	_build_widgets()
	_refresh_reachability()
	queue_redraw()


## Which act to draw. Incremental generation only materializes one act ahead, and the
## paths the player can pick next all live in the frontier act, so render the act of the
## reachable next nodes (at an act boundary the current node is the just-cleared boss,
## whose successors are the NEW act's entry). Falls back to the current node's act when
## there is nothing reachable (the terminal boss — run over).
func _current_display_act() -> int:
	if graph == null:
		return 0
	var reach: Array[int] = graph.reachable_from(graph.current_id)
	if not reach.is_empty():
		var first: MapNode = graph.get_node_by_id(reach[0])
		if first != null:
			return first.act
	var cur: MapNode = graph.get_node_by_id(graph.current_id)
	return cur.act if cur != null else 0


## Whether a node belongs to the act currently being rendered.
func _is_displayed(n: MapNode) -> bool:
	return n != null and n.act == _display_act


## x = depth * column spacing (auto-fit to width); y = lane row, centred. Columns
## that hold a single node (act entries, bosses) are vertically centred — those are
## the funnel chokepoints. Depth is normalized to the displayed act's first column so a
## deep act (large global depth) still lays out from the left margin.
func _layout() -> void:
	var min_depth: int = 1 << 30
	var max_depth: int = 0
	var lanes_present: Dictionary = {}   ## distinct lane values among displayed nodes
	var per_depth_count: Dictionary = {}
	for id: int in graph.nodes:
		var n: MapNode = graph.nodes[id]
		if not _is_displayed(n):
			continue
		min_depth = mini(min_depth, n.depth)
		max_depth = maxi(max_depth, n.depth)
		lanes_present[n.lane] = true
		per_depth_count[n.depth] = per_depth_count.get(n.depth, 0) + 1
	if min_depth > max_depth:
		min_depth = 0   # nothing displayed (defensive)

	# Map distinct lane values to contiguous row indices in lane order (round 2). Mini-branch
	# lanes (−1 above lane 0, 2 below lane 1) sort outside the two main lanes, so a branch row
	# sits lane_spacing beyond its parent lane. With only lanes {0,1} this reproduces the old
	# two-row layout exactly. Sole-at-depth nodes (funnels / crossovers) stay centred.
	var sorted_lanes: Array = lanes_present.keys()
	sorted_lanes.sort()
	var lane_to_row: Dictionary = {}
	for idx: int in range(sorted_lanes.size()):
		lane_to_row[sorted_lanes[idx]] = idx
	var rows: int = maxi(sorted_lanes.size(), 1)

	var span: int = maxi(max_depth - min_depth, 1)
	var avail_w: float = size.x - margin.x * 2.0
	var col_spacing: float = avail_w / float(span)
	var center_y: float = size.y / 2.0 + 30.0

	for id: int in graph.nodes:
		var n: MapNode = graph.nodes[id]
		if not _is_displayed(n):
			continue
		var x: float = margin.x + float(n.depth - min_depth) * col_spacing
		var y: float
		if per_depth_count[n.depth] == 1:
			y = center_y
		else:
			var row: int = lane_to_row[n.lane]
			y = center_y + (float(row) - float(rows - 1) / 2.0) * lane_spacing
		_positions[id] = Vector2(x, y)


func _build_widgets() -> void:
	for id: int in graph.nodes:
		var n: MapNode = graph.nodes[id]
		if not _is_displayed(n):
			continue
		var btn: Button = Button.new()
		btn.custom_minimum_size = node_size
		btn.size = node_size
		btn.position = _positions[id] - node_size / 2.0
		btn.text = _label_for(n)
		btn.add_theme_font_size_override("font_size", 13)
		btn.clip_text = true
		# Family icon (Phase 03 typed-shop slice): event AND challenge nodes show their reward-family
		# glyph so the routing/deposit decision reads off the map. Drawn as a non-interactive child
		# in the lower-centre of the button (clicks pass through to the button). Falls back to the
		# text glyph when no texture is registered (handled in _label_for).
		var icon_tex: Texture2D = _family_icon_for(n)
		if icon_tex != null:
			# Title-over-icon stack. The Button's built-in text is vertically CENTRED, so it
			# lands in the same band as a bottom-anchored icon and the two overlap. Route the
			# title through a top-anchored Label instead (btn.text cleared), then give the icon
			# the remaining lower band with explicit gaps (the icon_node_* exports). Both
			# children ignore the mouse so clicks pass through to the button, and both inherit
			# the button's modulate (reachability dim + selection pulse keep working).
			btn.text = ""
			var title: Label = Label.new()
			title.text = _label_for(n)
			title.add_theme_font_size_override("font_size", 13)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			title.position = Vector2.ZERO
			title.size = Vector2(node_size.x, icon_node_title_height)
			btn.add_child(title)

			var ico: TextureRect = TextureRect.new()
			ico.texture = icon_tex
			ico.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ico.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon_band_top: float = icon_node_title_height + icon_node_gap
			ico.size = Vector2(node_size.x, node_size.y - icon_band_top - icon_node_bottom_inset)
			ico.position = Vector2(0.0, icon_band_top)
			btn.add_child(ico)

		var nid: int = id
		btn.pressed.connect(func() -> void: _on_node_pressed(nid))
		add_child(btn)
		_buttons[id] = btn


func _on_node_pressed(id: int) -> void:
	var n: MapNode = graph.get_node_by_id(id)
	# Gate on the LIVE forward edges from the current node, the same query that decided the
	# button's enabled state in _refresh_reachability — never the cached per-node `reachable`
	# flag. The two could diverge at an act boundary (a freshly-generated act's entry carried
	# a stale reachable=false), making the button clickable but the click inert.
	if n == null or not graph.reachable_from(graph.current_id).has(id):
		return
	node_chosen.emit(n)


## Enable only the reachable next picks; dim everything else. Marks the current
## node and visited history so the player can read where they are.
func _refresh_reachability() -> void:
	var reach: Array[int] = graph.reachable_from(graph.current_id)
	var reachable_btns: Array[Button] = []
	for id: int in _buttons:
		var btn: Button = _buttons[id]
		var n: MapNode = graph.nodes[id]
		var is_reach: bool = reach.has(id)
		btn.disabled = not is_reach
		_style_button(btn, n, is_reach, id == graph.current_id)
		# The selectable next nodes (reachable, and never the current node — current is never in
		# its own forward edges) pulse to read as clickable.
		if is_reach and id != graph.current_id:
			reachable_btns.append(btn)
	_restart_pulse(reachable_btns)
	queue_redraw()


## (Re)build the looping modulate pulse on the selectable next nodes. Kills any prior tween first
## so refreshes never stack pulses or leave a tween driving freed buttons. Current/visited/locked
## widgets keep their static modulate (reset to white in _style_button).
func _restart_pulse(reachable_btns: Array[Button]) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	_pulse_buttons = reachable_btns
	if _pulse_buttons.is_empty() or not is_inside_tree():
		return
	# One tween drives a shared brightness float (dim → bright → dim) applied to every reachable
	# button each step, looping forever. SINE ease gives a smooth breathing cadence.
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_method(_apply_pulse, pulse_dim, pulse_bright, pulse_period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_method(_apply_pulse, pulse_bright, pulse_dim, pulse_period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Apply the current pulse brightness to every selectable-next button. Guards against freed
## widgets (a _rebuild frees buttons; the kill in _restart_pulse normally beats this, but stay safe).
func _apply_pulse(brightness: float) -> void:
	for btn: Button in _pulse_buttons:
		if is_instance_valid(btn):
			btn.modulate = Color(brightness, brightness, brightness, 1.0)


func _style_button(btn: Button, n: MapNode, is_reach: bool, is_current: bool) -> void:
	# Reset modulate to the resting value; the pulse tween (re)applies a breathing modulate to the
	# reachable buttons after styling, and a node that was reachable last refresh but isn't now must
	# fall back to a static white modulate here.
	btn.modulate = Color.WHITE
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
	var face_alpha: float = 0.95 if (is_reach or is_current) else 0.6
	btn.add_theme_color_override("font_color", Color(1, 1, 1, face_alpha))
	# Icon-bearing nodes (event/trial) carry their title in a Label child and their glyph in a
	# TextureRect child — neither inherits the Button's font_color override, so mirror the
	# reachability dim onto them here or they'd stay full-bright on locked nodes.
	for child: Node in btn.get_children():
		if child is Label:
			(child as Label).add_theme_color_override("font_color", Color(1, 1, 1, face_alpha))
		elif child is TextureRect:
			(child as TextureRect).self_modulate = Color(1, 1, 1, face_alpha)


func _color_for(n: MapNode) -> Color:
	match n.type:
		MapNode.Type.SHOP:
			return color_shop
		MapNode.Type.BOSS:
			return color_boss
		MapNode.Type.CHALLENGE:
			return color_challenge
		MapNode.Type.EVENT:
			# Tint by the rolled trade-family so the routing decision reads off the map.
			if n.event != null and family_icons != null:
				return family_icons.color_for(n.event.reward_family)
			return color_offbranch
		_:
			return color_offbranch if n.is_off_branch else color_leg


## The reward-family icon texture for an event or challenge node, or null when none is registered
## (the view then falls back to the text glyph). EVENT carries the family as a StringName; CHALLENGE
## carries it as a ScoringEnums.Family enum (mapped via EventFamilyIcons.key_for_family).
func _family_icon_for(n: MapNode) -> Texture2D:
	if family_icons == null:
		return null
	if n.type == MapNode.Type.EVENT and n.event != null:
		return family_icons.texture_for(n.event.reward_family)
	if n.type == MapNode.Type.CHALLENGE and n.challenge != null:
		return family_icons.texture_for(EventFamilyIcons.key_for_family(n.challenge.reward_family))
	return null


func _label_for(n: MapNode) -> String:
	match n.type:
		MapNode.Type.SHOP:
			return "Shop"
		MapNode.Type.BOSS:
			return "BOSS"
		MapNode.Type.CHALLENGE:
			return "Trial"
		MapNode.Type.EVENT:
			# With a real family icon the glyph is redundant — keep just "Event". Only when no
			# texture is registered does the text glyph stand in (the scaffold fallback).
			if n.event != null and family_icons != null and family_icons.texture_for(n.event.reward_family) == null:
				return "Event\n%s" % family_icons.label_for(n.event.reward_family)
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
