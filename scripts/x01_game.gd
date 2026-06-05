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

## Number of darts the player throws per turn. Default 3; bosses can modify.
var darts_per_turn: int = 3

## Total-dart budget ceiling for the current leg (the §9 challenge-node mode).
## 0 = legacy turn-based budget: the leg's darts = max_turns × darts_per_turn, the
## last turn always full. >0 = a hard cap on TOTAL darts thrown this leg (the
## ice-tray budget): the race ends the moment darts_used_in_leg reaches this, so the
## final turn may be partial. A normal leg is exactly the special case where this
## would equal max_turns × darts_per_turn — see _effective_budget(). Challenges set
## it via start_challenge_race(); start_leg_with() clears it back to legacy.
## See specs/map/02-challenge-nodes-impl.md §5, §9.
var dart_budget: int = 0

## When true, triples (and Triple Bull) count as valid checkout rings.
var allow_triple_checkout: bool = false

## When true, any dart at exactly 0 wins (any ring), but busts end the run.
var glass_cannon_active: bool = false

## When false (Mirror-Zone relic), a would-be-bust no longer reverts or ends the
## turn — the player overshoots below 0 and keeps throwing. Negative remaining_score
## becomes a legal state. Default true preserves vanilla bust behavior exactly.
var bust_ends_turn: bool = true

# Game state
var current_leg: int = 1
var target_score: int = 101
var remaining_score: int = 101
var current_turn: int = 1
var darts_this_turn: int = 0
var score_at_turn_start: int = 101

## Total darts consumed in the current leg (including bust waste).
## Used to calculate spare darts for the shop system.
var darts_used_in_leg: int = 0


## Reset everything and begin a fresh run from leg 1.
func start_run() -> void:
	current_leg = 1
	target_score = starting_target
	dart_budget = 0
	start_leg()


## Begin a new leg at the current target score.
func start_leg() -> void:
	remaining_score = target_score
	current_turn = 1
	darts_used_in_leg = 0
	start_turn()


## Begin a new 3-dart turn within the current leg.
func start_turn() -> void:
	darts_this_turn = 0
	score_at_turn_start = remaining_score


## Advance to the next leg (called after player confirms leg win).
## Legacy self-incrementing ladder, retained for debug paths. The map drives the
## normal flow via start_leg_with() instead (see specs/map/01-substrate-impl.md).
func advance_leg() -> void:
	current_leg += 1
	target_score += target_increment
	start_leg()


## Start the next leg with map-supplied parameters instead of the self-increment.
## The selected MapNode owns the difficulty: it hands over the target and the dart
## budget (as max_turns), keeping the engine's leg invariants in one place.
func start_leg_with(new_target: int, new_max_turns: int) -> void:
	current_leg += 1
	target_score = new_target
	max_turns = maxi(new_max_turns, 1)
	dart_budget = 0   # legacy turn-based budget (darts = max_turns × darts_per_turn)
	start_leg()


## Start a challenge race (Phase 02 challenge node, §5/§9). Unlike a normal leg, the
## budget is a hard cap on TOTAL darts (the deposit), regrouped into ice-tray rows of
## `race_dpt` with a possibly-partial final row. `race_dpt` is the per-node rolled
## darts-per-turn override (restored by the caller after the race). max_turns is the
## ice-tray row count = ceil(deposit / dpt), so the HUD's "turn X of Y" reads right;
## the final partial turn ends early when the dart_budget cap is hit.
func start_challenge_race(new_target: int, race_dpt: int, deposit: int) -> void:
	current_leg += 1
	target_score = new_target
	darts_per_turn = maxi(race_dpt, 1)
	dart_budget = maxi(deposit, 1)
	max_turns = maxi(int(ceil(float(dart_budget) / float(darts_per_turn))), 1)
	start_leg()


