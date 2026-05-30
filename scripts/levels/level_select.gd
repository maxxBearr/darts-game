class_name LevelSelectScreen
extends Control
## Full-screen level select menu. Each level renders as a card showing its name,
## lock/clear state, and fewest-darts record. Shown after "Start Game" on the
## start screen, before the assembly screen.

signal level_selected(level_definition: LevelDefinition)
signal back_pressed

## Ordered list of all available levels. Set from main.gd before adding to tree.
var levels: Array[LevelDefinition] = []

## Title text displayed at the top of the screen.
@export var title_text: String = "SELECT LEVEL"

## Font size for the title.
@export var title_font_size: int = 48

## Color of the title text.
@export var title_color: Color = Color(1.0, 0.95, 0.85)

## Vertical position of the title from the top of the screen.
@export var title_y: float = 80.0

## Font size for level card names.
@export var card_name_font_size: int = 32

## Font size for level card status text.
@export var card_status_font_size: int = 16

## Width of each level card in pixels.
@export var card_width: float = 200.0

## Height of each level card in pixels.
@export var card_height: float = 200.0

## Horizontal spacing between level cards.
@export var card_spacing: float = 40.0

## Vertical center position of the card row.
@export var cards_center_y: float = 340.0

## Color for locked level card backgrounds.
@export var locked_bg_color: Color = Color(0.15, 0.15, 0.18, 0.9)

## Border color for locked level cards.
@export var locked_border_color: Color = Color(0.3, 0.3, 0.35, 0.7)

## Color for unlocked (not yet cleared) level card backgrounds.
@export var unlocked_bg_color: Color = Color(0.12, 0.15, 0.22, 0.9)

## Border color for unlocked level cards.
@export var unlocked_border_color: Color = Color(0.5, 0.55, 0.7, 0.8)

## Color for cleared level card backgrounds.
@export var cleared_bg_color: Color = Color(0.1, 0.2, 0.12, 0.9)

## Border color for cleared level cards.
@export var cleared_border_color: Color = Color(0.3, 0.75, 0.35, 0.8)

## Color for the lock icon / locked text.
@export var locked_text_color: Color = Color(0.4, 0.4, 0.45)

## Color for the fewest-darts record text.
@export var best_text_color: Color = Color(0.85, 0.8, 0.5)

## Font size for the back button.
@export var back_button_font_size: int = 18

## Vertical position of the back button.
@export var back_button_y: float = 580.0

## Background color of the screen overlay.
@export var background_color: Color = Color(0.05, 0.05, 0.08, 0.95)

var _background: ColorRect
var _title_label: Label
var _card_container: HBoxContainer
var _card_buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


## Rebuild the card states to reflect current unlock/clear progress.
func refresh() -> void:
	for i: int in range(levels.size()):
		if i >= _card_buttons.size():
			break
		_update_card(i)


func _build_ui() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size

	_background = ColorRect.new()
	_background.color = background_color
	_background.position = Vector2.ZERO
	_background.size = viewport_size
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_background)

	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", title_font_size)
	_title_label.add_theme_color_override("font_color", title_color)
	_title_label.add_theme_constant_override("outline_size", 4)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	_title_label.size = Vector2(viewport_size.x, 70.0)
	_title_label.position = Vector2(0.0, title_y)
	add_child(_title_label)

	_build_level_cards(viewport_size)
	_build_nav_buttons(viewport_size)


func _build_level_cards(viewport_size: Vector2) -> void:
	_card_buttons.clear()

	var total_width: float = levels.size() * card_width + (levels.size() - 1) * card_spacing
	var start_x: float = (viewport_size.x - total_width) / 2.0
	var start_y: float = cards_center_y - card_height / 2.0

	for i: int in range(levels.size()):
		var level_def: LevelDefinition = levels[i]
		var card: Button = Button.new()
		card.custom_minimum_size = Vector2(card_width, card_height)
		card.size = Vector2(card_width, card_height)
		card.position = Vector2(start_x + i * (card_width + card_spacing), start_y)
		card.clip_text = true

		var idx: int = i
		card.pressed.connect(func() -> void: _on_card_pressed(idx))

		add_child(card)
		_card_buttons.append(card)

		var name_label: Label = Label.new()
		name_label.name = "NameLabel"
		name_label.text = level_def.display_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", card_name_font_size)
		name_label.size = Vector2(card_width - 16.0, 50.0)
		name_label.position = Vector2(8.0, 30.0)
		card.add_child(name_label)

		var status_label: Label = Label.new()
		status_label.name = "StatusLabel"
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.add_theme_font_size_override("font_size", card_status_font_size)
		status_label.size = Vector2(card_width - 16.0, 60.0)
		status_label.position = Vector2(8.0, 100.0)
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(status_label)

		_update_card(i)


