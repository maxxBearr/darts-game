extends Node
## Manages scoring modifiers that transform dart scores.
## Sits between dartboard.calculate_score() and x01_game.process_throw().
## Owns effective board state (wedge values and colors) and hit history.

# --- Standard dartboard color mapping ---
# Even-index wedges (0, 2, 4...): singles are BLACK, doubles/triples are RED
# Odd-index wedges (1, 3, 5...): singles are WHITE, doubles/triples are GREEN

## The default wedge number order from dartboard.gd, used to reset at run start.
const DEFAULT_WEDGE_ORDER: Array[int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

## The effective wedge values after all ON_ACQUIRE modifiers have been applied.
## Index 0 = top wedge (normally 20), index 1 = next clockwise (normally 1), etc.
## Dartboard reads from this for scoring and number rendering.
var effective_wedge_values: Array[int] = []

## The effective segment colors for each wedge. Index matches wedge position.
## Each entry is a dictionary with "single" and "multi" keys mapping to SegmentColor.
## "single" = color for inner_single and outer_single rings.
## "multi" = color for double and triple rings.
## Dartboard reads from this for segment color rendering (future) and score enrichment.
var effective_wedge_colors: Array[Dictionary] = []

## All currently active scoring modifiers, in acquisition order.
## ON_ACQUIRE modifiers are stored here too (for display/inspection purposes)
## but only PER_DART modifiers are called during process_score().
var active_modifiers: Array[Resource] = []

## Hit history for the current turn (cleared every turn via reset_for_turn).
var hit_history_turn: Array[Dictionary] = []

## Hit history for the current leg (cleared every leg via reset_for_leg).
var hit_history_leg: Array[Dictionary] = []

## Hit history for the entire run (cleared on new run via reset_for_run).
var hit_history_run: Array[Dictionary] = []

## Export test modifiers so developers can drag Resource files in via the inspector
## to test modifier behavior without needing a shop/acquisition flow.
## These are added via add_modifier() during _ready().
@export var debug_modifiers: Array[Resource] = []


func _ready() -> void:
	# Initialize board state to defaults
	_init_default_board_state()

	# Add any debug modifiers from the inspector
	for modifier: Resource in debug_modifiers:
		if modifier != null:
			add_modifier(modifier, {})


## Initialize effective wedge values and colors to standard dartboard defaults.
func _init_default_board_state() -> void:
	effective_wedge_values = DEFAULT_WEDGE_ORDER.duplicate()

	effective_wedge_colors.clear()
	for wedge_idx: int in range(20):
		var is_even: bool = wedge_idx % 2 == 0
		effective_wedge_colors.append({
			"single": ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE,
			"multi": ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN,
		})


## Run a raw score result through all active PER_DART modifiers.
## Call this after dartboard.calculate_score() and before x01_game.process_throw().
## Set is_preview to true for hover/tooltip display — runs the full pipeline
## but does NOT record the result to hit history.
func process_score(raw_result: Dictionary, is_preview: bool = false) -> Dictionary:
	var result: Dictionary = raw_result.duplicate()

	# Initialize the modifications tracking array — modifiers append to this
	result["modifications"] = []

	# Build context dictionary for modifiers that need history or board state
	var context: Dictionary = {
		"history_turn": hit_history_turn,
		"history_leg": hit_history_leg,
		"history_run": hit_history_run,
		"effective_wedge_values": effective_wedge_values,
		"effective_wedge_colors": effective_wedge_colors,
	}

	# Run through all active modifiers in acquisition order
	for modifier: Resource in active_modifiers:
		if modifier.timing == ScoringEnums.ModifierTiming.PER_DART:
			result = modifier.apply(result, context)

	# Only record to history if this is a real throw, not a hover preview
	if not is_preview:
		var history_entry: Dictionary = result.duplicate()
		hit_history_turn.append(history_entry)
		hit_history_leg.append(history_entry)
		hit_history_run.append(history_entry)

	return result


## Register a new modifier. For ON_ACQUIRE modifiers, immediately applies
## board-state changes. config is a Dictionary with modifier-specific settings
## (e.g., {"wedge_index": 5} for PICK_WEDGE modifiers).
## For NONE config_type modifiers, pass an empty dictionary.
func add_modifier(modifier: Resource, config: Dictionary) -> void:
	active_modifiers.append(modifier)

	# If this is an ON_ACQUIRE modifier, apply its board-state changes now
	if modifier.timing == ScoringEnums.ModifierTiming.ON_ACQUIRE:
		modifier.apply_to_board(effective_wedge_values, effective_wedge_colors, config)


## Get the effective face value for a wedge by index (0-19). For display/hover.
func get_effective_value(wedge_index: int) -> int:
	return effective_wedge_values[wedge_index]


## Get the effective SegmentColor for a wedge + ring type. For display/hover.
## is_multi should be true for double/triple rings, false for single rings.
func get_effective_color(wedge_index: int, is_multi: bool) -> ScoringEnums.SegmentColor:
	var color_entry: Dictionary = effective_wedge_colors[wedge_index]
	return color_entry["multi"] if is_multi else color_entry["single"]


## Get the SegmentColor for a bullseye hit. Single bull = GREEN, double bull = RED.
func get_bull_color(is_double_bull: bool) -> ScoringEnums.SegmentColor:
	return ScoringEnums.SegmentColor.RED if is_double_bull else ScoringEnums.SegmentColor.GREEN


## Clear turn-level history. Call from main.gd at the start of each new turn.
func reset_for_turn() -> void:
	hit_history_turn.clear()
	_reset_modifier_streaks(ScoringEnums.StreakScope.WITHIN_TURN)


## Clear leg-level history (and turn history). Call from main.gd at leg transitions.
func reset_for_leg() -> void:
	hit_history_turn.clear()
	hit_history_leg.clear()
	_reset_modifier_streaks(ScoringEnums.StreakScope.WITHIN_TURN)
	_reset_modifier_streaks(ScoringEnums.StreakScope.WITHIN_LEG)


## Full reset for a new run. Clears all history, all modifiers, resets board state.
func reset_for_run() -> void:
	hit_history_turn.clear()
	hit_history_leg.clear()
	hit_history_run.clear()
	active_modifiers.clear()
	_init_default_board_state()


## Reset streak state on modifiers matching the given scope.
func _reset_modifier_streaks(scope: ScoringEnums.StreakScope) -> void:
	for modifier: Resource in active_modifiers:
		if modifier.streak_scope == scope and modifier.has_method("reset_streak_state"):
			modifier.reset_streak_state()


## Calculate which double segments would win the leg at the given remaining score.
## Runs each double through the full modifier pipeline in preview mode.
func calculate_checkout_segments(remaining_score: int) -> Array[Dictionary]:
	var checkout_segments: Array[Dictionary] = []

	for wedge_idx: int in range(20):
		var face_value: int = effective_wedge_values[wedge_idx]
		var segment_color_value: int = -1
		if effective_wedge_colors.size() == 20:
			segment_color_value = effective_wedge_colors[wedge_idx]["multi"]
		else:
			var is_even: bool = wedge_idx % 2 == 0
			segment_color_value = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN

		var synthetic_result: Dictionary = {
			"face_value": face_value,
			"multiplier": 2,
			"total_score": face_value * 2,
			"ring_name": "Double",
			"wedge_index": wedge_idx,
			"segment_color": segment_color_value,
			"is_bull": false,
		}

		var modified_result: Dictionary = process_score(synthetic_result, true)
		if modified_result["total_score"] == remaining_score:
			checkout_segments.append({"type": "wedge", "wedge_idx": wedge_idx})

	# Check double bull
	var bull_result: Dictionary = {
		"face_value": 25,
		"multiplier": 2,
		"total_score": 50,
		"ring_name": "Double Bull",
		"wedge_index": -1,
		"segment_color": ScoringEnums.SegmentColor.RED,
		"is_bull": true,
	}
	var modified_bull: Dictionary = process_score(bull_result, true)
	if modified_bull["total_score"] == remaining_score:
		checkout_segments.append({"type": "double_bull"})

	return checkout_segments
