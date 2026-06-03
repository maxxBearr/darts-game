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
## Each entry is a dictionary with four ring keys mapping to SegmentColor:
## "inner_single", "triple", "outer_single", "double".
## Dartboard reads from this for segment color rendering and score enrichment.
var effective_wedge_colors: Array[Dictionary] = []

## All currently active scoring modifiers, in acquisition order.
## ON_ACQUIRE modifiers are stored here too (for display/inspection purposes)
## but only PER_DART modifiers are called during process_score().
var active_modifiers: Array[Resource] = []

## Segments voided by a boss this turn, keyed "<wedge_index>:<RingName>" (e.g.
## "3:Double"). A voided segment scores 0 no matter what modifiers would do to it.
## The Void boss sets this each turn; whole-void wedges (value zeroed) are included
## too so the solver, checkout segments, and hover tooltip all agree with live
## scoring. Empty in normal play. Drifted (partial) ring voids live ONLY here — the
## wedge keeps its value — which is why the solver must consult this, not just values.
var voided_rings: Dictionary = {}

## Maximum number of streak modifier slots. Default 3 (one per category).
var max_streak_slots: int = 3

## When true, triples count as valid checkout finishes for the solver.
var allow_triple_checkout: bool = false:
	set(value):
		if allow_triple_checkout != value:
			allow_triple_checkout = value
			_bump_state_version()

## When true, any ring counts as a valid checkout finish for the solver.
var glass_cannon_active: bool = false:
	set(value):
		if glass_cannon_active != value:
			glass_cannon_active = value
			_bump_state_version()

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

@export var debug_perf_log: bool = false

var _state_version: int = 0
var _last_sync_version: int = -1


func _bump_state_version() -> void:
	_state_version += 1


func _ready() -> void:
	# Initialize board state to defaults
	_init_default_board_state()

	# Add any debug modifiers from the inspector
	for modifier: Resource in debug_modifiers:
		if modifier != null:
			add_modifier(modifier, {})


func _perf_log(msg: String) -> void:
	if not debug_perf_log:
		return
	print("[PERF] %s" % msg)


func _streak_state_hash() -> int:
	var h: int = 0
	for modifier: Resource in active_modifiers:
		if modifier is ScoringModifier:
			h = (h * 31 + modifier.get_streak_state_hash()) & 0x7FFFFFFF
	return h


## Initialize effective wedge values and colors to standard dartboard defaults.
func _init_default_board_state() -> void:
	effective_wedge_values = DEFAULT_WEDGE_ORDER.duplicate()

	effective_wedge_colors.clear()
	for wedge_idx: int in range(20):
		var is_even: bool = wedge_idx % 2 == 0
		var single_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
		var multi_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
		effective_wedge_colors.append({
			"inner_single": single_color,
			"triple": multi_color,
			"outer_single": single_color,
			"double": multi_color,
		})


## Run a raw score result through all active PER_DART modifiers.
## Call this after dartboard.calculate_score() and before x01_game.process_throw().
## Set is_preview to true for hover/tooltip display — runs the full pipeline
## but does NOT record the result to hit history.
func process_score(raw_result: Dictionary, is_preview: bool = false) -> Dictionary:
	var result: Dictionary = raw_result.duplicate()

	# Initialize the modifications tracking array — modifiers append to this
	result["modifications"] = []

	# Mark boss-voided segments up front (synthesized results from the solver/tooltip
	# don't carry is_void; live results from calculate_score already do).
	_mark_void(result)

	# Build context dictionary for modifiers that need history or board state
	var context: Dictionary = {
		"history_turn": hit_history_turn,
		"history_leg": hit_history_leg,
		"history_run": hit_history_run,
		"effective_wedge_values": effective_wedge_values,
		"effective_wedge_colors": effective_wedge_colors,
		"is_preview": is_preview,
	}

	# Run through all enabled PER_DART modifiers in acquisition order.
	# FlipSignModifier is held back for a final pass (see _apply_flip_pass).
	for modifier: Resource in active_modifiers:
		if modifier.timing == ScoringEnums.ModifierTiming.PER_DART and modifier.enabled:
			if modifier is FlipSignModifier:
				continue
			result = modifier.apply(result, context)

	# Flip sign is the dead-last step so it composes cleanly with everything else.
	result = _apply_flip_pass(result, context)

	# A voided segment scores 0 regardless of what any modifier did to it — modifiers
	# recompute total_score from face×multiplier, which would otherwise resurrect the
	# void. This is the last word on the score.
	if result.get("is_void", false):
		result["total_score"] = 0

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


