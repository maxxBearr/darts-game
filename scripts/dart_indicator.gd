extends Control
## Displays 3 darts representing remaining throws in the current turn.
## When dart textures are set (from the assembly screen), shows mini assembled
## darts. Falls back to simple vertical lines when no textures are available.

## Color of active (remaining) dart lines (fallback mode).
@export var active_color: Color = Color(1.0, 1.0, 1.0, 0.9)

## Color of used (spent) dart lines (fallback mode).
@export var spent_color: Color = Color(0.4, 0.4, 0.4, 0.3)

## Width of each dart line in pixels (fallback mode).
@export var line_width: float = 4.0

## Height of each dart line in pixels (fallback mode).
@export var line_height: float = 30.0

## Horizontal spacing between dart lines in pixels (fallback mode).
@export var spacing: float = 12.0

## Height of each mini-dart in the texture mode.
@export var mini_dart_height: float = 20.0

## Vertical spacing between mini-darts in texture mode.
@export var mini_dart_spacing: float = 8.0

## Extra scale multiplier for barrel sprites.
@export_range(0.1, 1.0, 0.05) var barrel_scale_multiplier: float = 0.7

## Extra scale multiplier for shaft sprites.
@export_range(0.1, 1.0, 0.05) var shaft_scale_multiplier: float = 0.7

## Extra scale multiplier for flight sprites.
@export_range(0.1, 1.0, 0.05) var flight_scale_multiplier: float = 0.7

var _darts_remaining: int = 3
var _max_darts: int = 3
var _using_textures: bool = false
var _dart_containers: Array[HBoxContainer] = []
var _barrel_component: DartComponent
var _shaft_component: DartComponent
var _flight_component: DartComponent
var _original_position: Vector2 = Vector2.ZERO
var _position_saved: bool = false


## Update how many darts are remaining and refresh display.
func set_darts_remaining(count: int) -> void:
	_darts_remaining = maxi(count, 0)
	if _using_textures:
		_update_dart_modulate()
	else:
		queue_redraw()


## Set the equipped dart component textures. Creates mini-dart visuals if any
## texture is non-null. Pass null components to revert to line fallback.
func set_dart_components(barrel: DartComponent, shaft: DartComponent, flight: DartComponent) -> void:
	_barrel_component = barrel
	_shaft_component = shaft
	_flight_component = flight

	var has_any_texture: bool = false
	if barrel and barrel.texture:
		has_any_texture = true
	if shaft and shaft.texture:
		has_any_texture = true
	if flight and flight.texture:
		has_any_texture = true

	# Clear old texture containers
	for container: HBoxContainer in _dart_containers:
		container.queue_free()
	_dart_containers.clear()

	if has_any_texture:
		_using_textures = true
		_build_mini_darts()
		queue_redraw()
	else:
		_using_textures = false
		queue_redraw()


func _build_mini_darts() -> void:
	var count: int = maxi(_max_darts, 1)
	var dart_h: float = mini_dart_height
	var dart_sp: float = mini_dart_spacing
	if count > 6:
		dart_h = mini_dart_height * 0.6
		dart_sp = mini_dart_spacing * 0.4
	elif count > 3:
		dart_h = mini_dart_height * 0.8
		dart_sp = mini_dart_spacing * 0.6

	var base_scale: float = _compute_base_scale(dart_h)

	var row_width: float = _compute_row_width(base_scale, dart_h)

	for i: int in range(count):
		var dart_row: HBoxContainer = HBoxContainer.new()
		dart_row.position = Vector2(0.0, float(i) * (dart_h + dart_sp))
		dart_row.custom_minimum_size = Vector2(row_width, dart_h)
		dart_row.size = Vector2(row_width, dart_h)
		dart_row.add_theme_constant_override("separation", -2)
		add_child(dart_row)
		_dart_containers.append(dart_row)

		_add_point_part(dart_row, dart_h)
		_add_scaled_part(dart_row, _barrel_component, base_scale * barrel_scale_multiplier, dart_h)
		_add_scaled_part(dart_row, _shaft_component, base_scale * shaft_scale_multiplier, dart_h)
		_add_scaled_part(dart_row, _flight_component, base_scale * flight_scale_multiplier, dart_h)

	_update_dart_modulate()


func _add_point_part(container: HBoxContainer, height: float) -> void:
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.texture = preload("res://sprites/point.png")
	tex_rect.custom_minimum_size = Vector2(height * 0.8, height)
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(tex_rect)


func _compute_row_width(base_scale: float, row_height: float) -> float:
	var w: float = row_height * 0.8  # point
	var parts: Array[Array] = [
		[_barrel_component, barrel_scale_multiplier],
		[_shaft_component, shaft_scale_multiplier],
		[_flight_component, flight_scale_multiplier],
	]
	for part: Array in parts:
		var comp: DartComponent = part[0] as DartComponent
		var mult: float = part[1] as float
		if comp and comp.texture:
			w += comp.texture.get_size().x * base_scale * mult
		else:
			w += row_height * 1.5
	return w


