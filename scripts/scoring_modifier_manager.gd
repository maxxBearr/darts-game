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
		"is_preview": is_preview,
	}

	# Run through all enabled PER_DART modifiers in acquisition order
	for modifier: Resource in active_modifiers:
		if modifier.timing == ScoringEnums.ModifierTiming.PER_DART and modifier.enabled:
			result = modifier.apply(result, context)

	# Only record to history if this is a real throw, not a hover preview
	if not is_preview:
		var history_entry: Dictionary = result.duplicate()
		hit_history_turn.append(history_entry)
		hit_history_leg.append(history_entry)
		hit_history_run.append(history_entry)

	return result


## Get all active streak modifiers (those with a non-NONE streak category).
func get_active_streak_modifiers() -> Array:
	var result: Array = []
	for modifier: Resource in active_modifiers:
		if modifier is ScoringModifier and modifier.streak_category != ScoringEnums.StreakCategory.NONE:
			result.append(modifier)
	return result


## Check if adding a modifier would replace an existing streak modifier.
## Returns the existing modifier that would be replaced, or null if no conflict.
func get_streak_conflict(new_modifier: ScoringModifier) -> ScoringModifier:
	if new_modifier.streak_category == ScoringEnums.StreakCategory.NONE:
		return null
	for existing: Resource in active_modifiers:
		if existing is ScoringModifier and existing.streak_category == new_modifier.streak_category:
			return existing
	return null


## Remove a specific modifier from the active list.
## Used when a streak modifier is being replaced by a new one in the same category.
func remove_modifier(modifier: Resource) -> void:
	var idx: int = active_modifiers.find(modifier)
	if idx >= 0:
		active_modifiers.remove_at(idx)


## Register a new modifier. For ON_ACQUIRE modifiers, immediately applies
## board-state changes. config is a Dictionary with modifier-specific settings
## (e.g., {"wedge_index": 5} for PICK_WEDGE modifiers).
## For NONE config_type modifiers, pass an empty dictionary.
## If the modifier has a streak category that conflicts with an existing modifier,
## the existing one is removed first (replacement).
## Returns the replaced modifier, or null if no replacement occurred.
func add_modifier(modifier: Resource, config: Dictionary) -> Resource:
	# Check for streak slot conflict and remove the existing one
	var replaced: Resource = null
	if modifier is ScoringModifier:
		var conflict: ScoringModifier = get_streak_conflict(modifier as ScoringModifier)
		if conflict != null:
			remove_modifier(conflict)
			replaced = conflict

	active_modifiers.append(modifier)

	# If this is an ON_ACQUIRE modifier, apply its board-state changes now
	if modifier.timing == ScoringEnums.ModifierTiming.ON_ACQUIRE:
		modifier.apply_to_board(effective_wedge_values, effective_wedge_colors, config)

	return replaced


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


## Snapshot all active modifiers' streak state for speculative simulation.
func snapshot_all_streak_state() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for modifier: Resource in active_modifiers:
		if modifier is ScoringModifier:
			snapshots.append(modifier.save_streak_state())
		else:
			snapshots.append({})
	return snapshots


## Restore all active modifiers' streak state from a snapshot array.
func restore_all_streak_state(snapshots: Array[Dictionary]) -> void:
	for i: int in range(mini(snapshots.size(), active_modifiers.size())):
		var modifier: Resource = active_modifiers[i]
		if modifier is ScoringModifier and not snapshots[i].is_empty():
			modifier.restore_streak_state_from(snapshots[i])


## Run a score through the modifier pipeline speculatively — mutates streak state
## but does NOT record to hit history. Used by the checkout solver for multi-dart
## simulation where dart-2 must see the streak state dart-1 created.
func speculative_score(raw_result: Dictionary) -> Dictionary:
	var result: Dictionary = raw_result.duplicate()
	result["modifications"] = []

	var context: Dictionary = {
		"history_turn": hit_history_turn,
		"history_leg": hit_history_leg,
		"history_run": hit_history_run,
		"effective_wedge_values": effective_wedge_values,
		"effective_wedge_colors": effective_wedge_colors,
		"is_preview": false,
	}

	for modifier: Resource in active_modifiers:
		if modifier.timing == ScoringEnums.ModifierTiming.PER_DART and modifier.enabled:
			result = modifier.apply(result, context)

	return result