## Get all active streak modifiers of the same category that would be candidates
## for replacement. Returns empty if there's a free slot (no conflict).
## Base rule: 1 streak per category (3 base slots). Bonus slots (max_streak_slots - 3)
## allow duplicates within a category.
func get_streak_conflicts(new_modifier: ScoringModifier) -> Array:
	if new_modifier.streak_category == ScoringEnums.StreakCategory.NONE:
		return []
	var active_streaks: Array = get_active_streak_modifiers()
	var same_category: Array = []
	for existing: Resource in active_streaks:
		if existing is ScoringModifier and existing.streak_category == new_modifier.streak_category:
			same_category.append(existing)
	if same_category.is_empty():
		return []
	var unique_categories: int = _count_unique_streak_categories(active_streaks)
	var bonus_slots: int = max_streak_slots - 3
	var bonus_used: int = active_streaks.size() - unique_categories
	if bonus_used < bonus_slots:
		return []
	return same_category


func _count_unique_streak_categories(streaks: Array) -> int:
	var seen: Array[int] = []
	for s: Resource in streaks:
		if s is ScoringModifier:
			var cat: int = (s as ScoringModifier).streak_category
			if not seen.has(cat):
				seen.append(cat)
	return seen.size()


## Convenience: returns the single conflict if exactly one exists, or null.
## When multiple same-category conflicts exist, returns null — caller must
## use get_streak_conflicts() and present a choice to the player.
func get_streak_conflict(new_modifier: ScoringModifier) -> ScoringModifier:
	var conflicts: Array = get_streak_conflicts(new_modifier)
	if conflicts.size() == 1:
		return conflicts[0]
	return null


## Remove a specific modifier from the active list.
## Used when a streak modifier is being replaced by a new one in the same category.
func remove_modifier(modifier: Resource) -> void:
	var idx: int = active_modifiers.find(modifier)
	if idx >= 0:
		active_modifiers.remove_at(idx)
		_bump_state_version()


## Register a new modifier. For ON_ACQUIRE modifiers, immediately applies
## board-state changes. config is a Dictionary with modifier-specific settings
## (e.g., {"wedge_index": 5} for PICK_WEDGE modifiers).
## For NONE config_type modifiers, pass an empty dictionary.
## If the modifier has a streak category that conflicts with an existing modifier,
## the existing one is removed first (replacement). When multiple same-category
## conflicts exist, pass the chosen one via explicit_replacement.
## Returns the replaced modifier, or null if no replacement occurred.
func add_modifier(modifier: Resource, config: Dictionary, explicit_replacement: Resource = null) -> Resource:
	var replaced: Resource = null
	if explicit_replacement != null:
		remove_modifier(explicit_replacement)
		replaced = explicit_replacement
	elif modifier is ScoringModifier:
		var conflict: ScoringModifier = get_streak_conflict(modifier as ScoringModifier)
		if conflict != null:
			remove_modifier(conflict)
			replaced = conflict

	active_modifiers.append(modifier)
	_bump_state_version()

	# If this is an ON_ACQUIRE modifier, apply its board-state changes now
	if modifier.timing == ScoringEnums.ModifierTiming.ON_ACQUIRE:
		modifier.apply_to_board(effective_wedge_values, effective_wedge_colors, config)
		# A swap relocates a wedge's value and colors between two slots. Position-tied
		# per-dart state (sign flips) must travel with it, so notify other modifiers.
		# Keyed on the config shape, not the class, so any swap-style mutation works.
		if config.has("wedge_index_1") and config.has("wedge_index_2"):
			_notify_wedges_swapped(config["wedge_index_1"], config["wedge_index_2"])
		_bump_state_version()

	UnlockManager.on_item_acquired({
		"rarity": modifier.rarity_tier,
		"active_relic_count": _count_active_relics(),
	})
	if modifier is ScoringModifier and (modifier as ScoringModifier).streak_category != ScoringEnums.StreakCategory.NONE:
		UnlockManager.on_slots_state_changed(_build_slots_context())

	return replaced