func _compute_base_scale(target_height: float) -> float:
	var max_h: float = 0.0
	for comp: DartComponent in [_barrel_component, _shaft_component, _flight_component]:
		if comp and comp.texture:
			max_h = maxf(max_h, comp.texture.get_size().y)
	if max_h > 0.0:
		return target_height / max_h
	return 1.0


func _add_scaled_part(container: HBoxContainer, component: DartComponent, scale: float, row_height: float) -> void:
	if component and component.texture:
		var ts: Vector2 = component.texture.get_size()
		var w: float = ts.x * scale
		var h: float = ts.y * scale
		var tex_rect: TextureRect = TextureRect.new()
		tex_rect.texture = component.texture
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.custom_minimum_size = Vector2(w, h)
		tex_rect.size = Vector2(w, h)
		var wrapper: Control = Control.new()
		wrapper.custom_minimum_size = Vector2(w, row_height)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex_rect.position = Vector2(0.0, (row_height - h) / 2.0)
		wrapper.add_child(tex_rect)
		container.add_child(wrapper)
	else:
		var placeholder: Control = Control.new()
		placeholder.custom_minimum_size = Vector2(row_height * 1.5, row_height)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(placeholder)


func _update_dart_modulate() -> void:
	for i: int in range(_dart_containers.size()):
		var alpha: float = 1.0 if i < _darts_remaining else 0.3
		_dart_containers[i].modulate = Color(1.0, 1.0, 1.0, alpha)


## Set the indicator to shop mode showing a custom dart count.
## Shrinks darts when count > 3 to fit. Shifts position up for large counts.
func set_shop_darts(total: int, remaining: int) -> void:
	if not _position_saved:
		_original_position = position
		_position_saved = true

	# Rebuild with the right number of darts
	for container: HBoxContainer in _dart_containers:
		container.queue_free()
	_dart_containers.clear()

	var count: int = maxi(total, 1)
	var dart_h: float = mini_dart_height
	var dart_sp: float = mini_dart_spacing
	if count > 10:
		dart_h = mini_dart_height * 0.45
		dart_sp = mini_dart_spacing * 0.3
	elif count > 6:
		dart_h = mini_dart_height * 0.6
		dart_sp = mini_dart_spacing * 0.4
	elif count > 3:
		dart_h = mini_dart_height * 0.8
		dart_sp = mini_dart_spacing * 0.6

	# Shift position up so the stack doesn't overflow downward
	var total_height: float = float(count) * (dart_h + dart_sp) - dart_sp
	var normal_height: float = 3.0 * (mini_dart_height + mini_dart_spacing) - mini_dart_spacing
	var overflow: float = maxf(total_height - normal_height, 0.0)
	position = _original_position - Vector2(0.0, overflow)

	var base_scale: float = _compute_base_scale(dart_h)
	var row_width: float = _compute_row_width(base_scale, dart_h)

	for i: int in range(count):
		var dart_row: HBoxContainer = HBoxContainer.new()
		dart_row.position = Vector2(0.0, float(i) * (dart_h + dart_sp))
		dart_row.custom_minimum_size = Vector2(row_width, dart_h)
		dart_row.size = Vector2(row_width, dart_h)
		dart_row.add_theme_constant_override("separation", -2)
		add_child(dart_row)
		_dart_containers.append(dart_row)

		_add_point_part(dart_row, dart_h)
		_add_scaled_part(dart_row, _barrel_component, base_scale * barrel_scale_multiplier, dart_h)
		_add_scaled_part(dart_row, _shaft_component, base_scale * shaft_scale_multiplier, dart_h)
		_add_scaled_part(dart_row, _flight_component, base_scale * flight_scale_multiplier, dart_h)

	_darts_remaining = remaining
	_using_textures = true
	_update_dart_modulate()


func set_max_darts(count: int) -> void:
	_max_darts = maxi(count, 1)
	for container: HBoxContainer in _dart_containers:
		container.queue_free()
	_dart_containers.clear()
	if _using_textures:
		_build_mini_darts()
	else:
		queue_redraw()


## Restore the normal dart display after shop mode.
func restore_normal_darts() -> void:
	for container: HBoxContainer in _dart_containers:
		container.queue_free()
	_dart_containers.clear()
	if _position_saved:
		position = _original_position
	_using_textures = false
	set_dart_components(_barrel_component, _shaft_component, _flight_component)


func _draw() -> void:
	if _using_textures:
		return
	for i: int in range(_max_darts):
		var color: Color = active_color if i < _darts_remaining else spent_color
		var x: float = float(i) * spacing
		var start: Vector2 = Vector2(x, 0.0)
		var end: Vector2 = Vector2(x, line_height)
		draw_line(start, end, color, line_width, true)
