extends Node2D
## Main scene controller. Orchestrates the dartboard, throw mechanic, X01 game logic, and HUD.
## Manages game flow: X01 run → legs → turns → darts → score → upgrades → repeat.

## Radius of placed dart markers in pixels.
@export var dart_size: float = 5.0

## When enabled, the player picks a scoring modifier after building their dart,
## before the first throw — same UI as the post-leg modifier pick.
@export var debug_start_with_modifier: bool = false

## Seconds to wait after a dart lands before auto-starting the next throw.
## Only applies within a turn — turn boundaries still require a button press.
@export var next_dart_delay: float = 0.8

@onready var dartboard: Node2D = $Dartboard
@onready var throw_mechanic: Node2D = $ThrowMechanic
@onready var dart_container: Node2D = $DartContainer
@onready var hud: CanvasLayer = $HUD
@onready var x01_game: Node = $X01Game
@onready var scoring_modifier_manager: Node = $ScoringModifierManager
@onready var dart_component_registry: DartComponentRegistry = $DartComponentRegistry
@onready var dart_build: DartBuild = $DartBuild
@onready var assembly_screen: AssemblyScreen = $HUD/AssemblyScreen

# Upgrade type definitions — 4 pure buffs, 2 tradeoffs (consistency stats penalize each other)
const UPGRADE_TYPES: Array[Dictionary] = [
	{
		"name": "Horizontal Range",
		"property": "horizontal_range",
		"scale": "direct",
		"tradeoff": false,
		"description": "Narrows the horizontal aiming band",
	},
	{
		"name": "Vertical Range",
		"property": "vertical_range",
		"scale": "direct",
		"tradeoff": false,
		"description": "Shrinks the vertical positioning window",
	},
	{
		"name": "V Speed Control",
		"property": "vertical_speed",
		"scale": "speed",
		"tradeoff": false,
		"description": "Slows the vertical release marker",
	},
	{
		"name": "H Speed Control",
		"property": "horizontal_speed",
		"scale": "speed",
		"tradeoff": false,
		"description": "Slows the horizontal release marker",
	},
	{
		"name": "Vertical Accuracy",
		"property": "vertical_accuracy",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "horizontal_accuracy",
		"penalty_name": "Horizontal Accuracy",
		"penalty_amount": 3,
		"description": "Tightens vertical variance, but widens horizontal",
	},
	{
		"name": "Horizontal Accuracy",
		"property": "horizontal_accuracy",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "vertical_accuracy",
		"penalty_name": "Vertical Accuracy",
		"penalty_amount": 3,
		"description": "Tightens horizontal variance, but widens vertical",
	},
]

# Rarity tiers for standard (direct 1-100) stats
const STANDARD_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 5, "max_value": 8, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 9, "max_value": 12, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 13, "max_value": 15, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Rarity tiers for speed stats (1.0-5.0 internal scale)
const SPEED_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 2, "max_value": 4, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 5, "max_value": 7, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 8, "max_value": 10, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Rarity tiers for consistency stats (tradeoff upgrades — higher values to offset the penalty)
const CONSISTENCY_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 8, "max_value": 12, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 13, "max_value": 16, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 17, "max_value": 20, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Flow state — tracks what the game is waiting for between throws
var _awaiting_next_dart: bool = false
var _awaiting_next_turn: bool = false
var _awaiting_next_leg: bool = false
var _run_over: bool = false

# Raw stats — the throw_mechanic defaults before any dart build is applied.
# Captured once in _ready(), used to feed the assembly screen and dart build.
var _raw_stats: Dictionary = {}

# Base stats snapshot — saved after build is applied, restored between runs.
# Upgrades during a run are relative to these values.
var _base_horizontal_range: float = 0.0
var _base_vertical_range: float = 0.0
var _base_vertical_accuracy: float = 0.0
var _base_horizontal_accuracy: float = 0.0
var _base_vertical_speed: float = 0.0
var _base_horizontal_speed: float = 0.0
var _base_accuracy_skew_v: float = 0.0

# The 3 generated upgrade choices for the current leg-complete screen
var _current_upgrades: Array[Dictionary] = []

## End-of-leg phase: "", "accuracy_pick", "modifier_pick", "wedge_picker"
var _leg_phase: String = ""

## The 3 generated modifier choices for the modifier pick phase.
var _current_modifiers: Array[ScoringModifier] = []

## The modifier awaiting wedge picker configuration.
var _pending_modifier: ScoringModifier = null

## First selected wedge in PICK_TWO_WEDGES flow (-1 = none).
var _picker_selected_wedge: int = -1

# Cumulative score for the current turn (resets each turn)
var _turn_score: int = 0

# Whether hover feedback is currently active (set based on game state)
var _hover_active: bool = false

# Tracks temporary throw modifier bonuses so they can be reverted after the throw.
var _temp_throw_bonuses: Dictionary = {}

# Names of currently active throw modifiers (for HUD display).
var _active_throw_modifier_names: Array[String] = []

# Stored original gaussian_spread for reverting after throw.
var _original_gaussian_spread: float = 0.0

# Whether a trigger animation is currently playing (suppresses hover tooltip).
var _trigger_anim_active: bool = false

# Whether the current modifier pick is the debug start-of-game pick.
var _start_modifier_pending: bool = false

# --- Shop system state ---

## Saved darts accumulated across the current 3-leg window.
var _saved_darts_accumulator: int = 0

## Whether the game is currently in the shop phase.
var _in_shop: bool = false

## Shop darts remaining to throw.
var _shop_darts_remaining: int = 0

## Lit spots on the board for the current shop.
var _shop_lit_spots: Array[Dictionary] = []

## The 2 item choices generated when a lit spot is hit.
## Each entry: {type: "modifier"|"upgrade", data: ScoringModifier|Dictionary}
var _shop_pick_items: Array[Dictionary] = []

## Extra lit spots beyond the dart count (breathing room for target choice).
@export var shop_spot_slack: int = 3

## Duration of the zero-dart shop acknowledgment in seconds.
@export var shop_zero_dart_duration: float = 2.5

## How often shops occur (every N legs).
@export var shop_cadence: int = 3

## Duration of the board slide transition into/out of shop in seconds.
@export var shop_transition_duration: float = 0.5