## Build a synthetic score result for a candidate target (used by the solver).
## target: {wedge_index, ring_name, face_value, multiplier, is_bull, segment_color}
func synthesize_result(target: Dictionary) -> Dictionary:
	return {
		"face_value": target["face_value"],
		"multiplier": target["multiplier"],
		"total_score": target["face_value"] * target["multiplier"],
		"ring_name": target["ring_name"],
		"wedge_index": target.get("wedge_index", -1),
		"segment_color": target.get("segment_color", -1),
		"is_bull": target.get("is_bull", false),
	}


## Maximum checkout paths to return from the solver.
@export var max_displayed_paths: int = 5

## Cached candidate targets for the solver (rebuilt when board state changes).
var _solver_candidates: Array[Dictionary] = []

## Cached preferred remainders for the setup solver.
var _preferred_remainders: Array[int] = []

## Whether preferred remainders need recomputing.
var _preferred_remainders_dirty: bool = true

## Cached map of 1-dart-finishable remainders → fatness of best finishing target.
## Used by setup recommendation to prefer setups that leave the player at a
## single-dart finish next turn. Key = remainder value, value = fatness score
## (lower fatness = fatter, more reliable double).
## Computed cheaply: only iterates 22 double candidates through the preview pipeline.
var _one_dart_finishable: Dictionary = {}

## Whether the 1-dart finishable cache needs recomputing.
var _one_dart_finishable_dirty: bool = true


## Build the 83 candidate targets from current effective board state.
func _build_solver_candidates() -> void:
	_solver_candidates.clear()

	for wedge_idx: int in range(20):
		var face_value: int = effective_wedge_values[wedge_idx]
		var single_color: int = -1
		var multi_color: int = -1
		if effective_wedge_colors.size() == 20:
			single_color = effective_wedge_colors[wedge_idx]["single"]
			multi_color = effective_wedge_colors[wedge_idx]["multi"]
		else:
			var is_even: bool = wedge_idx % 2 == 0
			single_color = ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
			multi_color = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN

		# Inner Single
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Inner Single",
			"face_value": face_value, "multiplier": 1,
			"segment_color": single_color, "is_bull": false,
		})
		# Outer Single
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Outer Single",
			"face_value": face_value, "multiplier": 1,
			"segment_color": single_color, "is_bull": false,
		})
		# Double
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Double",
			"face_value": face_value, "multiplier": 2,
			"segment_color": multi_color, "is_bull": false,
		})
		# Triple
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Triple",
			"face_value": face_value, "multiplier": 3,
			"segment_color": multi_color, "is_bull": false,
		})

	# Single Bull
	_solver_candidates.append({
		"wedge_index": -1, "ring_name": "Single Bull",
		"face_value": 25, "multiplier": 1,
		"segment_color": ScoringEnums.SegmentColor.GREEN, "is_bull": true,
	})
	# Double Bull
	_solver_candidates.append({
		"wedge_index": -1, "ring_name": "Double Bull",
		"face_value": 25, "multiplier": 2,
		"segment_color": ScoringEnums.SegmentColor.RED, "is_bull": true,
	})
	# Deliberate off-board (streak breaker)
	_solver_candidates.append({
		"wedge_index": -1, "ring_name": "Off Board",
		"face_value": 0, "multiplier": 0,
		"segment_color": -1, "is_bull": false,
	})


## Solve for all valid checkout paths from a given remaining score and darts left.
## Returns an Array of paths, each path is an Array of {target, result} dicts.
## Ranked by: fewest darts, fattest segments, fewest off-board darts.
func solve_checkout(remaining: int, darts_left: int) -> Array[Array]:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	var cache: Dictionary = {}
	var raw_paths: Array[Array] = _solve_recursive(remaining, darts_left, cache)

	# Rank and limit
	raw_paths.sort_custom(_compare_paths)
	if raw_paths.size() > max_displayed_paths:
		raw_paths.resize(max_displayed_paths)

	return raw_paths


