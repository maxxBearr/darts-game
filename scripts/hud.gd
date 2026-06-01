extends CanvasLayer
## HUD overlay displaying X01 game state, per-dart feedback, upgrade cards, and control buttons.

signal next_dart_pressed
signal next_turn_pressed
signal next_leg_pressed
signal new_run_pressed
signal upgrade_selected(index: int)
signal modifier_selected(index: int)
signal modifier_toggled
signal modifier_skipped
signal reward_selected(index: int)
signal checkout_path_clicked(index: int)
signal streak_replace_selected(index: int)

@onready var score_label: Label = $ScoreLabel
@onready var instruction_label: Label = $InstructionLabel
@onready var remaining_label: Label = $RemainingLabel
@onready var turn_label: Label = $TurnLabel
@onready var dart_label: Label = $DartLabel
@onready var leg_label: Label = $LegLabel
@onready var bust_label: Label = $BustLabel
@onready var next_dart_button: Button = $NextDartButton
@onready var next_turn_button: Button = $NextTurnButton
@onready var next_leg_button: Button = $NextLegButton
@onready var new_run_button: Button = $NewRunButton
@onready var upgrade_container: HBoxContainer = $UpgradeContainer
@onready var upgrade_button_1: Button = $UpgradeContainer/UpgradeButton1
@onready var upgrade_button_2: Button = $UpgradeContainer/UpgradeButton2
@onready var upgrade_button_3: Button = $UpgradeContainer/UpgradeButton3
@onready var dart_indicator: Control = $DartIndicator
@onready var turn_score_label: Label = $TurnScoreLabel
@onready var hover_tooltip: Label = $HoverTooltip
@onready var modifier_tooltip: Label = $ModifierTooltip
@onready var modifier_panel: HBoxContainer = $ModifierPanel

@export_group("Modifier Panel")

## Size of each modifier square in the relic bar (pixels).
@export var modifier_square_size: int = 40

@export_group("Legendary Panel")

## Size of each legendary diamond icon in the panel (pixels).
@export var legendary_diamond_size: int = 40

## Spacing between legendary icons (pixels).
@export var legendary_panel_spacing: int = 6

## Gold tint color for legendary diamond icons.
@export var legendary_tint_color: Color = Color(1.0, 0.85, 0.2, 1.0)

@export_group("Tooltips")

## Vertical offset above the crosshair for the hover tooltip (pixels).
@export var hover_tooltip_offset_y: float = 50.0

## Font size for the hover/target tooltip label.
@export var hover_tooltip_font_size: int = 24

## Outline thickness around the hover tooltip text (pixels).
@export var hover_tooltip_outline_size: int = 2

## Outline color for the hover tooltip text.
@export var hover_tooltip_outline_color: Color = Color(0, 0, 0, 1)

## How many pixels a modifier square lifts during perk-up hover state.
@export var perkup_lift_pixels: float = 8.0

## Duration of the perk-up lift/drop animation in seconds.
@export var perkup_anim_duration: float = 0.15

@export_group("Action Button Pulse")

## Minimum opacity during the pulse cycle.
@export_range(0.0, 1.0, 0.05) var button_pulse_min_alpha: float = 0.4

## Maximum opacity during the pulse cycle (values above 1.0 make the button overbright).
@export_range(1.0, 2.0, 0.05) var button_pulse_max_alpha: float = 1.4

## Duration of one full pulse cycle (bright -> dim -> bright) in seconds.
@export var button_pulse_duration: float = 1.0

@export_group("Upgrade Cards")

## Background opacity of upgrade/modifier pick buttons (0 = transparent, 1 = solid).
@export_range(0.0, 1.0, 0.05) var upgrade_button_opacity: float = 0.85

## Corner radius of upgrade/modifier pick buttons in pixels.
@export_range(0.0, 16.0, 1.0) var upgrade_button_corner_radius: float = 6.0

@export_group("Checkout Helper")

## Font size for checkout path lines.
@export var checkout_font_size: int = 12

## Color for the checkout path text.
@export var checkout_text_color: Color = Color(0.85, 0.85, 0.85)

## Color for setup recommendation text.
@export var checkout_setup_color: Color = Color(0.7, 0.8, 1.0)

## Color for committed (already-thrown) steps in a path.
@export var checkout_committed_color: Color = Color(0.3, 1.0, 0.4)

## Color for the selected/illuminated path line (non-finishing step).
@export var illumination_text_color: Color = Color(0.4, 0.7, 1.0)

## Color for the selected path line when it's a direct checkout (gold = win).
@export var illumination_finish_text_color: Color = Color(1.0, 0.85, 0.2)

@export_group("Streak Section")

## Pixel size of the small icon in each streak section line.
@export var streak_icon_size: int = 20

## Alpha applied to a streak line when count is 0 (owned but no live streak).
@export var streak_idle_opacity: float = 0.5

## Alpha applied to a streak line when the modifier is toggled off.
@export var streak_disabled_opacity: float = 0.3

## Title shown above the streak section when at least one streak is owned.
@export var streak_section_title_text: String = "— Streaks —"

## Hint text shown when modifiers can be toggled.
@export var checkout_toggle_hint: String = "Try toggling a modifier to recalculate"

## Setup text for score-reduction mode (far from checkout range).
@export var score_reduction_text: String = "Score more points to enter checkout range"

## Setup text for off-board preservation mode (every scoring dart busts).
@export var off_board_preserve_text: String = "Aim off-board — any scoring dart busts"

## Gap in pixels between the stats bars and the checkout helper below them.
@export var checkout_top_margin: float = 12.0


@onready var stats_container: VBoxContainer = $StatsContainer

const STAT_KEYS: Array[String] = [
	"horizontal_range", "vertical_range",
	"horizontal_speed", "vertical_speed",
	"horizontal_accuracy", "vertical_accuracy",
]

const STAT_DISPLAY_NAMES: Dictionary = {
	"horizontal_range": "H Range",
	"vertical_range": "V Range",
	"horizontal_speed": "H Spd Ctrl",
	"vertical_speed": "V Spd Ctrl",
	"horizontal_accuracy": "H Accuracy",
	"vertical_accuracy": "V Accuracy",
}

const STAT_DESCRIPTIONS: Dictionary = {
	"horizontal_range": "Tightens the aiming ellipse to shrink towards your target. Allows for easier H meter timing",
	"vertical_range": "Shortens the aiming ellipse to shrink towards your target. Alows for easier V meter timing,",
	"horizontal_speed": "Slows the speed of the horizantal merer.",
	"vertical_speed": "Slows the speed of the vertical meter.",
	"horizontal_accuracy": "Shortens the width of the accruacy zone.",
	"vertical_accuracy": "Shrinks the height of the accuracy zone."
}

const BAR_MAX_WIDTH: float = 120.0
const BAR_HEIGHT: float = 12.0
const STAT_MAX_VALUE: float = 100.0

@export_group("Stat Panel")

## Width of stat name labels (shrink to pull labels closer to bars).
@export var stat_label_width: float = 75.0

var _stat_bars: Dictionary = {}
var _stat_value_labels: Dictionary = {}
var _stat_rows: Dictionary = {}
var _stats_title_label: Label = null
var _modifier_status_title: Label
var _modifier_rows: Array[Dictionary] = []
var _streak_section: VBoxContainer = null
var _streak_title_label: Label = null

## Whether upgrade buttons are in modifier selection mode.
var _modifier_mode: bool = false
var _reward_mode: bool = false
var _streak_replace_mode: bool = false
var _skip_modifier_button: Button = null
var _boss_status_label: Label = null
var _boss_bg_tint: ColorRect = null
var _boss_bg_layer: CanvasLayer = null
var _boss_bg_tween: Tween = null
var _legendary_panel: HBoxContainer = null
var _legendary_tooltip: Label = null

## Current upgrades for hover preview (set during accuracy pick phase).
var _preview_upgrades: Array[Dictionary] = []

## Cached current stats for restoring after hover preview.
var _cached_current_stats: Dictionary = {}

## Cached base stats for restoring after hover preview.
var _cached_base_stats: Dictionary = {}

## Color for stat bars showing a previewed upgrade boost.
const PREVIEW_BOOST_COLOR: Color = Color(0.3, 0.8, 1.0)

## Color for stat bars showing a previewed upgrade penalty.
const PREVIEW_PENALTY_COLOR: Color = Color(1.0, 0.5, 0.2)


## Total shop darts for the current shop (for "thrown/total" label).
var _shop_total_darts: int = 0

var _button_pulse_tween: Tween = null

## Checkout helper panel and state.
var _checkout_panel: VBoxContainer
var _checkout_toggle_button: Button
var _checkout_path_labels: Array[Label] = []
var _checkout_hint_label: Label
var _checkout_visible: bool = true
var _checkout_has_paths: bool = false
var _divergent_wedges: Dictionary = {}
var _checkout_paths_ref: Array[Array] = []