func _ready() -> void:
	# Connect throw mechanic signals
	throw_mechanic.throw_completed.connect(_on_throw_completed)
	throw_mechanic.state_changed.connect(_on_throw_state_changed)

	# Connect HUD button signals
	hud.next_turn_pressed.connect(_on_next_turn)
	hud.next_leg_pressed.connect(_on_next_leg)
	hud.new_run_pressed.connect(_on_new_run)
	hud.upgrade_selected.connect(_on_upgrade_selected)
	hud.modifier_selected.connect(_on_modifier_selected)

	# Connect assembly screen
	assembly_screen.dart_build = dart_build
	assembly_screen.registry = dart_component_registry
	assembly_screen.throw_mechanic = throw_mechanic
	assembly_screen.run_confirmed.connect(_on_run_confirmed)

	# Wire dartboard reference to throw_mechanic for target declaration
	throw_mechanic.dartboard = dartboard

	# Center the dartboard on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	dartboard.position = viewport_size / 2.0

	# Capture raw stats (throw_mechanic defaults before any build)
	_raw_stats = {
		"horizontal_range": throw_mechanic.horizontal_range,
		"vertical_range": throw_mechanic.vertical_range,
		"vertical_accuracy": throw_mechanic.vertical_accuracy,
		"horizontal_accuracy": throw_mechanic.horizontal_accuracy,
		"vertical_speed": throw_mechanic.vertical_speed,
		"horizontal_speed": throw_mechanic.horizontal_speed,
	}
	_snapshot_base_stats()

	# Sync dartboard with modifier manager's effective board state
	_sync_board_state()

	# Sync any debug modifiers to the HUD panel
	for modifier: Resource in scoring_modifier_manager.active_modifiers:
		hud.add_modifier_to_panel(modifier)

	# Show assembly screen instead of starting immediately
	_show_assembly()


func _process(_delta: float) -> void:
	# Picker mode hover — update wedge highlight under cursor
	if _leg_phase == "wedge_picker" and dartboard.picker_mode:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var wedge_idx: int = dartboard.update_picker_hover(mouse_pos)
		_update_picker_prompt(wedge_idx)
		return

	if not _hover_active:
		return

	# Feed the current mouse position to the dartboard for hover detection
	var mouse_pos: Vector2 = get_global_mouse_position()
	var hover_result: Dictionary = dartboard.update_hover(mouse_pos)

	# Shop-specific hover: show rarity of lit spots
	if _in_shop and _leg_phase == "shop":
		if hover_result.is_empty():
			hud.show_shop_hover_tooltip("Nothing", mouse_pos)
		else:
			var spot_idx: int = dartboard.check_shop_hit(mouse_pos)
			if spot_idx >= 0:
				var spot: Dictionary = _shop_lit_spots[spot_idx]
				var rarity_name: String = ScoringEnums.RARITY_DATA[spot["rarity"]]["name"]
				hud.show_shop_hover_tooltip("%s Upgrade" % rarity_name, mouse_pos)
			else:
				hud.show_shop_hover_tooltip("Nothing", mouse_pos)
		return

	# Update the hover tooltip on the HUD (suppress during trigger animations)
	if _trigger_anim_active or hover_result.is_empty():
		hud.hide_hover_tooltip()
		hud.clear_modifier_perkup()
	else:
		# Run through the modifier pipeline in preview mode to get the fully
		# modified score without recording to hit history
		var modified_result: Dictionary = scoring_modifier_manager.process_score(hover_result, true)
		var is_checkout: bool = _is_checkout_segment(modified_result)
		var streak_lines: Array[String] = _get_active_streak_info()
		hud.show_hover_tooltip(modified_result, dartboard.WEDGE_ORDER, mouse_pos, is_checkout, streak_lines)

		# Extract which modifiers triggered for perk-up display
		var triggered_names: Array[String] = []
		var modifications: Array = modified_result.get("modifications", [])
		for mod: Dictionary in modifications:
			var source: String = mod.get("source_name", "")
			if source != "" and source not in triggered_names:
				triggered_names.append(source)
		hud.set_modifier_perkup(triggered_names)


## Enable hover feedback on the board and tooltip display.
func _enable_hover() -> void:
	_hover_active = true
	dartboard.hover_enabled = true


## Disable hover feedback and clear any active highlight/tooltip.
func _disable_hover() -> void:
	_hover_active = false
	dartboard.hover_enabled = false
	dartboard.clear_hover()
	hud.hide_hover_tooltip()
	hud.clear_modifier_perkup()


## Add a scoring modifier to the game. Handles replacement, manager, and HUD panel.
func add_scoring_modifier(modifier: Resource, config: Dictionary) -> void:
	var replaced: Resource = scoring_modifier_manager.add_modifier(modifier, config)

	# If a modifier was replaced, remove its panel square
	if replaced != null:
		hud.remove_modifier_from_panel(replaced)

	hud.add_modifier_to_panel(modifier)
	_sync_board_state()
	_update_checkout_highlights()


## Start a new throw (single dart).
func _start_new_throw() -> void:
	_disable_hover()
	hud.hide_score()

	# Build context for throw modifier evaluation
	var context: Dictionary = {
		"remaining_score": x01_game.remaining_score,
		"target_score": x01_game.target_score,
		"darts_this_turn": x01_game.darts_this_turn,
		"current_turn": x01_game.current_turn,
		"current_leg": x01_game.current_leg,
		"max_turns": x01_game.max_turns,
	}

	# Evaluate and apply temporary throw modifier bonuses
	var result: Dictionary = dart_build.evaluate_throw_modifiers(context)
	_temp_throw_bonuses = result["bonuses"]
	_active_throw_modifier_names = result["activated"]
	_apply_temp_bonuses()
	_update_stats_display()
	hud.update_modifier_status(_active_throw_modifier_names)

	# Update dart counter to show which dart we're on
	var darts_remaining: int = 3 - x01_game.darts_this_turn
	var is_last_turn: bool = x01_game.current_turn == x01_game.max_turns
	hud.update_darts(darts_remaining, is_last_turn)
	hud.show_instruction("Move to aim, click to place zone")
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)


## Called when a dart lands — process through X01 logic and update state.
func _on_throw_completed(hit_position: Vector2) -> void:
	# Shop throws bypass the normal scoring pipeline
	if _in_shop:
		_on_shop_throw_completed(hit_position)
		return

	# Clear target highlight and tooltip
	dartboard.clear_declared_target()
	hud.hide_target_tooltip()

	# Revert any temporary throw modifier bonuses
	_revert_temp_bonuses()
	_update_stats_display()
	var no_modifiers: Array[String] = []
	hud.update_modifier_status(no_modifiers)

	# Score the throw (raw, before modifiers)
	var result: Dictionary = dartboard.calculate_score(hit_position)

	# Run through scoring modifier pipeline (color bonuses, streak effects, etc.)
	result = scoring_modifier_manager.process_score(result)

	# Place a dart marker at the hit position
	_place_dart(hit_position)
	AuidoManager.play_dart_thunk()

	# Floating score number
	var score_tween: Tween = _spawn_floating_score(hit_position, result)

	# Flash the hit segment for visual feedback
	dartboard.flash_segment(hit_position)

	# Show per-dart score feedback
	hud.show_score(result)

	# Process through X01 game logic (uses modified score)
	var response: Dictionary = x01_game.process_throw(result)

	# Accumulate turn score
	_turn_score += result["total_score"]
	hud.update_turn_score(_turn_score)

	# Update remaining score display
	hud.update_remaining(response["remaining_score"])

	# Branch on what happened
	if response["is_bust"]:
		hud.show_bust(response["bust_reason"])
		if response["is_game_over"]:
			# Run is over
			_run_over = true
			hud.show_game_over(response["current_leg"], response["target_score"])
		else:
			# Turn lost to bust, but run continues
			hud.next_turn_button.visible = true
			_awaiting_next_turn = true
	elif response["is_leg_won"]:
		# Leg complete — wait for score animation, then show upgrades
		_awaiting_next_leg = true
		if score_tween != null and score_tween.is_valid():
			score_tween.tween_callback(_show_leg_upgrades.bind(response))
		else:
			_show_leg_upgrades(response)
	elif response["is_turn_over"]:
		# Used all 3 darts without bust or win
		if response["is_game_over"]:
			_run_over = true
			hud.show_game_over(response["current_leg"], response["target_score"])
		else:
			hud.next_turn_button.visible = true
			_awaiting_next_turn = true
	else:
		# Darts remaining this turn — auto-advance after score animation + delay
		_awaiting_next_dart = true
		if score_tween != null and score_tween.is_valid():
			score_tween.tween_callback(_start_next_dart_timer)
		else:
			_start_next_dart_timer()

	# Update dart counter
	hud.update_darts(response["darts_remaining"], x01_game.current_turn == x01_game.max_turns)

	# Re-enable hover so the player can inspect the board while deciding
	_enable_hover()

	_update_checkout_highlights()