## Process a single dart throw. Returns a dictionary describing what happened.
## result is the dictionary from dartboard.calculate_score() containing:
## face_value, multiplier, total_score, ring_name.
func process_throw(result: Dictionary) -> Dictionary:
	darts_this_turn += 1
	darts_used_in_leg += 1

	# Effective total-dart budget for this leg. In legacy mode this is exactly
	# max_turns × darts_per_turn, so every branch below reduces to the old turn-based
	# behavior; in challenge mode it is the deposit cap and the final turn may be
	# partial. budget_left = darts still available AFTER the dart just thrown.
	var total_budget: int = _effective_budget()
	var budget_left: int = maxi(total_budget - darts_used_in_leg, 0)

	# Calculate what the new remaining score would be
	var points: int = result["total_score"]
	var new_remaining: int = remaining_score - points

	# Determine if this dart landed on a valid finishing ring
	var ring_name: String = result["ring_name"]
	var is_double: bool = ring_name == "Double" or ring_name == "Double Bull"
	var is_triple: bool = ring_name == "Triple"
	var is_valid_finish: bool = is_double or (allow_triple_checkout and is_triple) or glass_cannon_active

	# Check win condition: exactly 0 remaining AND valid finish ring
	var is_leg_won: bool = new_remaining == 0 and is_valid_finish

	# Check bust conditions
	var is_bust: bool = false
	var bust_reason: String = ""

	# When bust_ends_turn is false (Mirror-Zone relic), there is no bust at all:
	# overshoot below 0, remainder 1, and 0-without-double all become normal
	# remainders and the player keeps throwing. The turn only ends on a win or
	# when darts run out.
	if not is_leg_won and bust_ends_turn:
		if new_remaining < 0:
			is_bust = true
			bust_reason = "Score would go below zero"
		elif new_remaining == 1 and not glass_cannon_active:
			is_bust = true
			bust_reason = "Can't finish on 1"
		elif new_remaining == 0 and not is_valid_finish:
			is_bust = true
			bust_reason = "Must finish on a double"

	# Apply score changes
	if is_bust:
		# Revert to score at start of turn
		remaining_score = score_at_turn_start
	elif not is_leg_won:
		# Normal hit — deduct points
		remaining_score = new_remaining

	# Calculate darts remaining this turn. Capped by the budget so the final ice-tray
	# row (challenge mode) is short, and a bust never wastes past the budget. In legacy
	# mode budget_left always ≥ the per-turn remainder, so the min picks the per-turn
	# value and behavior is unchanged.
	var darts_remaining: int = mini(darts_per_turn - darts_this_turn, budget_left)
	# Bust or win ends the turn immediately regardless of darts left
	if is_bust:
		# Remaining darts in the busted turn are wasted (the §5 bust unit = one row).
		darts_used_in_leg += darts_remaining
		darts_remaining = 0

	# Determine if the turn is over
	var is_turn_over: bool = darts_remaining <= 0 or is_bust or is_leg_won

	# Determine if the entire run/race is over. Budget-exhaustion replaces the old
	# current_turn ≥ max_turns test: in legacy mode the two are equivalent (each
	# completed non-winning turn consumes exactly darts_per_turn, so the budget is hit
	# precisely on the last turn), while in challenge mode it ends the race on the
	# partial final row. Glass Cannon busts still end the run immediately.
	var budget_exhausted: bool = darts_used_in_leg >= total_budget
	var is_game_over: bool = (is_turn_over and budget_exhausted and not is_leg_won) or (is_bust and glass_cannon_active)

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
		"reverted_score": score_at_turn_start if is_bust else -1,
		"pre_revert_remaining": new_remaining if is_bust else -1
	}


## How many darts the player saved this leg (total budget minus consumed). Reads the
## effective budget so it returns the unused deposit on a won challenge race exactly
## as it returns unused leg darts on a normal win — the §11 bank-the-leftover path.
func get_saved_darts() -> int:
	return maxi(_effective_budget() - darts_used_in_leg, 0)


## The leg's total dart budget. Legacy (dart_budget == 0): max_turns × darts_per_turn,
## last turn always full. Challenge (dart_budget > 0): the deposit cap, last turn may
## be partial. The single place the two budget models reconcile (§9).
func _effective_budget() -> int:
	if dart_budget > 0:
		return dart_budget
	return max_turns * darts_per_turn


## Advance the turn counter. Call when main is ready to move to the next turn.
func end_turn() -> void:
	current_turn += 1