func _solve_recursive(remaining: int, darts_left: int, cache: Dictionary) -> Array[Array]:
	if darts_left <= 0 or remaining <= 0:
		return []

	# Build a cache key from remaining, darts_left, and streak state
	var streak_snap: Array[Dictionary] = snapshot_all_streak_state()
	var cache_key: String = "%d_%d_%s" % [remaining, darts_left, str(streak_snap).hash()]
	if cache.has(cache_key):
		return cache[cache_key]

	var paths: Array[Array] = []

	for target: Dictionary in _solver_candidates:
		var base_score: int = target["face_value"] * target["multiplier"]
		# Quick prune: if base score alone exceeds remaining, skip
		# (modifiers can only increase score, so this is safe)
		if base_score > remaining and base_score > 0:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]

		var ring_name: String = target["ring_name"]
		var is_double: bool = ring_name == "Double" or ring_name == "Double Bull"

		var step: Dictionary = {"target": target, "result": result}

		if scored == remaining and is_double:
			# Checkout on this dart
			paths.append([step])
		elif scored < remaining and scored >= 0 and darts_left > 1:
			var new_remaining: int = remaining - scored
			# Prune: can't finish from 1
			if new_remaining != 1:
				var sub_paths: Array[Array] = _solve_recursive(new_remaining, darts_left - 1, cache)
				for sub: Array in sub_paths:
					var full_path: Array = [step]
					full_path.append_array(sub)
					paths.append(full_path)

		restore_all_streak_state(snapshot)

	cache[cache_key] = paths
	return paths


## Rank a target by "fatness" — larger physical areas rank higher.
## Returns a lower number for fatter (more reliable) targets.
func _target_fatness(target: Dictionary) -> int:
	var ring: String = target["ring_name"]
	match ring:
		"Outer Single":
			return 0
		"Inner Single":
			return 1
		"Double":
			return 2
		"Single Bull":
			return 3
		"Triple":
			return 4
		"Double Bull":
			return 5
		"Off Board":
			return 6
	return 7


## Compare two paths for sorting: fewest darts, then fattest, then fewest off-board.
func _compare_paths(a: Array, b: Array) -> bool:
	# Fewest darts first
	if a.size() != b.size():
		return a.size() < b.size()

	# Fattest reliable segment (sum of fatness scores — lower is fatter)
	var fatness_a: int = 0
	var fatness_b: int = 0
	var offboard_a: int = 0
	var offboard_b: int = 0
	for step: Dictionary in a:
		fatness_a += _target_fatness(step["target"])
		if step["target"]["ring_name"] == "Off Board":
			offboard_a += 1
	for step: Dictionary in b:
		fatness_b += _target_fatness(step["target"])
		if step["target"]["ring_name"] == "Off Board":
			offboard_b += 1

	if fatness_a != fatness_b:
		return fatness_a < fatness_b

	# Fewest off-board darts
	return offboard_a < offboard_b


## Get a display-friendly name for a target (e.g., "T20", "D-Bull", "S5").
static func get_target_display_name(target: Dictionary) -> String:
	var ring: String = target["ring_name"]
	var face: int = target["face_value"]
	match ring:
		"Inner Single", "Outer Single":
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


## Compute which remainders (2-180) have at least one valid 3-dart checkout.
## Cached and invalidated on modifier state changes.
##
## Two key optimizations over the naive 179-solve approach:
##   1. Shared cache across all 179 iterations — sub-problems repeat heavily
##      (e.g., the 2-dart sub-problem from r=170 and r=169 overlap), so a
##      single shared cache turns redundant work into cache hits.
##   2. Find-first-path semantics (_solve_first) — we only need to know
##      WHETHER a checkout exists, not enumerate all of them, so we return
##      as soon as the first valid path is discovered.
##
## Combined, this drops the precompute from O(seconds) to O(milliseconds) in
## vanilla configurations.
func compute_preferred_remainders() -> void:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	_preferred_remainders.clear()
	# Save current streak state so the computation doesn't pollute it
	var saved: Array[Dictionary] = snapshot_all_streak_state()

	# Shared cache across all 179 iterations (see comment above).
	var shared_cache: Dictionary = {}

	for r: int in range(2, 181):
		# Reset streaks to turn-fresh state for V1
		for modifier: Resource in active_modifiers:
			if modifier.has_method("reset_streak_state"):
				modifier.reset_streak_state()
		if _solve_first(r, 3, shared_cache):
			_preferred_remainders.append(r)

	restore_all_streak_state(saved)
	_preferred_remainders_dirty = false


