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

## The rarity tier of this modifier instance.
@export var rarity_tier: ScoringEnums.Rarity = ScoringEnums.Rarity.COMMON

## Which streak slot category this modifier occupies.
## NONE means no slot restriction (non-streak modifiers).
## Streak modifiers set this to their category so the one-per-category rule can be enforced.
@export var streak_category: ScoringEnums.StreakCategory = ScoringEnums.StreakCategory.NONE

## Whether this modifier appears in the HUD modifier panel after acquisition.
## RELIC modifiers persist as inventory items. BOARD_MUTATION modifiers fire
## once and then leave only their effect on the board.
@export var kind: ScoringEnums.ModifierKind = ScoringEnums.ModifierKind.RELIC

## Whether this modifier is currently active. Only toggleable if unlocked.
var enabled: bool = true

## Whether the player can toggle this modifier on/off. Locked modifiers stay active.
var toggleable: bool = false

## Rarity name for display — derived from rarity_tier.
var rarity: String:
	get:
		return ScoringEnums.RARITY_DATA[rarity_tier]["name"]

## Rarity color for card/button tinting — derived from rarity_tier.
var rarity_color: Color:
	get:
		return ScoringEnums.RARITY_DATA[rarity_tier]["color"]


## Visual icon shape for the modifier panel. Override in RELIC subclasses.
func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.NONE


## Get the current streak count for display purposes.
## Override in streak modifier subclasses. Returns 0 for non-streak modifiers.
func get_streak_count() -> int:
	return 0


## Get a short display name for what this streak tracks (e.g., "Ring ×3").
## Override in streak modifier subclasses. Returns "" for non-streak modifiers.
func get_streak_display() -> String:
	return ""


## Return true if hitting target would continue this modifier's active streak.
## Override in streak modifier subclasses.
func would_continue_streak(_target: Dictionary) -> bool:
	return false


## Snapshot internal streak state for speculative simulation.
## Override in streak modifier subclasses. Returns empty dict for non-streak modifiers.
func save_streak_state() -> Dictionary:
	return {}


## Restore internal streak state from a snapshot.
## Override in streak modifier subclasses.
func restore_streak_state_from(snapshot: Dictionary) -> void:
	pass


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
		"source_modifier": self,
		"field": field,
		"old_value": old_value,
		"new_value": new_value,
	})


## Chance (0-100) that a generated modifier is unlocked (toggleable).
## The remaining percentage produces locked (always-on) modifiers.
const UNLOCK_CHANCE: int = 35


## Roll whether this modifier is toggleable. Call from subclass generate().
func roll_toggleable() -> void:
	toggleable = randi_range(1, 100) <= UNLOCK_CHANCE


## Relative weight for how likely this modifier type is to appear in the pool.
static func get_pool_weight() -> int:
	return 10


## Internal rarity distribution: [common_weight, uncommon_weight, rare_weight].
static func get_rarity_weights() -> Array[int]:
	return [65, 25, 10]


## Generate a random instance of this modifier type at the given rarity.
## Override in subclasses to randomize type-specific parameters.
static func generate(_rarity_tier: ScoringEnums.Rarity) -> ScoringModifier:
	return null


## Roll a rarity tier using the given weights [common, uncommon, rare].
static func roll_rarity(weights: Array[int]) -> ScoringEnums.Rarity:
	var total: int = weights[0] + weights[1] + weights[2]
	var roll: int = randi_range(1, total)
	if roll <= weights[0]:
		return ScoringEnums.Rarity.COMMON
	elif roll <= weights[0] + weights[1]:
		return ScoringEnums.Rarity.UNCOMMON
	else:
		return ScoringEnums.Rarity.RARE