## Tell every active modifier that two wedges swapped board positions, so any
## position-tied per-dart state (e.g. FlipSignModifier targets) follows its wedge.
func _notify_wedges_swapped(idx_a: int, idx_b: int) -> void:
	for m: Resource in active_modifiers:
		if m is ScoringModifier:
			(m as ScoringModifier).on_wedges_swapped(idx_a, idx_b)


## Count currently active RELIC-kind modifiers. Used by RelicCountCondition
## to drive "amass N items" unlock conditions. BOARD_MUTATION modifiers don't
## count — they fire once on acquire and don't persist as relics.
func _count_active_relics() -> int:
	var count: int = 0
	for m: Resource in active_modifiers:
		if m is ScoringModifier and (m as ScoringModifier).kind == ScoringEnums.ModifierKind.RELIC:
			count += 1
	return count


## Build the context payload for slots_state_changed events.
## Currently only enforces streak categories; non-streak relic counts are
## handled by RelicCountCondition listening on item_acquired instead.
func _build_slots_context() -> Dictionary:
	var categories: Dictionary = {}
	for m: Resource in active_modifiers:
		if m is ScoringModifier and m.streak_category != ScoringEnums.StreakCategory.NONE:
			categories[m.streak_category] = true
	var all_streak: bool = (
		categories.has(ScoringEnums.StreakCategory.WEDGE)
		and categories.has(ScoringEnums.StreakCategory.COLOR)
		and categories.has(ScoringEnums.StreakCategory.PARITY)
	)
	return {
		"all_streak_categories_filled": all_streak,
	}


## Get the effective face value for a wedge by index (0-19). For display/hover.
func get_effective_value(wedge_index: int) -> int:
	return effective_wedge_values[wedge_index]


## Get the effective SegmentColor for a wedge + ring. ring_key is one of
## "inner_single", "triple", "outer_single", "double".
func get_effective_color(wedge_index: int, ring_key: String) -> ScoringEnums.SegmentColor:
	var color_entry: Dictionary = effective_wedge_colors[wedge_index]
	return color_entry[ring_key]


## Get the SegmentColor for a bullseye hit. Single bull = GREEN, double bull = RED.
func get_bull_color(is_double_bull: bool) -> ScoringEnums.SegmentColor:
	return ScoringEnums.SegmentColor.RED if is_double_bull else ScoringEnums.SegmentColor.GREEN


## Map a display ring name ("Inner Single", "Triple", etc.) to the per-ring dict key.
static func _ring_name_to_key(ring_name: String) -> String:
	match ring_name:
		"Inner Single":
			return "inner_single"
		"Triple":
			return "triple"
		"Outer Single":
			return "outer_single"
		"Double":
			return "double"
	return "inner_single"


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
	voided_rings.clear()
	_init_default_board_state()
	# Drop the cached checkout-solver candidates and their derived caches. These are
	# built from effective_wedge_values and only rebuilt when empty, so without this
	# the solver (and the checkout helper) would keep suggesting the PREVIOUS run's
	# modified wedges — e.g. proposing a "D22" on a fresh, unmodified board.
	_solver_candidates.clear()
	invalidate_preferred_remainders()
	_last_sync_version = -1
	_bump_state_version()


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

	_mark_void(result)

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
			if modifier is FlipSignModifier:
				continue
			result = modifier.apply(result, context)

	result = _apply_flip_pass(result, context)

	if result.get("is_void", false):
		result["total_score"] = 0

	return result


## Flag a result as voided if its wedge+ring is in the boss void set. Synthesized
## results (solver, checkout segments, hover preview) don't carry is_void, so this is
## how those paths learn about drifted ring voids that aren't reflected in wedge values.
func _mark_void(result: Dictionary) -> void:
	if result.get("is_void", false):
		return
	var wi: int = result.get("wedge_index", -1)
	if wi < 0:
		return
	if voided_rings.has("%d:%s" % [wi, result.get("ring_name", "")]):
		result["is_void"] = true


## Whether a given board segment is voided this turn. Used by the hover tooltip so the
## player can see a zone is dead before committing a dart.
func is_segment_voided(wedge_index: int, ring_name: String) -> bool:
	if wedge_index < 0:
		return false
	return voided_rings.has("%d:%s" % [wedge_index, ring_name])


