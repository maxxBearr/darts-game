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

var _darts_remaining: int = 3
var _using_textures: bool = false
var _dart_containers: Array[HBoxContainer] = []
var _barrel_component: DartComponent
var _shaft_component: DartComponent
var _flight_component: DartComponent


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
	for i: int in range(3):
		var dart_row: HBoxContainer = HBoxContainer.new()
		dart_row.position = Vector2(0.0, float(i) * (mini_dart_height + mini_dart_spacing))
		dart_row.add_theme_constant_override("separation", -2)
		add_child(dart_row)
		_dart_containers.append(dart_row)

		_add_mini_part(dart_row, _barrel_component, "Barrel")
		_add_mini_part(dart_row, _shaft_component, "Shaft")
		_add_mini_part(dart_row, _flight_component, "Flight")

	_update_dart_modulate()


func _add_mini_part(container: HBoxContainer, component: DartComponent, slot_name: String) -> void:
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(mini_dart_height * 1.5, mini_dart_height)
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	if component and component.texture:
		tex_rect.texture = component.texture
	else:
		tex_rect.self_modulate = Color(0.5, 0.5, 0.5, 0.5)

	if component:
		tex_rect.set_meta("dart_component", component)
		tex_rect.set_meta("slot_name", slot_name)
		tex_rect.tooltip_text = "%s (%s)\n%s" % [component.component_name, slot_name, "\n".join(component.get_tooltip_lines())]

	container.add_child(tex_rect)


func _update_dart_modulate() -> void:
	for i: int in range(_dart_containers.size()):
		var alpha: float = 1.0 if i < _darts_remaining else 0.3
		_dart_containers[i].modulate = Color(1.0, 1.0, 1.0, alpha)


## Set the indicator to shop mode showing a custom dart count.
## Shrinks darts when count > 3 to fit. All darts start active.
func set_shop_darts(total: int, remaining: int) -> void:
	# Rebuild with the right number of darts
	for container: HBoxContainer in _dart_containers:
		container.queue_free()
	_dart_containers.clear()

	var count: int = maxi(total, 1)
	# Shrink height when many darts
	var dart_h: float = mini_dart_height
	var dart_sp: float = mini_dart_spacing
	if count > 6:
		dart_h = mini_dart_height * 0.6
		dart_sp = mini_dart_spacing * 0.4
	elif count > 3:
		dart_h = mini_dart_height * 0.8
		dart_sp = mini_dart_spacing * 0.6

	for i: int in range(count):
		var dart_row: HBoxContainer = HBoxContainer.new()
		dart_row.position = Vector2(0.0, float(i) * (dart_h + dart_sp))
		dart_row.add_theme_constant_override("separation", -2)
		add_child(dart_row)
		_dart_containers.append(dart_row)

		_add_mini_part_sized(dart_row, _barrel_component, dart_h)
		_add_mini_part_sized(dart_row, _shaft_component, dart_h)
		_add_mini_part_sized(dart_row, _flight_component, dart_h)

	_darts_remaining = remaining
	_using_textures = true
	_update_dart_modulate()


func _add_mini_part_sized(container: HBoxContainer, component: DartComponent, height: float) -> void:
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(height * 1.5, height)
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if component and component.texture:
		tex_rect.texture = component.texture
	else:
		tex_rect.self_modulate = Color(0.5, 0.5, 0.5, 0.5)
	container.add_child(tex_rect)


## Restore the normal 3-dart display after shop mode.
func restore_normal_darts() -> void:
	for container: HBoxContainer in _dart_containers:
		container.queue_free()
	_dart_containers.clear()
	_using_textures = false
	set_dart_components(_barrel_component, _shaft_component, _flight_component)


func _draw() -> void:
	if _using_textures:
		return
	# Fallback: draw 3 vertical lines
	for i: int in range(3):
		var color: Color = active_color if i < _darts_remaining else spent_color
		var x: float = float(i) * spacing
		var start: Vector2 = Vector2(x, 0.0)
		var end: Vector2 = Vector2(x, line_height)
		draw_line(start, end, color, line_width, true)