## Show the leg-complete upgrade UI or shop entry. Called after the score animation finishes.
func _show_leg_upgrades(response: Dictionary) -> void:
	# Accumulate saved darts for the shop window
	_saved_darts_accumulator += x01_game.get_saved_darts()

	# Check if this is a shop leg (every Nth leg)
	if response["current_leg"] % shop_cadence == 0:
		_leg_phase = "shop_enter"
		var saved: int = _saved_darts_accumulator
		hud.show_shop_entry(response["current_leg"], response["target_score"], response["current_turn"], saved)
		return

	_leg_phase = "accuracy_pick"
	_current_upgrades = _generate_upgrades()
	hud.show_leg_complete_with_upgrades(
		response["current_leg"],
		response["target_score"],
		response["current_turn"],
		_current_upgrades
	)


## Start the next-dart delay timer. Called after the score tween finishes.
func _start_next_dart_timer() -> void:
	if not _awaiting_next_dart:
		return
	get_tree().create_timer(next_dart_delay).timeout.connect(_auto_next_dart)


## Auto-advance to the next dart after the delay timer fires.
## Guards against stale timers — if the game state moved on, do nothing.
func _auto_next_dart() -> void:
	if not _awaiting_next_dart:
		return
	_awaiting_next_dart = false
	_start_new_throw()


## Player presses "Next Turn" — advance to next turn after bust or using all darts.
func _on_next_turn() -> void:
	_awaiting_next_turn = false
	_turn_score = 0
	hud.update_turn_score(0)
	scoring_modifier_manager.reset_for_turn()
	_clear_darts()
	x01_game.end_turn()
	x01_game.start_turn()
	hud.update_turn(x01_game.current_turn, x01_game.max_turns)
	_start_new_throw()
	_update_checkout_highlights()


## Player presses "Next Leg" — advance to next leg, enter shop, or leave shop.
func _on_next_leg() -> void:
	if _leg_phase == "shop_enter":
		var response: Dictionary = {
			"current_leg": x01_game.current_leg,
			"target_score": x01_game.target_score,
		}
		_start_shop(response)
		return

	if _leg_phase == "shop_complete":
		var response: Dictionary = {
			"current_leg": x01_game.current_leg,
			"target_score": x01_game.target_score,
		}
		_end_shop(response)
		return

	_awaiting_next_leg = false
	_turn_score = 0
	_leg_phase = ""
	hud.update_turn_score(0)
	scoring_modifier_manager.reset_for_leg()
	_clear_darts()
	x01_game.advance_leg()
	_update_all_hud()
	_start_new_throw()
	_update_checkout_highlights()


## Player presses "New Run" — start fresh after game over.
func _on_new_run() -> void:
	_run_over = false
	_turn_score = 0
	_leg_phase = ""
	_in_shop = false
	_saved_darts_accumulator = 0
	_start_modifier_pending = false
	hud.update_turn_score(0)
	hud.hide_picker()
	hud.hide_target_tooltip()
	dartboard.clear_declared_target()
	dartboard.clear_shop_spots()
	scoring_modifier_manager.reset_for_run()
	hud.clear_modifier_panel()
	hud.clear_modifier_status()
	_sync_board_state()
	_clear_darts()
	if dartboard.picker_mode:
		dartboard.set_picker_mode(false)
	# Restore to raw stats (before any build) so the assembly screen starts fresh
	_restore_raw_stats()
	_show_assembly()


# --- Shop System ---

## Start the shop phase. Called instead of normal upgrade picks on shop legs.
func _start_shop(response: Dictionary) -> void:
	_in_shop = true
	_shop_darts_remaining = _saved_darts_accumulator
	_leg_phase = "shop"
	_clear_darts()
	dartboard.clear_checkout_segments()
	hud.enter_shop_mode(_shop_darts_remaining)

	# Slide board off to the left, then back from the right with shop spots
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var off_left: Vector2 = Vector2(-dartboard.board_radius * 2.0, center.y)
	var off_right: Vector2 = Vector2(viewport_size.x + dartboard.board_radius * 2.0, center.y)

	var tween: Tween = create_tween()
	tween.tween_property(dartboard, "position", off_left, shop_transition_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_setup_shop_board.bind(response, off_right, center))


