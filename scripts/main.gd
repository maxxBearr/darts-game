extends Node2D
## Main scene controller. Orchestrates the dartboard, throw mechanic, X01 game logic, and HUD.
## Manages game flow: X01 run → legs → turns → darts → score → upgrades → repeat.

@export_group("Gameplay")

## Radius of placed dart markers in pixels.
@export var dart_size: float = 5.0

## Seconds to wait after a dart lands before auto-starting the next throw.
## Only applies within a turn — turn boundaries still require a button press.
@export var next_dart_delay: float = 0.8

@export_group("Debug")

## When enabled, the player picks a scoring modifier after building their dart,
## before the first throw — same UI as the post-leg modifier pick.
@export var debug_start_with_modifier: bool = false

## When enabled, resets the first-run tutorial flag at startup for testing.
@export var debug_reset_tutorial_seen: bool = false

## When enabled, the run starts at the boss leg (target = max_score_target)
## so you face a boss on the first leg. Useful for testing boss encounters.
@export var debug_boss_immediately: bool = false

@export_group("Path Illumination")

## Whether checkout path illumination is enabled (blue board highlights).
@export var illumination_enabled: bool = true

@export_group("Throw Anticipation")

## When enabled, a large dart flies in from the aim center and shrinks down onto the
## RNG landing point before the normal impact flow (thunk, shockwave, score) fires.
## The drift from aim center to landing point visualizes the accuracy miss.
## Disable to land instantly with no fly-in, exactly as before.
@export var throw_anticipation_enabled: bool = true

## How large the flying dart starts, as a multiple of the final marker size.
## Sells the "dart flying away from the player" read — bigger = starts closer in.
@export_range(1.0, 8.0, 0.1) var anticipation_start_scale: float = 3.0

## Starting opacity of the flying dart. It fades up to fully opaque as it arrives,
## reinforcing the far-to-near read. Set to 1.0 to disable the fade-in.
@export_range(0.0, 1.0, 0.05) var anticipation_start_alpha: float = 0.45

## Duration of the fly-in / shrink animation in seconds, before impact fires.
## Shorter = snappier; longer = more drawn-out anticipation.
@export_range(0.05, 1.0, 0.01) var anticipation_duration: float = 0.3

@onready var dartboard: Node2D = $Dartboard
@onready var throw_mechanic: Node2D = $ThrowMechanic
@onready var dart_container: Node2D = $DartContainer
@onready var hud: CanvasLayer = $HUD
@onready var x01_game: Node = $X01Game

var _score_layer: CanvasLayer
@onready var scoring_modifier_manager: Node = $ScoringModifierManager
@onready var dart_component_registry: DartComponentRegistry = $DartComponentRegistry
@onready var dart_build: DartBuild = $DartBuild
@onready var assembly_screen: AssemblyScreen = %AssemblyScreen

# Tutorial system nodes — instantiated in _ready()
var start_screen: StartScreen
var welcome_modal: WelcomeModal
var rules_slideshow: RulesSlideshow
var tutorial_callout: TutorialCallout
var tutorial_controller: TutorialController
var ghost_dart_layer: GhostDartLayer
var game_over_screen: GameOverScreen
var level_select: LevelSelectScreen
var boss_manager: BossManager
var map_view: MapView
var _challenge_entry_view: ChallengeEntryView

## The generated run map. Built at run start (_on_run_confirmed); drives leg/shop/
## boss scheduling between encounters. Null outside a run. See specs/map/.
var _map_graph: MapGraph = null

## The level definition for the current run. Null during tutorial/legacy mode.
var _current_level: LevelDefinition = null

## Whether the game is currently in tutorial sandbox mode.
var _in_tutorial: bool = false

# Upgrade type definitions — Phase 1 ("Accuracy as Shape, Not Climb"): all six are sibling-axis
# trades (V <-> H), never flat buffs. Each picks concentrates a conserved scatter budget instead
# of climbing it, so the throw-anticipation drift never vanishes. Penalty magnitude is
# rarity-scaled and lives in the rarity tables below (a rare buys a better exchange rate, not a
# bigger raw number), so penalty_amount is no longer a field on the type def.
const UPGRADE_TYPES: Array[Dictionary] = [
	{
		"name": "Horizontal Range",
		"property": "horizontal_range",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "vertical_range",
		"penalty_name": "Vertical Range",
		"description": "Narrows the horizontal aiming band, but widens the vertical",
	},
	{
		"name": "Vertical Range",
		"property": "vertical_range",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "horizontal_range",
		"penalty_name": "Horizontal Range",
		"description": "Shrinks the vertical positioning window, but widens the horizontal",
	},
	{
		"name": "V Speed Control",
		"property": "vertical_speed",
		"scale": "speed",
		"tradeoff": true,
		"penalty_property": "horizontal_speed",
		"penalty_name": "H Speed Control",
		"description": "Slows the vertical release marker, but speeds the horizontal",
	},
	{
		"name": "H Speed Control",
		"property": "horizontal_speed",
		"scale": "speed",
		"tradeoff": true,
		"penalty_property": "vertical_speed",
		"penalty_name": "V Speed Control",
		"description": "Slows the horizontal release marker, but speeds the vertical",
	},
	{
		"name": "Vertical Accuracy",
		"property": "vertical_accuracy",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "horizontal_accuracy",
		"penalty_name": "Horizontal Accuracy",
		"description": "Tightens vertical variance, but widens horizontal",
	},
	{
		"name": "Horizontal Accuracy",
		"property": "horizontal_accuracy",
		"scale": "direct",
		"tradeoff": true,
		"penalty_property": "vertical_accuracy",
		"penalty_name": "Vertical Accuracy",
		"description": "Tightens horizontal variance, but widens vertical",
	},
]

# Rarity tiers for all trades. Phase 1 model: the raw gain is ~flat across rarities; rarity buys
# a smaller sibling-axis "penalty" (a better exchange rate), not a bigger number. Net gain per
# rarity lands on the spec ladder: Common net ~0 (pure reshape), Uncommon net ~+2, Rare net ~+4.
# (net = avg gain - penalty). These are first-pass numbers meant to be felt and retuned in
# playtest, not final balance.

