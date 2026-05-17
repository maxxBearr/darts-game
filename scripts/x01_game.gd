extends Node
## Pure game-logic controller for X01 mode. No rendering, no signals.
## Main calls into this after each throw and reads back what happened.
## Roguelike run structure: beat a leg → target increases. Fail → run over.

## How many 3-dart turns the player gets per leg.
@export var max_turns: int = 5

## Target score for leg 1 (useful for debug, skip easy legs).
@export var starting_target: int = 101

## How much the target increases each leg after a win.
@export var target_increment: int = 100

# Game state
var current_leg: int = 1
var target_score: int = 101
var remaining_score: int = 101
var current_turn: int = 1
var darts_this_turn: int = 0
var score_at_turn_start: int = 101


## Reset everything and begin a fresh run from leg 1.
func start_run() -> void:
	current_leg = 1
	target_score = starting_target
	start_leg()


## Begin a new leg at the current target score.
func start_leg() -> void:
	remaining_score = target_score
	current_turn = 1
	start_turn()


## Begin a new 3-dart turn within the current leg.
func start_turn() -> void:
	darts_this_turn = 0
	score_at_turn_start = remaining_score


## Advance to the next leg (called after player confirms leg win).
func advance_leg() -> void:
	current_leg += 1
	target_score += target_increment
	start_leg()


## Process a single dart throw. Returns a dictionary describing what happened.
## result is the dictionary from dartboard.calculate_score() containing:
## face_value, multiplier, total_score, ring_name.
func process_throw(result: Dictionary) -> Dictionary:
	darts_this_turn += 1

	# Calculate what the new remaining score would be
	var points: int = result["total_score"]
	var new_remaining: int = remaining_score - points

	# Determine if this dart landed on a double
	var ring_name: String = result["ring_name"]
	var is_double: bool = ring_name == "Double" or ring_name == "Double Bull"

	# Check win condition: exactly 0 remaining AND finished on a double
	var is_leg_won: bool = new_remaining == 0 and is_double

	# Check bust conditions
	var is_bust: bool = false
	var bust_reason: String = ""

	if not is_leg_won:
		if new_remaining < 0:
			is_bust = true
			bust_reason = "Score would go below zero"
		elif new_remaining == 1:
			is_bust = true
			bust_reason = "Can't finish on 1"
		elif new_remaining == 0 and not is_double:
			is_bust = true
			bust_reason = "Must finish on a double"

	# Apply score changes
	if is_bust:
		# Revert to score at start of turn
		remaining_score = score_at_turn_start
	elif not is_leg_won:
		# Normal hit — deduct points
		remaining_score = new_remaining

	# Calculate darts remaining this turn
	var darts_remaining: int = 3 - darts_this_turn
	# Bust or win ends the turn immediately regardless of darts left
	if is_bust:
		darts_remaining = 0

	# Determine if the turn is over
	var is_turn_over: bool = darts_remaining <= 0 or is_bust or is_leg_won

	# Determine if the entire run is over (out of turns without winning)
	var is_game_over: bool = is_turn_over and current_turn >= max_turns and not is_leg_won

	return {
		"points_scored": points,
		"remaining_score": remaining_score,
		"is_bust": is_bust,
		"bust_reason": bust_reason,
		"is_leg_won": is_leg_won,
		"is_game_over": is_game_over,
		"is_turn_over": is_turn_over,
		"darts_remaining": darts_remaining,
		"current_turn": current_turn,
		"current_leg": current_leg,
		"target_score": target_score,
		"reverted_score": score_at_turn_start if is_bust else -1
	}


## Advance the turn counter. Call when main is ready to move to the next turn.
func end_turn() -> void:
	current_turn += 1
