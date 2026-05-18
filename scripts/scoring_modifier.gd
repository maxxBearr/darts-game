class_name ScoringModifier
extends Resource
## Base class for all scoring modifiers. Subclass this to create specific modifier types.
## ON_ACQUIRE modifiers override apply_to_board() to change wedge values/colors.
## PER_DART modifiers override apply() to transform score results each throw.

## Human-readable name shown on the upgrade card and in the modifier list.
@export var modifier_name: String = ""

## Description shown on hover/inspect. Should explain the effect clearly.
@export var description: String = ""

## When this modifier fires in the scoring pipeline.
@export var timing: ScoringEnums.ModifierTiming = ScoringEnums.ModifierTiming.PER_DART

## Streak scope — how long hit history persists for this modifier.
## Only relevant for PER_DART modifiers that read hit history.
@export var streak_scope: ScoringEnums.StreakScope = ScoringEnums.StreakScope.NONE

## Config type — whether the player must make a selection after acquiring.
@export var config_type: ScoringEnums.ConfigType = ScoringEnums.ConfigType.NONE

## Rarity name for display (e.g., "Common", "Uncommon", "Rare").
@export var rarity: String = "Common"

## Rarity color for card/button tinting.
@export var rarity_color: Color = Color(0.6, 0.6, 0.6)


## Override in PER_DART subclasses. Receives the enriched score dictionary and
## a context dictionary containing hit history arrays and board state.
## Return the modified result dictionary.
func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	return result


## Override in ON_ACQUIRE subclasses. Mutate the wedge_values and/or wedge_colors
## arrays in place. config contains player choices (e.g., {"wedge_index": 5}).
func apply_to_board(wedge_values: Array[int], wedge_colors: Array[Dictionary], config: Dictionary) -> void:
	pass


## Record a modification entry in the result's tracking array.
## Call this from apply() before changing the value, so old_value is captured.
func _track_modification(result: Dictionary, field: String, old_value: Variant, new_value: Variant) -> void:
	if not result.has("modifications"):
		result["modifications"] = []
	result["modifications"].append({
		"source_name": modifier_name,
		"source_description": description,
		"source_rarity_color": rarity_color,
		"field": field,
		"old_value": old_value,
		"new_value": new_value,
	})