## Set up the shop board and slide it in from the right.
func _setup_shop_board(response: Dictionary, from_pos: Vector2, to_pos: Vector2) -> void:
	dartboard.position = from_pos

	if _shop_darts_remaining <= 0:
		# Zero-dart shop — slide in empty board with message
		var tween: Tween = create_tween()
		tween.tween_property(dartboard, "position", to_pos, shop_transition_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(func() -> void:
			hud.show_shop_zero_darts()
			get_tree().create_timer(shop_zero_dart_duration).timeout.connect(_end_shop.bind(response))
		)
		return

	# Generate and place lit spots
	_shop_lit_spots = _generate_shop_spots(_shop_darts_remaining)
	dartboard.set_shop_spots(_shop_lit_spots)

	var tween: Tween = create_tween()
	tween.tween_property(dartboard, "position", to_pos, shop_transition_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		hud.show_shop_header(_shop_darts_remaining)
		_start_new_throw()
	)


## Generate lit spot layout for the shop.
func _generate_shop_spots(shop_darts: int) -> Array[Dictionary]:
	var lit_count: int = shop_darts + shop_spot_slack
	var rares: int = maxi(1, lit_count / 6)
	var uncommons: int = lit_count / 3
	var commons: int = lit_count - rares - uncommons

	var spots: Array[Dictionary] = []
	var used_segments: Array[String] = []

	# Rares and uncommons go on doubles/triples
	for _i: int in range(rares):
		spots.append(_random_shop_spot(ScoringEnums.Rarity.RARE, true, used_segments))
	for _i: int in range(uncommons):
		spots.append(_random_shop_spot(ScoringEnums.Rarity.UNCOMMON, true, used_segments))
	# Commons go on singles
	for _i: int in range(commons):
		spots.append(_random_shop_spot(ScoringEnums.Rarity.COMMON, false, used_segments))

	return spots


## Generate a single random shop spot, avoiding duplicates.
func _random_shop_spot(rarity: ScoringEnums.Rarity, multi_ring: bool, used: Array[String]) -> Dictionary:
	var ring_options: Array[String]
	if multi_ring:
		ring_options = ["Double", "Triple"]
	else:
		ring_options = ["Inner Single", "Outer Single"]

	# Try to place on a unique segment
	for _attempt: int in range(40):
		var wedge_idx: int = randi_range(0, 19)
		var ring: String = ring_options[randi_range(0, ring_options.size() - 1)]
		var key: String = "%d_%s" % [wedge_idx, ring]
		if key not in used:
			used.append(key)
			return {"wedge_index": wedge_idx, "ring_name": ring, "rarity": rarity, "active": true}

	# Fallback — place anyway (board may be crowded)
	var wedge_idx: int = randi_range(0, 19)
	var ring: String = ring_options[0]
	return {"wedge_index": wedge_idx, "ring_name": ring, "rarity": rarity, "active": true}


## Handle a throw during the shop phase.
func _on_shop_throw_completed(hit_position: Vector2) -> void:
	dartboard.clear_declared_target()
	hud.hide_target_tooltip()

	# Revert temp bonuses from throw modifiers
	_revert_temp_bonuses()
	_update_stats_display()
	var no_modifiers: Array[String] = []
	hud.update_modifier_status(no_modifiers)

	# Place dart marker
	_place_dart(hit_position)
	AuidoManager.play_dart_thunk()
	dartboard.flash_segment(hit_position)

	_shop_darts_remaining -= 1

	# Check if a lit spot was hit
	var spot_idx: int = dartboard.check_shop_hit(hit_position)

	if spot_idx >= 0:
		# Hit a lit spot — deactivate it and generate 2 mixed picks
		var spot: Dictionary = _shop_lit_spots[spot_idx]
		dartboard.deactivate_shop_spot(spot_idx)
		var rarity: ScoringEnums.Rarity = spot["rarity"] as ScoringEnums.Rarity
		_shop_pick_items = _generate_shop_picks(rarity)
		_leg_phase = "shop_pick"
		hud.show_shop_pick_items(_shop_pick_items, _shop_darts_remaining)
	else:
		# Miss — continue or end
		hud.show_shop_header(_shop_darts_remaining)
		if _shop_darts_remaining <= 0:
			_end_shop_delayed()
		else:
			_enable_hover()
			_awaiting_next_dart = true
			_start_next_dart_timer()


## Generate 2 mixed shop picks (accuracy upgrades or modifiers) at a given rarity.
func _generate_shop_picks(rarity: ScoringEnums.Rarity) -> Array[Dictionary]:
	var picks: Array[Dictionary] = []

	for _i: int in range(2):
		# 50/50 chance of accuracy upgrade vs modifier
		if randi_range(0, 1) == 0:
			picks.append(_generate_shop_accuracy_pick(rarity))
		else:
			var mods: Array[ScoringModifier] = ModifierRegistry.generate_distinct_at_rarity(1, rarity)
			if mods.size() > 0:
				picks.append({"type": "modifier", "data": mods[0]})
			else:
				picks.append(_generate_shop_accuracy_pick(rarity))

	return picks


## Generate a single accuracy upgrade pick at a given rarity tier.
func _generate_shop_accuracy_pick(rarity: ScoringEnums.Rarity) -> Dictionary:
	var type_idx: int = randi_range(0, UPGRADE_TYPES.size() - 1)
	var upgrade_type: Dictionary = UPGRADE_TYPES[type_idx]

	var rarity_table: Array[Dictionary]
	if upgrade_type["tradeoff"]:
		rarity_table = CONSISTENCY_RARITY_TABLE
	elif upgrade_type["scale"] == "speed":
		rarity_table = SPEED_RARITY_TABLE
	else:
		rarity_table = STANDARD_RARITY_TABLE

	# Map ScoringEnums.Rarity to the rarity table entry
	var rarity_idx: int = clampi(rarity, 0, 2)
	var rarity_entry: Dictionary = rarity_table[rarity_idx]
	var value: int = randi_range(rarity_entry["min_value"], rarity_entry["max_value"])

	var upgrade: Dictionary = {
		"name": upgrade_type["name"],
		"property": upgrade_type["property"],
		"scale": upgrade_type["scale"],
		"description": upgrade_type["description"],
		"rarity": rarity_entry["name"],
		"color": rarity_entry["color"],
		"value": value,
		"tradeoff": upgrade_type["tradeoff"],
		"penalty_property": upgrade_type.get("penalty_property", ""),
		"penalty_name": upgrade_type.get("penalty_name", ""),
		"penalty_amount": upgrade_type.get("penalty_amount", 0),
	}

	return {"type": "upgrade", "data": upgrade}


## Player picks an item from the shop's 2-of-2 menu.
func _on_shop_pick_selected(index: int) -> void:
	var item: Dictionary = _shop_pick_items[index]

	if item["type"] == "upgrade":
		_apply_upgrade(item["data"])
		_update_stats_display()
		_continue_shop_after_pick()
		return

	# Modifier pick
	var modifier: ScoringModifier = item["data"] as ScoringModifier

	if modifier.config_type == ScoringEnums.ConfigType.NONE:
		add_scoring_modifier(modifier, {})
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_WEDGE:
		_pending_modifier = modifier
		_leg_phase = "wedge_picker"
		_picker_selected_wedge = -1
		dartboard.set_picker_mode(true)
		if modifier is ColorFlipModifier:
			hud.show_picker_header("Flip a wedge's colors")
		else:
			hud.show_picker_header("Add +%d to a wedge" % modifier.bonus_value)
		hud.show_picker_prompt("Hover over a wedge and click to select")
		return
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_TWO_WEDGES:
		_pending_modifier = modifier
		_leg_phase = "wedge_picker"
		_picker_selected_wedge = -1
		dartboard.set_picker_mode(true)
		hud.show_picker_header("Swap two wedges")
		hud.show_picker_prompt("Click to select the first wedge")
		return

	_continue_shop_after_pick()


## Continue the shop after a pick is resolved (including wedge picker).
func _continue_shop_after_pick() -> void:
	_leg_phase = "shop"
	if _shop_darts_remaining <= 0:
		_end_shop_delayed()
	else:
		hud.show_shop_header(_shop_darts_remaining)
		_start_new_throw()


## Show shop complete screen with a button to advance.
func _end_shop_delayed() -> void:
	_leg_phase = "shop_complete"
	hud.show_shop_complete()


## Finalize the shop and advance to the next leg with a slide transition.
func _end_shop(response: Dictionary) -> void:
	_in_shop = false
	_saved_darts_accumulator = 0
	_shop_lit_spots.clear()
	_leg_phase = ""
	_clear_darts()
	hud.exit_shop_mode()

	# Slide board off to the right, clear shop, slide back from the left
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var off_right: Vector2 = Vector2(viewport_size.x + dartboard.board_radius * 2.0, center.y)
	var off_left: Vector2 = Vector2(-dartboard.board_radius * 2.0, center.y)

	var tween: Tween = create_tween()
	tween.tween_property(dartboard, "position", off_right, shop_transition_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		dartboard.clear_shop_spots()
		dartboard.position = off_left
		_awaiting_next_leg = false
		scoring_modifier_manager.reset_for_leg()
		x01_game.advance_leg()
		_update_all_hud()
		_sync_board_state()
		_update_checkout_highlights()
	)
	tween.tween_property(dartboard, "position", center, shop_transition_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_start_new_throw)


## Show the dart assembly screen before starting a run.
func _show_assembly() -> void:
	assembly_screen.show_assembly(_raw_stats)


## Called when the player confirms their dart build on the assembly screen.
func _on_run_confirmed() -> void:
	dart_build.apply_to_throw_mechanic(throw_mechanic, _raw_stats)
	# Re-snapshot after applying build so upgrades are relative to the built dart
	_snapshot_base_stats()
	# Update dart indicator with equipped component visuals
	hud.dart_indicator.set_dart_components(
		dart_build.equipped_barrel,
		dart_build.equipped_shaft,
		dart_build.equipped_flight
	)
	# Set up throw perk status display
	var modifier_info: Array[Dictionary] = []
	for part: DartComponent in [dart_build.equipped_barrel, dart_build.equipped_shaft, dart_build.equipped_flight]:
		if part != null and part.throw_modifier != null:
			modifier_info.append({
				"name": part.throw_modifier.modifier_name,
				"description": part.throw_modifier.description,
				"active_color": part.throw_modifier.active_color,
			})
	hud.setup_modifier_status(modifier_info)

	x01_game.start_run()
	_update_all_hud()
	_update_checkout_highlights()

	if debug_start_with_modifier:
		_start_modifier_pending = true
		_leg_phase = "modifier_pick"
		_current_modifiers = []
		var generated: Array[ScoringModifier] = ModifierRegistry.generate_distinct(3)
		for mod: ScoringModifier in generated:
			_current_modifiers.append(mod)

		# Build replacement info for each modifier choice
		var replacement_info: Array[String] = []
		for mod: ScoringModifier in _current_modifiers:
			var conflict: ScoringModifier = scoring_modifier_manager.get_streak_conflict(mod)
			if conflict != null:
				replacement_info.append("Replaces: %s" % conflict.modifier_name)
			else:
				replacement_info.append("")
		hud.show_modifier_choices_with_replacement(_current_modifiers, replacement_info)
	else:
		_start_new_throw()


## Player picks an accuracy upgrade card.
func _on_upgrade_selected(index: int) -> void:
	_apply_upgrade(_current_upgrades[index])
	_update_stats_display()

	# Move to Phase 2: modifier pick
	_leg_phase = "modifier_pick"
	_current_modifiers = []
	var generated: Array[ScoringModifier] = ModifierRegistry.generate_distinct(3)
	for mod: ScoringModifier in generated:
		_current_modifiers.append(mod)

	# Build replacement info for each modifier choice
	var replacement_info: Array[String] = []
	for mod: ScoringModifier in _current_modifiers:
		var conflict: ScoringModifier = scoring_modifier_manager.get_streak_conflict(mod)
		if conflict != null:
			replacement_info.append("Replaces: %s" % conflict.modifier_name)
		else:
			replacement_info.append("")
	hud.show_modifier_choices_with_replacement(_current_modifiers, replacement_info)


## Player picks a scoring modifier card.
func _on_modifier_selected(index: int) -> void:
	# Shop pick uses its own modifier array (2-of-2)
	if _in_shop:
		_on_shop_pick_selected(index)
		return

	var modifier: ScoringModifier = _current_modifiers[index]

	if modifier.config_type == ScoringEnums.ConfigType.NONE:
		add_scoring_modifier(modifier, {})
		_leg_phase = ""
		if _start_modifier_pending:
			_start_modifier_pending = false
			_start_new_throw()
		else:
			hud.next_leg_button.visible = true
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_WEDGE:
		_pending_modifier = modifier
		_leg_phase = "wedge_picker"
		_picker_selected_wedge = -1
		dartboard.set_picker_mode(true)
		if modifier is ColorFlipModifier:
			hud.show_picker_header("Flip a wedge's colors")
		else:
			hud.show_picker_header("Add +%d to a wedge" % modifier.bonus_value)
		hud.show_picker_prompt("Hover over a wedge and click to select")
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_TWO_WEDGES:
		_pending_modifier = modifier
		_leg_phase = "wedge_picker"
		_picker_selected_wedge = -1
		dartboard.set_picker_mode(true)
		hud.show_picker_header("Swap two wedges")
		hud.show_picker_prompt("Click to select the first wedge")


## Apply temporary throw modifier bonuses to throw_mechanic.
func _apply_temp_bonuses() -> void:
	for key: String in _temp_throw_bonuses.keys():
		var current: float = throw_mechanic.get(key)
		throw_mechanic.set(key, current + _temp_throw_bonuses[key])

	# Apply gaussian spread override if any active modifier provides one
	_original_gaussian_spread = throw_mechanic.gaussian_spread
	var tightest_spread: float = 0.0
	for part: DartComponent in [dart_build.equipped_barrel, dart_build.equipped_shaft, dart_build.equipped_flight]:
		if part == null or part.throw_modifier == null:
			continue
		if part.throw_modifier.gaussian_spread_override > 0.0:
			var context: Dictionary = {
				"remaining_score": x01_game.remaining_score,
				"target_score": x01_game.target_score,
				"darts_this_turn": x01_game.darts_this_turn,
				"current_turn": x01_game.current_turn,
				"current_leg": x01_game.current_leg,
				"max_turns": x01_game.max_turns,
			}
			if part.throw_modifier.should_activate(context):
				if tightest_spread == 0.0 or part.throw_modifier.gaussian_spread_override < tightest_spread:
					tightest_spread = part.throw_modifier.gaussian_spread_override
	if tightest_spread > 0.0:
		throw_mechanic.gaussian_spread = tightest_spread


## Revert temporary throw modifier bonuses after a throw completes.
func _revert_temp_bonuses() -> void:
	for key: String in _temp_throw_bonuses.keys():
		var current: float = throw_mechanic.get(key)
		throw_mechanic.set(key, current - _temp_throw_bonuses[key])
	_temp_throw_bonuses = {}
	_active_throw_modifier_names = []
	throw_mechanic.gaussian_spread = _original_gaussian_spread


## Save throw_mechanic stats at the start of a run for later restoration.
func _snapshot_base_stats() -> void:
	_base_horizontal_range = throw_mechanic.horizontal_range
	_base_vertical_range = throw_mechanic.vertical_range
	_base_vertical_accuracy = throw_mechanic.vertical_accuracy
	_base_horizontal_accuracy = throw_mechanic.horizontal_accuracy
	_base_vertical_speed = throw_mechanic.vertical_speed
	_base_horizontal_speed = throw_mechanic.horizontal_speed
	_base_accuracy_skew_v = throw_mechanic.accuracy_skew_v


## Restore throw_mechanic stats to raw defaults (before any dart build).
## Used when starting a new run so the assembly screen begins from scratch.
func _restore_raw_stats() -> void:
	throw_mechanic.horizontal_range = _raw_stats["horizontal_range"]
	throw_mechanic.vertical_range = _raw_stats["vertical_range"]
	throw_mechanic.vertical_accuracy = _raw_stats["vertical_accuracy"]
	throw_mechanic.horizontal_accuracy = _raw_stats["horizontal_accuracy"]
	throw_mechanic.vertical_speed = _raw_stats["vertical_speed"]
	throw_mechanic.horizontal_speed = _raw_stats["horizontal_speed"]
	throw_mechanic.accuracy_skew_v = 0.0


## Restore throw_mechanic stats to their base values (post-build, pre-upgrades).
func _restore_base_stats() -> void:
	throw_mechanic.horizontal_range = _base_horizontal_range
	throw_mechanic.vertical_range = _base_vertical_range
	throw_mechanic.vertical_accuracy = _base_vertical_accuracy
	throw_mechanic.horizontal_accuracy = _base_horizontal_accuracy
	throw_mechanic.vertical_speed = _base_vertical_speed
	throw_mechanic.horizontal_speed = _base_horizontal_speed
	throw_mechanic.accuracy_skew_v = _base_accuracy_skew_v


## Get base stats as a dictionary for the assembly screen and dart build.
func _get_base_stats_dict() -> Dictionary:
	return {
		"horizontal_range": _base_horizontal_range,
		"vertical_range": _base_vertical_range,
		"vertical_accuracy": _base_vertical_accuracy,
		"horizontal_accuracy": _base_horizontal_accuracy,
		"vertical_speed": _base_vertical_speed,
		"horizontal_speed": _base_horizontal_speed,
	}


## Generate 3 distinct upgrade cards with random rarities and values.
func _generate_upgrades() -> Array[Dictionary]:
	# Pick 3 distinct upgrade types from the 6 available
	var indices: Array[int] = [0, 1, 2, 3, 4, 5]
	indices.shuffle()
	var chosen_indices: Array[int] = [indices[0], indices[1], indices[2]]

	var upgrades: Array[Dictionary] = []
	for idx: int in chosen_indices:
		var upgrade_type: Dictionary = UPGRADE_TYPES[idx]

		# Select rarity table based on stat type
		var rarity_table: Array[Dictionary]
		if upgrade_type["tradeoff"]:
			rarity_table = CONSISTENCY_RARITY_TABLE
		elif upgrade_type["scale"] == "speed":
			rarity_table = SPEED_RARITY_TABLE
		else:
			rarity_table = STANDARD_RARITY_TABLE

		# Roll rarity using weighted random (1-100 roll)
		var roll: int = randi_range(1, 100)
		var rarity: Dictionary
		if roll <= 65:
			rarity = rarity_table[0]
		elif roll <= 90:
			rarity = rarity_table[1]
		else:
			rarity = rarity_table[2]

		# Roll value within the rarity's range
		var value: int = randi_range(rarity["min_value"], rarity["max_value"])

		upgrades.append({
			"name": upgrade_type["name"],
			"property": upgrade_type["property"],
			"scale": upgrade_type["scale"],
			"description": upgrade_type["description"],
			"rarity": rarity["name"],
			"color": rarity["color"],
			"value": value,
			"tradeoff": upgrade_type["tradeoff"],
			"penalty_property": upgrade_type.get("penalty_property", ""),
			"penalty_name": upgrade_type.get("penalty_name", ""),
			"penalty_amount": upgrade_type.get("penalty_amount", 0),
		})

	return upgrades


## Apply a chosen upgrade to the throw_mechanic.
func _apply_upgrade(upgrade: Dictionary) -> void:
	# Apply the main boost
	if upgrade["scale"] == "direct":
		var current: float = throw_mechanic.get(upgrade["property"])
		var new_value: float = minf(current + float(upgrade["value"]), 100.0)
		throw_mechanic.set(upgrade["property"], new_value)
	elif upgrade["scale"] == "speed":
		var internal_boost: float = float(upgrade["value"]) * (4.0 / 40.0)
		var current: float = throw_mechanic.get(upgrade["property"])
		var new_value: float = minf(current + internal_boost, 5.0)
		throw_mechanic.set(upgrade["property"], new_value)

	# Apply tradeoff penalty if applicable
	if upgrade["tradeoff"]:
		var penalty_current: float = throw_mechanic.get(upgrade["penalty_property"])
		var new_penalty_value: float = penalty_current - float(upgrade["penalty_amount"])
		throw_mechanic.set(upgrade["penalty_property"], new_penalty_value)


## Update all HUD elements to reflect current game state.
func _update_all_hud() -> void:
	hud.update_leg(x01_game.current_leg, x01_game.target_score)
	hud.update_turn(x01_game.current_turn, x01_game.max_turns)
	hud.update_remaining(x01_game.remaining_score)
	hud.update_darts(3 - x01_game.darts_this_turn, x01_game.current_turn == x01_game.max_turns)
	_update_stats_display()


## Refresh the stats panel on the HUD with current throw_mechanic values.
func _update_stats_display() -> void:
	var current_stats: Dictionary = {
		"horizontal_range": throw_mechanic.horizontal_range,
		"vertical_range": throw_mechanic.vertical_range,
		"vertical_accuracy": throw_mechanic.vertical_accuracy,
		"horizontal_accuracy": throw_mechanic.horizontal_accuracy,
		"vertical_speed": throw_mechanic.vertical_speed,
		"horizontal_speed": throw_mechanic.horizontal_speed,
	}
	var base_stats: Dictionary = {
		"horizontal_range": _base_horizontal_range,
		"vertical_range": _base_vertical_range,
		"vertical_accuracy": _base_vertical_accuracy,
		"horizontal_accuracy": _base_horizontal_accuracy,
		"vertical_speed": _base_vertical_speed,
		"horizontal_speed": _base_horizontal_speed,
	}
	hud.update_stats(current_stats, base_stats)


## Recalculate and update which double segments would win the current leg.
## Also updates the remaining score color — gold when a single-dart checkout exists.
func _update_checkout_highlights() -> void:
	var remaining: int = x01_game.remaining_score
	var checkout_segments: Array[Dictionary] = scoring_modifier_manager.calculate_checkout_segments(remaining)
	dartboard.set_checkout_segments(checkout_segments)
	hud.set_remaining_checkout_available(checkout_segments.size() > 0)


## Check if a hovered segment is one of the checkout-winning doubles.
## Uses the same checkout list that drives the board highlights and gold score.
func _is_checkout_segment(result: Dictionary) -> bool:
	if result["total_score"] != x01_game.remaining_score:
		return false
	var checkout_segments: Array[Dictionary] = scoring_modifier_manager.calculate_checkout_segments(x01_game.remaining_score)
	var wedge_index: int = result.get("wedge_index", -1)
	var is_bull: bool = result.get("is_bull", false)
	for seg: Dictionary in checkout_segments:
		if seg["type"] == "double_bull" and is_bull and result.get("ring_name", "") == "Double Bull":
			return true
		if seg["type"] == "wedge" and seg["wedge_idx"] == wedge_index and result.get("ring_name", "") == "Double":
			return true
	return false


## Push the modifier manager's effective wedge values and colors to the dartboard
## so it renders and scores correctly. Call after any modifier changes.
func _sync_board_state() -> void:
	dartboard.effective_wedge_values = scoring_modifier_manager.effective_wedge_values
	dartboard.effective_wedge_colors = scoring_modifier_manager.effective_wedge_colors
	dartboard.queue_redraw()


## Remove all dart markers from the board.
func _clear_darts() -> void:
	for child: Node in dart_container.get_children():
		child.queue_free()


## Create a visual dart marker at the landing position.
func _place_dart(position: Vector2) -> void:
	var dart: Node2D = Node2D.new()
	dart.position = position
	dart.set_script(preload("res://scripts/dart_marker.gd"))
	dart.set("dart_color", dart_build.dart_outer_color)
	dart.set("dart_inner_color", dart_build.dart_inner_color)
	dart.set("dart_size", dart_size)
	dart_container.add_child(dart)


func _on_throw_state_changed(new_state: int) -> void:
	match new_state:
		throw_mechanic.ThrowState.AIMING:
			_enable_hover()
		throw_mechanic.ThrowState.VERTICAL_RELEASE:
			_disable_hover()
			hud.clear_modifier_perkup()
			hud.show_instruction("Click or Space to lock vertical")
			# Declare target and show highlight
			var target: Dictionary = throw_mechanic._declared_target
			if not target.is_empty():
				dartboard.set_declared_target(target)
			else:
				dartboard.clear_declared_target()
		throw_mechanic.ThrowState.HORIZONTAL_RELEASE:
			_disable_hover()
			hud.show_instruction("Click or Space to lock horizontal")
		throw_mechanic.ThrowState.RESOLVING:
			_disable_hover()
			hud.show_instruction("Releasing...")


func _unhandled_input(event: InputEvent) -> void:
	if _leg_phase != "wedge_picker":
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var wedge_idx: int = dartboard.get_wedge_at_position(get_global_mouse_position())
		if wedge_idx < 0:
			return
		get_viewport().set_input_as_handled()

		if _pending_modifier.config_type == ScoringEnums.ConfigType.PICK_WEDGE:
			_complete_pick_wedge(wedge_idx)
		elif _pending_modifier.config_type == ScoringEnums.ConfigType.PICK_TWO_WEDGES:
			_handle_pick_two_wedges_click(wedge_idx)

	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel_picker()


func _complete_pick_wedge(wedge_idx: int) -> void:
	add_scoring_modifier(_pending_modifier, {"wedge_index": wedge_idx})
	_finish_picker()


func _handle_pick_two_wedges_click(wedge_idx: int) -> void:
	if _picker_selected_wedge < 0:
		_picker_selected_wedge = wedge_idx
		var selected: Array[int] = [wedge_idx]
		dartboard.set_picker_selected(selected)
		var value: int = scoring_modifier_manager.get_effective_value(wedge_idx)
		hud.show_picker_header("Now pick a wedge to swap with %d" % value)
		hud.show_picker_prompt("Click another wedge to swap, or click the selected wedge to deselect")
	elif wedge_idx == _picker_selected_wedge:
		_picker_selected_wedge = -1
		var empty: Array[int] = []
		dartboard.set_picker_selected(empty)
		hud.show_picker_header("Swap two wedges")
		hud.show_picker_prompt("Click to select the first wedge")
	else:
		add_scoring_modifier(_pending_modifier, {
			"wedge_index_1": _picker_selected_wedge,
			"wedge_index_2": wedge_idx,
		})
		_finish_picker()


func _cancel_picker() -> void:
	dartboard.set_picker_mode(false)
	hud.hide_picker()
	_pending_modifier = null
	_picker_selected_wedge = -1

	if _in_shop:
		_leg_phase = "shop_pick"
		hud.show_shop_pick_items(_shop_pick_items, _shop_darts_remaining)
		return

	_leg_phase = "modifier_pick"

	# Rebuild replacement info when returning to modifier pick
	var replacement_info: Array[String] = []
	for mod: ScoringModifier in _current_modifiers:
		var conflict: ScoringModifier = scoring_modifier_manager.get_streak_conflict(mod)
		if conflict != null:
			replacement_info.append("Replaces: %s" % conflict.modifier_name)
		else:
			replacement_info.append("")
	hud.show_modifier_choices_with_replacement(_current_modifiers, replacement_info)


func _finish_picker() -> void:
	dartboard.set_picker_mode(false)
	hud.hide_picker()
	_pending_modifier = null
	_picker_selected_wedge = -1
	if _in_shop:
		_continue_shop_after_pick()
		return
	_leg_phase = ""
	if _start_modifier_pending:
		_start_modifier_pending = false
		_start_new_throw()
	else:
		hud.next_leg_button.visible = true


func _update_picker_prompt(wedge_idx: int) -> void:
	if wedge_idx < 0:
		if _pending_modifier.config_type == ScoringEnums.ConfigType.PICK_WEDGE:
			hud.show_picker_prompt("Hover over a wedge and click to select")
		elif _picker_selected_wedge < 0:
			hud.show_picker_prompt("Click to select the first wedge")
		else:
			hud.show_picker_prompt("Click another wedge to swap")
		return

	if _pending_modifier.config_type == ScoringEnums.ConfigType.PICK_WEDGE:
		var current_val: int = scoring_modifier_manager.get_effective_value(wedge_idx)
		if _pending_modifier is ColorFlipModifier:
			var current_single: ScoringEnums.SegmentColor = scoring_modifier_manager.get_effective_color(wedge_idx, false)
			var from_name: String = ColorFlipModifier.get_color_pair_name(current_single)
			var to_single: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.WHITE if current_single == ScoringEnums.SegmentColor.BLACK else ScoringEnums.SegmentColor.BLACK
			var to_name: String = ColorFlipModifier.get_color_pair_name(to_single)
			hud.show_picker_prompt("Flip %d from %s to %s? Click to confirm, Escape to cancel" % [current_val, from_name, to_name])
		else:
			var new_val: int = current_val + _pending_modifier.bonus_value
			hud.show_picker_prompt("Make %d into %d? Click to confirm, Escape to cancel" % [current_val, new_val])
	elif _pending_modifier.config_type == ScoringEnums.ConfigType.PICK_TWO_WEDGES:
		if _picker_selected_wedge < 0:
			var val: int = scoring_modifier_manager.get_effective_value(wedge_idx)
			hud.show_picker_prompt("Select %d? Click to pick first wedge" % val)
		elif wedge_idx != _picker_selected_wedge:
			var val1: int = scoring_modifier_manager.get_effective_value(_picker_selected_wedge)
			var val2: int = scoring_modifier_manager.get_effective_value(wedge_idx)
			hud.show_picker_prompt("Swap %d and %d? Click to confirm, Escape to cancel" % [val1, val2])


func _spawn_floating_score(hit_position: Vector2, result: Dictionary) -> Tween:
	var score: int = result["total_score"]
	if score == 0:
		return null

	var modifications: Array = result.get("modifications", [])
	var multiplier_mods: Array[Dictionary] = []
	for mod: Dictionary in modifications:
		if mod["field"] == "multiplier":
			multiplier_mods.append(mod)

	if multiplier_mods.is_empty():
		return _spawn_simple_floating_score(hit_position, result)
	else:
		return _spawn_trigger_animation(hit_position, result, multiplier_mods)


func _spawn_simple_floating_score(hit_position: Vector2, result: Dictionary) -> Tween:
	var label: Label = _create_score_label(result["total_score"], hit_position, result)
	add_child(label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(25.0, -55.0), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	return tween


func _spawn_trigger_animation(hit_position: Vector2, result: Dictionary, multiplier_mods: Array[Dictionary]) -> Tween:
	var face_value: int = result["face_value"]
	var base_score: int = face_value * int(multiplier_mods[0]["old_value"])
	var main_label: Label = _create_score_label(base_score, hit_position, result, 30)
	main_label.pivot_offset = main_label.size / 2.0
	add_child(main_label)

	# Suppress hover tooltip while the animation plays
	hud.hide_hover_tooltip()
	_trigger_anim_active = true

	var tween: Tween = create_tween()
	tween.tween_interval(0.3)

	var trigger_labels: Array[Label] = []
	var num_triggers: int = multiplier_mods.size()
	var running_total: int = base_score

	for i: int in range(num_triggers):
		var angle: float = PI * (0.3 + 0.4 * float(i) / float(maxi(num_triggers - 1, 1)))
		var offset: Vector2 = Vector2(cos(angle), -sin(angle)) * 50.0
		var trigger_label: Label = Label.new()
		trigger_label.text = "+%d" % face_value
		trigger_label.position = hit_position + offset + Vector2(-10.0, -10.0)
		trigger_label.z_index = 101
		trigger_label.add_theme_font_size_override("font_size", 20)
		trigger_label.add_theme_constant_override("outline_size", 3)
		var rarity_color: Color = multiplier_mods[i].get("source_rarity_color", Color(0.8, 0.8, 0.8))
		trigger_label.add_theme_color_override("font_color", rarity_color)
		trigger_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		trigger_label.modulate.a = 0.0
		add_child(trigger_label)
		trigger_labels.append(trigger_label)

	for i: int in range(num_triggers):
		running_total += face_value
		var final_total: int = running_total
		var scale_bump: float = 1.0 + 0.1 * float(i + 1)
		var trigger_lbl: Label = trigger_labels[i]

		tween.tween_property(trigger_lbl, "modulate:a", 1.0, 0.1)
		tween.tween_property(trigger_lbl, "position", main_label.position, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(_on_trigger_impact.bind(trigger_lbl, main_label, final_total, scale_bump, i))
		var shake_offset: Vector2 = Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0))
		tween.tween_property(main_label, "position", main_label.position + shake_offset, 0.04)
		tween.tween_property(main_label, "position", hit_position + Vector2(-10.0, -10.0), 0.04)
		if i < num_triggers - 1:
			tween.tween_interval(0.1)

	tween.tween_interval(0.15)
	tween.tween_callback(func() -> void: _trigger_anim_active = false)
	tween.set_parallel(true)
	tween.tween_property(main_label, "position", main_label.position + Vector2(25.0, -55.0), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(main_label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(false)
	tween.tween_callback(main_label.queue_free)
	return tween


func _on_trigger_impact(trigger_lbl: Label, main_label: Label, total: int, scale: float, trigger_index: int) -> void:
	trigger_lbl.queue_free()
	main_label.text = str(total)
	main_label.scale = Vector2(scale, scale)
	AuidoManager.play_bonus_hit(trigger_index)


func _create_score_label(score: int, hit_position: Vector2, result: Dictionary, font_size: int = 26) -> Label:
	var label: Label = Label.new()
	label.text = str(score)
	label.position = hit_position + Vector2(-10.0, -10.0)
	label.z_index = 100
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 3)

	var segment_color: int = result.get("segment_color", -1)
	match segment_color:
		ScoringEnums.SegmentColor.RED:
			label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
			label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		ScoringEnums.SegmentColor.GREEN:
			label.add_theme_color_override("font_color", Color(0.2, 0.85, 0.3))
			label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		ScoringEnums.SegmentColor.BLACK:
			label.add_theme_color_override("font_color", Color(0.25, 0.25, 0.3))
			label.add_theme_color_override("font_outline_color", Color(0.85, 0.85, 0.85, 0.8))
		ScoringEnums.SegmentColor.WHITE:
			label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
			label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		_:
			label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))

	return label