func _ready() -> void:
	if hover_tooltip.label_settings:
		hover_tooltip.label_settings.font_size = hover_tooltip_font_size
		hover_tooltip.label_settings.outline_size = hover_tooltip_outline_size
		hover_tooltip.label_settings.outline_color = hover_tooltip_outline_color
	else:
		hover_tooltip.add_theme_font_size_override("font_size", hover_tooltip_font_size)
		hover_tooltip.add_theme_constant_override("outline_size", hover_tooltip_outline_size)
		hover_tooltip.add_theme_color_override("font_outline_color", hover_tooltip_outline_color)

	# Connect action buttons
	next_dart_button.pressed.connect(func() -> void: next_dart_pressed.emit())
	next_turn_button.pressed.connect(func() -> void: next_turn_pressed.emit())
	next_leg_button.pressed.connect(func() -> void: next_leg_pressed.emit())
	new_run_button.pressed.connect(func() -> void: new_run_pressed.emit())

	# Pulse action buttons when they become visible
	for btn: Button in [next_dart_button, next_turn_button, next_leg_button, new_run_button]:
		btn.visibility_changed.connect(_on_action_button_visibility_changed.bind(btn))

	# Connect upgrade buttons — each emits upgrade_selected with its index
	upgrade_button_1.pressed.connect(func() -> void: _select_upgrade(0))
	upgrade_button_2.pressed.connect(func() -> void: _select_upgrade(1))
	upgrade_button_3.pressed.connect(func() -> void: _select_upgrade(2))

	# Style upgrade/modifier pick buttons
	_apply_upgrade_button_style(upgrade_button_1)
	_apply_upgrade_button_style(upgrade_button_2)
	_apply_upgrade_button_style(upgrade_button_3)

	# Build skip modifier button (right of upgrade cards, independent of HBox layout)
	_skip_modifier_button = Button.new()
	_skip_modifier_button.name = "SkipModifierButton"
	_skip_modifier_button.text = "Skip"
	_skip_modifier_button.visible = false
	_skip_modifier_button.custom_minimum_size = Vector2(100.0, 36.0)
	_skip_modifier_button.anchor_left = 1.0
	_skip_modifier_button.anchor_right = 1.0
	_skip_modifier_button.anchor_top = 0.5
	_skip_modifier_button.anchor_bottom = 0.5
	_skip_modifier_button.offset_left = -130.0
	_skip_modifier_button.offset_right = -10.0
	_skip_modifier_button.offset_top = -18.0
	_skip_modifier_button.offset_bottom = 18.0
	_skip_modifier_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_apply_upgrade_button_style(_skip_modifier_button)
	_skip_modifier_button.pressed.connect(func() -> void:
		AuidoManager.play_ui_click()
		_skip_modifier_button.visible = false
		upgrade_container.visible = false
		_modifier_mode = false
		modifier_skipped.emit()
	)
	add_child(_skip_modifier_button)

	# Build legendary panel (left of modifier panel, gold diamonds for boss rewards)
	_legendary_panel = HBoxContainer.new()
	_legendary_panel.name = "LegendaryPanel"
	_legendary_panel.add_theme_constant_override("separation", legendary_panel_spacing)
	_legendary_panel.anchor_top = 1.0
	_legendary_panel.anchor_bottom = 1.0
	_legendary_panel.offset_top = modifier_panel.offset_top
	_legendary_panel.offset_bottom = modifier_panel.offset_bottom
	_legendary_panel.offset_right = modifier_panel.offset_left - 12.0
	_legendary_panel.offset_left = _legendary_panel.offset_right - 300.0
	_legendary_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legendary_panel.alignment = BoxContainer.ALIGNMENT_END
	_legendary_panel.visible = false
	add_child(_legendary_panel)

	_legendary_tooltip = Label.new()
	_legendary_tooltip.name = "LegendaryTooltip"
	_legendary_tooltip.visible = false
	_legendary_tooltip.add_theme_font_size_override("font_size", 13)
	_legendary_tooltip.add_theme_color_override("font_color", legendary_tint_color)
	add_child(_legendary_tooltip)

	# Start with all buttons and optional labels hidden
	hide_all_buttons()
	bust_label.visible = false
	upgrade_container.visible = false
	hover_tooltip.visible = false
	modifier_tooltip.visible = false

	_build_stat_bars()
	_build_streak_section()
	_build_checkout_panel()


## Display the result of the current throw (per-dart feedback).
func show_score(result: Dictionary) -> void:
	var ring_name: String = result["ring_name"]
	if ring_name == "Off Board":
		score_label.text = "Off Board — 0 points"
	elif ring_name == "Double Bull":
		score_label.text = "Double Bull — 50 points!"
	elif ring_name == "Single Bull":
		score_label.text = "Single Bull — 25 points"
	else:
		var face: int = result["face_value"]
		var total: int = result["total_score"]
		score_label.text = "%s %d — %d points!" % [ring_name, face, total]


## Update the remaining score display.
func update_remaining(score: int, glass_cannon: bool = false) -> void:
	if glass_cannon:
		remaining_label.text = "%d  [GC]" % score
	else:
		remaining_label.text = str(score)


## Set the remaining score label to gold when a single-dart checkout exists,
## or back to default when it doesn't. Driven by the same checkout logic
## that highlights finishing spots on the board — single source of truth.
func set_remaining_checkout_available(has_checkout: bool) -> void:
	if has_checkout:
		remaining_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		remaining_label.modulate = Color(1.0, 1.0, 1.0)


func set_remaining_bust(is_bust: bool) -> void:
	if is_bust:
		remaining_label.modulate = Color(1.0, 0.15, 0.1)
	else:
		remaining_label.modulate = Color(1.0, 1.0, 1.0)


## Update the turn counter display.
func update_turn(turn: int, max_turns: int) -> void:
	if turn == max_turns:
		turn_label.text = "Turn %d/%d — LAST TURN!" % [turn, max_turns]
		turn_label.modulate = Color(1.0, 0.4, 0.3)
	else:
		turn_label.text = "Turn %d/%d" % [turn, max_turns]
		turn_label.modulate = Color(1.0, 1.0, 1.0)


## Update the dart counter display and visual indicator.
func update_darts(darts_remaining: int, is_last_turn: bool = false, darts_per_turn: int = 3) -> void:
	dart_label.text = "Dart %d/%d" % [darts_per_turn - darts_remaining, darts_per_turn]
	if dart_indicator._max_darts != darts_per_turn:
		dart_indicator.set_max_darts(darts_per_turn)
	dart_indicator.set_darts_remaining(darts_remaining)
	if darts_remaining == 1 and is_last_turn:
		dart_label.text = "FINAL DART!"
		dart_label.add_theme_font_size_override("font_size", 28)
		dart_label.modulate = Color(1.0, 0.25, 0.2)
		_shake_label(dart_label)
	elif darts_remaining == 1:
		dart_label.text += " — LAST DART!"
		dart_label.remove_theme_font_size_override("font_size")
		dart_label.modulate = Color(1.0, 1.0, 1.0)
	else:
		dart_label.remove_theme_font_size_override("font_size")
		dart_label.modulate = Color(1.0, 1.0, 1.0)


func _shake_label(label: Label) -> void:
	var original_pos: Vector2 = label.position
	var tween: Tween = create_tween()
	for i: int in range(6):
		var offset: Vector2 = Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0))
		tween.tween_property(label, "position", original_pos + offset, 0.05)
	tween.tween_property(label, "position", original_pos, 0.05)


## Update the leg label display.
func update_leg(leg: int, target: int, is_boss: bool = false) -> void:
	leg_label.text = "Leg %d — %d" % [leg, target]
	if is_boss:
		leg_label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
	else:
		leg_label.remove_theme_color_override("font_color")


## Show the persistent boss status label with name, description, and status text.
## Shifts gameplay labels down to make room.
func show_boss_status(boss_name: String, status_text: String, color: Color) -> void:
	if _boss_status_label == null:
		_boss_status_label = Label.new()
		_boss_status_label.name = "BossStatusLabel"
		_boss_status_label.add_theme_font_size_override("font_size", boss_status_font_size)
		_boss_status_label.add_theme_constant_override("outline_size", 2)
		_boss_status_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
		_boss_status_label.size = Vector2(500.0, 24.0)
		add_child(_boss_status_label)
	_boss_status_label.text = "BOSS: %s — %s" % [boss_name, status_text]
	_boss_status_label.add_theme_color_override("font_color", color)
	_boss_status_label.position = Vector2(leg_label.position.x, boss_status_y)
	if not _boss_status_label.visible:
		_boss_status_label.visible = true
		_shift_gameplay_labels(boss_label_offset)


## Update just the status text portion of the boss status label.
func update_boss_status_text(boss_name: String, status_text: String) -> void:
	if _boss_status_label != null and _boss_status_label.visible:
		_boss_status_label.text = "BOSS: %s — %s" % [boss_name, status_text]


## Hide the boss status label and background tint. Restores label positions.
func hide_boss_status() -> void:
	if _boss_status_label != null and _boss_status_label.visible:
		_boss_status_label.visible = false
		_shift_gameplay_labels(-boss_label_offset)
	_hide_boss_bg_tint()