## Existence-only checkout solver. Returns true as soon as any valid path is
## found, without enumerating the full set. Used by compute_preferred_remainders
## which only cares about whether checkouts exist, not what they look like.
## Cache stores bool results keyed by (remaining, darts_left, streak_state).
func _solve_first(remaining: int, darts_left: int, cache: Dictionary) -> bool:
	if darts_left <= 0 or remaining <= 0:
		return false

	# Build cache key including streak state so different states don't collide
	var streak_snap: Array[Dictionary] = snapshot_all_streak_state()
	var cache_key: String = "%d_%d_%s" % [remaining, darts_left, str(streak_snap).hash()]
	if cache.has(cache_key):
		return cache[cache_key]

	var found: bool = false

	for target: Dictionary in _solver_candidates:
		if found:
			break
		var base_score: int = target["face_value"] * target["multiplier"]
		# Prune: base score alone exceeds remaining (modifiers only add)
		if base_score > remaining and base_score > 0:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]

		var ring_name: String = target["ring_name"]
		var is_double: bool = ring_name == "Double" or ring_name == "Double Bull"

		if scored == remaining and is_double:
			# Found a finishing dart at this remaining
			found = true
		elif scored < remaining and scored >= 0 and darts_left > 1:
			var new_remaining: int = remaining - scored
			# Can't finish from 1 (no double sums to 1)
			if new_remaining != 1:
				if _solve_first(new_remaining, darts_left - 1, cache):
					found = true

		restore_all_streak_state(snapshot)

	cache[cache_key] = found
	return found


## Compute the map of remainders that have a 1-dart checkout under the
## current modifier configuration. Cheap — only runs the 22 double candidates
## through the preview pipeline (no recursion). Maps remainder → fatness of
## the best finishing target so setup ranking can prefer fatter finishes.
func _compute_one_dart_finishable() -> void:
	_one_dart_finishable.clear()

	# Save and reset to turn-fresh streak state for V1 consistency
	var saved: Array[Dictionary] = snapshot_all_streak_state()
	for modifier: Resource in active_modifiers:
		if modifier.has_method("reset_streak_state"):
			modifier.reset_streak_state()

	var double_fatness: int = _target_fatness({"ring_name": "Double"})
	var double_bull_fatness: int = _target_fatness({"ring_name": "Double Bull"})

	# 20 wedge doubles — what score does each produce under current modifiers?
	for wedge_idx: int in range(20):
		var face: int = effective_wedge_values[wedge_idx]
		var color: int = ScoringEnums.SegmentColor.RED if wedge_idx % 2 == 0 else ScoringEnums.SegmentColor.GREEN
		if effective_wedge_colors.size() == 20:
			color = effective_wedge_colors[wedge_idx]["multi"]
		var synth: Dictionary = synthesize_result({
			"wedge_index": wedge_idx, "ring_name": "Double",
			"face_value": face, "multiplier": 2,
			"segment_color": color, "is_bull": false,
		})
		# Preview mode — does NOT mutate streak state
		var result: Dictionary = process_score(synth, true)
		var score: int = result["total_score"]
		if score > 0:
			# Keep the fattest finishing target if multiple doubles produce
			# the same score under modifiers
			var current: int = _one_dart_finishable.get(score, 999)
			if double_fatness < current:
				_one_dart_finishable[score] = double_fatness

	# Double bull
	var bull_synth: Dictionary = synthesize_result({
		"wedge_index": -1, "ring_name": "Double Bull",
		"face_value": 25, "multiplier": 2,
		"segment_color": ScoringEnums.SegmentColor.RED, "is_bull": true,
	})
	var bull_result: Dictionary = process_score(bull_synth, true)
	var bull_score: int = bull_result["total_score"]
	if bull_score > 0:
		var current: int = _one_dart_finishable.get(bull_score, 999)
		if double_bull_fatness < current:
			_one_dart_finishable[bull_score] = double_bull_fatness

	restore_all_streak_state(saved)
	_one_dart_finishable_dirty = false