## Build target tooltip info from a declared target and the modifier pipeline.
func _build_target_tooltip(target_result: Dictionary) -> Dictionary:
	var face_value: int = target_result["face_value"]
	var base_multiplier: int = target_result["multiplier"]
	var base_score: int = face_value * base_multiplier

	# Run through modifier pipeline in preview mode
	var modified: Dictionary = scoring_modifier_manager.process_score(target_result.duplicate(), true)
	var modified_multiplier: int = modified["multiplier"]
	var total_score: int = modified["total_score"]
	var bonus_mult: int = modified_multiplier - base_multiplier

	var prefix: String = _get_ring_prefix(target_result["ring_name"])
	var streak_lines: Array[String] = _get_active_streak_info()

	return {
		"prefix": prefix,
		"face_value": face_value,
		"base_score": base_score,
		"total_score": total_score,
		"bonus_multiplier_total": bonus_mult,
		"streak_lines": streak_lines,
	}


func _get_ring_prefix(ring_name: String) -> String:
	match ring_name:
		"Inner Single", "Outer Single":
			return "S"
		"Double":
			return "D"
		"Triple":
			return "T"
		"Single Bull":
			return "SB"
		"Double Bull":
			return "DB"
	return ""


## Query active streak modifiers for current streak counts.
func _get_active_streak_info() -> Array[String]:
	var lines: Array[String] = []
	for modifier: Resource in scoring_modifier_manager.active_modifiers:
		if modifier is ScoringModifier and modifier.enabled:
			var display: String = modifier.get_streak_display()
			if display != "":
				lines.append(display)
	return lines
