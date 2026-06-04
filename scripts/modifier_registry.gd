class_name ModifierRegistry
extends RefCounted
## Central registry of all scoring modifier types available in the item pool.
## Handles weighted random selection and rarity rolling to produce fully
## configured modifier instances ready for the player to acquire.

const _WedgeValue = preload("res://scripts/modifiers/wedge_value_modifier.gd")
const _StreakBonus = preload("res://scripts/modifiers/streak_bonus_modifier.gd")
const _WedgeSwap = preload("res://scripts/modifiers/wedge_swap_modifier.gd")
const _Brush = preload("res://scripts/modifiers/brush_modifier.gd")
const _ColorStreak = preload("res://scripts/modifiers/color_streak_modifier.gd")
const _Hotspot = preload("res://scripts/modifiers/hotspot_modifier.gd")

## Rarity weight shift applied to all modifier rolls during the current run.
## Set from main.gd based on LevelDefinition.rarity_weight_shift.
static var current_rarity_shift: float = 0.0

## Colors available for BrushModifier generation. Set by the shop call site
## based on which color modifiers the player owns. Empty = no brushes offered.
static var available_brush_colors: Array[ScoringEnums.SegmentColor] = []

## Apply the current rarity shift to a [common, uncommon, rare] weight array.
## Positive shift moves weight from common to rare; negative does the reverse.
static func _shifted_weights(weights: Array[int]) -> Array[int]:
	if current_rarity_shift == 0.0:
		return weights
	var shift_amount: int = int(absf(current_rarity_shift) * float(weights[0] + weights[1] + weights[2]))
	var result: Array[int] = [weights[0], weights[1], weights[2]]
	if current_rarity_shift > 0.0:
		result[0] = maxi(result[0] - shift_amount, 1)
		result[2] = result[2] + shift_amount
	else:
		result[2] = maxi(result[2] - shift_amount, 1)
		result[0] = result[0] + shift_amount
	return result


## The live item pool after the scoring-on-the-board migration. Three board-item
## families (Scoring / Placement / Brush) plus the two streak axes:
##   Scoring:   Hotspot, Wedge Value
##   Placement: Wedge Swap
##   Brush:     Brush (affinity-gated — weight 0 until the player owns a color)
##   Streaks:   Wedge Streak (shaft-gated), Color Streak (barrel-gated)
## Dropped from the pool: ColorBonus, OddEvenBonus, Even/Odd/Parity streaks (anti-spatial
## globals/parity). Sidelined: FlipSign (class + Mirror-Zone relic kept, just unlisted).
const MODIFIER_TYPES: Array = [
	_Hotspot,
	_WedgeValue,
	_WedgeSwap,
	_Brush,
	_StreakBonus,
	_ColorStreak,
]


## Generate a fully random modifier: pick a type from the pool (weighted),
## roll its rarity, and return a configured instance.
static func generate_random() -> ScoringModifier:
	var total_weight: int = 0
	var weights: Array[int] = []
	for type in MODIFIER_TYPES:
		var weight: int = type.get_pool_weight()
		weights.append(weight)
		total_weight += weight

	var roll: int = randi_range(1, total_weight)
	var cumulative: int = 0
	var chosen_type = MODIFIER_TYPES[0]
	for i: int in range(MODIFIER_TYPES.size()):
		cumulative += weights[i]
		if roll <= cumulative:
			chosen_type = MODIFIER_TYPES[i]
			break

	var rarity_weights: Array[int] = _shifted_weights(chosen_type.get_rarity_weights())
	var rarity: ScoringEnums.Rarity = ScoringModifier.roll_rarity(rarity_weights)
	return chosen_type.generate(rarity)


## Generate a random modifier of a specific type by index.
static func generate_of_type(type_index: int) -> ScoringModifier:
	var chosen_type = MODIFIER_TYPES[clampi(type_index, 0, MODIFIER_TYPES.size() - 1)]
	var rarity_weights: Array[int] = _shifted_weights(chosen_type.get_rarity_weights())
	var rarity: ScoringEnums.Rarity = ScoringModifier.roll_rarity(rarity_weights)
	return chosen_type.generate(rarity)