## Apply all enabled FlipSignModifiers as the final scoring step. Held back from the
## main PER_DART loop so the sign flip always runs after every other modifier,
## regardless of acquisition order.
func _apply_flip_pass(result: Dictionary, context: Dictionary) -> Dictionary:
	for modifier: Resource in active_modifiers:
		if modifier is FlipSignModifier and modifier.enabled:
			result = modifier.apply(result, context)
	return result


## Board positions (0-19) currently flipped by a FlipSignModifier. Used by the HUD
## to draw a "+" suffix on those wedge numbers.
func get_flipped_wedge_indices() -> Array[int]:
	var indices: Array[int] = []
	for modifier: Resource in active_modifiers:
		if modifier is FlipSignModifier and modifier.enabled:
			var idx: int = (modifier as FlipSignModifier).target_wedge_index
			if idx >= 0 and not indices.has(idx):
				indices.append(idx)
	return indices


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

## Highest total_score any single scoring dart produces under current modifiers.
## Cached alongside preferred remainders; invalidated by the same call.
var _max_single_dart_score: int = 0

## Highest value in _preferred_remainders (last element, since it's sorted ascending).
var _max_preferred_remainder: int = 0


## Build the 83 candidate targets from current effective board state.
func _build_solver_candidates() -> void:
	_solver_candidates.clear()

	for wedge_idx: int in range(20):
		var face_value: int = effective_wedge_values[wedge_idx]
		var colors: Dictionary = {}
		if effective_wedge_colors.size() == 20:
			colors = effective_wedge_colors[wedge_idx]
		else:
			var is_even: bool = wedge_idx % 2 == 0
			var sc: int = ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
			var mc: int = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
			colors = {"inner_single": sc, "triple": mc, "outer_single": sc, "double": mc}

		# Inner Single
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Inner Single",
			"face_value": face_value, "multiplier": 1,
			"segment_color": colors["inner_single"], "is_bull": false,
		})
		# Outer Single
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Outer Single",
			"face_value": face_value, "multiplier": 1,
			"segment_color": colors["outer_single"], "is_bull": false,
		})
		# Double
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Double",
			"face_value": face_value, "multiplier": 2,
			"segment_color": colors["double"], "is_bull": false,
		})
		# Triple
		_solver_candidates.append({
			"wedge_index": wedge_idx, "ring_name": "Triple",
			"face_value": face_value, "multiplier": 3,
			"segment_color": colors["triple"], "is_bull": false,
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

	var _perf_start: int = Time.get_ticks_usec() if debug_perf_log else 0
	var _perf_counters: Array[int] = [0, 0, 0, 0]

	var cache: Dictionary = {}
	var raw_paths: Array[Array] = _solve_recursive(remaining, darts_left, cache, _perf_counters)

	# Rank and limit
	raw_paths.sort_custom(_compare_paths)
	if raw_paths.size() > max_displayed_paths:
		raw_paths.resize(max_displayed_paths)

	if debug_perf_log:
		var ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0
		_perf_log("solve_checkout r=%d d=%d  %.1fms  recursive_calls=%d  spec_calls=%d  cache_hits=%d  cache_misses=%d  paths=%d" % [remaining, darts_left, ms, _perf_counters[0], _perf_counters[1], _perf_counters[2], _perf_counters[3], raw_paths.size()])

	return raw_paths


## Check if a ring name is a valid checkout finish given current reward rules.
func _is_valid_finish(ring_name: String) -> bool:
	if glass_cannon_active:
		return ring_name != "Off Board"
	if ring_name == "Double" or ring_name == "Double Bull":
		return true
	if allow_triple_checkout and ring_name == "Triple":
		return true
	return false


func _solve_recursive(remaining: int, darts_left: int, cache: Dictionary, _pc: Array[int] = [0, 0, 0, 0]) -> Array[Array]:
	_pc[0] += 1
	if darts_left <= 0 or remaining <= 0:
		return []

	if _max_single_dart_score > 0 and remaining > _max_single_dart_score * darts_left:
		var cache_key_neg: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
		cache[cache_key_neg] = []
		return []

	var cache_key: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
	if cache.has(cache_key):
		_pc[2] += 1
		return cache[cache_key]
	_pc[3] += 1

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
		_pc[1] += 1
		var scored: int = result["total_score"]

		var ring_name: String = target["ring_name"]

		var step: Dictionary = {"target": target, "result": result}

		if scored == remaining and _is_valid_finish(ring_name):
			# Checkout on this dart
			paths.append([step])
		elif scored < remaining and scored >= 0 and darts_left > 1:
			var new_remaining: int = remaining - scored
			# Prune: can't finish from 1 (unless Glass Cannon is active — any ring works)
			if new_remaining != 1 or glass_cannon_active:
				var sub_paths: Array[Array] = _solve_recursive(new_remaining, darts_left - 1, cache, _pc)
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


## Check if a wedge's inner and outer singles produce different total_score
## under the current scoring pipeline (preview mode, no streak mutation).
func singles_diverge(wedge_index: int) -> bool:
	if wedge_index < 0 or wedge_index >= effective_wedge_values.size():
		return false
	var face_value: int = effective_wedge_values[wedge_index]
	var colors: Dictionary = effective_wedge_colors[wedge_index]
	var inner_synth: Dictionary = {
		"face_value": face_value, "multiplier": 1, "total_score": face_value,
		"ring_name": "Inner Single", "wedge_index": wedge_index,
		"segment_color": colors.get("inner_single", -1), "is_bull": false,
	}
	var outer_synth: Dictionary = {
		"face_value": face_value, "multiplier": 1, "total_score": face_value,
		"ring_name": "Outer Single", "wedge_index": wedge_index,
		"segment_color": colors.get("outer_single", -1), "is_bull": false,
	}
	var inner_result: Dictionary = process_score(inner_synth, true)
	var outer_result: Dictionary = process_score(outer_synth, true)
	return inner_result["total_score"] != outer_result["total_score"]


## Get a display-friendly name for a target (e.g., "T20", "D-Bull", "S5").
## Singles show "Inner S18" / "Outer S18" only when the wedge's two singles diverge.
func get_target_display_name(target: Dictionary) -> String:
	var ring: String = target["ring_name"]
	var face: int = target["face_value"]
	match ring:
		"Inner Single":
			var wi: int = target.get("wedge_index", -1)
			if wi >= 0 and singles_diverge(wi):
				return "Inner S%d" % face
			return "S%d" % face
		"Outer Single":
			var wi: int = target.get("wedge_index", -1)
			if wi >= 0 and singles_diverge(wi):
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

	if _one_dart_finishable_dirty:
		_compute_one_dart_finishable()

	var _perf_start: int = Time.get_ticks_usec() if debug_perf_log else 0

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
	_max_preferred_remainder = _preferred_remainders[-1] if _preferred_remainders.size() > 0 else 0

	if debug_perf_log:
		var ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0
		_perf_log("compute_preferred_remainders  %.1fms  results=%d" % [ms, _preferred_remainders.size()])


## Existence-only checkout solver. Returns true as soon as any valid path is
## found, without enumerating the full set. Used by compute_preferred_remainders
## which only cares about whether checkouts exist, not what they look like.
## Cache stores bool results keyed by (remaining, darts_left, streak_state).
func _solve_first(remaining: int, darts_left: int, cache: Dictionary) -> bool:
	if darts_left <= 0 or remaining <= 0:
		return false

	if _max_single_dart_score > 0 and remaining > _max_single_dart_score * darts_left:
		return false

	var cache_key: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
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

		if scored == remaining and _is_valid_finish(ring_name):
			found = true
		elif scored < remaining and scored >= 0 and darts_left > 1:
			var new_remaining: int = remaining - scored
			if new_remaining != 1 or glass_cannon_active:
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
	var _perf_start: int = Time.get_ticks_usec() if debug_perf_log else 0
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
			color = effective_wedge_colors[wedge_idx]["double"]
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

	# Compute _max_single_dart_score by sweeping all scoring candidates.
	# Streak state is already turn-fresh from the reset above.
	if _solver_candidates.is_empty():
		_build_solver_candidates()
	_max_single_dart_score = 0
	for target: Dictionary in _solver_candidates:
		if target["face_value"] * target["multiplier"] <= 0:
			continue
		var snap: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = process_score(synth, true)
		if result["total_score"] > _max_single_dart_score:
			_max_single_dart_score = result["total_score"]
		restore_all_streak_state(snap)

	restore_all_streak_state(saved)
	_one_dart_finishable_dirty = false

	if debug_perf_log:
		var ms: float = (Time.get_ticks_usec() - _perf_start) / 1000.0
		_perf_log("_compute_one_dart_finishable  %.1fms  entries=%d" % [ms, _one_dart_finishable.size()])


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
	if debug_perf_log:
		_perf_log("invalidate_preferred_remainders")
		print_stack()


## Recommend a single setup target when no checkout exists this turn.
## Returns {target, result, resulting_remainder, mode} where mode is a
## ScoringEnums.SetupMode value. Modes evaluated in priority order:
##   ENDGAME_SETUP — scoring dart lands at a 1-dart-finishable remainder.
##   SCORE_REDUCTION — too far from checkout range; just score points.
##   MID_ZONE_SETUP — scoring dart lands in preferred remainders.
##   OFF_BOARD_PRESERVE — every scoring dart busts or leaves remainder=1.
func get_setup_recommendation(remaining: int) -> Dictionary:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	var one_dart: Dictionary = get_one_dart_finishable()
	var preferred: Array[int] = get_preferred_remainders()

	# Mode 2: Endgame setup — scan for candidates landing at 1-dart finishable.
	var endgame_best: Dictionary = {}
	var endgame_key: Array = []

	var saved: Array[Dictionary] = snapshot_all_streak_state()

	for target: Dictionary in _solver_candidates:
		var base_score: int = target["face_value"] * target["multiplier"]
		if base_score <= 0 or base_score > remaining:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]
		restore_all_streak_state(snapshot)

		var new_remaining: int = remaining - scored
		if new_remaining < 2 or scored > remaining:
			continue

		if one_dart.has(new_remaining):
			var key: Array = [one_dart[new_remaining], new_remaining]
			if endgame_key.is_empty() or key < endgame_key:
				endgame_best = {
					"target": target, "result": result,
					"resulting_remainder": new_remaining,
					"mode": ScoringEnums.SetupMode.ENDGAME_SETUP,
				}
				endgame_key = key

	restore_all_streak_state(saved)

	if not endgame_best.is_empty():
		return endgame_best

	# Mode 3: Score-reduction — no scoring dart can reach preferred remainders.
	if remaining - _max_single_dart_score > _max_preferred_remainder:
		return {
			"target": {}, "result": {},
			"resulting_remainder": remaining,
			"mode": ScoringEnums.SetupMode.SCORE_REDUCTION,
		}

	# Mode 4: Mid-zone setup — scoring dart lands in preferred remainders.
	var midzone_best: Dictionary = {}
	var midzone_key: Array = []

	saved = snapshot_all_streak_state()

	for target: Dictionary in _solver_candidates:
		var base_score: int = target["face_value"] * target["multiplier"]
		if base_score <= 0 or base_score > remaining:
			continue

		var snapshot: Array[Dictionary] = snapshot_all_streak_state()
		var synth: Dictionary = synthesize_result(target)
		var result: Dictionary = speculative_score(synth)
		var scored: int = result["total_score"]
		restore_all_streak_state(snapshot)

		var new_remaining: int = remaining - scored
		if new_remaining < 2 or scored > remaining:
			continue

		if new_remaining in preferred:
			var key: Array = [999, new_remaining]
			if midzone_key.is_empty() or key < midzone_key:
				midzone_best = {
					"target": target, "result": result,
					"resulting_remainder": new_remaining,
					"mode": ScoringEnums.SetupMode.MID_ZONE_SETUP,
				}
				midzone_key = key

	restore_all_streak_state(saved)

	if not midzone_best.is_empty():
		return midzone_best

	# Mode 5: Off-board preservation — every scoring dart busts.
	return {
		"target": {"ring_name": "Off Board", "face_value": 0, "multiplier": 0,
			"wedge_index": -1, "segment_color": -1, "is_bull": false},
		"result": {"total_score": 0},
		"resulting_remainder": remaining,
		"mode": ScoringEnums.SetupMode.OFF_BOARD_PRESERVE,
	}


## Calculate which segments would win the leg at the given remaining score.
## Checks doubles (always), triples (if allow_triple_checkout), and all rings (if glass_cannon_active).
func calculate_checkout_segments(remaining_score: int) -> Array[Dictionary]:
	var checkout_segments: Array[Dictionary] = []

	# Rings to check for wedge-based finishes
	var finish_rings: Array[Dictionary] = [
		{"ring_name": "Double", "multiplier": 2, "type": "wedge"},
	]
	if allow_triple_checkout or glass_cannon_active:
		finish_rings.append({"ring_name": "Triple", "multiplier": 3, "type": "triple_wedge"})
	if glass_cannon_active:
		finish_rings.append({"ring_name": "Inner Single", "multiplier": 1, "type": "single_wedge", "ring_key": "inner_single"})
		finish_rings.append({"ring_name": "Outer Single", "multiplier": 1, "type": "single_wedge", "ring_key": "outer_single"})

	for wedge_idx: int in range(20):
		var face_value: int = effective_wedge_values[wedge_idx]
		var colors: Dictionary = {}
		if effective_wedge_colors.size() == 20:
			colors = effective_wedge_colors[wedge_idx]
		else:
			var is_even: bool = wedge_idx % 2 == 0
			var sc: int = ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE
			var mc: int = ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
			colors = {"inner_single": sc, "triple": mc, "outer_single": sc, "double": mc}

		for ring_info: Dictionary in finish_rings:
			var mult: int = ring_info["multiplier"]
			var ring_name: String = ring_info["ring_name"]
			var ring_key: String = _ring_name_to_key(ring_name)
			var synthetic_result: Dictionary = {
				"face_value": face_value,
				"multiplier": mult,
				"total_score": face_value * mult,
				"ring_name": ring_name,
				"wedge_index": wedge_idx,
				"segment_color": colors[ring_key],
				"is_bull": false,
			}
			var modified_result: Dictionary = process_score(synthetic_result, true)
			if modified_result["total_score"] == remaining_score:
				var seg_entry: Dictionary = {"type": ring_info["type"], "wedge_idx": wedge_idx}
				if ring_info.has("ring_key"):
					seg_entry["ring_key"] = ring_info["ring_key"]
				checkout_segments.append(seg_entry)

	# Check double bull (always a valid finish)
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

	# Check single bull (Glass Cannon only)
	if glass_cannon_active:
		var single_bull: Dictionary = {
			"face_value": 25,
			"multiplier": 1,
			"total_score": 25,
			"ring_name": "Single Bull",
			"wedge_index": -1,
			"segment_color": ScoringEnums.SegmentColor.GREEN,
			"is_bull": true,
		}
		var modified_sb: Dictionary = process_score(single_bull, true)
		if modified_sb["total_score"] == remaining_score:
			checkout_segments.append({"type": "single_bull"})

	return checkout_segments


## Find all board segments that produce a given total_score under the current
## scoring pipeline. Used by path illumination to highlight equivalent aims.
## When is_finish is true, only includes segments with valid checkout rings.
func find_equivalent_segments(target_score: int, is_finish: bool = false) -> Array[Dictionary]:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	var equivalents: Array[Dictionary] = []
	for candidate: Dictionary in _solver_candidates:
		var ring_name: String = candidate["ring_name"]
		if ring_name == "Off Board":
			continue
		if is_finish and not _is_valid_finish(ring_name):
			continue
		var synth: Dictionary = synthesize_result(candidate)
		var result: Dictionary = process_score(synth, true)
		if result["total_score"] == target_score:
			equivalents.append(_candidate_to_segment_descriptor(candidate))
	return equivalents


func _candidate_to_segment_descriptor(candidate: Dictionary) -> Dictionary:
	var ring: String = candidate["ring_name"]
	var wedge_idx: int = candidate.get("wedge_index", -1)
	match ring:
		"Double":
			return {"type": "wedge", "wedge_idx": wedge_idx}
		"Triple":
			return {"type": "triple_wedge", "wedge_idx": wedge_idx}
		"Inner Single":
			return {"type": "single_wedge", "wedge_idx": wedge_idx, "ring_key": "inner_single"}
		"Outer Single":
			return {"type": "single_wedge", "wedge_idx": wedge_idx, "ring_key": "outer_single"}
		"Double Bull":
			return {"type": "double_bull"}
		"Single Bull":
			return {"type": "single_bull"}
	return {}