## Get the 1-dart finishable map, computing it if dirty.
## Map structure: { remainder_value: fatness_of_best_finishing_target }.
func get_one_dart_finishable() -> Dictionary:
	if _one_dart_finishable_dirty:
		_compute_one_dart_finishable()
	return _one_dart_finishable


## Get the preferred remainders list, computing if dirty.
func get_preferred_remainders() -> Array[int]:
	if _preferred_remainders_dirty:
		compute_preferred_remainders()
	return _preferred_remainders


## Mark preferred remainders + 1-dart finishable cache for recomputation.
## Call on any modifier state change (acquire, sell, swap, toggle).
func invalidate_preferred_remainders() -> void:
	_preferred_remainders_dirty = true
	_one_dart_finishable_dirty = true


## Recommend a single setup target when no checkout exists this turn.
## Returns {target, result, resulting_remainder} or an off-board fallback.
##
## Ranking is two-tier, lexicographic (lower tuple = better):
##   Tier 0 — resulting remainder has a 1-dart finish next turn (ideal setup).
##   Tier 1 — resulting remainder is 3-dart-finishable (acceptable setup).
##   (Otherwise, candidate is skipped; if no candidate qualifies, falls back
##    to off-board preservation.)
##
## Within a tier, the tiebreak order is:
##   1. Fattest next-turn finishing target (lower fatness = bigger / safer).
##   2. Fattest this-throw target (so we recommend safe darts this turn too).
##   3. Higher new_remaining as a final stable tiebreak.
func get_setup_recommendation(remaining: int) -> Dictionary:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	var one_dart: Dictionary = get_one_dart_finishable()
	var preferred: Array[int] = get_preferred_remainders()

	var best_target: Dictionary = {}
	# Lexicographic key: [tier, next_turn_fatness, this_throw_fatness, -new_remaining].
	# Lower values are better; comparing arrays in GDScript does the right thing.
	var best_key: Array = []

	var saved: Array[Dictionary] = snapshot_all_streak_state()

	for target: Dictionary in _solver_candidates:
		var base_score: int = target["face_value"] * target["multiplier"]
		# Skip the off-board candidate here — it's handled by the fallback below.
		# Skip anything that would bust outright on base score.
		if base_score <= 0:
			continue
		if base_score > remaining:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]
		restore_all_streak_state(snapshot)

		var new_remaining: int = remaining - scored
		# Skip illegal/non-checkout-eligible resulting states
		if new_remaining < 2 or scored > remaining:
			continue

		# Determine which tier this setup falls into
		var tier: int
		var next_turn_fatness: int
		if one_dart.has(new_remaining):
			# Ideal: lands at a 1-dart finish next turn
			tier = 0
			next_turn_fatness = one_dart[new_remaining]
		elif new_remaining in preferred:
			# Fallback: 3-dart-checkoutable next turn
			tier = 1
			next_turn_fatness = 999  # unknown / multi-dart finish
		else:
			# Not even 3-dart-reachable — skip
			continue

		var this_fatness: int = _target_fatness(target)
		# Lexicographic comparison key (lower = better)
		var key: Array = [tier, next_turn_fatness, this_fatness, -new_remaining]

		if best_key.is_empty() or key < best_key:
			best_target = {"target": target, "result": result, "resulting_remainder": new_remaining}
			best_key = key

	restore_all_streak_state(saved)

	# Fallback: if no candidate qualified, recommend off-board preservation
	if best_target.is_empty():
		best_target = {
			"target": {"ring_name": "Off Board", "face_value": 0, "multiplier": 0,
				"wedge_index": -1, "segment_color": -1, "is_bull": false},
			"result": {"total_score": 0},
			"resulting_remainder": remaining,
		}

	return best_target


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