func _hide_boss_bg_tint() -> void:
	if _boss_bg_tint == null or not _boss_bg_tint.visible:
		return
	_kill_boss_bg_tween()
	var target: Color = Color(_boss_bg_tint.color, 0.0)
	_boss_bg_tween = create_tween()
	_boss_bg_tween.tween_property(_boss_bg_tint, "color", target, boss_bg_tween_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_boss_bg_tween.tween_callback(func() -> void: _boss_bg_tint.visible = false)


func _kill_boss_bg_tween() -> void:
	if _boss_bg_tween != null and _boss_bg_tween.is_valid():
		_boss_bg_tween.kill()
	_boss_bg_tween = null


## Shift the left-column gameplay labels vertically by the given amount.
func _shift_gameplay_labels(offset: float) -> void:
	remaining_label.position.y += offset
	turn_label.position.y += offset
	dart_label.position.y += offset
	turn_score_label.position.y += offset


## Show a full-screen background tint during boss legs (tweened fade-in).
func show_boss_background_tint(tint: Color) -> void:
	if tint.a <= 0.0:
		_hide_boss_bg_tint()
		return
	if _boss_bg_tint == null:
		_boss_bg_layer = CanvasLayer.new()
		_boss_bg_layer.layer = -100
		get_tree().root.add_child(_boss_bg_layer)
		_boss_bg_tint = ColorRect.new()
		_boss_bg_tint.name = "BossBgTint"
		_boss_bg_tint.size = get_viewport().get_visible_rect().size
		_boss_bg_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_boss_bg_layer.add_child(_boss_bg_tint)
	_kill_boss_bg_tween()
	if not _boss_bg_tint.visible:
		_boss_bg_tint.color = Color(tint, 0.0)
		_boss_bg_tint.visible = true
	_boss_bg_tween = create_tween()
	_boss_bg_tween.tween_property(_boss_bg_tint, "color", tint, boss_bg_tween_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Show bust message and make the bust label visible.
func show_bust(reason: String) -> void:
	bust_label.text = "BUST! %s" % reason
	bust_label.visible = true


## Show a centered "LEG WON!" banner that scales in and fades out.
## Returns the tween so callers can chain callbacks after it finishes.
## Font size for the "LEG WON!" banner.
@export var leg_won_font_size: int = 48

## Color of the "LEG WON!" banner text.
@export var leg_won_color: Color = Color(1.0, 0.85, 0.2)

## Duration the leg-won banner stays visible before fading.
@export var leg_won_hold_duration: float = 0.8

## Duration of the leg-won banner scale-in animation.
@export var leg_won_scale_in_duration: float = 0.3

## Duration of the leg-won banner fade-out animation.
@export var leg_won_fade_out_duration: float = 0.4

## Font size for the boss announcement title.
@export var boss_announce_title_font_size: int = 42

## Font size for the boss announcement description.
@export var boss_announce_desc_font_size: int = 20

## Duration the boss announcement stays visible before fading.
@export var boss_announce_hold_duration: float = 1.5

## Duration of the boss announcement scale-in animation.
@export var boss_announce_scale_in_duration: float = 0.35

## Duration of the boss announcement fade-out animation.
@export var boss_announce_fade_out_duration: float = 0.4

## Font size for the persistent boss status label.
@export var boss_status_font_size: int = 16

## Y position for the persistent boss status label (below the leg label).
@export var boss_status_y: float = 42.0

## How many pixels to shift the left-column labels down during a boss leg
## to make room for the boss status label.
@export var boss_label_offset: float = 24.0

## Duration of the boss background tint fade in/out.
@export var boss_bg_tween_duration: float = 0.6


func show_leg_won_banner() -> Tween:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var banner: Label = Label.new()
	banner.text = "LEG WON!"
	banner.add_theme_font_size_override("font_size", leg_won_font_size)
	banner.add_theme_color_override("font_color", leg_won_color)
	banner.add_theme_constant_override("outline_size", 6)
	banner.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.size = Vector2(400.0, 80.0)
	banner.position = Vector2((viewport_size.x - 400.0) / 2.0, (viewport_size.y - 80.0) / 2.0)
	banner.pivot_offset = Vector2(200.0, 40.0)
	banner.scale = Vector2(0.3, 0.3)
	banner.modulate.a = 0.0
	add_child(banner)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(banner, "scale", Vector2(1.0, 1.0), leg_won_scale_in_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(banner, "modulate:a", 1.0, leg_won_scale_in_duration * 0.5)
	tween.set_parallel(false)
	tween.tween_interval(leg_won_hold_duration)
	tween.set_parallel(true)
	tween.tween_property(banner, "modulate:a", 0.0, leg_won_fade_out_duration).set_ease(Tween.EASE_IN)
	tween.tween_property(banner, "position:y", banner.position.y - 30.0, leg_won_fade_out_duration).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(banner.queue_free)
	return tween


## Show a boss arrival announcement with name and description. Returns the tween
## so the caller can chain a callback after it finishes.
func show_boss_announcement(boss_name: String, boss_description: String, title_color: Color = Color(0.9, 0.2, 0.2), desc_color: Color = Color(0.85, 0.75, 0.65)) -> Tween:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var container: VBoxContainer = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 8)
	container.size = Vector2(500.0, 140.0)
	container.position = Vector2((viewport_size.x - 500.0) / 2.0, (viewport_size.y - 140.0) / 2.0)
	container.pivot_offset = Vector2(250.0, 70.0)
	container.scale = Vector2(0.3, 0.3)
	container.modulate.a = 0.0
	add_child(container)

	var name_label: Label = Label.new()
	name_label.text = "BOSS: %s" % boss_name
	name_label.add_theme_font_size_override("font_size", boss_announce_title_font_size)
	name_label.add_theme_color_override("font_color", title_color)
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.text = boss_description
	desc_label.add_theme_font_size_override("font_size", boss_announce_desc_font_size)
	desc_label.add_theme_color_override("font_color", desc_color)
	desc_label.add_theme_constant_override("outline_size", 3)
	desc_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(desc_label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(container, "scale", Vector2(1.0, 1.0), boss_announce_scale_in_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(container, "modulate:a", 1.0, boss_announce_scale_in_duration * 0.5)
	tween.set_parallel(false)
	tween.tween_interval(boss_announce_hold_duration)
	tween.set_parallel(true)
	tween.tween_property(container, "modulate:a", 0.0, boss_announce_fade_out_duration).set_ease(Tween.EASE_IN)
	tween.tween_property(container, "position:y", container.position.y - 30.0, boss_announce_fade_out_duration).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(container.queue_free)
	return tween


## Show leg complete message with upgrade card choices.
func show_leg_complete_with_upgrades(leg: int, target: int, turns_used: int, upgrades: Array[Dictionary]) -> void:
	score_label.text = "Leg %d Complete! Cleared %d in %d turns" % [leg, target, turns_used]
	_preview_upgrades = upgrades
	_skip_modifier_button.visible = false

	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var upgrade: Dictionary = upgrades[i]
		var button_text: String = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
		if upgrade["tradeoff"]:
			button_text += "\n-%d %s" % [upgrade["penalty_amount"], upgrade["penalty_name"]]
		buttons[i].text = button_text
		var color: Color = upgrade["color"]
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = upgrade["description"]
		buttons[i].visible = true

		# Connect hover preview signals (disconnect any previous connections)
		if buttons[i].mouse_entered.is_connected(_on_upgrade_hover):
			buttons[i].mouse_entered.disconnect(_on_upgrade_hover)
		if buttons[i].mouse_exited.is_connected(_on_upgrade_unhover):
			buttons[i].mouse_exited.disconnect(_on_upgrade_unhover)
		buttons[i].mouse_entered.connect(_on_upgrade_hover.bind(i))
		buttons[i].mouse_exited.connect(_on_upgrade_unhover)

	upgrade_container.visible = true
	next_leg_button.visible = false



## Show game over message.
func show_game_over(leg_reached: int, target_reached: int) -> void:
	score_label.text = "Run Over! Reached Leg %d (%d)" % [leg_reached, target_reached]
	new_run_button.visible = true


## Hide all action buttons.
func hide_all_buttons() -> void:
	next_dart_button.visible = false
	next_turn_button.visible = false
	next_leg_button.visible = false
	new_run_button.visible = false


func _on_action_button_visibility_changed(btn: Button) -> void:
	if btn.visible:
		_start_button_pulse(btn)
	else:
		_stop_button_pulse(btn)


func _start_button_pulse(btn: Button) -> void:
	_stop_button_pulse(btn)
	var half: float = button_pulse_duration / 2.0
	btn.modulate.a = button_pulse_max_alpha
	_button_pulse_tween = create_tween().set_loops()
	_button_pulse_tween.tween_property(btn, "modulate:a", button_pulse_min_alpha, half).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_button_pulse_tween.tween_property(btn, "modulate:a", button_pulse_max_alpha, half).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _stop_button_pulse(btn: Button) -> void:
	if _button_pulse_tween != null and _button_pulse_tween.is_valid():
		_button_pulse_tween.kill()
	_button_pulse_tween = null
	btn.modulate.a = 1.0


## Hide the bust label.
func reset_bust() -> void:
	bust_label.visible = false


## Show instruction text to the player.
func show_instruction(text: String) -> void:
	instruction_label.text = text


## Hide the per-dart score text and all buttons (called at start of each throw).
func hide_score() -> void:
	score_label.text = ""
	hide_all_buttons()
	reset_bust()
	upgrade_container.visible = false


## Show a fresh set of upgrade choices (for subsequent rounds).
func show_upgrade_choices(upgrades: Array[Dictionary]) -> void:
	_preview_upgrades = upgrades
	score_label.text = "Choose another upgrade!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var upgrade: Dictionary = upgrades[i]
		var button_text: String = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
		if upgrade["tradeoff"]:
			button_text += "\n-%d %s" % [upgrade["penalty_amount"], upgrade["penalty_name"]]
		buttons[i].text = button_text
		var color: Color = upgrade["color"]
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = upgrade["description"]
	upgrade_container.visible = true
	next_leg_button.visible = false


## Update the turn score display.
func update_turn_score(score: int) -> void:
	turn_score_label.text = "Turn Score: %d" % score


## Build stat bar rows inside the StatsContainer, replacing scene-defined labels.
func _build_stat_bars() -> void:
	for child: Node in stats_container.get_children():
		child.queue_free()

	var tooltip_theme: Theme = _create_tooltip_theme()
	stats_container.theme = tooltip_theme

	_stats_title_label = Label.new()
	_stats_title_label.text = "— Stats —"
	_stats_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_title_label.add_theme_font_size_override("font_size", 14)
	_stats_title_label.modulate = Color(0.8, 0.8, 0.6)
	stats_container.add_child(_stats_title_label)

	for key: String in STAT_KEYS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = STAT_DESCRIPTIONS[key]
		stats_container.add_child(row)

		var name_lbl: Label = Label.new()
		name_lbl.text = STAT_DISPLAY_NAMES[key] + ":"
		name_lbl.custom_minimum_size = Vector2(stat_label_width, BAR_HEIGHT + 2.0)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_lbl.size_flags_horizontal = 0
		name_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(name_lbl)

		var bar_bg: ColorRect = ColorRect.new()
		bar_bg.color = Color(0.15, 0.15, 0.2)
		bar_bg.custom_minimum_size = Vector2(BAR_MAX_WIDTH, BAR_HEIGHT)
		bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar_bg)

		var bar_fill: ColorRect = ColorRect.new()
		bar_fill.color = Color(0.3, 0.7, 0.4)
		bar_fill.position = Vector2.ZERO
		bar_fill.size = Vector2(0.0, BAR_HEIGHT)
		bar_bg.add_child(bar_fill)

		var val_lbl: Label = Label.new()
		val_lbl.custom_minimum_size = Vector2(30.0, BAR_HEIGHT + 2.0)
		val_lbl.size_flags_horizontal = 0
		val_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(val_lbl)

		_stat_bars[key] = bar_fill
		_stat_value_labels[key] = val_lbl
		_stat_rows[key] = row


## Set visibility on specific stat bar rows. Used by the tutorial to progressively reveal stats.
func set_stat_bar_visibility(stat_keys: Array[String], is_visible: bool) -> void:
	for key: String in stat_keys:
		if _stat_rows.has(key):
			(_stat_rows[key] as Control).visible = is_visible


## Set visibility on the stats title label ("— Stats —").
func set_stats_title_visible(is_visible: bool) -> void:
	if _stats_title_label != null:
		_stats_title_label.visible = is_visible


## Fade in specific stat bar rows with a tween animation.
func fade_in_stat_bars(stat_keys: Array[String], duration: float = 0.4) -> void:
	for key: String in stat_keys:
		if not _stat_rows.has(key):
			continue
		var row: Control = _stat_rows[key] as Control
		row.modulate = Color(1.0, 1.0, 1.0, 0.0)
		row.visible = true
		var tween: Tween = create_tween()
		tween.tween_property(row, "modulate:a", 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Show all stat bars and the title — convenience for restoring after tutorial.
func show_all_stat_bars() -> void:
	if _stats_title_label != null:
		_stats_title_label.visible = true
	for key: String in STAT_KEYS:
		if _stat_rows.has(key):
			var row: Control = _stat_rows[key] as Control
			row.visible = true
			row.modulate = Color(1.0, 1.0, 1.0, 1.0)


## Update the stats panel bars with current values and color coding.
func update_stats(stats: Dictionary, base_stats: Dictionary) -> void:
	for key: String in STAT_KEYS:
		var current: float = stats[key]
		var base: float = base_stats[key]

		if key == "horizontal_speed" or key == "vertical_speed":
			current = float(_speed_to_display(current))
			base = float(_speed_to_display(base))

		var bar_fill: ColorRect = _stat_bars[key]
		var val_label: Label = _stat_value_labels[key]
		var bar_width: float = bar_fill.get_parent().size.x if bar_fill.get_parent().size.x > 0.0 else BAR_MAX_WIDTH

		var fill_fraction: float = clampf(current / STAT_MAX_VALUE, 0.0, 1.0)
		bar_fill.size = Vector2(bar_width * fill_fraction, BAR_HEIGHT)

		if current > base:
			bar_fill.color = Color(0.3, 0.75, 0.4)
		elif current < base:
			bar_fill.color = Color(0.75, 0.35, 0.3)
		else:
			bar_fill.color = Color(0.5, 0.5, 0.5)

		val_label.text = str(roundi(current))


## Cache current stats so hover preview can restore them.
func cache_stats(stats: Dictionary, base_stats: Dictionary) -> void:
	_cached_current_stats = stats.duplicate()
	_cached_base_stats = base_stats.duplicate()


## Show a preview of what stats would look like if an upgrade were picked.
## Highlights the affected bar(s) in preview colors.
func _show_stat_preview(upgrade: Dictionary) -> void:
	if _cached_current_stats.is_empty():
		return

	var preview_stats: Dictionary = _cached_current_stats.duplicate()
	var property: String = upgrade["property"]
	var value: int = upgrade["value"]
	var scale: String = upgrade["scale"]

	# Apply the boost
	if scale == "direct":
		preview_stats[property] = minf(preview_stats[property] + float(value), 100.0)
	elif scale == "speed":
		var internal_boost: float = float(value) * (4.0 / 40.0)
		preview_stats[property] = minf(preview_stats[property] + internal_boost, 5.0)

	# Apply tradeoff penalty
	if upgrade["tradeoff"]:
		var penalty_prop: String = upgrade["penalty_property"]
		var penalty_amount: int = upgrade["penalty_amount"]
		preview_stats[penalty_prop] = preview_stats[penalty_prop] - float(penalty_amount)

	# Update bars with preview coloring
	for key: String in STAT_KEYS:
		var current: float = preview_stats[key]
		var base_val: float = _cached_current_stats[key]

		if key == "horizontal_speed" or key == "vertical_speed":
			current = float(_speed_to_display(current))
			base_val = float(_speed_to_display(base_val))

		var bar_fill: ColorRect = _stat_bars[key]
		var val_label: Label = _stat_value_labels[key]
		var bar_width: float = bar_fill.get_parent().size.x if bar_fill.get_parent().size.x > 0.0 else BAR_MAX_WIDTH

		var fill_fraction: float = clampf(current / STAT_MAX_VALUE, 0.0, 1.0)
		bar_fill.size = Vector2(bar_width * fill_fraction, BAR_HEIGHT)

		if current > base_val:
			bar_fill.color = PREVIEW_BOOST_COLOR
		elif current < base_val:
			bar_fill.color = PREVIEW_PENALTY_COLOR
		else:
			var cached_base: float = _cached_base_stats[key]
			if key == "horizontal_speed" or key == "vertical_speed":
				cached_base = float(_speed_to_display(cached_base))
			if base_val > cached_base:
				bar_fill.color = Color(0.3, 0.75, 0.4)
			elif base_val < cached_base:
				bar_fill.color = Color(0.75, 0.35, 0.3)
			else:
				bar_fill.color = Color(0.5, 0.5, 0.5)

		val_label.text = str(roundi(current))


## Called when the mouse enters an upgrade button — show stat preview.
## Only previews if the item at this index is an accuracy upgrade (not a modifier).
func _on_upgrade_hover(index: int) -> void:
	if index >= _preview_upgrades.size():
		return
	var upgrade: Dictionary = _preview_upgrades[index]
	if upgrade.is_empty():
		return
	_show_stat_preview(upgrade)


## Called when the mouse exits an upgrade button — restore real stats.
func _on_upgrade_unhover() -> void:
	if _cached_current_stats.is_empty():
		return
	update_stats(_cached_current_stats, _cached_base_stats)


## Convert internal speed (1.0-5.0) to a display value (0-100).
func _speed_to_display(speed: float) -> int:
	return roundi((speed - 1.0) / 4.0 * 100.0)


## Apply a StyleBoxFlat to an upgrade button for controllable opacity and corners.
func _apply_upgrade_button_style(button: Button) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, upgrade_button_opacity)
	style.set_corner_radius_all(int(upgrade_button_corner_radius))
	style.set_content_margin_all(8)
	style.border_color = Color(0.4, 0.4, 0.5, upgrade_button_opacity)
	style.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", style)

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = Color(0.2, 0.2, 0.28, minf(upgrade_button_opacity + 0.1, 1.0))
	hover_style.border_color = Color(0.5, 0.5, 0.6, minf(upgrade_button_opacity + 0.1, 1.0))
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style: StyleBoxFlat = style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.1, 0.15, upgrade_button_opacity)
	button.add_theme_stylebox_override("pressed", pressed_style)


## Create a Theme with opaque tooltip styling for readability.
func _create_tooltip_theme() -> Theme:
	var t: Theme = Theme.new()
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8)
	panel_style.border_color = Color(0.4, 0.4, 0.5, 0.6)
	panel_style.set_border_width_all(1)
	t.set_stylebox("panel", "TooltipPanel", panel_style)
	t.set_font_size("font_size", "TooltipLabel", 13)
	t.set_color("font_color", "TooltipLabel", Color(0.9, 0.9, 0.9))
	return t


## Populate the throw perk status section below stat bars.
func setup_modifier_status(modifiers: Array[Dictionary]) -> void:
	clear_modifier_status()
	if modifiers.is_empty():
		return

	_modifier_status_title = Label.new()
	_modifier_status_title.text = "— Throw Perks —"
	_modifier_status_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_status_title.add_theme_font_size_override("font_size", 14)
	_modifier_status_title.modulate = Color(0.8, 0.8, 0.6)
	stats_container.add_child(_modifier_status_title)

	for mod: Dictionary in modifiers:
		var row_container: VBoxContainer = VBoxContainer.new()
		row_container.add_theme_constant_override("separation", 1)
		stats_container.add_child(row_container)

		var name_label: Label = Label.new()
		name_label.text = "%s: Inactive" % mod["name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.modulate = Color(0.5, 0.5, 0.5)
		row_container.add_child(name_label)

		var desc_label: Label = Label.new()
		desc_label.text = mod["description"]
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.modulate = Color(0.6, 0.8, 1.0, 0.0)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(280.0, 0.0)
		row_container.add_child(desc_label)

		_modifier_rows.append({
			"name": mod["name"],
			"active_color": mod.get("active_color", Color(0.3, 1.0, 0.4)),
			"name_label": name_label,
			"desc_label": desc_label,
		})


## Update throw perk active/inactive state each throw.
func update_modifier_status(active_names: Array[String]) -> void:
	for row: Dictionary in _modifier_rows:
		var is_active: bool = row["name"] in active_names
		var name_label: Label = row["name_label"]
		var desc_label: Label = row["desc_label"]
		var color: Color = row["active_color"]
		if is_active:
			name_label.text = "%s: Active" % row["name"]
			name_label.modulate = color
			desc_label.modulate = Color(color.r, color.g, color.b, 0.8)
		else:
			name_label.text = "%s: Inactive" % row["name"]
			name_label.modulate = Color(0.5, 0.5, 0.5)
			desc_label.modulate = Color(color.r, color.g, color.b, 0.0)


## Remove all throw perk status rows.
func clear_modifier_status() -> void:
	for row: Dictionary in _modifier_rows:
		(row["name_label"] as Label).get_parent().queue_free()
	_modifier_rows.clear()
	if _modifier_status_title != null:
		_modifier_status_title.queue_free()
		_modifier_status_title = null


## Show hover tooltip above the crosshair with simplified score readout.
## Positioned directly above the aim point for in-focus feedback during aiming.
## Format: "Target: D7 ×3 = 35" (with modifier), or "Target: D7 = 14" (without).
## Turns gold when hovering a segment that would win the leg in one dart.
## streak_lines: current streak display strings appended after the score readout.
func show_hover_tooltip(result: Dictionary, original_wedge_order: Array[int], screen_pos: Vector2 = Vector2.ZERO, is_checkout: bool = false, streak_lines: Array[String] = [], would_bust: bool = false) -> void:
	if result.is_empty():
		hover_tooltip.visible = false
		return

	var ring_name: String = result["ring_name"]
	var face_value: int = result["face_value"]
	var total_score: int = result["total_score"]
	var multiplier: int = result["multiplier"]
	var is_bull: bool = result.get("is_bull", false)

	if ring_name == "Off Board":
		hover_tooltip.visible = false
		return

	# Build simplified prefix (S/D/T/SB/DB)
	var prefix: String = _get_hover_prefix(ring_name)

	# Build the compact tooltip text
	var text: String
	var base_multiplier: int = _get_base_multiplier(ring_name)
	var bonus_mult: int = multiplier - base_multiplier
	if bonus_mult > 0:
		text = "Target: %s%d ×%d = %d" % [prefix, face_value, multiplier, total_score]
	else:
		text = "Target: %s%d = %d" % [prefix, face_value, total_score]

	# Append bust warning or streak info
	if would_bust:
		text += " | !! BUST"
	else:
		for line: String in streak_lines:
			text += " | " + line

	hover_tooltip.text = text
	hover_tooltip.visible = true

	# Color: red for bust, gold for checkout, white otherwise
	if would_bust:
		hover_tooltip.modulate = Color(1.0, 0.3, 0.25)
	elif is_checkout:
		hover_tooltip.modulate = Color(1.0, 0.85, 0.2)
	else:
		hover_tooltip.modulate = Color(1.0, 1.0, 1.0)

	# Position above the crosshair
	if screen_pos != Vector2.ZERO:
		hover_tooltip.position = Vector2(
			screen_pos.x - hover_tooltip.size.x / 2.0,
			screen_pos.y - hover_tooltip_offset_y - hover_tooltip.size.y
		)


## Get the ring prefix abbreviation for the simplified tooltip.
func _get_hover_prefix(ring_name: String) -> String:
	match ring_name:
		"Inner Single":
			return "iS"
		"Outer Single":
			return "oS"
		"Double":
			return "D"
		"Triple":
			return "T"
		"Single Bull":
			return "SB"
		"Double Bull":
			return "DB"
	return ""


## Get the base multiplier for a ring type (before modifier effects).
func _get_base_multiplier(ring_name: String) -> int:
	match ring_name:
		"Double", "Double Bull":
			return 2
		"Triple":
			return 3
	return 1


## Hide the hover tooltip.
func hide_hover_tooltip() -> void:
	hover_tooltip.visible = false


## Show streak info during a throw (replaces the full target tooltip).
## Only displays active streak lines near the crosshair.
func show_streak_info(streak_lines: Array[String]) -> void:
	var text: String = ""
	for i: int in range(streak_lines.size()):
		if i > 0:
			text += " | "
		text += streak_lines[i]
	hover_tooltip.text = text
	hover_tooltip.visible = true


## Hide the target tooltip (when throw completes or new run starts).
func hide_target_tooltip() -> void:
	hover_tooltip.visible = false


## Highlight modifier squares whose modifiers triggered on the hovered segment.
## triggered_names: modifier_name strings that appeared in the modifications array.
## Uses absolute rest/perked positions to avoid drift from overlapping tweens.
func set_modifier_perkup(triggered_names: Array[String]) -> void:
	for child: Node in modifier_panel.get_children():
		if not child.has_meta("modifier") or not child.has_meta("rest_y"):
			continue
		var modifier: Resource = child.get_meta("modifier")
		var rest_y: float = child.get_meta("rest_y")
		var should_perkup: bool = modifier.modifier_name in triggered_names
		var is_perked: bool = child.get_meta("perked_up")

		if should_perkup and not is_perked:
			child.set_meta("perked_up", true)
			var tween: Tween = create_tween()
			tween.tween_property(child, "position:y", rest_y - perkup_lift_pixels, perkup_anim_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			child.modulate = Color(1.3, 1.3, 1.3, 1.0)
		elif not should_perkup and is_perked:
			child.set_meta("perked_up", false)
			var tween: Tween = create_tween()
			tween.tween_property(child, "position:y", rest_y, perkup_anim_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			_update_modifier_square_visual(child as Control)


## Clear all perk-up states on modifier squares.
func clear_modifier_perkup() -> void:
	for child: Node in modifier_panel.get_children():
		if not child.has_meta("perked_up") or not child.get_meta("perked_up"):
			continue
		child.set_meta("perked_up", false)
		if child.has_meta("rest_y"):
			var rest_y: float = child.get_meta("rest_y")
			var tween: Tween = create_tween()
			tween.tween_property(child, "position:y", rest_y, perkup_anim_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_update_modifier_square_visual(child as Control)


## Build the streak section container between TurnScoreLabel and DartIndicator.
func _build_streak_section() -> void:
	_streak_section = VBoxContainer.new()
	_streak_section.add_theme_constant_override("separation", 2)
	_streak_section.visible = false
	_streak_section.theme = _create_tooltip_theme()
	add_child(_streak_section)

	# Position between TurnScoreLabel and DartIndicator
	_streak_section.position = Vector2(20.0, 200.0)
	_streak_section.size = Vector2(260.0, 0.0)

	_streak_title_label = Label.new()
	_streak_title_label.text = streak_section_title_text
	_streak_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak_title_label.add_theme_font_size_override("font_size", 14)
	_streak_title_label.modulate = Color(0.8, 0.8, 0.6)
	_streak_section.add_child(_streak_title_label)


## Update the streak section with current streak modifier states.
func update_streak_section(streak_modifiers: Array, effective_wedge_values: Array[int]) -> void:
	# Clear existing streak lines (keep title)
	for i: int in range(_streak_section.get_child_count() - 1, 0, -1):
		_streak_section.get_child(i).queue_free()

	if streak_modifiers.is_empty():
		_streak_section.visible = false
		return

	_streak_section.visible = true

	const SCOPE_NAMES: Dictionary = {
		ScoringEnums.StreakScope.WITHIN_TURN: "per turn",
		ScoringEnums.StreakScope.WITHIN_LEG: "per leg",
		ScoringEnums.StreakScope.WITHIN_RUN: "per run",
	}

	for mod: Resource in streak_modifiers:
		if not mod is ScoringModifier:
			continue
		var streak_mod: ScoringModifier = mod as ScoringModifier

		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		line.tooltip_text = "%s\n%s" % [streak_mod.modifier_name, streak_mod.description]

		# Small icon
		var icon: ModifierIcon = ModifierIcon.new()
		icon.modifier = streak_mod
		icon.custom_minimum_size = Vector2(streak_icon_size, streak_icon_size)
		icon.size = Vector2(streak_icon_size, streak_icon_size)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)

		# Name label — for wedge streak, prepend the streaked wedge value
		var name_label: Label = Label.new()
		if streak_mod is StreakBonusModifier:
			var wedge_mod: StreakBonusModifier = streak_mod as StreakBonusModifier
			if wedge_mod._streak_wedge_index >= 0 and wedge_mod._streak_wedge_index < effective_wedge_values.size():
				name_label.text = "%d %s" % [effective_wedge_values[wedge_mod._streak_wedge_index], streak_mod.modifier_name]
			else:
				name_label.text = "— %s" % streak_mod.modifier_name
		else:
			name_label.text = streak_mod.modifier_name
		name_label.add_theme_font_size_override("font_size", 13)
		line.add_child(name_label)

		# Scope label — colored by rarity
		var scope_label: Label = Label.new()
		var scope_name: String = SCOPE_NAMES.get(streak_mod.streak_scope, "")
		scope_label.text = "(%s)" % scope_name
		scope_label.add_theme_font_size_override("font_size", 13)
		scope_label.modulate = streak_mod.rarity_color
		line.add_child(scope_label)

		# Count label
		var count_label: Label = Label.new()
		count_label.text = ": x%d" % streak_mod.get_streak_count()
		count_label.add_theme_font_size_override("font_size", 13)
		line.add_child(count_label)

		# Set opacity based on state
		if streak_mod.get_streak_count() == 0:
			line.modulate = Color(1.0, 1.0, 1.0, streak_idle_opacity)
		else:
			line.modulate = Color(1.0, 1.0, 1.0, 1.0)

		_streak_section.add_child(line)


## Clear the streak section entirely.
func clear_streak_section() -> void:
	for i: int in range(_streak_section.get_child_count() - 1, 0, -1):
		_streak_section.get_child(i).queue_free()
	_streak_section.visible = false


## Add a modifier to the relic panel. Streak modifiers are shown only in the
## streak section, not here. BOARD_MUTATION modifiers have no panel presence.
func add_modifier_to_panel(modifier: Resource) -> void:
	if modifier is ScoringModifier:
		if modifier.kind != ScoringEnums.ModifierKind.RELIC:
			return
		if modifier.streak_category != ScoringEnums.StreakCategory.NONE:
			return
	var wrapper: Control = Control.new()
	wrapper.custom_minimum_size = Vector2(modifier_square_size, modifier_square_size)
	wrapper.set_meta("modifier", modifier)
	wrapper.set_meta("perked_up", false)
	wrapper.mouse_entered.connect(_on_modifier_hover.bind(wrapper))
	wrapper.mouse_exited.connect(_on_modifier_unhover)
	wrapper.gui_input.connect(_on_modifier_clicked.bind(wrapper))
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP

	var icon: ModifierIcon = ModifierIcon.new()
	icon.modifier = modifier
	icon.custom_minimum_size = Vector2(modifier_square_size, modifier_square_size)
	icon.size = Vector2(modifier_square_size, modifier_square_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(icon)
	wrapper.set_meta("icon", icon)

	modifier_panel.add_child(wrapper)
	_update_modifier_square_visual(wrapper)
	# HBoxContainer children sit at y=0 in local space — set rest position
	# immediately so the perk-up animation has a baseline to lift from.
	wrapper.set_meta("rest_y", 0.0)


## Remove a modifier square from the panel by matching the modifier reference.
## Called when a streak modifier is replaced by a new one in the same category.
func remove_modifier_from_panel(modifier: Resource) -> void:
	for child: Node in modifier_panel.get_children():
		if child.has_meta("modifier") and child.get_meta("modifier") == modifier:
			child.queue_free()
			break


## Clear all modifier squares from the panel. Called on new run.
func clear_modifier_panel() -> void:
	for child: Node in modifier_panel.get_children():
		child.queue_free()
	modifier_tooltip.visible = false


## Add a legendary reward icon to the legendary panel.
func add_legendary(reward: RuleModifierReward) -> void:
	var wrapper: Control = Control.new()
	wrapper.custom_minimum_size = Vector2(legendary_diamond_size, legendary_diamond_size)
	wrapper.set_meta("reward", reward)
	wrapper.mouse_entered.connect(_on_legendary_hover.bind(wrapper))
	wrapper.mouse_exited.connect(_on_legendary_unhover)
	wrapper.mouse_filter = Control.MOUSE_FILTER_STOP

	var icon: LegendaryIcon = LegendaryIcon.new()
	icon.reward = reward
	icon.tint_color = legendary_tint_color
	icon.custom_minimum_size = Vector2(legendary_diamond_size, legendary_diamond_size)
	icon.size = Vector2(legendary_diamond_size, legendary_diamond_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(icon)

	_legendary_panel.add_child(wrapper)
	_legendary_panel.visible = true


## Clear all legendary icons. Called on new run.
func clear_legendary_panel() -> void:
	for child: Node in _legendary_panel.get_children():
		child.queue_free()
	_legendary_panel.visible = false
	_legendary_tooltip.visible = false


func _on_legendary_hover(wrapper: Control) -> void:
	var reward: RuleModifierReward = wrapper.get_meta("reward") as RuleModifierReward
	if reward:
		_legendary_tooltip.text = "%s — %s" % [reward.display_name, reward.description]
		var icon_rect: Rect2 = wrapper.get_global_rect()
		_legendary_tooltip.position = Vector2(icon_rect.position.x, icon_rect.position.y - 20.0)
		_legendary_tooltip.visible = true


func _on_legendary_unhover() -> void:
	_legendary_tooltip.visible = false


## Called when the mouse enters a modifier square.
func _on_modifier_hover(wrapper: Control) -> void:
	var modifier: Resource = wrapper.get_meta("modifier")
	if modifier:
		var status: String = "ON" if modifier.enabled else "OFF"
		var lock_info: String = "Click to toggle" if modifier.toggleable else "Always on"
		modifier_tooltip.text = "%s [%s]\n%s\n%s" % [modifier.modifier_name, status, modifier.description, lock_info]
		modifier_tooltip.visible = true


## Called when the mouse exits a modifier square.
func _on_modifier_unhover() -> void:
	modifier_tooltip.visible = false


## Toggle modifier on click (only if unlocked/toggleable).
func _on_modifier_clicked(event: InputEvent, wrapper: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var modifier: Resource = wrapper.get_meta("modifier")
		if modifier and modifier.toggleable:
			modifier.enabled = not modifier.enabled
			_update_modifier_square_visual(wrapper)
			_on_modifier_hover(wrapper)
			modifier_toggled.emit()


## Update the visual appearance of a modifier wrapper based on enabled/locked state.
func _update_modifier_square_visual(wrapper: Control) -> void:
	var modifier: Resource = wrapper.get_meta("modifier")
	if not modifier:
		return

	if modifier.enabled:
		wrapper.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		wrapper.modulate = Color(0.3, 0.3, 0.3, 0.6)

	# Trigger icon redraw
	if wrapper.has_meta("icon"):
		(wrapper.get_meta("icon") as ModifierIcon).queue_redraw()

	# Add or update lock/unlock indicator
	var lock_label: Label
	if wrapper.has_meta("lock_label"):
		lock_label = wrapper.get_meta("lock_label")
	else:
		lock_label = Label.new()
		lock_label.add_theme_font_size_override("font_size", 10)
		lock_label.position = Vector2(2.0, 0.0)
		lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(lock_label)
		wrapper.set_meta("lock_label", lock_label)
	lock_label.text = "O" if modifier.toggleable else "X"


## Handle upgrade button selection — hide cards, let main.gd decide what shows next.
func _select_upgrade(index: int) -> void:
	AuidoManager.play_ui_click()
	_skip_modifier_button.visible = false
	upgrade_container.visible = false
	if _streak_replace_mode:
		_streak_replace_mode = false
		streak_replace_selected.emit(index)
	elif _reward_mode:
		_reward_mode = false
		reward_selected.emit(index)
	elif _modifier_mode:
		_modifier_mode = false
		modifier_selected.emit(index)
	else:
		upgrade_selected.emit(index)


## Show 3 modifier cards for the player to pick from.
func show_modifier_choices(modifiers: Array) -> void:
	var empty_info: Array[String] = []
	for _i: int in range(modifiers.size()):
		empty_info.append("")
	show_modifier_choices_with_replacement(modifiers, empty_info)


## Show 3 modifier cards with optional replacement warnings.
## replacement_info is an Array[String] of length 3. Empty string = no warning.
## Non-empty string = warning text shown on the card (e.g., "Replaces: Wedge Streak").
func show_modifier_choices_with_replacement(modifiers: Array, replacement_info: Array[String]) -> void:
	_modifier_mode = true
	_preview_upgrades.clear()
	score_label.text = "Choose a scoring modifier!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		if buttons[i].mouse_entered.is_connected(_on_upgrade_hover):
			buttons[i].mouse_entered.disconnect(_on_upgrade_hover)
		if buttons[i].mouse_exited.is_connected(_on_upgrade_unhover):
			buttons[i].mouse_exited.disconnect(_on_upgrade_unhover)
		if i < modifiers.size():
			var modifier: Resource = modifiers[i]
			var button_text: String = "%s\n%s\n%s" % [modifier.rarity, modifier.modifier_name, modifier.description]
			if modifier.timing == ScoringEnums.ModifierTiming.PER_DART and modifier.streak_category == ScoringEnums.StreakCategory.NONE:
				var lock_tag: String = "[OPEN] Toggleable" if modifier.toggleable else "[ALWAYS ON]"
				button_text += "\n%s" % lock_tag
			if i < replacement_info.size() and replacement_info[i] != "":
				button_text += "\n!! %s" % replacement_info[i]
			buttons[i].text = button_text
			var color: Color = modifier.rarity_color
			buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
			buttons[i].tooltip_text = modifier.description
			buttons[i].visible = true
		else:
			buttons[i].visible = false
	_skip_modifier_button.visible = true
	upgrade_container.visible = true
	next_leg_button.visible = false


## Show boss reward choices (up to 3 cards).
func show_reward_choices(rewards: Array[RuleModifierReward]) -> void:
	_reward_mode = true
	_modifier_mode = false
	_skip_modifier_button.visible = false
	_preview_upgrades.clear()
	score_label.text = "Choose a boss reward!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		if buttons[i].mouse_entered.is_connected(_on_upgrade_hover):
			buttons[i].mouse_entered.disconnect(_on_upgrade_hover)
		if buttons[i].mouse_exited.is_connected(_on_upgrade_unhover):
			buttons[i].mouse_exited.disconnect(_on_upgrade_unhover)
		if i < rewards.size():
			var reward: RuleModifierReward = rewards[i]
			var button_text: String = "%s\n%s" % [reward.display_name, reward.description]
			if reward.is_trade:
				button_text += "\n[TRADE]"
			buttons[i].text = button_text
			var card_color: Color = Color(0.9, 0.7, 0.2) if not reward.is_trade else Color(0.9, 0.3, 0.2)
			buttons[i].self_modulate = Color(card_color.r, card_color.g, card_color.b, 1.0)
			buttons[i].tooltip_text = reward.description
			buttons[i].visible = true
		else:
			buttons[i].visible = false
	upgrade_container.visible = true
	next_leg_button.visible = false


## Show the wedge picker header text (uses the score label).
func show_picker_header(text: String) -> void:
	score_label.text = text


## Show a picker confirmation prompt (uses the instruction label).
func show_picker_prompt(text: String) -> void:
	instruction_label.text = text


## Hide picker UI elements (clear the labels used for picker text).
func hide_picker() -> void:
	score_label.text = ""
	instruction_label.text = ""


# --- Shop UI ---

## Enter shop mode — hide leg-specific HUD elements, show shop dart indicator.
func enter_shop_mode(saved_darts: int) -> void:
	remaining_label.visible = false
	turn_label.visible = false
	turn_score_label.visible = false
	leg_label.visible = false
	bust_label.visible = false
	_shop_total_darts = saved_darts
	dart_label.text = "Thrown: 0 / %d" % saved_darts
	dart_label.remove_theme_font_size_override("font_size")
	dart_label.modulate = Color(1.0, 1.0, 1.0)
	dart_indicator.set_shop_darts(saved_darts, saved_darts)


## Exit shop mode — restore leg-specific HUD elements and normal dart display.
func exit_shop_mode() -> void:
	remaining_label.visible = true
	turn_label.visible = true
	turn_score_label.visible = true
	leg_label.visible = true
	remaining_label.modulate = Color(1.0, 1.0, 1.0)
	dart_indicator.restore_normal_darts()
	reset_next_leg_button()


## Show the shop entry screen after completing a shop leg.
func show_shop_entry(leg: int, target: int, turns_used: int, saved_darts: int) -> void:
	score_label.text = "Leg %d Complete! Cleared %d in %d turns" % [leg, target, turns_used]
	upgrade_container.visible = false
	next_leg_button.text = "Enter Shop (%d dart%s saved)" % [saved_darts, "" if saved_darts == 1 else "s"]
	next_leg_button.visible = true


## Show the shop header with remaining dart count and update indicator.
func show_shop_header(darts_remaining: int) -> void:
	upgrade_container.visible = false
	next_leg_button.visible = false
	var thrown: int = _shop_total_darts - darts_remaining
	dart_label.text = "Thrown: %d / %d" % [thrown, _shop_total_darts]
	dart_indicator.set_darts_remaining(darts_remaining)
	if darts_remaining > 0:
		score_label.text = "SHOP — Throw at the lit spots!"
	else:
		score_label.text = "SHOP — No darts left!"


## Show the zero-dart shop acknowledgment.
func show_shop_zero_darts() -> void:
	upgrade_container.visible = false
	next_leg_button.visible = false
	score_label.text = "Oh dear... you didn't save any darts. Oh well!"


## Show the shop's 2-of-2 mixed item pick (modifiers and/or accuracy upgrades).
## items is an Array[Dictionary] with {type: "modifier"|"upgrade", data: ...}.
func show_shop_pick_items(items: Array[Dictionary], darts_remaining: int, replacement_info: Array[String] = []) -> void:
	_modifier_mode = true
	_skip_modifier_button.visible = true
	score_label.text = "You hit a spot! Pick one (%d dart%s left)" % [darts_remaining, "" if darts_remaining == 1 else "s"]

	# Build preview data — upgrade dicts for accuracy items, empty for modifiers
	_preview_upgrades = []
	for item: Dictionary in items:
		if item["type"] == "upgrade":
			_preview_upgrades.append(item["data"])
		else:
			_preview_upgrades.append({})

	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(mini(items.size(), 2)):
		var item: Dictionary = items[i]
		var button_text: String
		var button_color: Color

		if item["type"] == "modifier":
			var modifier: Resource = item["data"]
			button_text = "%s\n%s\n%s" % [modifier.rarity, modifier.modifier_name, modifier.description]
			if modifier.timing == ScoringEnums.ModifierTiming.PER_DART and modifier.streak_category == ScoringEnums.StreakCategory.NONE:
				var lock_tag: String = "[OPEN] Toggleable" if modifier.toggleable else "[ALWAYS ON]"
				button_text += "\n%s" % lock_tag
			button_color = modifier.rarity_color
			buttons[i].tooltip_text = modifier.description
		else:
			var upgrade: Dictionary = item["data"]
			button_text = "%s\n%s\n+%d" % [upgrade["rarity"], upgrade["name"], upgrade["value"]]
			if upgrade["tradeoff"]:
				button_text += "\n-%d %s" % [upgrade["penalty_amount"], upgrade["penalty_name"]]
			button_color = upgrade["color"]
			buttons[i].tooltip_text = upgrade["description"]

		if i < replacement_info.size() and replacement_info[i] != "":
			button_text += "\n!! %s" % replacement_info[i]

		buttons[i].text = button_text
		buttons[i].self_modulate = Color(button_color.r, button_color.g, button_color.b, 1.0)
		buttons[i].visible = true

		# Connect hover preview signals
		if buttons[i].mouse_entered.is_connected(_on_upgrade_hover):
			buttons[i].mouse_entered.disconnect(_on_upgrade_hover)
		if buttons[i].mouse_exited.is_connected(_on_upgrade_unhover):
			buttons[i].mouse_exited.disconnect(_on_upgrade_unhover)
		buttons[i].mouse_entered.connect(_on_upgrade_hover.bind(i))
		buttons[i].mouse_exited.connect(_on_upgrade_unhover)

	# Hide the third button for 2-of-2 pick
	buttons[2].visible = false
	upgrade_container.visible = true
	next_leg_button.visible = false


## Show a chooser for which existing streak to replace when multiple same-category conflicts exist.
func show_streak_replace_chooser(new_modifier: ScoringModifier, conflicts: Array) -> void:
	_streak_replace_mode = true
	score_label.text = "Replace which streak with %s?" % new_modifier.modifier_name
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		if i < conflicts.size():
			var existing: ScoringModifier = conflicts[i] as ScoringModifier
			buttons[i].text = "%s\n%s" % [existing.modifier_name, existing.description]
			buttons[i].self_modulate = Color(existing.rarity_color.r, existing.rarity_color.g, existing.rarity_color.b, 1.0)
			buttons[i].tooltip_text = existing.description
			buttons[i].visible = true
		else:
			buttons[i].visible = false
	upgrade_container.visible = true
	_skip_modifier_button.visible = false
	next_leg_button.visible = false


## Show the shop hover tooltip above the crosshair with rarity info.
func show_shop_hover_tooltip(rarity_text: String, screen_pos: Vector2) -> void:
	hover_tooltip.text = "Target: %s" % rarity_text
	hover_tooltip.visible = true
	if rarity_text == "Nothing":
		hover_tooltip.modulate = Color(0.6, 0.6, 0.6)
	elif "Rare" in rarity_text:
		hover_tooltip.modulate = Color(0.7, 0.3, 0.9)
	elif "Uncommon" in rarity_text:
		hover_tooltip.modulate = Color(0.3, 0.5, 1.0)
	else:
		hover_tooltip.modulate = Color(1.0, 1.0, 1.0)
	hover_tooltip.position = Vector2(
		screen_pos.x - hover_tooltip.size.x / 2.0,
		screen_pos.y - hover_tooltip_offset_y - hover_tooltip.size.y
	)


## Show the shop complete message with a button to advance.
func show_shop_complete() -> void:
	upgrade_container.visible = false
	score_label.text = "Shop complete!"
	next_leg_button.text = "Next Leg"
	next_leg_button.visible = true


## Reset the next leg button text to default.
func reset_next_leg_button() -> void:
	next_leg_button.text = "Next Leg"


# --- Checkout Helper ---

## Build the checkout helper panel as a child of the stats container.
func _build_checkout_panel() -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, checkout_top_margin)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_container.add_child(spacer)

	var container: VBoxContainer = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 4)
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_container.add_child(container)

	_checkout_toggle_button = Button.new()
	_checkout_toggle_button.text = "Show Checkout"
	_checkout_toggle_button.add_theme_font_size_override("font_size", 12)
	_checkout_toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_checkout_toggle_button.pressed.connect(_on_checkout_toggle)
	container.add_child(_checkout_toggle_button)
	_checkout_toggle_button.visible = false

	_checkout_panel = VBoxContainer.new()
	_checkout_panel.add_theme_constant_override("separation", 2)
	_checkout_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_checkout_panel.visible = false
	container.add_child(_checkout_panel)

	_checkout_hint_label = Label.new()
	_checkout_hint_label.add_theme_font_size_override("font_size", 11)
	_checkout_hint_label.modulate = Color(0.6, 0.6, 0.7)
	_checkout_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkout_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_checkout_hint_label.visible = false
	container.add_child(_checkout_hint_label)


## Toggle checkout helper visibility.
func _on_checkout_toggle() -> void:
	_checkout_visible = not _checkout_visible
	_checkout_panel.visible = _checkout_visible
	_checkout_toggle_button.text = "Hide Checkout" if _checkout_visible else "Show Checkout"


## Update the checkout helper display with solved paths.
## paths: Array of Arrays of {target, result} dicts from the solver.
## has_toggleable_modifiers: whether the hint should show.
func update_checkout_display(paths: Array[Array], has_toggleable_modifiers: bool, divergent_wedges: Dictionary = {}, selected_index: int = -1) -> void:
	_checkout_has_paths = paths.size() > 0
	_divergent_wedges = divergent_wedges
	_checkout_paths_ref = paths

	# Clear old path labels
	for label: Label in _checkout_path_labels:
		label.queue_free()
	_checkout_path_labels.clear()

	if _checkout_has_paths:
		_checkout_toggle_button.visible = true
		_checkout_toggle_button.disabled = false
		_checkout_toggle_button.text = "Hide Checkout" if _checkout_visible else "Show Checkout"
		_checkout_panel.visible = _checkout_visible

		# Title
		var title: Label = Label.new()
		title.text = "— Checkout Paths —"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", checkout_font_size)
		title.modulate = Color(0.8, 0.8, 0.6)
		_checkout_panel.add_child(title)
		_checkout_path_labels.append(title)

		for i: int in range(paths.size()):
			var path: Array = paths[i]
			var line: Label = Label.new()
			line.text = _format_checkout_path(path)
			line.add_theme_font_size_override("font_size", checkout_font_size)
			if i == selected_index:
				var sel_color: Color = illumination_finish_text_color if path.size() == 1 else illumination_text_color
				line.add_theme_color_override("font_color", sel_color)
			else:
				line.add_theme_color_override("font_color", checkout_text_color)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size = Vector2(280.0, 0.0)
			line.mouse_filter = Control.MOUSE_FILTER_STOP
			line.gui_input.connect(_on_checkout_path_gui_input.bind(i))
			_checkout_panel.add_child(line)
			_checkout_path_labels.append(line)

		if paths.size() > 1:
			var nav_hint: Label = Label.new()
			nav_hint.text = "Scroll or ↑↓ to browse paths"
			nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nav_hint.add_theme_font_size_override("font_size", checkout_font_size - 2)
			nav_hint.modulate = Color(0.6, 0.6, 0.6, 0.7)
			_checkout_panel.add_child(nav_hint)
			_checkout_path_labels.append(nav_hint)
	else:
		_checkout_toggle_button.visible = true
		_checkout_toggle_button.disabled = true
		_checkout_toggle_button.text = "No Checkout"
		_checkout_panel.visible = false

	# Hint
	if has_toggleable_modifiers:
		_checkout_hint_label.text = checkout_toggle_hint
		_checkout_hint_label.visible = _checkout_visible or not _checkout_has_paths
	else:
		_checkout_hint_label.visible = false


## Update the display with a setup recommendation (no checkout available).
func update_setup_display(recommendation: Dictionary, has_toggleable_modifiers: bool, divergent_wedges: Dictionary = {}) -> void:
	_divergent_wedges = divergent_wedges
	# Clear old path labels
	for label: Label in _checkout_path_labels:
		label.queue_free()
	_checkout_path_labels.clear()

	_checkout_toggle_button.visible = true
	_checkout_toggle_button.disabled = true
	_checkout_toggle_button.text = "No Checkout"
	_checkout_has_paths = false
	_checkout_panel.visible = true

	var title: Label = Label.new()
	title.text = "— Setup —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", checkout_font_size)
	title.modulate = Color(0.8, 0.8, 0.6)
	_checkout_panel.add_child(title)
	_checkout_path_labels.append(title)

	var mode: int = recommendation.get("mode", ScoringEnums.SetupMode.OFF_BOARD_PRESERVE)

	var line: Label = Label.new()
	match mode:
		ScoringEnums.SetupMode.ENDGAME_SETUP, ScoringEnums.SetupMode.MID_ZONE_SETUP:
			var target: Dictionary = recommendation.get("target", {})
			var remainder: int = recommendation.get("resulting_remainder", 0)
			line.text = "Aim %s -> leaves you at %d" % [_get_target_display_name(target), remainder]
		ScoringEnums.SetupMode.SCORE_REDUCTION:
			line.text = score_reduction_text
		ScoringEnums.SetupMode.OFF_BOARD_PRESERVE:
			line.text = off_board_preserve_text
	line.add_theme_font_size_override("font_size", checkout_font_size)
	line.add_theme_color_override("font_color", checkout_setup_color)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(280.0, 0.0)
	_checkout_panel.add_child(line)
	_checkout_path_labels.append(line)

	if has_toggleable_modifiers:
		_checkout_hint_label.text = checkout_toggle_hint
		_checkout_hint_label.visible = true
	else:
		_checkout_hint_label.visible = false


## Hide the checkout helper entirely (e.g., during shop or between legs).
func hide_checkout_helper() -> void:
	_checkout_panel.visible = false
	_checkout_toggle_button.visible = false
	_checkout_hint_label.visible = false


## Update which path line is visually selected.
func set_selected_path(index: int) -> void:
	# Path labels start at index 1 (index 0 is the title); nav hint may be at end
	for i: int in range(1, _checkout_path_labels.size()):
		var path_index: int = i - 1
		if path_index >= _checkout_paths_ref.size():
			break
		if path_index == index:
			var is_finish: bool = _checkout_paths_ref[path_index].size() == 1
			var sel_color: Color = illumination_finish_text_color if is_finish else illumination_text_color
			_checkout_path_labels[i].add_theme_color_override("font_color", sel_color)
		else:
			_checkout_path_labels[i].add_theme_color_override("font_color", checkout_text_color)


func _on_checkout_path_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		checkout_path_clicked.emit(index)


## Get a display-friendly name for a solver target (e.g., "T20", "D-Bull", "S5").
## Singles show "Inner S18" / "Outer S18" only when the wedge's two singles diverge.
func _get_target_display_name(target: Dictionary) -> String:
	var ring: String = target.get("ring_name", "")
	var face: int = target.get("face_value", 0)
	match ring:
		"Inner Single":
			var wi: int = target.get("wedge_index", -1)
			if wi >= 0 and _divergent_wedges.get(wi, false):
				return "Inner S%d" % face
			return "S%d" % face
		"Outer Single":
			var wi: int = target.get("wedge_index", -1)
			if wi >= 0 and _divergent_wedges.get(wi, false):
				return "Outer S%d" % face
			return "S%d" % face
		"Double":
			return "D%d" % face
		"Triple":
			return "T%d" % face
		"Single Bull":
			return "Bull"
		"Double Bull":
			return "D-Bull"
		"Off Board":
			return "Off"
	return "?"


## Format a single checkout path into a display string.
func _format_checkout_path(path: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for step: Dictionary in path:
		var target: Dictionary = step["target"]
		var result: Dictionary = step["result"]
		var name: String = _get_target_display_name(target)
		var scored: int = result["total_score"]

		var annotation: String = ""
		if target["ring_name"] == "Off Board":
			annotation = "break streak"
		elif result.has("streak_triggered") and result["streak_triggered"]:
			var streak_name: String = result.get("streak_name", "")
			var streak_count: int = result.get("streak_count", 0)
			annotation = "%s ×%d: %d" % [streak_name, streak_count, scored]
		else:
			annotation = str(scored)

		parts.append("%s (%s)" % [name, annotation])

	return " -> ".join(parts)