## Generate N distinct random modifiers (no duplicate types unless N > type count).
## excluded_fingerprints: fingerprints to reject (owned inventory + intra-batch).
static func generate_distinct(count: int, excluded_fingerprints: Array[String] = []) -> Array[ScoringModifier]:
	var results: Array[ScoringModifier] = []

	if count >= MODIFIER_TYPES.size():
		for i: int in range(MODIFIER_TYPES.size()):
			results.append(generate_of_type(i))
		while results.size() < count:
			results.append(generate_random())
		return results

	var available_indices: Array[int] = []
	for i: int in range(MODIFIER_TYPES.size()):
		available_indices.append(i)

	while results.size() < count and not available_indices.is_empty():
		var total_weight: int = 0
		var weights: Array[int] = []
		for idx: int in available_indices:
			var weight: int = MODIFIER_TYPES[idx].get_pool_weight()
			weights.append(weight)
			total_weight += weight

		var roll: int = randi_range(1, total_weight)
		var cumulative: int = 0
		var chosen_local: int = 0
		for i: int in range(weights.size()):
			cumulative += weights[i]
			if roll <= cumulative:
				chosen_local = i
				break

		var chosen_global_idx: int = available_indices[chosen_local]
		var mod: ScoringModifier = generate_of_type(chosen_global_idx)
		if excluded_fingerprints.size() > 0:
			var attempts: int = 0
			while mod.get_config_fingerprint() in excluded_fingerprints and attempts < 8:
				mod = generate_of_type(chosen_global_idx)
				attempts += 1
			if mod.get_config_fingerprint() in excluded_fingerprints:
				available_indices.remove_at(chosen_local)
				continue
		results.append(mod)
		available_indices.remove_at(chosen_local)

	while results.size() < count:
		results.append(generate_random())

	return results


## Generate N distinct modifiers all at a forced rarity tier.
## Used by the shop system where the hit spot's rarity determines the tier.
## weight_overrides: optional {Script: float_multiplier} to bias pool weights.
## excluded_fingerprints: fingerprints to reject (owned inventory + intra-batch).
static func generate_distinct_at_rarity(count: int, rarity: ScoringEnums.Rarity, weight_overrides: Dictionary = {}, excluded_fingerprints: Array[String] = []) -> Array[ScoringModifier]:
	var results: Array[ScoringModifier] = []

	var available_indices: Array[int] = []
	for i: int in range(MODIFIER_TYPES.size()):
		available_indices.append(i)

	while results.size() < count and not available_indices.is_empty():
		var total_weight: float = 0.0
		var weights: Array[float] = []
		for idx: int in available_indices:
			var base_weight: float = float(MODIFIER_TYPES[idx].get_pool_weight())
			var multiplier: float = weight_overrides.get(MODIFIER_TYPES[idx], 1.0)
			var w: float = base_weight * multiplier
			weights.append(w)
			total_weight += w

		var roll: float = randf() * total_weight
		var cumulative: float = 0.0
		var chosen_local: int = 0
		for i: int in range(weights.size()):
			cumulative += weights[i]
			if roll <= cumulative:
				chosen_local = i
				break

		var chosen_global_idx: int = available_indices[chosen_local]
		var chosen_type = MODIFIER_TYPES[chosen_global_idx]
		var mod: ScoringModifier = chosen_type.generate(rarity)
		if excluded_fingerprints.size() > 0:
			var attempts: int = 0
			while mod.get_config_fingerprint() in excluded_fingerprints and attempts < 8:
				mod = chosen_type.generate(rarity)
				attempts += 1
			if mod.get_config_fingerprint() in excluded_fingerprints:
				available_indices.remove_at(chosen_local)
				continue
		results.append(mod)
		available_indices.remove_at(chosen_local)

	while results.size() < count:
		var fallback_type = MODIFIER_TYPES[randi_range(0, MODIFIER_TYPES.size() - 1)]
		results.append(fallback_type.generate(rarity))

	return results


## Get the total number of modifier types in the pool.
static func get_type_count() -> int:
	return MODIFIER_TYPES.size()