# Range stats (direct 1-100): gain 6-8 (avg 7), penalty 7/5/3 -> net ~0/+2/+4.
const STANDARD_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 6, "max_value": 8, "penalty": 7, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 6, "max_value": 8, "penalty": 5, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 6, "max_value": 8, "penalty": 3, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Speed stats. Values are in DISPLAY units — the same 0-100 space the stat bars show via
# _speed_to_display — so a "+N" on a speed card moves the bar by N, exactly like accuracy/range.
# Converted to the 1.0-5.0 internal scale at apply-time via x(4/100) (1 display point = 0.04
# internal). gain 8-10 (avg 9), penalty 9/7/5 -> net ~0/+2/+4, matching the accuracy ladder.
const SPEED_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 8, "max_value": 10, "penalty": 9, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 8, "max_value": 10, "penalty": 7, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 8, "max_value": 10, "penalty": 5, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# Accuracy stats (direct 1-100): gain 8-10 (avg 9), penalty 9/7/5 -> net ~0/+2/+4.
const CONSISTENCY_RARITY_TABLE: Array[Dictionary] = [
	{"name": "Common", "min_value": 8, "max_value": 10, "penalty": 9, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
	{"name": "Uncommon", "min_value": 8, "max_value": 10, "penalty": 7, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
	{"name": "Rare", "min_value": 8, "max_value": 10, "penalty": 5, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]

# ── Event nodes (specs/map/03-events-impl.md §3) — the diagonal-swing trade ───
# The rarity ramp + swing table live in EventRewards (a pure, headless-testable roller) so
# the rolled distribution is unit-tested directly. Events reuse UPGRADE_TYPES + _apply_upgrade
# here; EventRewards only rolls the rarity/gain/penalty into the upgrade-dict shape.

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

## End-of-leg phase: "", "accuracy_pick", "modifier_pick", "wedge_picker", "segment_picker", "boss_reward_pick"
var _leg_phase: String = ""

## Cached checkout paths for illumination (from last solver run).
var _checkout_paths: Array[Array] = []

## Index of the selected path for illumination (-1 = none).
var _selected_path_index: int = -1

## The 3 generated modifier choices for the modifier pick phase.
var _current_modifiers: Array[ScoringModifier] = []

## Boss reward choices for the current reward pick phase.
var _current_rewards: Array[RuleModifierReward] = []

## All rewards picked during this run. Used for exclusion and reset.
var _active_rewards: Array[RuleModifierReward] = []

## Whether the current boss leg was a boss (for triggering reward flow after upgrades).
var _boss_leg_just_cleared: bool = false

# --- Phase 02 challenge-node state (specs/map/02-challenge-nodes-impl.md) ---

## Highest score the player has actually CLEARED this run (boss or leg). The §3 anchor:
## a challenge target rolls within −target_undercut of this, never above it. Updated on
## every banked win; reset on run start.
var _highest_cleared: int = 0

## True for the duration of a challenge race (between deposit and win/loss). Gates the
## win/loss handling onto the challenge paths (forfeit-not-run-end, typed reward) and
## disables the bailout (a fixed wager can't be bailed). §11/§9.
var _challenge_active: bool = false

## The ChallengeNode being raced (its target/dpt/deposit band/reward family/handicap).
var _active_challenge: ChallengeNode = null

## The deposit staked on the active race (withheld from the bank at entry; forfeited on
## loss, its unused remainder banked on win via get_saved_darts). §11.
var _challenge_deposit: int = 0

## darts_per_turn captured before the race's dpt override, restored when the race ends.
var _challenge_prev_dpt: int = 3

## The instantiated handicap boss effect for this race (rotation / narrow_double), or
## null for a clean precision race. Driven directly (not via boss_manager) so it doesn't
## draw from the level boss pool. §8.
var _challenge_handicap: Boss = null

## True while a typed challenge reward pick is pending, so the shared pick chokepoint
## (_continue_shop_after_pick) returns to the map instead of resuming a shop. §6.
var _challenge_reward_pending: bool = false

## True while an EVENT node's free 1-of-3 trade pick is pending (specs/map/03-events-impl.md).
## Reuses the upgrade-card UI (accuracy) or the shop-pick UI (brush); this flag routes both
## the selection and the skip back to the map (no shop resume, no bank touch) via the shared
## pick chokepoints, exactly like _challenge_reward_pending but with no x01/board slide.
var _event_pending: bool = false

## Run-scoped RNG for the arrival-time challenge target roll (§3). Randomized at run start.
var _challenge_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Run-scoped RNG for the event reward rolls (rarity ramp + swing table, 03 §3). Randomized
## at run start; threaded into EventRewards so each event node rolls fresh.
var _event_rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The modifier awaiting wedge picker configuration.
var _pending_modifier: ScoringModifier = null

## Streak replacement chooser state — set when a modifier has multiple same-category conflicts.
var _streak_replace_candidates: Array = []
var _streak_replace_modifier: ScoringModifier = null
var _streak_replace_config: Dictionary = {}

## First selected wedge in PICK_TWO_WEDGES flow (-1 = none).
var _picker_selected_wedge: int = -1

## How many wedges remain to be flipped in the Mirror-Zone relic picker flow.
## > 0 means the relic_flip_picker phase is active. The flow grants one
## FlipSignModifier per pick and only continues to shop/next-leg once it hits 0.
var _relic_flips_remaining: int = 0

# Cumulative score for the current turn (resets each turn)
var _turn_score: int = 0

# How many darts scored > 0 this turn (for unlock conditions).
var _turn_darts_scored: int = 0

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

## Total darts thrown across the entire run (for game over stats).
var _run_total_darts: int = 0

## Persistent run-long dart bank. Grows by leg savings (get_saved_darts), only
## ever shrinks by spending (shop purchases or bailout turns). Reset to 0 on run start.
var _banked_darts: int = 0

## Whether the game is currently in the shop phase.
var _in_shop: bool = false

## Shop darts remaining to throw.
var _shop_darts_remaining: int = 0

## Lit spots on the board for the current shop.
var _shop_lit_spots: Array[Dictionary] = []

## The 2 item choices generated when a lit spot is hit.
## Each entry: {type: "modifier"|"upgrade", data: ScoringModifier|Dictionary}
var _shop_pick_items: Array[Dictionary] = []

@export_group("Shop")

## Extra lit spots beyond the dart count (breathing room for target choice).
@export var shop_spot_slack: int = 3

## Number of pick choices shown when a shop spot is hit. Default 2.
var shop_pick_count: int = 2

## Duration of the zero-dart shop acknowledgment in seconds.
@export var shop_zero_dart_duration: float = 2.5

## How often shops occur (every N legs).
@export var shop_cadence: int = 3
var _default_shop_cadence: int

## When true, a free shop always appears after beating a boss (in addition to the reward pick).
@export var shop_after_boss: bool = true

## When true, shop only offers modifiers (no accuracy upgrades).
var all_in_active: bool = false

## Duration of the board slide transition into/out of shop in seconds.
@export var shop_transition_duration: float = 0.5

## Duration of the board slide transition between legs in seconds.
@export var leg_transition_duration: float = 0.5

@export_group("Score Animation")

## Font size for the number that floats up after a dart scores (e.g. "20", "0").
@export var score_font_size: int = 26

## Font size for the center number during a streak/multiplier combo animation.
@export var score_trigger_font_size: int = 30

## Font size for individual trigger "+N" labels that fly into the center number.
@export var score_trigger_pip_font_size: int = 20

## Font size for the modifier name caption below the combo (e.g. "Red Streak: +3x!").
@export var score_source_font_size: int = 16


func _ready() -> void:
	_default_shop_cadence = shop_cadence

	_score_layer = CanvasLayer.new()
	_score_layer.layer = 2
	add_child(_score_layer)

	# Connect throw mechanic signals
	throw_mechanic.throw_completed.connect(_on_throw_completed)
	throw_mechanic.state_changed.connect(_on_throw_state_changed)

	# Connect HUD button signals
	hud.next_turn_pressed.connect(_on_next_turn)
	hud.next_leg_pressed.connect(_on_next_leg)
	hud.new_run_pressed.connect(_on_new_run)
	hud.upgrade_selected.connect(_on_upgrade_selected)
	hud.modifier_selected.connect(_on_modifier_selected)
	hud.modifier_skipped.connect(_on_modifier_skipped)
	hud.reward_selected.connect(_on_reward_selected)
	hud.streak_replace_selected.connect(_on_streak_replace_selected)
	hud.modifier_toggled.connect(_on_modifier_toggled)
	hud.checkout_path_clicked.connect(_on_checkout_path_clicked)
	hud.throw_aim_pressed.connect(func() -> void: throw_mechanic.confirm_aim_placement())

	# Connect assembly screen
	assembly_screen.dart_build = dart_build
	assembly_screen.registry = dart_component_registry
	assembly_screen.throw_mechanic = throw_mechanic
	assembly_screen.run_confirmed.connect(_on_run_confirmed)
	assembly_screen.play_tutorial_pressed.connect(_on_play_tutorial.bind("assembly"))
	assembly_screen.rules_pressed.connect(_on_show_rules)

	# Wire dartboard reference to throw_mechanic for target declaration
	throw_mechanic.dartboard = dartboard

	# Touch devices (incl. mobile browsers) can't hover-then-click to aim, so the AIMING
	# stage switches to drag-to-position + an on-screen Throw button. The two release meters
	# stay tap-to-lock either way. Desktop keeps mouse hover + click.
	throw_mechanic.touch_mode = DisplayServer.is_touchscreen_available()

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

	# Sync any debug modifiers to the HUD panel (BOARD_MUTATION filtered inside)
	for modifier: Resource in scoring_modifier_manager.active_modifiers:
		hud.add_modifier_to_panel(modifier)

	# --- Tutorial system setup ---
	_setup_tutorial_system()

	# Debug: reset tutorial seen flag for testing
	if debug_reset_tutorial_seen:
		SettingsStore.set_tutorial_seen(false)

	# First-run check: show welcome modal or start screen
	if not SettingsStore.get_tutorial_seen():
		assembly_screen.visible = false
		_hide_gameplay_hud()
		welcome_modal.show_modal()
	else:
		_show_start_screen()


func _process(_delta: float) -> void:
	# Picker mode hover — update wedge highlight under cursor
	if _leg_phase == "wedge_picker" and dartboard.picker_mode:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var wedge_idx: int = dartboard.update_picker_hover(mouse_pos)
		_update_picker_prompt(wedge_idx)
		return

	# Relic-flip picker hover — highlight the wedge under the cursor. The prompt is
	# static (no _pending_modifier to inspect), so just update the highlight.
	if _leg_phase == "relic_flip_picker" and dartboard.picker_mode:
		dartboard.update_picker_hover(get_global_mouse_position())
		return

	# Segment picker mode hover — update single-ring highlight under cursor
	if _leg_phase == "segment_picker" and dartboard.segment_picker_mode:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var seg: Dictionary = dartboard.update_segment_picker_hover(mouse_pos)
		_update_segment_picker_prompt(seg)
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
		var would_bust: bool = _would_bust(modified_result)
		var streak_lines: Array[String] = _get_active_streak_info()
		hud.show_hover_tooltip(modified_result, dartboard.WEDGE_ORDER, mouse_pos, is_checkout, streak_lines, would_bust)

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
func add_scoring_modifier(modifier: Resource, config: Dictionary, explicit_replacement: Resource = null) -> void:
	var replaced: Resource = scoring_modifier_manager.add_modifier(modifier, config, explicit_replacement)

	# If a modifier was replaced, remove its panel square
	if replaced != null:
		hud.remove_modifier_from_panel(replaced)

	# Add to panel (BOARD_MUTATION modifiers are filtered out inside add_modifier_to_panel)
	hud.add_modifier_to_panel(modifier)
	_sync_board_state()
	hud.update_streak_section(
		scoring_modifier_manager.get_active_streak_modifiers(),
		scoring_modifier_manager.effective_wedge_values
	)
	scoring_modifier_manager.invalidate_preferred_remainders()
	scoring_modifier_manager._build_solver_candidates()
	_update_checkout_highlights()
	_update_checkout_helper()


## Build the replacement warning string for a streak modifier.
## Returns "" if no conflict, "Replaces: X" for single conflict,
## or "Choose streak to replace" for multiple same-category conflicts.
func _get_replacement_text(mod: ScoringModifier) -> String:
	var conflicts: Array = scoring_modifier_manager.get_streak_conflicts(mod)
	if conflicts.size() == 1:
		return "Replaces: %s" % conflicts[0].modifier_name
	elif conflicts.size() > 1:
		return "Choose streak to replace"
	return ""


## Show the streak replacement chooser for a modifier with multiple same-category conflicts.
func _show_streak_replace_chooser(modifier: ScoringModifier, config: Dictionary, conflicts: Array) -> void:
	_streak_replace_modifier = modifier
	_streak_replace_config = config
	_streak_replace_candidates = conflicts
	_leg_phase = "streak_replace"
	hud.show_streak_replace_chooser(modifier, conflicts)


## Player picked which streak to replace in the multi-conflict chooser.
func _on_streak_replace_selected(index: int) -> void:
	var replacement: Resource = _streak_replace_candidates[index]
	add_scoring_modifier(_streak_replace_modifier, _streak_replace_config, replacement)
	_streak_replace_modifier = null
	_streak_replace_candidates = []
	_streak_replace_config = {}
	if _in_shop:
		_continue_shop_after_pick()
	else:
		_leg_phase = ""
		if _start_modifier_pending:
			_start_modifier_pending = false
			_start_new_throw()
		else:
			hud.score_label.text = ""
			hud.next_leg_button.visible = true


## Start a new throw (single dart).
func _start_new_throw() -> void:
	_disable_hover()
	hud.hide_score()

	if _in_shop:
		# Shop throws skip scoring modifiers and leg HUD updates
		hud.show_instruction("Move to aim, click to place zone")
		# hide_score() above cleared the Leave Shop button — restore it so the player
		# can bank the rest and leave at any time, not only once the darts run out.
		hud.show_shop_leave_button(_shop_darts_remaining)
		throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)
		return

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
	var darts_remaining: int = x01_game.darts_per_turn - x01_game.darts_this_turn
	var is_last_turn: bool = x01_game.current_turn == x01_game.max_turns
	hud.update_darts(darts_remaining, is_last_turn, x01_game.darts_per_turn)
	hud.show_instruction("Move to aim, click to place zone")
	throw_mechanic.start_throw(dartboard.global_position, dartboard.board_radius)


## Called when a dart lands — process through X01 logic and update state.
func _on_throw_completed(hit_position: Vector2) -> void:
	# Tutorial throws are handled by the tutorial controller — skip all game logic
	if _in_tutorial:
		return

	# Shop throws bypass the normal scoring pipeline
	if _in_shop:
		_on_shop_throw_completed(hit_position)
		return

	# Anticipation pre-step: fly a large dart in from the aim center, shrinking and
	# drifting onto the RNG landing point, THEN run the normal impact flow unchanged.
	play_throw_anticipation(hit_position, dart_build.dart_outer_color, dart_build.dart_inner_color, _resolve_throw_impact.bind(hit_position))


## Fly-in pre-step shared by EVERY throw path (normal, shop, tutorial): spawn a large,
## faint dart marker at the aim center and tween it down to normal size while it drifts
## onto the RNG landing point, THEN invoke on_landed — a zero-arg Callable that runs the
## caller's real impact logic (bind the hit_position at the call site). The shrink reads
## as the dart flying away from the player; the drift is the accuracy miss made visible.
## outer/inner_color let each caller match its own marker so the hand-off is seamless.
## When anticipation is disabled, on_landed fires immediately (original behavior).
func play_throw_anticipation(hit_position: Vector2, outer_color: Color, inner_color: Color, on_landed: Callable) -> void:
	if not throw_anticipation_enabled:
		on_landed.call()
		return

	var start_pos: Vector2 = throw_mechanic.get_resolve_center()

	# Transient flying dart — same visual as the marker the caller will place, so it ends
	# at hit_position at exactly final marker size right as the real marker appears.
	var flyer: Node2D = Node2D.new()
	flyer.set_script(preload("res://scripts/dart_marker.gd"))
	flyer.set("dart_color", outer_color)
	flyer.set("dart_inner_color", inner_color)
	flyer.set("dart_size", dart_size)
	flyer.position = start_pos
	flyer.scale = Vector2.ONE * anticipation_start_scale
	flyer.modulate = Color(1.0, 1.0, 1.0, anticipation_start_alpha)
	dart_container.add_child(flyer)

	# Accelerate in (EASE_IN) so arrival lands like a sudden thunk — the anticipation payoff.
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(flyer, "position", hit_position, anticipation_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(flyer, "scale", Vector2.ONE, anticipation_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(flyer, "modulate:a", 1.0, anticipation_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(_on_anticipation_landed.bind(flyer, on_landed))


## Called when the fly-in finishes: drop the transient and run the caller's impact logic.
func _on_anticipation_landed(flyer: Node2D, on_landed: Callable) -> void:
	if is_instance_valid(flyer):
		flyer.queue_free()
	on_landed.call()


## Run the full landing flow — score, marker, thunk, shockwave, floating score, and
## game logic. Called either immediately (anticipation off) or at the end of the fly-in.
func _resolve_throw_impact(hit_position: Vector2) -> void:
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
	var dart_node: Node2D = _place_dart(hit_position)
	# Tag the marker with its landing spot and refresh streak pulses (process_score above already
	# advanced streak state, so an active streak's darts light up immediately).
	dart_node.set("hit_target", {
		"wedge_index": result.get("wedge_index", -1),
		"ring_name": result.get("ring_name", ""),
		"segment_color": result.get("segment_color", -1),
		"is_bull": result.get("is_bull", false),
	})
	_refresh_streak_pulses()

	# If the dart hit a voided wedge, tween it away into the void
	var hit_wedge: int = result.get("wedge_index", -1)
	var hit_void: bool = result.get("is_void", false) or (hit_wedge >= 0 and dartboard._boss_void_wedges.has(hit_wedge))
	if hit_void:
		var void_tween: Tween = create_tween()
		void_tween.tween_property(dart_node, "scale", Vector2.ZERO, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		AuidoManager.play_void_hit()
	else:
		AuidoManager.play_dart_thunk()

	# Process through X01 game logic early so the score animation knows if this is a winning dart
	var response: Dictionary = x01_game.process_throw(result)

	# Floating score number (gold if winning dart)
	var recession_data: Dictionary = boss_manager.get_weak_board_data(hit_wedge)

	# Reactive bosses mutate the board in response to this hit. Done after the
	# landing dart's own score/recession_data are captured above, so the change
	# only affects subsequent darts.
	if boss_manager.is_boss_active():
		boss_manager.on_dart_landed(result, _build_game_state())

	# Build remaining-countdown info for trigger animations
	var remaining_info: Dictionary = {}
	if not response["is_leg_won"]:
		if response["is_bust"]:
			remaining_info = {
				"remaining_before": response["pre_revert_remaining"] + result["total_score"],
				"remaining_final": response["pre_revert_remaining"],
				"face_value": result["face_value"],
				"glass_cannon": x01_game.glass_cannon_active,
				"is_bust": true,
			}
		else:
			remaining_info = {
				"remaining_before": response["remaining_score"] + result["total_score"],
				"remaining_final": response["remaining_score"],
				"face_value": result["face_value"],
				"glass_cannon": x01_game.glass_cannon_active,
			}
	var score_tween: Tween = _spawn_floating_score(hit_position, result, recession_data, response["is_leg_won"], remaining_info)

	# Flash the hit segment for visual feedback
	dartboard.flash_segment(hit_position, response["is_leg_won"], response["is_bust"])

	# Update streak section
	hud.update_streak_section(
		scoring_modifier_manager.get_active_streak_modifiers(),
		scoring_modifier_manager.effective_wedge_values
	)

	# Show per-dart score feedback
	hud.show_score(result)

	# Show what was hit in the instruction label
	var ring_name: String = result["ring_name"]
	if ring_name == "Off Board":
		hud.show_instruction("Missed board!")
	elif result.get("is_bull", false):
		hud.show_instruction("Hit: %s" % ring_name)
	else:
		var face_value: int = result["face_value"]
		hud.show_instruction("Hit: %s %d" % [ring_name, face_value])

	# Accumulate turn score
	_turn_score += result["total_score"]
	if result["total_score"] > 0:
		_turn_darts_scored += 1
	hud.update_turn_score(_turn_score)

	# Update remaining score display — for trigger animations on normal hits,
	# defer the update so it counts down in sync with each trigger impact.
	# A flipped wedge scores negative (remaining climbs UP), which the multiplier
	# countdown can't represent, so flips never defer — they snap to the true value.
	var _has_trigger_anim: bool = false
	var _is_flip_hit: bool = false
	for _mod: Dictionary in result.get("modifications", []):
		if _mod["field"] == "multiplier":
			_has_trigger_anim = true
		elif _mod["field"] == "flip":
			_is_flip_hit = true
	if _is_flip_hit:
		_has_trigger_anim = false
	var _defer_remaining: bool = _has_trigger_anim and not response["is_leg_won"]
	if not _defer_remaining:
		if response["is_bust"]:
			hud.update_remaining(response["pre_revert_remaining"], x01_game.glass_cannon_active)
		else:
			hud.update_remaining(response["remaining_score"], x01_game.glass_cannon_active)

	# Branch on what happened
	if response["is_bust"]:
		if not _has_trigger_anim:
			AuidoManager.play_bust_sound()
		if x01_game.glass_cannon_active:
			hud.show_bust("GLASS CANNON — RUN OVER")
		else:
			hud.show_bust(response["bust_reason"])
		hud.set_remaining_bust(true)
		hud.mark_turn_busted(response["current_turn"])
		hud.hide_checkout_helper()
		dartboard.clear_illumination()
		if response["is_game_over"] and not _try_bailout(response, score_tween):
			_run_total_darts += x01_game.darts_used_in_leg
			if _challenge_active:
				# A lost challenge forfeits the staked deposit but NEVER ends the run — it
				# returns to the map (the parallel leg is gone, that's the cost). §4/§11.
				if score_tween != null and score_tween.is_valid():
					score_tween.tween_callback(_fail_challenge)
				else:
					_fail_challenge()
			else:
				_run_over = true
				if score_tween != null and score_tween.is_valid():
					score_tween.tween_callback(_show_game_over.bind(response["current_leg"]))
				else:
					_show_game_over(response["current_leg"])
		else:
			_awaiting_next_turn = true
			if score_tween != null and score_tween.is_valid():
				score_tween.tween_callback(func() -> void: hud.next_turn_button.visible = true)
			else:
				hud.next_turn_button.visible = true
	elif response["is_leg_won"]:
		_run_total_darts += x01_game.darts_used_in_leg
		# Leg complete — show golden 0, clear checkout highlights and helper
		hud.update_remaining(0)
		hud.set_remaining_checkout_available(true)
		dartboard.clear_checkout_segments()
		hud.hide_checkout_helper()
		dartboard.clear_illumination()
		_awaiting_next_leg = true
		_notify_leg_won(result, response)
		if score_tween != null and score_tween.is_valid():
			score_tween.tween_callback(_show_leg_won_banner.bind(response))
		else:
			_show_leg_won_banner(response)
	elif response["is_turn_over"]:
		# Used all 3 darts without bust or win — hide helper until next turn
		hud.hide_checkout_helper()
		dartboard.clear_illumination()
		if response["is_game_over"] and not _try_bailout(response, score_tween):
			_run_total_darts += x01_game.darts_used_in_leg
			if _challenge_active:
				# A lost challenge forfeits the staked deposit but NEVER ends the run — it
				# returns to the map (the parallel leg is gone, that's the cost). §4/§11.
				if score_tween != null and score_tween.is_valid():
					score_tween.tween_callback(_fail_challenge)
				else:
					_fail_challenge()
			else:
				_run_over = true
				if score_tween != null and score_tween.is_valid():
					score_tween.tween_callback(_show_game_over.bind(response["current_leg"]))
				else:
					_show_game_over(response["current_leg"])
		else:
			_awaiting_next_turn = true
			if score_tween != null and score_tween.is_valid():
				score_tween.tween_callback(func() -> void: hud.next_turn_button.visible = true)
			else:
				hud.next_turn_button.visible = true
	else:
		# Darts remaining this turn — auto-advance after score animation + delay
		_awaiting_next_dart = true
		if score_tween != null and score_tween.is_valid():
			score_tween.tween_callback(_start_next_dart_timer)
		else:
			_start_next_dart_timer()

	# Update dart counter
	hud.update_darts(response["darts_remaining"], x01_game.current_turn == x01_game.max_turns, x01_game.darts_per_turn)

	# Re-enable hover so the player can inspect the board while deciding
	_enable_hover()

	if not response["is_bust"] and not response["is_leg_won"]:
		_update_checkout_highlights()
	if not response["is_turn_over"] and not response["is_bust"] and not response["is_leg_won"]:
		_update_checkout_helper()


## Build the unlock context for a leg win and notify the UnlockManager.
func _notify_leg_won(result: Dictionary, response: Dictionary) -> void:
	var target: Dictionary = throw_mechanic._declared_target
	var was_on_target: bool = true
	if not target.is_empty():
		was_on_target = target.get("wedge_index", -1) == result.get("wedge_index", -2)

	var modifier_cats: Array[String] = []
	var streak_names: Array[String] = []
	for mod: Resource in scoring_modifier_manager.get_active_streak_modifiers():
		streak_names.append(mod.modifier_name)
	for mod_info: Dictionary in result.get("modifications", []):
		var source: String = mod_info.get("source_name", "")
		if streak_names.has(source) and not modifier_cats.has("streak"):
			modifier_cats.append("streak")

	var was_final: bool = (x01_game.current_turn == x01_game.max_turns
		and x01_game.darts_this_turn == x01_game.darts_per_turn)

	var leg_context: Dictionary = {
		"target_score": response["target_score"],
		"winning_ring": result.get("ring_name", ""),
		"winning_wedge_value": result.get("face_value", 0),
		"winning_score": result.get("total_score", 0),
		"was_final_possible_dart": was_final,
		"winning_modifier_categories": modifier_cats,
		"was_winning_dart_on_target": was_on_target,
		"checkout_total": _turn_score,
		# Strict reading: all three darts of the winning turn must have scored.
		# Excludes 1-dart and 2-dart finishes even if every dart thrown scored.
		"winning_turn_all_darts_scored": _turn_darts_scored == x01_game.darts_per_turn and x01_game.darts_this_turn == x01_game.darts_per_turn,
	}
	UnlockManager.on_leg_won(leg_context)


## Show the "LEG WON!" banner, then transition to upgrades after it finishes.
func _show_leg_won_banner(response: Dictionary) -> void:
	AuidoManager.play_leg_win(1.15)
	AuidoManager.on_leg_won()
	var banner_tween: Tween = hud.show_leg_won_banner()
	banner_tween.tween_callback(_show_leg_upgrades.bind(response))


## Show the leg-complete upgrade UI or shop entry. Called after the score animation finishes.
func _show_leg_upgrades(response: Dictionary) -> void:
	# End the boss leg if one was active (clean up mutations before upgrades/victory)
	_boss_leg_just_cleared = false
	if boss_manager.is_boss_active():
		boss_manager.end_boss_leg(_build_game_state(), true)
		_sync_board_and_solver()
		_boss_leg_just_cleared = true
		hud.hide_boss_status()

	# Check for run victory — player cleared the terminal boss node (the act-3 boss).
	# The map's terminal test is the source of truth; the score test is kept as a
	# belt-and-suspenders fallback for the debug skip path (no map advance there).
	var map_victory: bool = _map_graph != null and _map_graph.is_terminal(_map_graph.current_id)
	var score_victory: bool = _current_level != null and response["target_score"] >= _current_level.max_score_target
	if map_victory or score_victory:
		_show_run_won()
		return

	# Track the highest score actually cleared (boss or leg) — the §3 challenge anchor.
	# A challenge re-clears an OLD number, so it never raises this (target ≤ highest).
	_highest_cleared = maxi(_highest_cleared, int(response["target_score"]))

	# Incremental map gen (slice 3 §3.6): a cleared boss that wasn't the run victory
	# unlocks the next act. Append it now — against the LIVE run-state, so a state-gated
	# event family (brush) is only placed where its prereq holds — BEFORE the map is next
	# shown. A challenge race is not a boss, so it never triggers this.
	if _boss_leg_just_cleared and _map_graph != null:
		_map_graph.generate_next_act(_build_map_run_state())

	# Accumulate this leg's unused darts into the persistent bank, trickling them
	# into the rail's saved cache. For a won challenge race get_saved_darts() returns the
	# unused deposit (budget − used), so the same line banks the leftover wager. §11.
	var leg_saved: int = x01_game.get_saved_darts()
	_banked_darts += leg_saved
	hud.bank_leg_savings(leg_saved, _banked_darts)

	# A won challenge race grants a TYPED reward at the earned rarity instead of the
	# normal accuracy pick / boss reward (§6). The bank line above already returned the
	# unused deposit.
	if _challenge_active:
		_finish_challenge_win()
		return

	# Boss reward pick — show 3 rewards before normal upgrades/shop
	if _boss_leg_just_cleared:
		_leg_phase = "boss_reward_pick"
		_current_rewards = RewardRegistry.generate_picks(3, _build_run_state())
		hud.show_reward_choices(_current_rewards)
		return

	# The per-leg free pick was REMOVED (03 §5b): that accuracy/modifier drip moved off
	# "every leg" and onto the scarcer, weightier EVENT nodes (a bigger diagonal swing).
	# A normal leg now ends at its leg-complete banner and returns to the map via the Next
	# button — no upgrade panel. _show_accuracy_pick / _generate_upgrades stay in the file
	# for the shop + (unchanged) boss-reward paths; events are their own sibling generator.
	_leg_phase = ""
	hud.score_label.text = "Leg %d Complete! Cleared %d in %d turns" % [x01_game.current_leg, x01_game.target_score, x01_game.current_turn]
	hud.next_leg_button.visible = true


func _show_accuracy_pick() -> void:
	_leg_phase = "accuracy_pick"
	_current_upgrades = _generate_upgrades()
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
	hud.cache_stats(current_stats, base_stats)
	hud.show_leg_complete_with_upgrades(
		x01_game.current_leg,
		x01_game.target_score,
		x01_game.current_turn,
		_current_upgrades
	)


# ── Phase 03: event nodes (specs/map/03-events-impl.md) ──────────────────────

## Arrive at an EVENT node: a menu moment (no board slide, no x01). Roll the 3 free
## same-family trade options from the node's rolled family + its section (act) and show the
## 1-of-3 pick UI. accuracy uses the upgrade-card surface (swing table); brush uses the
## shop-pick surface (modifier-pool draw). The opportunity cost is purely spatial — the
## forgone parallel run — so events never touch the bank (§4). §5a.
func _enter_event(node: MapNode) -> void:
	var family: StringName = node.event.reward_family if node.event != null else &"accuracy"
	var section: int = node.act
	_disable_hover()
	# Residual arrival fallback (§2): if brush colors vanished between act-gen and arrival,
	# downgrade to accuracy so the node never offers an empty family.
	if family == &"brush":
		_sync_brush_affinity()
		if ModifierRegistry.available_brush_colors.is_empty():
			family = &"accuracy"
	var option_count: int = node.event.option_count if node.event != null else 3
	if family == &"brush":
		_enter_brush_event(section, option_count)
	else:
		_enter_accuracy_event(section)


## The accuracy event surface: 3 distinct stat-axis swing trades on the upgrade-card UI. The
## card UI is hardwired to 3 buttons (and the 6-axis pool always supplies 3 distinct), so this
## surface is fixed at 3 regardless of option_count. Selection routes through
## _on_upgrade_selected (which sees _event_pending and returns to the map without chaining the
## per-leg modifier pick).
func _enter_accuracy_event(section: int) -> void:
	_event_pending = true
	_leg_phase = "event_pick"
	_current_upgrades = _generate_event_picks(&"accuracy", section)
	# Cache stats so the card hover-preview reads the live throw stats (mirrors the pick).
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
	hud.cache_stats(current_stats, base_stats)
	hud.show_upgrade_choices(_current_upgrades)
	hud.score_label.text = "EVENT — choose an Accuracy trade"


## The brush event surface: a family-pure ScoringModifier draw at a section-ramp rarity,
## reusing the challenge reward's pick generation + the shop-pick UI. Selection routes
## through the shop-pick path (gated by _event_pending) back to the map. If the pool can't
## supply any brush picks, fall back to the accuracy surface (the §2 residual guard).
func _enter_brush_event(section: int, option_count: int = 3) -> void:
	var rarity: ScoringEnums.Rarity = _event_rarity_enum(section)
	# Ask for option_count distinct brushes; the pool may supply fewer (then we offer fewer,
	# the §2 relax-distinctness note). If it can supply none, fall back to the accuracy surface.
	var picks: Array[Dictionary] = _generate_challenge_reward_picks(ScoringEnums.Family.BRUSH, rarity, option_count)
	if picks.is_empty():
		_enter_accuracy_event(section)
		return
	_shop_pick_items = picks
	_event_pending = true
	_leg_phase = "event_pick"
	var replacement_info: Array[String] = []
	for item: Dictionary in picks:
		replacement_info.append(_get_replacement_text(item["data"] as ScoringModifier))
	hud.show_shop_pick_items(_shop_pick_items, _banked_darts, replacement_info)
	hud.score_label.text = "EVENT — choose a Brush trade"


## Generate the 3 free same-family options for an event. accuracy draws 3 distinct stat-axis
## trades off the swing table (§3) via EventRewards; brush is handled at its own surface in
## _enter_brush_event, so this only builds accuracy.
func _generate_event_picks(family: StringName, section: int) -> Array[Dictionary]:
	return EventRewards.generate_accuracy_picks(UPGRADE_TYPES, section, _event_rng)


## The section-ramp rarity as a ScoringEnums.Rarity (for the brush modifier-pool draw).
func _event_rarity_enum(section: int) -> ScoringEnums.Rarity:
	match EventRewards.roll_rarity_index(section, _event_rng):
		2:
			return ScoringEnums.Rarity.RARE
		1:
			return ScoringEnums.Rarity.UNCOMMON
		_:
			return ScoringEnums.Rarity.COMMON


## The event pick is resolved (accuracy applied or brush modifier added/declined) — clear
## state and return to the map. No bank mutation ever happens here (§4).
func _finish_event() -> void:
	_event_pending = false
	_shop_pick_items.clear()
	_current_upgrades = []
	_leg_phase = ""
	_turn_score = 0
	_turn_darts_scored = 0
	hud.update_turn_score(0)
	hud.upgrade_container.visible = false
	_show_map()


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
	AuidoManager.play_ui_click()
	_awaiting_next_turn = false
	_turn_score = 0
	_turn_darts_scored = 0
	hud.update_turn_score(0)
	hud.set_remaining_bust(false)
	hud.update_remaining(x01_game.remaining_score, x01_game.glass_cannon_active)
	scoring_modifier_manager.reset_for_turn()
	_clear_darts()
	AuidoManager.on_turn_ended(x01_game.current_turn)
	x01_game.end_turn()
	x01_game.start_turn()
	if boss_manager.is_boss_active():
		boss_manager.on_turn_start(_build_game_state())
		_sync_board_and_solver()
		_update_boss_status()
	# A challenge handicap (rotation re-rolls each turn, etc.) is driven directly, not via
	# boss_manager (it doesn't draw from the level boss pool). §8.
	if _challenge_handicap != null:
		_challenge_handicap.on_turn_start(_build_game_state())
		_sync_board_and_solver()
	hud.update_turn(x01_game.current_turn, x01_game.max_turns)
	hud.update_streak_section(
		scoring_modifier_manager.get_active_streak_modifiers(),
		scoring_modifier_manager.effective_wedge_values
	)
	_start_new_throw()
	_update_checkout_highlights()
	_update_checkout_helper()


## Player presses "Next Leg" — advance to next leg, enter shop, or leave shop.
func _on_next_leg() -> void:
	AuidoManager.play_ui_click()
	hud.next_leg_button.visible = false

	# "shop_complete" = ran the shop dry; "shop" = player chose to leave early. Both
	# bank the unspent remainder via _end_shop, which returns to the map. Cancel any
	# pending auto-advance so a queued shop throw doesn't fire after we've left.
	if _leg_phase == "shop_complete" or _leg_phase == "shop":
		_awaiting_next_dart = false
		var response: Dictionary = {
			"current_leg": x01_game.current_leg,
			"target_score": x01_game.target_score,
		}
		_end_shop(response)
		return

	# Normal post-leg advance: show the map and let the player pick the next node.
	_awaiting_next_leg = false
	_turn_score = 0
	_turn_darts_scored = 0
	hud.update_turn_score(0)
	_show_map()


## Show the run-map overlay so the player can choose their next encounter.
func _show_map() -> void:
	if _map_graph == null:
		return
	_leg_phase = "map"
	hud.next_leg_button.visible = false
	map_view.display(_map_graph)
	map_view.visible = true


## The player picked a node on the map. Hide the map and route by node type:
## shop nodes enter the shop; everything else slides into a new leg (boss-aware).
func _on_map_node_chosen(node: MapNode) -> void:
	if node == null:
		return
	map_view.visible = false
	_map_graph.advance_to(node.id)
	_leg_phase = ""
	if node.type == MapNode.Type.SHOP:
		var response: Dictionary = {
			"current_leg": x01_game.current_leg,
			"target_score": x01_game.target_score,
		}
		_start_shop(response)
	elif node.type == MapNode.Type.CHALLENGE:
		_enter_challenge(node)
	elif node.type == MapNode.Type.EVENT:
		_enter_event(node)
	else:
		_slide_to_leg_node(node)


## Slide the board out/in and start a leg with the chosen node's parameters. This
## replaces advance_leg()'s self-increment — the node owns (target, dart budget),
## and a BOSS node rolls a concrete boss from the level pool on arrival.
func _slide_to_leg_node(node: MapNode) -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var off_left: Vector2 = Vector2(-dartboard.board_radius * 2.0, center.y)
	var off_right: Vector2 = Vector2(viewport_size.x + dartboard.board_radius * 2.0, center.y)

	var tween: Tween = create_tween()
	tween.tween_property(dartboard, "position", off_left, leg_transition_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		scoring_modifier_manager.reset_for_leg()
		_clear_darts()
		x01_game.start_leg_with(node.target_score, node.max_turns)
		_update_all_hud()
		hud.update_streak_section(
			scoring_modifier_manager.get_active_streak_modifiers(),
			scoring_modifier_manager.effective_wedge_values
		)
		if node.type == MapNode.Type.BOSS:
			var game_state: Dictionary = _build_game_state()
			boss_manager.start_boss_leg(game_state)
			boss_manager.on_turn_start(game_state)
			_sync_board_and_solver()
			_update_boss_status()
		dartboard.position = off_right
	)
	tween.tween_property(dartboard, "position", center, leg_transition_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		_update_checkout_highlights()
		_update_checkout_helper()
		if boss_manager.is_boss_active():
			var boss_def: BossDefinition = boss_manager.get_active_boss_definition()
			var announce_tween: Tween = hud.show_boss_announcement(boss_def.display_name, boss_def.description, boss_def.title_color, boss_def.description_color)
			announce_tween.tween_callback(_start_new_throw)
		else:
			_start_new_throw()
	)


# ── Phase 02: challenge nodes (specs/map/02-challenge-nodes-impl.md) ─────────

## Arrive at a challenge node: compute its target + deposit band from the LIVE
## highest_cleared (§3/§4), then open the pre-entry readout + deposit picker (§10). The
## actual wager/withdrawal happens on confirm.
func _enter_challenge(node: MapNode) -> void:
	if node.challenge == null:
		_slide_to_leg_node(node)   # safety: malformed node, treat as a leg
		return
	_active_challenge = node.challenge
	_map_graph.compute_challenge_params(node, _highest_cleared, _challenge_rng)
	_disable_hover()
	_challenge_entry_view.show_for(node.challenge, _banked_darts)


## Player declined the challenge — take the parallel leg (§12). The fork rejoins
## immediately, so just return to the map for the next pick.
func _on_challenge_skipped() -> void:
	_active_challenge = null
	_show_map()


## Player confirmed the wager. Withhold the deposit from the bank (forfeited on a loss,
## its unused remainder returned on a win) and start the race. §11.
func _on_challenge_confirmed(deposit: int) -> void:
	_challenge_deposit = clampi(deposit, _active_challenge.min_deposit, _banked_darts)
	_banked_darts -= _challenge_deposit
	hud.update_bank(_banked_darts)
	_challenge_active = true
	_start_challenge_race()


## Slide the board in and start the x01 race under the challenge's constrained front:
## its target, its dpt override, and the deposit as the total-dart budget (§9). Mirrors
## _slide_to_leg_node but routes through start_challenge_race + applies a handicap.
func _start_challenge_race() -> void:
	var c: ChallengeNode = _active_challenge
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var off_left: Vector2 = Vector2(-dartboard.board_radius * 2.0, center.y)
	var off_right: Vector2 = Vector2(viewport_size.x + dartboard.board_radius * 2.0, center.y)

	var tween: Tween = create_tween()
	tween.tween_property(dartboard, "position", off_left, leg_transition_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		scoring_modifier_manager.reset_for_leg()
		_clear_darts()
		# Capture dpt before the per-race override so it restores cleanly afterward (the
		# same mutate/restore contract two_darts_boss uses). §9.
		_challenge_prev_dpt = x01_game.darts_per_turn
		x01_game.start_challenge_race(c.target_score, c.darts_per_turn, _challenge_deposit)
		_update_all_hud()
		hud.update_streak_section(
			scoring_modifier_manager.get_active_streak_modifiers(),
			scoring_modifier_manager.effective_wedge_values
		)
		_apply_handicap(c.handicap_id)
		dartboard.position = off_right
	)
	tween.tween_property(dartboard, "position", center, leg_transition_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		_update_checkout_highlights()
		_update_checkout_helper()
		_start_new_throw()
	)


## Instantiate + start a recycled benched-boss aim handicap for this race (§8). Driven
## directly (not via boss_manager) so it doesn't draw from the level boss pool. Empty id
## = a clean precision race.
func _apply_handicap(id: StringName) -> void:
	_challenge_handicap = null
	var script: GDScript = _handicap_script_for(id)
	if script == null:
		return
	_challenge_handicap = script.new() as Boss
	_challenge_handicap.configure({})
	var gs: Dictionary = _build_game_state()
	_challenge_handicap.on_leg_start(gs)
	_challenge_handicap.on_turn_start(gs)
	_sync_board_and_solver()


## Tear down the active handicap, restoring any board mutations (rotation offset, double
## ring width). Safe to call when there is no handicap.
func _end_handicap() -> void:
	if _challenge_handicap == null:
		return
	_challenge_handicap.on_leg_end(_build_game_state())
	_challenge_handicap = null
	_sync_board_and_solver()


## Map a handicap id to its benched-boss script (the aim handicaps only — see §8 and the
## generator's _roll_challenge_node for why two_darts is excluded).
func _handicap_script_for(id: StringName) -> GDScript:
	match id:
		&"rotation":
			return load("res://scripts/bosses/rotation_boss.gd")
		&"narrow_double":
			return load("res://scripts/bosses/narrow_double_ring_boss.gd")
		_:
			return null


## A won challenge race: restore the dpt override, tear down the handicap, then grant the
## TYPED reward at the rarity earned by finish-efficiency (§6). The unused deposit was
## already banked by _show_leg_upgrades's get_saved_darts line.
func _finish_challenge_win() -> void:
	_end_handicap()
	x01_game.darts_per_turn = _challenge_prev_dpt
	x01_game.dart_budget = 0
	var used: int = x01_game.darts_used_in_leg
	var rarity: ScoringEnums.Rarity = _active_challenge.rarity_for_used(used)
	var family: ScoringEnums.Family = _active_challenge.reward_family
	_challenge_active = false
	_show_challenge_reward(family, rarity)


## Offer the earned typed reward: a ScoringModifier of `family` at `rarity`, drawn from
## the modifier pool (the only pool that carries family + rarity). Reuses the shop pick
## UI + selection path; the pick chokepoint returns to the map via _finish_challenge_reward.
func _show_challenge_reward(family: ScoringEnums.Family, rarity: ScoringEnums.Rarity) -> void:
	_sync_brush_affinity()
	# Challenge families are FLAT board families only (SCORING / PLACEMENT) since the events
	# slice moved the brush *trade* off the earned surface (03 §1.2). The old empty-brush
	# fallback is therefore dead — a challenge can never roll BRUSH.
	var picks: Array[Dictionary] = _generate_challenge_reward_picks(family, rarity)
	if picks.is_empty():
		_finish_challenge_reward()
		return
	_shop_pick_items = picks
	_challenge_reward_pending = true
	_leg_phase = "challenge_reward"
	var replacement_info: Array[String] = []
	for item: Dictionary in picks:
		replacement_info.append(_get_replacement_text(item["data"] as ScoringModifier))
	hud.show_shop_pick_items(_shop_pick_items, _banked_darts, replacement_info)
	# Reframe the shop-flavored header as the earned reward (the pick UI is reused as-is).
	hud.score_label.text = "CHALLENGE CLEARED — claim your %s reward" % _rarity_name(rarity)


## Player-facing rarity label for the challenge reward header.
func _rarity_name(rarity: ScoringEnums.Rarity) -> String:
	match rarity:
		ScoringEnums.Rarity.RARE:
			return "RARE"
		ScoringEnums.Rarity.UNCOMMON:
			return "UNCOMMON"
		_:
			return "COMMON"


## Build the typed reward picks: distinct modifiers whose family matches, at the earned
## rarity. Generated per-type (not via generate_distinct_at_rarity's weight overrides) so
## the offer stays family-PURE even for single-type families (its fallback would leak an
## off-family type). Capped at `max_count` (default shop_pick_count; a brush event passes its
## option_count). Offers fewer if the family pool can't supply that many distinct types.
func _generate_challenge_reward_picks(family: ScoringEnums.Family, rarity: ScoringEnums.Rarity, max_count: int = -1) -> Array[Dictionary]:
	if max_count < 0:
		max_count = shop_pick_count
	var family_types: Array = []
	for type in ModifierRegistry.MODIFIER_TYPES:
		var sample: ScoringModifier = type.generate(rarity)
		if sample != null and sample.family == family:
			family_types.append(type)
	family_types.shuffle()
	var picks: Array[Dictionary] = []
	var owned: Array[String] = _get_owned_fingerprints()
	for type in family_types:
		if picks.size() >= max_count:
			break
		var mod: ScoringModifier = type.generate(rarity)
		var attempts: int = 0
		while mod.get_config_fingerprint() in owned and attempts < 8:
			mod = type.generate(rarity)
			attempts += 1
		owned.append(mod.get_config_fingerprint())
		picks.append({"type": "modifier", "data": mod})
	return picks


## The typed reward has been picked (and configured) — clean up and return to the map.
func _finish_challenge_reward() -> void:
	_active_challenge = null
	_leg_phase = ""
	_turn_score = 0
	_turn_darts_scored = 0
	hud.update_turn_score(0)
	_show_map()


## A lost challenge race: the deposit is forfeit (already withheld), the run CONTINUES.
## Restore the dpt override, tear down the handicap, flash a notice, and return to the map.
func _fail_challenge() -> void:
	_end_handicap()
	x01_game.darts_per_turn = _challenge_prev_dpt
	x01_game.dart_budget = 0
	_challenge_active = false
	_active_challenge = null
	AuidoManager.on_leg_lost()
	hud.update_bank(_banked_darts)
	hud.show_bust("CHALLENGE FAILED — wager forfeit")
	get_tree().create_timer(next_dart_delay * 2.0).timeout.connect(func() -> void:
		hud.set_remaining_bust(false)
		_show_map()
	)


## Bailout: rescue a would-be run-ending leg by spending banked darts.
##
## Fires automatically when the player runs out of turns without checking out
## (the out-of-turns game-over branch) and the bank holds a full turn's worth
## (>= 3). Spends 3 from the bank and raises the leg's turn ceiling by one so the
## player throws another turn. Returns true if a bailout turn was granted (caller
## then continues the leg instead of ending the run); false if the run should end.
##
## Glass Cannon busts never bail — they end the run immediately. With 1-2 banked,
## no bailout is possible and the stranded darts are lost with the run.
##
## Bailout-turn leftovers refund naturally: raising max_turns grows the leg's dart
## budget by 3, so get_saved_darts() (max_turns*darts_per_turn - darts_used_in_leg)
## returns the unused bailout darts back to the bank on the eventual leg win.
func _try_bailout(response: Dictionary, score_tween: Tween) -> bool:
	# A challenge race is a fixed wager — its budget can't be topped up. Never bail (the
	# loss must forfeit the deposit and continue the run, handled by _fail_challenge). §9/§11.
	if _challenge_active:
		return false
	# Glass Cannon busts end the run immediately — never bail.
	if response["is_bust"] and x01_game.glass_cannon_active:
		return false
	if _banked_darts < x01_game.darts_per_turn:
		return false

	# Cost is one turn's worth of darts (darts_per_turn, not a hardcoded 3) so the
	# refund stays exact when a relic changes the turn size: raising max_turns grows
	# the budget by darts_per_turn, matching what we spend here. The bank/ceiling
	# mutation happens now (the caller's branch depends on it), but the rescue banner
	# and rail fly-in wait until the score trigger animations finish so they don't
	# pop over the still-counting score.
	var cost: int = x01_game.darts_per_turn
	_banked_darts -= cost
	x01_game.max_turns += 1
	if score_tween != null and score_tween.is_valid():
		score_tween.tween_callback(hud.show_bailout.bind(cost, _banked_darts, x01_game.max_turns))
	else:
		hud.show_bailout(cost, _banked_darts, x01_game.max_turns)
	return true


## Show the game over overlay with run stats.
func _show_game_over(current_leg: int) -> void:
	if boss_manager.is_boss_active():
		boss_manager.end_boss_leg(_build_game_state(), false)
		_sync_board_and_solver()
		hud.hide_boss_status()
	AuidoManager.on_leg_lost()
	_hide_gameplay_hud()
	game_over_screen.show_results(current_leg - 1, _run_total_darts)


## Show the run victory screen after clearing the final leg of a level.
func _show_run_won() -> void:
	_run_over = true
	_hide_gameplay_hud()
	var is_new_best: bool = not PlayerProgress.is_level_cleared(_current_level.resource_path) or _run_total_darts < PlayerProgress.get_fewest_darts(_current_level.resource_path)
	PlayerProgress.record_level_clear(_current_level, _run_total_darts)
	game_over_screen.show_victory(_current_level.display_name, _run_total_darts, is_new_best)


## Update the persistent boss status display and background tint on the HUD.
func _update_boss_status() -> void:
	if boss_manager.is_boss_active():
		var def: BossDefinition = boss_manager.get_active_boss_definition()
		var boss: Boss = boss_manager.get_active_boss()
		hud.show_boss_status(def.display_name, boss.get_status_text(), def.status_color)
		hud.show_boss_background_tint(def.background_tint)
	else:
		hud.hide_boss_status()


## Build the game_state dictionary passed to boss lifecycle hooks.
func _build_game_state() -> Dictionary:
	return {
		"x01_game": x01_game,
		"scoring_modifier_manager": scoring_modifier_manager,
		"dartboard": dartboard,
		"hud": hud,
		"throw_mechanic": throw_mechanic,
	}


## Build the run_state dictionary passed to reward apply/is_applicable.
func _build_run_state() -> Dictionary:
	return {
		"x01_game": x01_game,
		"scoring_modifier_manager": scoring_modifier_manager,
		"main": self,
		"active_rewards": _active_rewards,
	}


## Build the snapshot MapGraph.generate_next_act consults for state-gated placement
## (slice 3 §3.6): the currently-available brush colors (so a brush event only spawns
## where it can pay off) and the highest score cleared. Syncs brush affinity first so the
## colors reflect freshly-owned color modifiers.
func _build_map_run_state() -> Dictionary:
	_sync_brush_affinity()
	return {
		"available_brush_colors": ModifierRegistry.available_brush_colors.duplicate(),
		"highest_cleared": _highest_cleared,
	}


## Called when the player picks a boss reward.
func _on_reward_selected(index: int) -> void:
	if index < 0 or index >= _current_rewards.size():
		return
	var reward: RuleModifierReward = _current_rewards[index]
	reward.apply(_build_run_state())
	_active_rewards.append(reward)
	hud.add_legendary(reward)
	_current_rewards.clear()
	_boss_leg_just_cleared = false

	# Some relics (Mirror Zone) require the player to pick wedges to flip before
	# continuing. Drop into the relic-flip picker; it resumes via _continue_after_reward.
	var flips: int = reward.wedge_flips_granted()
	if flips > 0:
		_start_relic_flip_picker(flips)
		return

	_continue_after_reward()


## Resume the post-reward flow (enter shop or show the next-leg button). Shared by
## the normal reward path and the relic-flip picker once all flips are placed.
func _continue_after_reward() -> void:
	# Post-boss shopping is now a map routing choice (a shop node after the boss),
	# not an automatic appendage. Surface the Next Leg button → map.
	_leg_phase = ""
	hud.score_label.text = ""
	hud.next_leg_button.visible = true


## Begin the Mirror-Zone relic's wedge-flip picker. The player must pick `count`
## wedges to flip — there is no cancel (the relic can't exist without its flips).
func _start_relic_flip_picker(count: int) -> void:
	_relic_flips_remaining = count
	_leg_phase = "relic_flip_picker"
	_picker_selected_wedge = -1
	dartboard.set_picker_mode(true)
	_update_relic_flip_picker_prompt()


func _update_relic_flip_picker_prompt() -> void:
	hud.show_picker_header("Mirror Zone — flip your wedges")
	hud.show_picker_prompt("Pick a wedge to flip (%d left)" % _relic_flips_remaining)


## Place one flipped wedge during the relic picker. Advances to the next pick or
## resumes the post-reward flow once all flips are placed.
func _complete_relic_flip(wedge_idx: int) -> void:
	# Don't let the player spend both flips on the same wedge — the relic flips two.
	if scoring_modifier_manager.get_flipped_wedge_indices().has(wedge_idx):
		hud.show_picker_prompt("That wedge is already flipped — pick another (%d left)" % _relic_flips_remaining)
		return
	var flip: FlipSignModifier = FlipSignModifier.new()
	flip.target_wedge_index = wedge_idx
	var value: int = scoring_modifier_manager.get_effective_value(wedge_idx)
	flip.modifier_name = "Flipped Wedge (%d)" % value
	flip.description = "Wedge %d's scoring now adds to the score" % value
	add_scoring_modifier(flip, {"wedge_index": wedge_idx})
	_relic_flips_remaining -= 1
	if _relic_flips_remaining > 0:
		_update_relic_flip_picker_prompt()
		return
	dartboard.set_picker_mode(false)
	hud.hide_picker()
	_leg_phase = ""
	_continue_after_reward()


## Reset all run state (shared by all post-game-over paths).
func _reset_run_state() -> void:
	AuidoManager.transition_to_menu_music()
	_run_over = false
	_turn_score = 0
	_turn_darts_scored = 0
	_run_total_darts = 0
	_leg_phase = ""
	_in_shop = false
	_banked_darts = 0
	_start_modifier_pending = false
	_current_level = null
	_active_rewards.clear()
	_current_rewards.clear()
	_boss_leg_just_cleared = false
	# Phase 02 challenge state.
	_highest_cleared = 0
	_challenge_active = false
	_active_challenge = null
	_challenge_deposit = 0
	_challenge_handicap = null
	_challenge_reward_pending = false
	x01_game.darts_per_turn = 3
	x01_game.max_turns = 5
	x01_game.dart_budget = 0
	x01_game.allow_triple_checkout = false
	x01_game.glass_cannon_active = false
	x01_game.bust_ends_turn = true
	# Base per-category streak capacity; the equipped build re-applies its grants on run
	# start (see _on_run_confirmed). reset_for_run() also resets this.
	scoring_modifier_manager.streak_capacity = {
		ScoringEnums.StreakCategory.WEDGE: 1,
		ScoringEnums.StreakCategory.COLOR: 1,
	}
	scoring_modifier_manager.allow_triple_checkout = false
	scoring_modifier_manager.glass_cannon_active = false
	shop_cadence = _default_shop_cadence
	shop_pick_count = 2
	ModifierRegistry.current_rarity_shift = 0.0
	boss_manager.configure_for_level(null)
	_map_graph = null
	if map_view != null:
		map_view.visible = false
	dartboard.clear_boss_overlays()
	dartboard.clear_illumination()
	_checkout_paths.clear()
	_selected_path_index = -1
	hud.update_turn_score(0)
	hud.hide_picker()
	hud.hide_target_tooltip()
	dartboard.clear_declared_target()
	dartboard.clear_shop_spots()
	scoring_modifier_manager.reset_for_run()
	hud.clear_modifier_panel()
	hud.clear_legendary_panel()
	hud.clear_modifier_status()
	hud.clear_streak_section()
	_sync_board_state()
	_clear_darts()
	if dartboard.picker_mode:
		dartboard.set_picker_mode(false)
	_restore_raw_stats()
	game_over_screen.visible = false


## Player presses "Return to Assembly" on the game over screen.
func _on_game_over_to_assembly() -> void:
	var level: LevelDefinition = _current_level
	_reset_run_state()
	_current_level = level
	_show_assembly()


## Player presses "Level Select" on the game over screen.
func _on_game_over_to_level_select() -> void:
	_reset_run_state()
	_show_level_select()


## Player presses "Main Menu" on the game over screen.
func _on_game_over_to_menu() -> void:
	_reset_run_state()
	_show_start_screen()


## Player presses "New Run" — start fresh after game over.
func _on_new_run() -> void:
	_reset_run_state()
	_show_start_screen()


# --- Shop System ---

## Start the shop phase. Called instead of normal upgrade picks on shop legs.
func _start_shop(response: Dictionary) -> void:
	_in_shop = true
	_shop_darts_remaining = _banked_darts
	_leg_phase = "shop"
	AuidoManager.on_shop_entered()
	UnlockManager.on_shop_opened()
	_clear_darts()
	dartboard.clear_checkout_segments()
	hud.enter_shop_mode(_shop_darts_remaining)

	# Cache stats so shop upgrade picks can show hover previews
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
	hud.cache_stats(current_stats, base_stats)

	# Slide board up off the top, then drop down from the top with shop spots
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var off_top: Vector2 = Vector2(center.x, -dartboard.board_radius * 2.0)

	var tween: Tween = create_tween()
	tween.tween_property(dartboard, "position", off_top, shop_transition_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_setup_shop_board.bind(response, off_top, center))


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


## Handle a throw during the shop phase — fly-in pre-step, then the shop impact.
func _on_shop_throw_completed(hit_position: Vector2) -> void:
	play_throw_anticipation(hit_position, dart_build.dart_outer_color, dart_build.dart_inner_color, _resolve_shop_impact.bind(hit_position))


## Shop landing flow: marker, thunk, segment flash, and shop spot/pick logic.
func _resolve_shop_impact(hit_position: Vector2) -> void:
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
		dartboard.deactivate_shop_spot(spot_idx, hit_position)
		var rarity: ScoringEnums.Rarity = spot["rarity"] as ScoringEnums.Rarity
		_shop_pick_items = _generate_shop_picks(rarity)
		_leg_phase = "shop_pick"

		# Build replacement warnings for modifier items
		var replacement_info: Array[String] = []
		for item: Dictionary in _shop_pick_items:
			if item["type"] == "modifier":
				var mod: ScoringModifier = item["data"] as ScoringModifier
				replacement_info.append(_get_replacement_text(mod))
			else:
				replacement_info.append("")
		hud.show_shop_pick_items(_shop_pick_items, _shop_darts_remaining, replacement_info)
	else:
		# Miss — continue or end
		hud.show_shop_header(_shop_darts_remaining)
		if _shop_darts_remaining <= 0:
			_end_shop_delayed()
		else:
			_enable_hover()
			_awaiting_next_dart = true
			_start_next_dart_timer()


func _get_owned_fingerprints() -> Array[String]:
	var result: Array[String] = []
	for mod: Resource in scoring_modifier_manager.active_modifiers:
		if mod is ScoringModifier:
			result.append((mod as ScoringModifier).get_config_fingerprint())
	return result


## Compute which brush colors are available based on owned color modifiers.
## Sets ModifierRegistry.available_brush_colors so BrushModifier.generate() can use it.
func _sync_brush_affinity() -> void:
	var colors: Array[ScoringEnums.SegmentColor] = []
	for m: Resource in scoring_modifier_manager.active_modifiers:
		if (m is ColorStreakModifier or m is ColorBonusModifier) and not m.target_color in colors:
			colors.append(m.target_color)
	ModifierRegistry.available_brush_colors = colors


## Generate 2 mixed shop picks (accuracy upgrades or modifiers) at a given rarity.
func _generate_shop_picks(rarity: ScoringEnums.Rarity) -> Array[Dictionary]:
	var picks: Array[Dictionary] = []

	_sync_brush_affinity()
	var weight_overrides: Dictionary = {}
	if dart_build.equipped_flight != null and dart_build.equipped_flight.shop_bias != null:
		weight_overrides = dart_build.equipped_flight.shop_bias.get_weight_overrides()
	# Gate brushes out of the pool when no color modifiers are owned
	if ModifierRegistry.available_brush_colors.is_empty():
		const _Brush = preload("res://scripts/modifiers/brush_modifier.gd")
		weight_overrides[_Brush] = 0.0

	var offered_mod_fingerprints: Array[String] = _get_owned_fingerprints()
	var offered_accuracy_keys: Array[String] = []

	for _i: int in range(shop_pick_count):
		# 50/50 chance of accuracy upgrade vs modifier (unless All In is active)
		if not all_in_active and randi_range(0, 1) == 0:
			var pick: Dictionary = _generate_shop_accuracy_pick(rarity, offered_accuracy_keys)
			offered_accuracy_keys.append(pick["data"].get("property", "") + "|" + str(rarity))
			picks.append(pick)
		else:
			var mods: Array[ScoringModifier] = ModifierRegistry.generate_distinct_at_rarity(1, rarity, weight_overrides, offered_mod_fingerprints)
			if mods.size() > 0:
				offered_mod_fingerprints.append(mods[0].get_config_fingerprint())
				picks.append({"type": "modifier", "data": mods[0]})
			else:
				var pick: Dictionary = _generate_shop_accuracy_pick(rarity, offered_accuracy_keys)
				offered_accuracy_keys.append(pick["data"].get("property", "") + "|" + str(rarity))
				picks.append(pick)

	return picks


## Generate a single accuracy upgrade pick at a given rarity tier.
func _generate_shop_accuracy_pick(rarity: ScoringEnums.Rarity, forbidden_keys: Array[String] = []) -> Dictionary:
	var type_idx: int = randi_range(0, UPGRADE_TYPES.size() - 1)
	var upgrade_type: Dictionary = UPGRADE_TYPES[type_idx]
	if forbidden_keys.size() > 0:
		var attempts: int = 0
		while (upgrade_type["property"] + "|" + str(rarity)) in forbidden_keys and attempts < 8:
			type_idx = randi_range(0, UPGRADE_TYPES.size() - 1)
			upgrade_type = UPGRADE_TYPES[type_idx]
			attempts += 1

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
		"penalty_amount": rarity_entry.get("penalty", 0),
	}

	return {"type": "upgrade", "data": upgrade}


## Player picks an item from the shop's 2-of-2 menu.
func _on_shop_pick_selected(index: int) -> void:
	var item: Dictionary = _shop_pick_items[index]

	if item["type"] == "upgrade":
		_apply_upgrade(item["data"])
		_update_stats_display()
		_recache_stats()
		_continue_shop_after_pick()
		return

	# Modifier pick
	var modifier: ScoringModifier = item["data"] as ScoringModifier

	# Check for multi-conflict streak replacement before adding
	var conflicts: Array = scoring_modifier_manager.get_streak_conflicts(modifier)
	if conflicts.size() > 1:
		_show_streak_replace_chooser(modifier, {}, conflicts)
		return

	if modifier.config_type == ScoringEnums.ConfigType.NONE:
		add_scoring_modifier(modifier, {})
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_WEDGE:
		_pending_modifier = modifier
		_leg_phase = "wedge_picker"
		_picker_selected_wedge = -1
		dartboard.set_picker_mode(true)
		hud.show_picker_header(modifier.get_pick_wedge_header())
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
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_SEGMENT:
		_pending_modifier = modifier
		_leg_phase = "segment_picker"
		dartboard.set_segment_picker_mode(true)
		_show_segment_picker_header(modifier)
		hud.show_picker_prompt("Hover over a segment and click to select")
		return

	_continue_shop_after_pick()


## Continue the shop after a pick is resolved (including wedge picker). This is the single
## chokepoint every pick path (direct, wedge/segment/streak config) funnels through, so a
## pending challenge reward (§6) finishes here and returns to the map instead of resuming a
## shop that isn't running.
func _continue_shop_after_pick() -> void:
	if _challenge_reward_pending:
		_challenge_reward_pending = false
		_shop_pick_items.clear()
		_finish_challenge_reward()
		return
	# A brush event pick (or its decline / wedge-config tail) funnels here too — finish the
	# event and return to the map rather than resuming a shop that isn't running. 03 §5.
	if _event_pending:
		_finish_event()
		return
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


## Finalize the shop and return to the map. A shop is its own node now, so leaving
## it does NOT advance a leg — the player picks the next encounter from the map.
func _end_shop(response: Dictionary) -> void:
	_in_shop = false
	# Persist the bank: keep whatever darts went unspent in the shop. The seed at
	# _start_shop was _banked_darts, untouched during the shop, so the leftover
	# (_shop_darts_remaining) is exactly bank-minus-spent.
	_banked_darts = _shop_darts_remaining
	_shop_lit_spots.clear()
	_leg_phase = ""
	AuidoManager.on_shop_exited()
	_clear_darts()
	hud.exit_shop_mode()
	UnlockManager.on_shop_closed()

	# Slide the board up off the top, clear the shop, drop it back to centre, then
	# show the map for the next pick (no leg advance — the shop was the encounter).
	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size / 2.0
	var off_top: Vector2 = Vector2(center.x, -dartboard.board_radius * 2.0)

	var tween: Tween = create_tween()
	tween.tween_property(dartboard, "position", off_top, shop_transition_duration * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		dartboard.clear_shop_spots()
		dartboard.position = off_top
		_awaiting_next_leg = false
		_update_all_hud()
		_sync_board_state()
		_update_checkout_highlights()
	)
	tween.tween_property(dartboard, "position", center, shop_transition_duration * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_show_map)


# ── Tutorial system ───────────────────────────────────────────────────────

## Create and wire all tutorial system nodes (called once in _ready).
func _setup_tutorial_system() -> void:
	# Ghost dart layer — sibling of DartContainer, draws under landed darts
	ghost_dart_layer = GhostDartLayer.new()
	ghost_dart_layer.name = "GhostDartLayer"
	add_child(ghost_dart_layer)
	move_child(ghost_dart_layer, dart_container.get_index())

	# Tutorial controller — orchestrates the mechanics tutorial
	tutorial_controller = TutorialController.new()
	tutorial_controller.name = "TutorialController"
	tutorial_controller.throw_mechanic = throw_mechanic
	tutorial_controller.dartboard = dartboard
	tutorial_controller.ghost_dart_layer = ghost_dart_layer
	tutorial_controller.hud = hud
	tutorial_controller.tutorial_finished.connect(_on_tutorial_finished)
	tutorial_controller.request_rules.connect(_on_tutorial_request_rules)
	add_child(tutorial_controller)

	# Start screen — lives in the HUD canvas layer
	start_screen = StartScreen.new()
	start_screen.name = "StartScreen"
	start_screen.start_game_pressed.connect(_on_start_game)
	start_screen.play_tutorial_pressed.connect(_on_play_tutorial.bind("start_screen"))
	start_screen.stats_walkthrough_pressed.connect(_on_play_tutorial.bind("start_screen", TutorialController.TutorialMode.STATS_ONLY))
	start_screen.rules_pressed.connect(_on_show_rules)
	start_screen.visible = false
	hud.add_child(start_screen)

	# Level select screen — primary entry point, replaces start screen
	level_select = LevelSelectScreen.new()
	level_select.name = "LevelSelectScreen"
	level_select.levels = [
		preload("res://resources/levels/level_501.tres"),
		preload("res://resources/levels/level_1001.tres"),
		preload("res://resources/levels/level_1501.tres"),
	]
	level_select.level_selected.connect(_on_level_selected)
	level_select.back_pressed.connect(_on_level_select_back)
	level_select.visible = false
	hud.add_child(level_select)

	# Run map overlay — shown between encounters, lets the player pick the next node.
	map_view = MapView.new()
	map_view.name = "MapView"
	map_view.node_chosen.connect(_on_map_node_chosen)
	map_view.visible = false
	hud.add_child(map_view)

	# Challenge entry / deposit picker overlay (Phase 02). Shown on arriving at a
	# challenge node; emits the chosen wager or a skip.
	_challenge_entry_view = ChallengeEntryView.new()
	_challenge_entry_view.name = "ChallengeEntryView"
	_challenge_entry_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_challenge_entry_view.confirmed.connect(_on_challenge_confirmed)
	_challenge_entry_view.skipped.connect(_on_challenge_skipped)
	_challenge_entry_view.visible = false
	hud.add_child(_challenge_entry_view)

	# Boss manager — handles boss scheduling and lifecycle
	boss_manager = BossManager.new()
	boss_manager.name = "BossManager"
	add_child(boss_manager)

	# Welcome modal — lives in the HUD canvas layer
	welcome_modal = WelcomeModal.new()
	welcome_modal.name = "WelcomeModal"
	welcome_modal.tutorial_chosen.connect(_on_play_tutorial.bind("start_screen"))
	welcome_modal.skip_chosen.connect(_on_welcome_skipped)
	welcome_modal.visible = false
	hud.add_child(welcome_modal)

	# Rules slideshow — lives in the HUD canvas layer
	rules_slideshow = RulesSlideshow.new()
	rules_slideshow.name = "RulesSlideshow"
	rules_slideshow.dartboard = dartboard
	rules_slideshow.slideshow_closed.connect(_on_rules_closed)
	rules_slideshow.visible = false
	hud.add_child(rules_slideshow)

	# Tutorial callout — lives in the HUD canvas layer
	tutorial_callout = TutorialCallout.new()
	tutorial_callout.name = "TutorialCalloutLayer"
	tutorial_callout.visible = false
	hud.add_child(tutorial_callout)

	# Wire the callout to the controller
	tutorial_controller.callout = tutorial_callout

	# Game over screen — lives in the HUD canvas layer
	game_over_screen = GameOverScreen.new()
	game_over_screen.name = "GameOverScreen"
	game_over_screen.return_to_assembly_pressed.connect(_on_game_over_to_assembly)
	game_over_screen.return_to_level_select_pressed.connect(_on_game_over_to_level_select)
	game_over_screen.return_to_menu_pressed.connect(_on_game_over_to_menu)
	game_over_screen.visible = false
	hud.add_child(game_over_screen)

	# Unlock notification queue — lives in the HUD canvas layer
	var unlock_queue: UnlockNotificationQueue = UnlockNotificationQueue.new()
	unlock_queue.name = "UnlockNotificationQueue"
	hud.add_child(unlock_queue)


## Show the start screen, hiding other overlays.
func _show_start_screen() -> void:
	assembly_screen.visible = false
	level_select.visible = false
	start_screen.visible = true
	welcome_modal.visible = false
	rules_slideshow.visible = false
	_hide_gameplay_hud()


## Show the level select screen between start screen and assembly.
func _show_level_select() -> void:
	start_screen.visible = false
	assembly_screen.visible = false
	level_select.refresh()
	level_select.visible = true
	_hide_gameplay_hud()


## Hide gameplay-specific HUD elements (score, turn, dart labels etc).
func _hide_gameplay_hud() -> void:
	hud.score_label.visible = false
	hud.instruction_label.visible = false
	hud.remaining_label.visible = false
	hud.turn_label.visible = false
	hud.dart_label.visible = false
	hud.leg_label.visible = false
	hud.bust_label.visible = false
	hud.turn_score_label.visible = false
	hud.stats_container.visible = false
	hud.modifier_panel.visible = false
	hud.dart_indicator.visible = false
	if hud._streak_section != null:
		hud._streak_section.visible = false
	hud.hide_boss_status()
	hud.hide_all_buttons()
	hud.upgrade_container.visible = false
	hud.hide_checkout_helper()
	dartboard.clear_illumination()


## Restore gameplay HUD elements after tutorial/start screen.
func _show_gameplay_hud() -> void:
	hud.score_label.visible = true
	hud.instruction_label.visible = true
	hud.remaining_label.visible = true
	hud.turn_label.visible = true
	hud.dart_label.visible = true
	hud.leg_label.visible = true
	hud.turn_score_label.visible = true
	hud.stats_container.visible = true
	hud.modifier_panel.visible = true
	hud.dart_indicator.visible = true


## Called when "Start Game" is pressed on the start screen.
func _on_start_game() -> void:
	_show_level_select()


## Called when a level card is pressed on the level select screen.
func _on_level_selected(level_def: LevelDefinition) -> void:
	_current_level = level_def
	level_select.visible = false
	_show_assembly()


## Called when the back button is pressed on the level select screen.
func _on_level_select_back() -> void:
	level_select.visible = false
	_show_start_screen()


## Called when "Play Tutorial" is pressed from start screen or assembly.
func _on_play_tutorial(source: String, mode: TutorialController.TutorialMode = TutorialController.TutorialMode.FULL) -> void:
	start_screen.visible = false
	level_select.visible = false
	assembly_screen.visible = false
	welcome_modal.visible = false
	_in_tutorial = true
	_hide_gameplay_hud()

	# Show an exit button during the tutorial
	_show_exit_tutorial_button()

	tutorial_controller.start_mechanics_tutorial(source, mode)


## Called when the tutorial finishes (player chose "Play a real game" or "Back to start").
func _on_tutorial_finished(destination: String) -> void:
	_in_tutorial = false
	_clear_darts()
	_hide_exit_tutorial_button()
	dartboard.clear_declared_target()

	if destination == "assembly":
		_show_assembly()
	else:
		_show_start_screen()


## Called when the tutorial requests opening the rules slideshow as a continuation.
func _on_tutorial_request_rules(destination: String) -> void:
	_in_tutorial = false
	_clear_darts()
	_hide_exit_tutorial_button()
	dartboard.clear_declared_target()
	rules_slideshow.show_slideshow_from_tutorial(destination)


## Called when "Rules of Darts" is pressed.
func _on_show_rules() -> void:
	rules_slideshow.show_slideshow()


## Called when the rules slideshow is closed.
func _on_rules_closed() -> void:
	dartboard.clear_tutorial_highlight()
	if rules_slideshow.launched_from_tutorial:
		var dest: String = rules_slideshow.tutorial_destination
		rules_slideshow.launched_from_tutorial = false
		rules_slideshow.tutorial_destination = ""
		_on_tutorial_finished(dest)


## Called when the welcome modal "No thanks" is chosen.
func _on_welcome_skipped() -> void:
	_show_start_screen()


## Show the "Exit Tutorial" button during tutorial sandbox.
var _exit_tutorial_button: Button = null

func _show_exit_tutorial_button() -> void:
	if _exit_tutorial_button != null:
		_exit_tutorial_button.visible = true
		return
	_exit_tutorial_button = Button.new()
	_exit_tutorial_button.text = "Exit Tutorial"
	_exit_tutorial_button.add_theme_font_size_override("font_size", 14)
	_exit_tutorial_button.position = Vector2(1140.0, 16.0)
	_exit_tutorial_button.custom_minimum_size = Vector2(120.0, 32.0)
	_exit_tutorial_button.pressed.connect(func() -> void:
		tutorial_controller.stop_tutorial()
		_on_tutorial_finished("start_screen" if tutorial_controller.entry_source == "start_screen" else "assembly")
	)
	hud.add_child(_exit_tutorial_button)


## Hide the "Exit Tutorial" button.
func _hide_exit_tutorial_button() -> void:
	if _exit_tutorial_button != null:
		_exit_tutorial_button.visible = false


## Show the dart assembly screen before starting a run.
func _show_assembly() -> void:
	start_screen.visible = false
	level_select.visible = false
	_show_gameplay_hud()
	assembly_screen.show_assembly(_raw_stats)


## Called when the player confirms their dart build on the assembly screen.
func _on_run_confirmed() -> void:
	dart_build.apply_to_throw_mechanic(throw_mechanic, _raw_stats)
	# Streak-slot capacity is sourced from the equipped components: shaft → wedge slots,
	# barrel → color slots (base 1 each). This sets the build's scaling ceiling for the run.
	scoring_modifier_manager.streak_capacity = dart_build.get_streak_capacity()
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
	AuidoManager.transition_to_game_music()

	_run_total_darts = 0
	x01_game.darts_per_turn = 3
	x01_game.allow_triple_checkout = false
	x01_game.glass_cannon_active = false
	scoring_modifier_manager.allow_triple_checkout = false
	scoring_modifier_manager.glass_cannon_active = false
	ModifierRegistry.current_rarity_shift = _current_level.rarity_weight_shift if _current_level != null else 0.0
	UnlockManager.bind_registry(dart_component_registry)
	UnlockManager.on_run_started()
	if _current_level != null:
		boss_manager.configure_for_level(_current_level)
	x01_game.start_run()

	# Generate the run map and step onto its start node (leg 1). The start node's
	# tier matches start_run()'s target, so the engine and map agree on leg 1; the
	# map only drives picks from the second encounter onward.
	var run_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	run_rng.randomize()
	_map_graph = MapGraph.generate(_current_level, run_rng, x01_game.starting_target, x01_game.target_increment)
	_map_graph.advance_to(_map_graph.start_id)

	# Challenge-node state: anchor starts at leg-1's target (the lowest score in play) and
	# climbs with every banked win; the roll RNG is run-scoped so each node anchors fresh.
	_highest_cleared = x01_game.starting_target
	_challenge_rng.randomize()
	_event_rng.randomize()

	# Debug: skip to the boss leg by jumping to the final leg's target
	if debug_boss_immediately and _current_level != null:
		var final_target: int = _current_level.max_score_target
		x01_game.current_leg = (final_target - x01_game.starting_target) / x01_game.target_increment + 1
		x01_game.target_score = final_target
		x01_game.remaining_score = final_target
		x01_game.score_at_turn_start = final_target

	_update_all_hud()
	_update_checkout_highlights()

	# Start boss if the initial leg is a boss leg (debug skip or future multi-boss levels)
	if boss_manager.is_boss_leg(x01_game.current_leg):
		var game_state: Dictionary = _build_game_state()
		var boss_def: BossDefinition = boss_manager.start_boss_leg(game_state)
		boss_manager.on_turn_start(game_state)
		_sync_board_and_solver()
		_update_boss_status()
		_update_all_hud()
		var announce_tween: Tween = hud.show_boss_announcement(boss_def.display_name, boss_def.description, boss_def.title_color, boss_def.description_color)
		announce_tween.tween_callback(_start_new_throw)
	elif debug_start_with_modifier:
		_start_modifier_pending = true
		_leg_phase = "modifier_pick"
		_current_modifiers = []
		_sync_brush_affinity()
		var generated: Array[ScoringModifier] = ModifierRegistry.generate_distinct(3, _get_owned_fingerprints())
		for mod: ScoringModifier in generated:
			_current_modifiers.append(mod)

		# Build replacement info for each modifier choice
		var replacement_info: Array[String] = []
		for mod: ScoringModifier in _current_modifiers:
			replacement_info.append(_get_replacement_text(mod))
		hud.show_modifier_choices_with_replacement(_current_modifiers, replacement_info)
	else:
		_start_new_throw()


## Player picks an accuracy upgrade card.
func _on_upgrade_selected(index: int) -> void:
	_apply_upgrade(_current_upgrades[index])
	_update_stats_display()

	# An EVENT accuracy pick is a standalone free trade — apply it and go straight back to
	# the map (no per-leg modifier-pick chain; that drip was removed with the per-leg pick).
	if _event_pending:
		_recache_stats()
		_finish_event()
		return

	# Move to Phase 2: modifier pick
	_leg_phase = "modifier_pick"
	_current_modifiers = []
	_sync_brush_affinity()
	var generated: Array[ScoringModifier] = ModifierRegistry.generate_distinct(3, _get_owned_fingerprints())
	for mod: ScoringModifier in generated:
		_current_modifiers.append(mod)

	# Build replacement info for each modifier choice. Use _get_replacement_text() (like every
	# other call site) so the warning is correct at any capacity — including the multi-conflict
	# "Choose streak to replace" case, which singular get_streak_conflict() returns null for.
	var replacement_info: Array[String] = []
	for mod: ScoringModifier in _current_modifiers:
		replacement_info.append(_get_replacement_text(mod))
	hud.show_modifier_choices_with_replacement(_current_modifiers, replacement_info)


## Player picks a scoring modifier card.
func _on_modifier_selected(index: int) -> void:
	# Shop pick, the challenge typed-reward pick, AND the brush event pick all populate
	# _shop_pick_items and reuse the shop selection path (none but the shop is in a shop,
	# hence the extra flags). §6 / 03 §5.
	if _in_shop or _challenge_reward_pending or _event_pending:
		_on_shop_pick_selected(index)
		return

	var modifier: ScoringModifier = _current_modifiers[index]

	# Check for multi-conflict streak replacement before adding
	var conflicts: Array = scoring_modifier_manager.get_streak_conflicts(modifier)
	if conflicts.size() > 1:
		_show_streak_replace_chooser(modifier, {}, conflicts)
		return

	if modifier.config_type == ScoringEnums.ConfigType.NONE:
		add_scoring_modifier(modifier, {})
		_leg_phase = ""
		if _start_modifier_pending:
			_start_modifier_pending = false
			_start_new_throw()
		else:
			hud.score_label.text = ""
			hud.next_leg_button.visible = true
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_WEDGE:
		_pending_modifier = modifier
		_leg_phase = "wedge_picker"
		_picker_selected_wedge = -1
		dartboard.set_picker_mode(true)
		hud.show_picker_header(modifier.get_pick_wedge_header())
		hud.show_picker_prompt("Hover over a wedge and click to select")
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_TWO_WEDGES:
		_pending_modifier = modifier
		_leg_phase = "wedge_picker"
		_picker_selected_wedge = -1
		dartboard.set_picker_mode(true)
		hud.show_picker_header("Swap two wedges")
		hud.show_picker_prompt("Click to select the first wedge")
	elif modifier.config_type == ScoringEnums.ConfigType.PICK_SEGMENT:
		_pending_modifier = modifier
		_leg_phase = "segment_picker"
		dartboard.set_segment_picker_mode(true)
		_show_segment_picker_header(modifier)
		hud.show_picker_prompt("Hover over a segment and click to select")


## Player skips the scoring modifier pick.
func _on_modifier_skipped() -> void:
	# Declining the earned typed reward — or a free brush event trade — is allowed; it funnels
	# through the same chokepoint, which returns to the map (the offer was free, not forced).
	if _in_shop or _challenge_reward_pending or _event_pending:
		_continue_shop_after_pick()
		return
	_leg_phase = ""
	if _start_modifier_pending:
		_start_modifier_pending = false
		_start_new_throw()
	else:
		hud.score_label.text = ""
		hud.next_leg_button.visible = true


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


## Second-pass throw modifier evaluation after the player places the aim crosshair.
## Reverts the first-pass bonuses, rebuilds context with declared_target and
## active_streak_modifiers, then re-evaluates and reapplies.
func _evaluate_aim_placed_bonuses(declared_target: Dictionary) -> void:
	_revert_temp_bonuses()

	var context: Dictionary = {
		"remaining_score": x01_game.remaining_score,
		"target_score": x01_game.target_score,
		"darts_this_turn": x01_game.darts_this_turn,
		"current_turn": x01_game.current_turn,
		"current_leg": x01_game.current_leg,
		"max_turns": x01_game.max_turns,
		"declared_target": declared_target,
		"active_streak_modifiers": scoring_modifier_manager.get_active_streak_modifiers(),
	}

	var result: Dictionary = dart_build.evaluate_throw_modifiers(context)
	_temp_throw_bonuses = result["bonuses"]
	_active_throw_modifier_names = result["activated"]
	_apply_temp_bonuses()
	_update_stats_display()
	hud.update_modifier_status(_active_throw_modifier_names)


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
			"penalty_amount": rarity.get("penalty", 0),
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
		# Speed card values are in display units (0-100); convert to the 1.0-5.0 internal scale.
		# This is the inverse of hud._speed_to_display: 1 display point = 4/100 internal.
		var internal_boost: float = float(upgrade["value"]) * (4.0 / 100.0)
		var current: float = throw_mechanic.get(upgrade["property"])
		var new_value: float = minf(current + internal_boost, 5.0)
		throw_mechanic.set(upgrade["property"], new_value)

	# Apply tradeoff penalty if applicable. Speed penalties use the same display->internal scaling
	# as the speed boost above, or the penalty would be on a different scale than the stat. Floor at
	# 1.0 (the documented worst) so a hard specialization saturates the sibling axis instead of
	# going negative — the mirror of the boost clamping at 100.0 / 5.0.
	if upgrade["tradeoff"]:
		var penalty_current: float = throw_mechanic.get(upgrade["penalty_property"])
		var penalty_delta: float = float(upgrade["penalty_amount"])
		if upgrade["scale"] == "speed":
			penalty_delta *= (4.0 / 100.0)
		var new_penalty_value: float = maxf(penalty_current - penalty_delta, 1.0)
		throw_mechanic.set(upgrade["penalty_property"], new_penalty_value)


## Update all HUD elements to reflect current game state.
func _update_all_hud() -> void:
	hud.update_leg(x01_game.current_leg, x01_game.target_score, boss_manager.is_boss_active())
	hud.update_turn(x01_game.current_turn, x01_game.max_turns)
	hud.update_remaining(x01_game.remaining_score, x01_game.glass_cannon_active)
	hud.update_darts(x01_game.darts_per_turn - x01_game.darts_this_turn, x01_game.current_turn == x01_game.max_turns, x01_game.darts_per_turn)
	hud.update_bank(_banked_darts)
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


func _recache_stats() -> void:
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
	hud.cache_stats(current_stats, base_stats)


## Recalculate and update which double segments would win the current leg.
## Also updates the remaining score color — gold when a single-dart checkout exists.
## Skipped during shop mode (no scoring in the shop).
func _update_checkout_highlights() -> void:
	if _in_shop:
		return
	# Under Prism the board recolors reactively, so color/value can't be trusted —
	# suppress the checkout hints entirely (the uncertainty is the boss).
	if boss_manager.get_active_boss() is PrismBoss:
		dartboard.set_checkout_segments([] as Array[Dictionary])
		hud.set_remaining_checkout_available(false)
		return
	var remaining: int = x01_game.remaining_score
	var checkout_segments: Array[Dictionary] = scoring_modifier_manager.calculate_checkout_segments(remaining)
	# Defense-in-depth: drop any segment that would actually bust when thrown
	var verified: Array[Dictionary] = []
	for seg: Dictionary in checkout_segments:
		var synth: Dictionary = _synthesize_checkout_segment(seg)
		if synth.is_empty():
			verified.append(seg)
			continue
		var modified: Dictionary = scoring_modifier_manager.process_score(synth, true)
		if not _would_bust(modified):
			verified.append(seg)
	dartboard.set_checkout_segments(verified)
	hud.set_remaining_checkout_available(verified.size() > 0)


## Update the checkout helper panel with solver results.
## Runs the solver for the current remaining score and darts left.
func _update_checkout_helper() -> void:
	if _in_shop:
		hud.hide_checkout_helper()
		dartboard.clear_illumination()
		return

	# Under Prism the board recolors reactively — the checkout helper goes dark
	# because color/value can no longer be trusted.
	if boss_manager.get_active_boss() is PrismBoss:
		hud.hide_checkout_helper()
		dartboard.clear_illumination()
		return

	var _perf_start: int = Time.get_ticks_usec() if scoring_modifier_manager.debug_perf_log else 0

	var remaining: int = x01_game.remaining_score
	var darts_left: int = x01_game.darts_per_turn - x01_game.darts_this_turn

	# Check if the player has any unlocked (toggleable) modifiers (for the hint)
	var has_toggleable: bool = false
	for modifier: Resource in scoring_modifier_manager.active_modifiers:
		if modifier is ScoringModifier and modifier.toggleable:
			has_toggleable = true
			break

	var paths: Array[Array] = scoring_modifier_manager.solve_checkout(remaining, darts_left)

	# Cache paths and reset selection
	_checkout_paths = paths
	_selected_path_index = 0 if paths.size() > 0 else -1

	# Compute divergence map for necessity-gated ring labels
	var divergent_wedges: Dictionary = {}
	for path: Array in paths:
		for step: Dictionary in path:
			var target: Dictionary = step["target"]
			var ring: String = target.get("ring_name", "")
			if ring == "Inner Single" or ring == "Outer Single":
				var wi: int = target.get("wedge_index", -1)
				if wi >= 0 and not divergent_wedges.has(wi):
					divergent_wedges[wi] = scoring_modifier_manager.singles_diverge(wi)

	if paths.size() > 0:
		hud.update_checkout_display(paths, has_toggleable, divergent_wedges, _selected_path_index)
		_update_illumination()
	else:
		hud.update_checkout_display(paths, has_toggleable, divergent_wedges, -1)
		dartboard.clear_illumination()
		var setup: Dictionary = scoring_modifier_manager.get_setup_recommendation(remaining)
		hud.update_setup_display(setup, has_toggleable, divergent_wedges)

	if scoring_modifier_manager.debug_perf_log:
		var ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0
		print("[PERF] _update_checkout_helper r=%d darts_left=%d  %.1fms" % [remaining, darts_left, ms])


## Recompute and push illumination segments for the selected path's first step.
func _update_illumination() -> void:
	if not illumination_enabled or _selected_path_index < 0 or _selected_path_index >= _checkout_paths.size():
		dartboard.clear_illumination()
		return
	var path: Array = _checkout_paths[_selected_path_index]
	if path.is_empty():
		dartboard.clear_illumination()
		return
	var target_score: int = path[0]["result"]["total_score"]
	var is_finish: bool = path.size() == 1
	var equivalents: Array[Dictionary] = scoring_modifier_manager.find_equivalent_segments(target_score, is_finish)
	dartboard.set_illumination_segments(equivalents, is_finish)


## Called when a checkout path line is clicked in the HUD.
func _on_checkout_path_clicked(index: int) -> void:
	if index < 0 or index >= _checkout_paths.size():
		return
	_selected_path_index = index
	hud.set_selected_path(index)
	_update_illumination()


## Called when a modifier is toggled on/off — recompute checkout helper and streak display.
func _on_modifier_toggled() -> void:
	scoring_modifier_manager._bump_state_version()
	scoring_modifier_manager.invalidate_preferred_remainders()
	_update_checkout_highlights()
	_update_checkout_helper()
	hud.update_streak_section(
		scoring_modifier_manager.get_active_streak_modifiers(),
		scoring_modifier_manager.effective_wedge_values
	)


## Build a synthetic score result from a checkout segment marker for verification.
## Returns empty dict for bull types (always safe, no ring ambiguity).
func _synthesize_checkout_segment(seg: Dictionary) -> Dictionary:
	var seg_type: String = seg["type"]
	if seg_type == "double_bull" or seg_type == "single_bull":
		return {}
	var wedge_idx: int = seg["wedge_idx"]
	var face_value: int = scoring_modifier_manager.effective_wedge_values[wedge_idx]
	var colors: Dictionary = scoring_modifier_manager.effective_wedge_colors[wedge_idx]
	var ring_name: String
	var multiplier: int
	var ring_key: String
	match seg_type:
		"wedge":
			ring_name = "Double"
			multiplier = 2
			ring_key = "double"
		"triple_wedge":
			ring_name = "Triple"
			multiplier = 3
			ring_key = "triple"
		"single_wedge":
			ring_key = seg.get("ring_key", "outer_single")
			if ring_key == "inner_single":
				ring_name = "Inner Single"
			else:
				ring_name = "Outer Single"
			multiplier = 1
		_:
			return {}
	return {
		"face_value": face_value,
		"multiplier": multiplier,
		"total_score": face_value * multiplier,
		"ring_name": ring_name,
		"wedge_index": wedge_idx,
		"segment_color": colors.get(ring_key, -1),
		"is_bull": false,
	}


func _would_bust(result: Dictionary) -> bool:
	var points: int = result["total_score"]
	var new_remaining: int = x01_game.remaining_score - points
	if new_remaining < 0:
		return true
	if new_remaining == 1 and not x01_game.glass_cannon_active:
		return true
	if new_remaining == 0:
		var ring_name: String = result.get("ring_name", "")
		var is_double: bool = ring_name == "Double" or ring_name == "Double Bull"
		var is_triple: bool = ring_name == "Triple"
		var is_valid: bool = is_double or (x01_game.allow_triple_checkout and is_triple) or x01_game.glass_cannon_active
		if not is_valid:
			return true
	return false


## Check if a hovered segment is one of the checkout-winning doubles.
## Uses the same checkout list that drives the board highlights and gold score.
func _is_checkout_segment(result: Dictionary) -> bool:
	if result["total_score"] != x01_game.remaining_score:
		return false
	var checkout_segments: Array[Dictionary] = scoring_modifier_manager.calculate_checkout_segments(x01_game.remaining_score)
	var wedge_index: int = result.get("wedge_index", -1)
	var is_bull: bool = result.get("is_bull", false)
	var ring_name: String = result.get("ring_name", "")
	for seg: Dictionary in checkout_segments:
		if seg["type"] == "double_bull" and is_bull and ring_name == "Double Bull":
			return true
		if seg["type"] == "single_bull" and is_bull and ring_name == "Single Bull":
			return true
		if seg["type"] == "wedge" and seg["wedge_idx"] == wedge_index and ring_name == "Double":
			return true
		if seg["type"] == "triple_wedge" and seg["wedge_idx"] == wedge_index and ring_name == "Triple":
			return true
		if seg["type"] == "single_wedge" and seg["wedge_idx"] == wedge_index:
			var seg_ring: String = seg.get("ring_key", "outer_single")
			var hover_ring_key: String = "inner_single" if ring_name == "Inner Single" else "outer_single"
			if seg_ring == hover_ring_key:
				return true
	return false


## Push the modifier manager's effective wedge values and colors to the dartboard
## so it renders and scores correctly. Call after any modifier changes.
func _sync_board_state() -> void:
	dartboard.effective_wedge_values = scoring_modifier_manager.effective_wedge_values
	dartboard.effective_wedge_colors = scoring_modifier_manager.effective_wedge_colors
	dartboard.flipped_wedges = scoring_modifier_manager.get_flipped_wedge_indices()
	dartboard.hotspot_rings = scoring_modifier_manager.hotspot_rings
	dartboard.queue_redraw()


## Sync board state and rebuild the checkout solver after boss mutations.
func _sync_board_and_solver() -> void:
	_sync_board_state()
	if scoring_modifier_manager._state_version == scoring_modifier_manager._last_sync_version:
		return
	scoring_modifier_manager._build_solver_candidates()
	scoring_modifier_manager.invalidate_preferred_remainders()
	scoring_modifier_manager._last_sync_version = scoring_modifier_manager._state_version


## Remove all dart markers from the board.
func _clear_darts() -> void:
	for child: Node in dart_container.get_children():
		child.queue_free()


## Refresh the recurring streak pulse on every board dart marker. A marker pulses while its landing
## spot is part of an active scoring streak (count >= 2), brightening grey -> white with the streak
## length. Called after each throw resolves (streak state is current by then); markers are cleared
## on turn/leg end, so broken-streak darts stop pulsing naturally.
func _refresh_streak_pulses() -> void:
	for child: Node in dart_container.get_children():
		var tgt: Variant = child.get("hit_target")
		if typeof(tgt) != TYPE_DICTIONARY or (tgt as Dictionary).is_empty():
			continue
		child.set("streak_level", scoring_modifier_manager.get_streak_level_for(tgt))


## Create a visual dart marker at the landing position.
func _place_dart(position: Vector2) -> Node2D:
	var dart: Node2D = Node2D.new()
	dart.position = position
	dart.set_script(preload("res://scripts/dart_marker.gd"))
	dart.set("dart_color", dart_build.dart_outer_color)
	dart.set("dart_inner_color", dart_build.dart_inner_color)
	dart.set("dart_size", dart_size)
	dart_container.add_child(dart)
	return dart


func _on_throw_state_changed(new_state: int) -> void:
	# Tutorial manages its own UI — skip normal state change handling
	if _in_tutorial:
		return

	# The Throw button only exists on touch devices, and only during AIMING.
	hud.set_throw_aim_button_visible(throw_mechanic.touch_mode and new_state == throw_mechanic.ThrowState.AIMING)

	match new_state:
		throw_mechanic.ThrowState.AIMING:
			_enable_hover()
			dartboard.clear_declared_target()
			_revert_temp_bonuses()
			_update_stats_display()
			var no_modifiers: Array[String] = []
			hud.update_modifier_status(no_modifiers)
			if throw_mechanic.touch_mode:
				hud.show_instruction("Drag to aim  |  tap Throw to place zone")
			else:
				hud.show_instruction("Move to aim, click to place zone")
		throw_mechanic.ThrowState.VERTICAL_RELEASE:
			_disable_hover()
			hud.clear_modifier_perkup()
			if throw_mechanic.touch_mode:
				hud.show_instruction("Tap to lock vertical")
			else:
				hud.show_instruction("Click or Space to lock vertical  |  Right-click or Esc to undo")
			# Declare target and show highlight
			var target: Dictionary = throw_mechanic._declared_target
			if not target.is_empty():
				dartboard.set_declared_target(target)
			else:
				dartboard.clear_declared_target()
			# Second-pass throw modifier evaluation with target context
			if not _in_shop and not _in_tutorial:
				_evaluate_aim_placed_bonuses(target)
		throw_mechanic.ThrowState.HORIZONTAL_RELEASE:
			_disable_hover()
			if throw_mechanic.touch_mode:
				hud.show_instruction("Tap to lock horizontal")
			else:
				hud.show_instruction("Click or Space to lock horizontal")
		throw_mechanic.ThrowState.RESOLVING:
			_disable_hover()
			hud.show_instruction("Releasing...")


func _unhandled_input(event: InputEvent) -> void:
	# --- Debug shortcuts ---
	# Only active in editor / debug builds. Stripped from shipped builds.
	# F9  → wipe all unlock state and career stats (lock everything back up).
	# F10 → unlock every registered component (preview full pool on assembly screen).
	# Effects are visible next time the assembly screen refreshes a slot.
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		# F9 or Cmd+Shift+R → reset all unlock state
		if event.keycode == KEY_F9 or (event.keycode == KEY_R and event.meta_pressed and event.shift_pressed):
			PlayerProgress.debug_reset_all()
			get_viewport().set_input_as_handled()
			return
		# F10 or Cmd+Shift+U → unlock all components
		elif event.keycode == KEY_F10 or (event.keycode == KEY_U and event.meta_pressed and event.shift_pressed):
			PlayerProgress.debug_unlock_all(dart_component_registry)
			get_viewport().set_input_as_handled()
			return

	# Scroll wheel / arrow keys to cycle selected checkout path
	if _leg_phase == "" and not _in_shop and not _in_tutorial and illumination_enabled and _checkout_paths.size() > 1:
		var path_delta: int = 0
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				path_delta = -1
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				path_delta = 1
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_UP or event.keycode == KEY_LEFT:
				path_delta = -1
			elif event.keycode == KEY_DOWN or event.keycode == KEY_RIGHT:
				path_delta = 1
		if path_delta != 0:
			_selected_path_index = (_selected_path_index + path_delta + _checkout_paths.size()) % _checkout_paths.size()
			hud.set_selected_path(_selected_path_index)
			_update_illumination()
			get_viewport().set_input_as_handled()
			return

	if _leg_phase == "segment_picker":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var seg: Dictionary = dartboard.get_segment_at_position(get_global_mouse_position())
			if seg.is_empty():
				return
			get_viewport().set_input_as_handled()
			_complete_pick_segment(seg)
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel_picker()
		return

	# Mirror-Zone relic: pick wedges to flip. No cancel — the relic always grants
	# its flips, so Escape is swallowed and only a wedge click advances.
	if _leg_phase == "relic_flip_picker":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var flip_idx: int = dartboard.get_wedge_at_position(get_global_mouse_position())
			if flip_idx < 0:
				return
			get_viewport().set_input_as_handled()
			_complete_relic_flip(flip_idx)
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
		return

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
	_pending_modifier.apply_picked_wedge(wedge_idx)
	add_scoring_modifier(_pending_modifier, {"wedge_index": wedge_idx})
	_finish_picker()


func _complete_pick_segment(seg: Dictionary) -> void:
	# Hotspots don't stack: a ring already carrying a hotspot is rejected (never a silent
	# downgrade). Keep the picker open so the player chooses a different ring.
	if _pending_modifier is HotspotModifier and scoring_modifier_manager.is_segment_hotspotted(seg["wedge_index"], seg["ring_key"]):
		var ring_display: String = RING_DISPLAY_NAMES.get(seg["ring_key"], seg["ring_key"])
		hud.show_picker_prompt("%s is already a hotspot — pick a different ring" % ring_display)
		return
	# Brush recolors animate; a hotspot doesn't change ring color, so skip the recolor flash.
	if not (_pending_modifier is HotspotModifier):
		dartboard.animate_color_transition()
	add_scoring_modifier(_pending_modifier, {"wedge_index": seg["wedge_index"], "ring_name": seg["ring_key"]})
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
	dartboard.set_segment_picker_mode(false)
	hud.hide_picker()
	_pending_modifier = null
	_picker_selected_wedge = -1

	if _in_shop:
		_leg_phase = "shop_pick"
		var shop_replace_info: Array[String] = []
		for item: Dictionary in _shop_pick_items:
			if item["type"] == "modifier":
				var mod: ScoringModifier = item["data"] as ScoringModifier
				shop_replace_info.append(_get_replacement_text(mod))
			else:
				shop_replace_info.append("")
		hud.show_shop_pick_items(_shop_pick_items, _shop_darts_remaining, shop_replace_info)
		return

	_leg_phase = "modifier_pick"

	# Rebuild replacement info when returning to modifier pick
	var replacement_info: Array[String] = []
	for mod: ScoringModifier in _current_modifiers:
		replacement_info.append(_get_replacement_text(mod))
	hud.show_modifier_choices_with_replacement(_current_modifiers, replacement_info)


func _finish_picker() -> void:
	dartboard.set_picker_mode(false)
	dartboard.set_segment_picker_mode(false)
	hud.hide_picker()
	_pending_modifier = null
	_picker_selected_wedge = -1
	# A challenge reward OR brush event modifier that needed board config (Hotspot / Wedge
	# Swap / Brush) finishes here too — route through the shared chokepoint back to the map.
	if _in_shop or _challenge_reward_pending or _event_pending:
		_continue_shop_after_pick()
		return
	_leg_phase = ""
	if _start_modifier_pending:
		_start_modifier_pending = false
		_start_new_throw()
	else:
		hud.score_label.text = ""
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
		hud.show_picker_prompt(_pending_modifier.get_pick_wedge_prompt(current_val))
	elif _pending_modifier.config_type == ScoringEnums.ConfigType.PICK_TWO_WEDGES:
		if _picker_selected_wedge < 0:
			var val: int = scoring_modifier_manager.get_effective_value(wedge_idx)
			hud.show_picker_prompt("Select %d? Click to pick first wedge" % val)
		elif wedge_idx != _picker_selected_wedge:
			var val1: int = scoring_modifier_manager.get_effective_value(_picker_selected_wedge)
			var val2: int = scoring_modifier_manager.get_effective_value(wedge_idx)
			hud.show_picker_prompt("Swap %d and %d? Click to confirm, Escape to cancel" % [val1, val2])


const RING_DISPLAY_NAMES: Dictionary = {
	"inner_single": "Inner Single",
	"triple": "Triple",
	"outer_single": "Outer Single",
	"double": "Double",
}

const COLOR_DISPLAY_NAMES: Dictionary = {
	ScoringEnums.SegmentColor.RED: "Red",
	ScoringEnums.SegmentColor.GREEN: "Green",
	ScoringEnums.SegmentColor.BLACK: "Black",
	ScoringEnums.SegmentColor.WHITE: "White",
}


func _show_segment_picker_header(modifier: ScoringModifier) -> void:
	hud.show_picker_header(modifier.get_pick_segment_header())


func _update_segment_picker_prompt(seg: Dictionary) -> void:
	if seg.is_empty():
		hud.show_picker_prompt("Hover over a segment and click to select")
		return
	var wedge_idx: int = seg["wedge_index"]
	var ring_key: String = seg["ring_key"]
	var ring_display: String = RING_DISPLAY_NAMES.get(ring_key, ring_key)
	# A hotspot can't stack on an already-hot ring — surface that on hover instead of a prompt.
	if _pending_modifier is HotspotModifier and scoring_modifier_manager.is_segment_hotspotted(wedge_idx, ring_key):
		hud.show_picker_prompt("%s %d is already a hotspot — pick a different ring" % [ring_display, scoring_modifier_manager.get_effective_value(wedge_idx)])
		return
	var value: int = scoring_modifier_manager.get_effective_value(wedge_idx)
	var current_color: ScoringEnums.SegmentColor = scoring_modifier_manager.get_effective_color(wedge_idx, ring_key)
	var color_name: String = COLOR_DISPLAY_NAMES.get(current_color, "?")
	hud.show_picker_prompt(_pending_modifier.get_pick_segment_prompt(ring_display, value, color_name))


func _spawn_floating_score(hit_position: Vector2, result: Dictionary, recession_data: Dictionary = {}, is_leg_won: bool = false, remaining_info: Dictionary = {}) -> Tween:
	var score: int = result["total_score"]
	if score == 0:
		return _spawn_zero_floating_score(hit_position)

	var modifications: Array = result.get("modifications", [])
	var multiplier_mods: Array[Dictionary] = []
	var is_flip: bool = false
	for mod: Dictionary in modifications:
		if mod["field"] == "multiplier":
			multiplier_mods.append(mod)
		elif mod["field"] == "flip":
			is_flip = true

	# Flipped wedges score negative; the multiplier countdown animation assumes a
	# positive subtract, so show flips with the simple float (final value shown directly).
	if multiplier_mods.is_empty() or is_flip:
		return _spawn_simple_floating_score(hit_position, result, recession_data, is_leg_won)
	else:
		return _spawn_trigger_animation(hit_position, result, multiplier_mods, recession_data, is_leg_won, remaining_info)


func _spawn_zero_floating_score(hit_position: Vector2) -> Tween:
	var label: Label = Label.new()
	label.text = "0"
	label.position = hit_position + Vector2(-10.0, -10.0)
	label.z_index = 100
	label.add_theme_font_size_override("font_size", score_font_size)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	label.pivot_offset = label.size / 2.0
	_score_layer.add_child(label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(25.0, -55.0), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	return tween


func _spawn_simple_floating_score(hit_position: Vector2, result: Dictionary, recession_data: Dictionary = {}, is_leg_won: bool = false) -> Tween:
	var has_recession: bool = not recession_data.is_empty()
	var actual_score: int = result["total_score"]
	var display_score: int = actual_score

	if has_recession:
		var original_face: int = recession_data["original_face_value"]
		var reduced_face: int = result["face_value"]
		if reduced_face > 0:
			display_score = int(actual_score * float(original_face) / float(reduced_face))

	var label: Label = _create_score_label(display_score, hit_position, result)
	label.pivot_offset = label.size / 2.0
	_score_layer.add_child(label)

	if is_leg_won:
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		AuidoManager.play_leg_win()

	if has_recession:
		var percent_text: String = "-%d%%" % int(recession_data["percent"] * 100)
		var scale_factor: float = 1.0 - recession_data["percent"]

		var recession_label: Label = Label.new()
		recession_label.text = percent_text
		recession_label.z_index = 101
		recession_label.add_theme_font_size_override("font_size", 22)
		recession_label.add_theme_constant_override("outline_size", 3)
		recession_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		recession_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		recession_label.position = hit_position + Vector2(50.0, -40.0)
		recession_label.modulate.a = 0.0
		_score_layer.add_child(recession_label)

		var tween: Tween = create_tween()
		tween.tween_interval(0.3)
		tween.tween_property(recession_label, "modulate:a", 1.0, 0.1)
		tween.tween_property(recession_label, "position", label.position, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.tween_callback(func() -> void:
			recession_label.queue_free()
			label.text = str(actual_score)
			label.scale = Vector2(scale_factor, scale_factor)
			AuidoManager.play_void_hit()
		)
		tween.tween_interval(0.2)
		tween.set_parallel(true)
		tween.tween_property(label, "position", label.position + Vector2(25.0, -55.0), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(label, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tween.set_parallel(false)
		tween.tween_callback(label.queue_free)
		return tween

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector2(25.0, -55.0), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	return tween


func _group_multiplier_mods(multiplier_mods: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var current_group: Dictionary = {}
	for mod: Dictionary in multiplier_mods:
		var mod_name: String = mod.get("source_name", "")
		if current_group.is_empty() or current_group["source_name"] != mod_name:
			current_group = {
				"source_name": mod_name,
				"source_modifier": mod.get("source_modifier", null),
				"source_rarity_color": mod.get("source_rarity_color", Color(0.8, 0.8, 0.8)),
				"mods": [] as Array[Dictionary],
				"total_contribution": 0,
			}
			groups.append(current_group)
		current_group["mods"].append(mod)
		current_group["total_contribution"] += 1
	return groups


func _create_source_label(group: Dictionary, start_position: Vector2) -> HBoxContainer:
	var container: HBoxContainer = HBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.z_index = 102
	container.position = start_position
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var source_mod: Resource = group.get("source_modifier", null)
	if source_mod != null and source_mod is ScoringModifier:
		var icon: ModifierIcon = ModifierIcon.new()
		icon.modifier = source_mod
		icon.custom_minimum_size = Vector2(20, 20)
		icon.size = Vector2(20, 20)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(icon)

	var text_label: Label = Label.new()
	var base_name: String = group["source_name"].split(" +")[0]
	var contribution: int = group["total_contribution"]
	text_label.text = "%s: +%dx!" % [base_name, contribution]
	text_label.add_theme_font_size_override("font_size", score_source_font_size)
	text_label.add_theme_constant_override("outline_size", 3)
	text_label.add_theme_color_override("font_color", group["source_rarity_color"])
	text_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(text_label)

	return container


func _spawn_trigger_animation(hit_position: Vector2, result: Dictionary, multiplier_mods: Array[Dictionary], recession_data: Dictionary = {}, is_leg_won: bool = false, remaining_info: Dictionary = {}) -> Tween:
	var has_recession: bool = not recession_data.is_empty()
	var face_value: int = result["face_value"]
	var display_face: int = face_value
	if has_recession:
		display_face = recession_data["original_face_value"]

	var base_score: int = display_face * int(multiplier_mods[0]["old_value"])
	var main_label: Label = _create_score_label(base_score, hit_position, result, score_trigger_font_size)
	main_label.pivot_offset = main_label.size / 2.0
	_score_layer.add_child(main_label)

	hud.hide_hover_tooltip()
	_trigger_anim_active = true

	# Remaining score countdown: show remaining after base score, then tick down per trigger
	var remaining_countdown: int = -1
	var gc: bool = remaining_info.get("glass_cannon", false)
	var is_bust_anim: bool = remaining_info.get("is_bust", false)
	# A winning dart passes no remaining_info — the leg-won path owns the remaining
	# display (it snaps to a golden 0). Without this flag the per-trigger loop below
	# would tick the uninitialised counter (-1) down by face_value per trigger and
	# write garbage to the remaining label (e.g. a 3-trigger D16 win → -1-16-16-16 = -49).
	var do_countdown: bool = not remaining_info.is_empty()
	if do_countdown:
		var base_mult: int = int(multiplier_mods[0]["old_value"])
		remaining_countdown = remaining_info["remaining_before"] - face_value * base_mult
		if is_bust_anim and remaining_countdown <= 0:
			hud.set_remaining_bust(true)
		hud.update_remaining(remaining_countdown, gc)

	var tween: Tween = create_tween()
	tween.tween_interval(0.3)

	var trigger_labels: Array[Label] = []
	var num_triggers: int = multiplier_mods.size()
	var running_total: int = base_score

	for i: int in range(num_triggers):
		var angle: float = PI * (0.3 + 0.4 * float(i) / float(maxi(num_triggers - 1, 1)))
		var offset: Vector2 = Vector2(cos(angle), -sin(angle)) * 50.0
		var trigger_label: Label = Label.new()
		trigger_label.text = "+%d" % display_face
		trigger_label.position = hit_position + offset + Vector2(-10.0, -10.0)
		trigger_label.z_index = 101
		trigger_label.add_theme_font_size_override("font_size", score_trigger_pip_font_size)
		trigger_label.add_theme_constant_override("outline_size", 3)
		var rarity_color: Color = multiplier_mods[i].get("source_rarity_color", Color(0.8, 0.8, 0.8))
		trigger_label.add_theme_color_override("font_color", rarity_color)
		trigger_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		trigger_label.modulate.a = 0.0
		_score_layer.add_child(trigger_label)
		trigger_labels.append(trigger_label)

	var groups: Array[Dictionary] = _group_multiplier_mods(multiplier_mods)
	var global_trigger_idx: int = 0
	var prev_source_label: HBoxContainer = null
	var source_rest_pos: Vector2 = hit_position + Vector2(-10.0, -65.0)

	for group_idx: int in range(groups.size()):
		var group: Dictionary = groups[group_idx]
		var is_first_group: bool = (group_idx == 0)
		var source_start_pos: Vector2 = source_rest_pos + Vector2(0.0, -40.0)
		var new_source_label: HBoxContainer = _create_source_label(group, source_start_pos)
		new_source_label.modulate.a = 0.0
		new_source_label.set_meta("rest_position", source_rest_pos)

		var old_label_ref: HBoxContainer = prev_source_label

		tween.tween_callback(func() -> void:
			_score_layer.add_child(new_source_label)
		)

		tween.set_parallel(true)
		tween.tween_property(new_source_label, "modulate:a", 1.0, 0.08)
		tween.tween_property(new_source_label, "position", source_rest_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.set_parallel(false)

		tween.tween_callback(func() -> void:
			new_source_label.pivot_offset = new_source_label.size / 2.0
			AuidoManager.play_source_label_slam(not is_first_group)
			if old_label_ref != null and is_instance_valid(old_label_ref):
				var exit_tw: Tween = create_tween()
				exit_tw.set_parallel(true)
				exit_tw.tween_property(old_label_ref, "position:y", old_label_ref.position.y + 25.0, 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				exit_tw.tween_property(old_label_ref, "modulate:a", 0.0, 0.1)
				exit_tw.set_parallel(false)
				exit_tw.tween_callback(old_label_ref.queue_free)
		)

		tween.tween_interval(0.12)

		var group_mods: Array = group["mods"]
		for j: int in range(group_mods.size()):
			running_total += display_face
			var final_total: int = running_total
			var scale_bump: float = 1.0 + 0.1 * float(global_trigger_idx + 1)
			var trigger_lbl: Label = trigger_labels[global_trigger_idx]
			var source_ref: HBoxContainer = new_source_label
			var local_j: int = j

			remaining_countdown -= face_value
			var snap_remaining: int = remaining_countdown

			if num_triggers > 3 and global_trigger_idx > 2:
				var speed: float = 1.0 + 0.2 * float(global_trigger_idx - 2)
				tween.tween_callback(tween.set_speed_scale.bind(speed))

			tween.tween_property(trigger_lbl, "modulate:a", 1.0, 0.1)
			tween.tween_property(trigger_lbl, "position", main_label.position, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tween.tween_callback(_on_trigger_impact_with_source.bind(trigger_lbl, main_label, source_ref, final_total, scale_bump, global_trigger_idx, local_j, snap_remaining, is_bust_anim))
			# Only drive the remaining counter when we have real countdown info — a
			# winning dart leaves this to the leg-won path (snaps to golden 0).
			if do_countdown:
				if snap_remaining >= 0:
					tween.tween_callback(hud.update_remaining.bind(snap_remaining, gc))
				else:
					# Going below zero: a bust in vanilla, but a legal remainder under the
					# Mirror-Zone relic. Either way keep the counter live; only paint it as a
					# bust when it actually is one.
					if is_bust_anim and snap_remaining + face_value >= 0:
						tween.tween_callback(hud.set_remaining_bust.bind(true))
					tween.tween_callback(hud.update_remaining.bind(snap_remaining, gc))
			var shake_offset: Vector2 = Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0))
			tween.tween_property(main_label, "position", main_label.position + shake_offset, 0.04)
			tween.tween_property(main_label, "position", hit_position + Vector2(-10.0, -10.0), 0.04)
			if global_trigger_idx < num_triggers - 1:
				tween.tween_interval(0.1)
			global_trigger_idx += 1

		prev_source_label = new_source_label

	tween.tween_callback(tween.set_speed_scale.bind(1.0))

	if is_leg_won:
		tween.tween_callback(func() -> void:
			main_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			AuidoManager.play_leg_win()
		)

	if has_recession:
		var actual_score: int = result["total_score"]
		var percent_text: String = "-%d%%" % int(recession_data["percent"] * 100)
		var scale_factor: float = 1.0 - recession_data["percent"]

		tween.tween_interval(0.15)
		var recession_label: Label = Label.new()
		recession_label.text = percent_text
		recession_label.z_index = 101
		recession_label.add_theme_font_size_override("font_size", 22)
		recession_label.add_theme_constant_override("outline_size", 3)
		recession_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
		recession_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		recession_label.position = hit_position + Vector2(55.0, -45.0)
		recession_label.modulate.a = 0.0
		_score_layer.add_child(recession_label)

		tween.tween_property(recession_label, "modulate:a", 1.0, 0.1)
		tween.tween_property(recession_label, "position", main_label.position, 0.15).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		var final_remaining: int = remaining_info.get("remaining_final", -1)
		tween.tween_callback(func() -> void:
			recession_label.queue_free()
			main_label.text = str(actual_score)
			main_label.scale *= scale_factor
			AuidoManager.play_void_hit()
			if final_remaining >= 0:
				hud.update_remaining(final_remaining, gc)
			if is_bust_anim and final_remaining > 0:
				AuidoManager.play_bust_sound()
		)
		var r_shake: Vector2 = Vector2(randf_range(-5.0, 5.0), randf_range(-4.0, 4.0))
		tween.tween_property(main_label, "position", main_label.position + r_shake, 0.04)
		tween.tween_property(main_label, "position", hit_position + Vector2(-10.0, -10.0), 0.04)

	if is_bust_anim and not has_recession:
		var bust_final: int = remaining_info.get("remaining_final", -1)
		tween.tween_callback(func() -> void:
			hud.update_remaining(bust_final, gc)
			if bust_final > 0:
				AuidoManager.play_bust_sound()
		)

	var final_source: HBoxContainer = prev_source_label
	tween.tween_interval(0.15)
	tween.tween_callback(func() -> void:
		_trigger_anim_active = false
		AuidoManager.reset_slam_pitch()
		if final_source != null and is_instance_valid(final_source):
			var source_fade: Tween = create_tween()
			source_fade.tween_property(final_source, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			source_fade.tween_callback(final_source.queue_free)
	)
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


func _on_trigger_impact_with_source(trigger_lbl: Label, main_label: Label, source_label: HBoxContainer, total: int, scale: float, global_trigger_index: int, group_local_index: int, remaining: int = -1, is_bust: bool = false) -> void:
	trigger_lbl.queue_free()
	main_label.text = str(total)
	main_label.scale = Vector2(scale, scale)
	if is_bust and remaining != -1 and remaining <= 0:
		AuidoManager.play_bust_sound()
	else:
		AuidoManager.play_bonus_hit(global_trigger_index)
	if is_instance_valid(source_label):
		var source_scale: float = 1.0 + 0.03 * float(group_local_index + 1)
		source_label.scale = Vector2(source_scale, source_scale)
		var rest_pos: Vector2 = source_label.get_meta("rest_position", source_label.position)
		var shake: Vector2 = Vector2(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5))
		var rot_jolt: float = deg_to_rad(randf_range(-10.0, 10.0))
		source_label.rotation = rot_jolt
		var shake_tween: Tween = create_tween()
		shake_tween.tween_property(source_label, "position", rest_pos + shake, 0.05)
		shake_tween.tween_property(source_label, "position", rest_pos, 0.05)
		shake_tween.tween_callback(func() -> void:
			source_label.rotation = 0.0
		)


func _create_score_label(score: int, hit_position: Vector2, result: Dictionary, font_size: int = -1) -> Label:
	if font_size < 0:
		font_size = score_font_size
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


## Query active streak modifiers for current streak counts.
func _get_active_streak_info() -> Array[String]:
	var lines: Array[String] = []
	for modifier: Resource in scoring_modifier_manager.active_modifiers:
		if modifier is ScoringModifier and modifier.enabled:
			var display: String = modifier.get_streak_display()
			if display != "":
				lines.append(display)
	return lines
