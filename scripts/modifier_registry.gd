class_name ModifierRegistry
extends RefCounted
## Central registry of all scoring modifier types available in the item pool.
## Handles weighted random selection and rarity rolling to produce fully
## configured modifier instances ready for the player to acquire.

const _ColorBonus = preload("res://scripts/modifiers/color_bonus_modifier.gd")
const _WedgeValue = preload("res://scripts/modifiers/wedge_value_modifier.gd")
const _StreakBonus = preload("res://scripts/modifiers/streak_bonus_modifier.gd")
const _WedgeSwap = preload("res://scripts/modifiers/wedge_swap_modifier.gd")
const _OddEvenBonus = preload("res://scripts/modifiers/odd_even_bonus_modifier.gd")
const _ColorFlip = preload("res://scripts/modifiers/color_flip_modifier.gd")

const MODIFIER_TYPES: Array = [
	_ColorBonus,
	_WedgeValue,
	_StreakBonus,
	_WedgeSwap,
	_OddEvenBonus,
	_ColorFlip,
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

	var rarity_weights: Array[int] = chosen_type.get_rarity_weights()
	var rarity: ScoringEnums.Rarity = ScoringModifier.roll_rarity(rarity_weights)
	return chosen_type.generate(rarity)


## Generate a random modifier of a specific type by index.
static func generate_of_type(type_index: int) -> ScoringModifier:
	var chosen_type = MODIFIER_TYPES[clampi(type_index, 0, MODIFIER_TYPES.size() - 1)]
	var rarity_weights: Array[int] = chosen_type.get_rarity_weights()
	var rarity: ScoringEnums.Rarity = ScoringModifier.roll_rarity(rarity_weights)
	return chosen_type.generate(rarity)


## Generate N distinct random modifiers (no duplicate types unless N > type count).
static func generate_distinct(count: int) -> Array[ScoringModifier]:
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

	for _n: int in range(count):
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
		results.append(generate_of_type(chosen_global_idx))
		available_indices.remove_at(chosen_local)

	return results


## Get the total number of modifier types in the pool.
static func get_type_count() -> int:
	return MODIFIER_TYPES.size()