func _update_card(index: int) -> void:
	var level_def: LevelDefinition = levels[index]
	var card: Button = _card_buttons[index]
	var name_label: Label = card.get_node("NameLabel")
	var status_label: Label = card.get_node("StatusLabel")
	var path: String = level_def.resource_path

	var is_locked: bool = level_def.unlock_condition != null and not level_def.unlock_condition.is_satisfied(&"", {})
	var is_cleared: bool = PlayerProgress.is_level_cleared(path)
	if level_def.unlock_condition != null:
		var cond: UnlockCondition = level_def.unlock_condition
		var req_path: String = cond.required_level_path if "required_level_path" in cond else ""
		print("DEBUG level_select: '%s' required_path='%s', is_satisfied=%s, cleared_levels=%s" % [level_def.display_name, req_path, cond.is_satisfied(&"", {}), str(PlayerProgress.cleared_levels)])

	if is_locked:
		card.disabled = true
		name_label.add_theme_color_override("font_color", locked_text_color)
		status_label.add_theme_color_override("font_color", locked_text_color)
		if level_def.unlock_condition != null:
			status_label.text = level_def.unlock_condition.description
		else:
			status_label.text = "Locked"
		_apply_card_style(card, locked_bg_color, locked_border_color)
	elif is_cleared:
		card.disabled = false
		name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		var best: int = PlayerProgress.get_fewest_darts(path)
		var boss_text: String = "%d boss" % level_def.boss_count if level_def.boss_count == 1 else "%d bosses" % level_def.boss_count
		status_label.text = "%s\nBest: %d darts" % [boss_text, best]
		status_label.add_theme_color_override("font_color", best_text_color)
		_apply_card_style(card, cleared_bg_color, cleared_border_color)
	else:
		card.disabled = false
		name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		var boss_text: String = "%d boss" % level_def.boss_count if level_def.boss_count == 1 else "%d bosses" % level_def.boss_count
		status_label.text = boss_text
		status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		_apply_card_style(card, unlocked_bg_color, unlocked_border_color)


func _apply_card_style(card: Button, bg: Color, border: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(bg.r + 0.05, bg.g + 0.05, bg.b + 0.05, bg.a)
	hover_style.border_color = Color(border.r, border.g, border.b, mini(border.a + 0.2, 1.0))
	card.add_theme_stylebox_override("hover", hover_style)

	var pressed_style: StyleBoxFlat = style.duplicate()
	pressed_style.bg_color = Color(bg.r - 0.03, bg.g - 0.03, bg.b - 0.03, bg.a)
	card.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style: StyleBoxFlat = style.duplicate()
	disabled_style.bg_color = Color(bg.r * 0.6, bg.g * 0.6, bg.b * 0.6, bg.a * 0.7)
	disabled_style.border_color = Color(border.r * 0.5, border.g * 0.5, border.b * 0.5, border.a * 0.5)
	card.add_theme_stylebox_override("disabled", disabled_style)


func _build_nav_buttons(viewport_size: Vector2) -> void:
	var back_button: Button = _create_nav_button("Back", Color(0.5, 0.5, 0.55))
	back_button.position = Vector2((viewport_size.x - 120.0) / 2.0, back_button_y)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back_button)


func _create_nav_button(text: String, accent: Color) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", back_button_font_size)
	button.custom_minimum_size = Vector2(160.0, 40.0)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.8)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, 0.9)
	hover_style.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style: StyleBoxFlat = style.duplicate()
	pressed_style.bg_color = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.8)
	button.add_theme_stylebox_override("pressed", pressed_style)

	return button


func _on_card_pressed(index: int) -> void:
	if index < 0 or index >= levels.size():
		return
	var level_def: LevelDefinition = levels[index]
	level_selected.emit(level_def)
