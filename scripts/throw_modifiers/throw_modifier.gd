class_name ThrowModifier
extends Resource
## Base class for conditional throw stat modifiers.
## Subclass this and override should_activate() to create new effects.
## Stat bonuses are applied temporarily before each throw and reverted after.

## Human-readable name shown in tooltips and HUD.
@export var modifier_name: String = ""

## Description of the condition and effect, shown on hover.
@export var description: String = ""

## Color used for the status text and description when this modifier is active.
@export var active_color: Color = Color(0.3, 1.0, 0.4)

## --- Temporary stat bonuses applied when the condition is met ---
## All default to 0.0. Only set the ones this modifier affects.

## Temporary bonus to horizontal_range while active.
@export var h_range_bonus: float = 0.0

## Temporary bonus to vertical_range while active.
@export var v_range_bonus: float = 0.0

## Temporary bonus to horizontal_speed while active.
@export var h_speed_bonus: float = 0.0

## Temporary bonus to vertical_speed while active.
@export var v_speed_bonus: float = 0.0

## Temporary bonus to horizontal_accuracy while active.
@export var h_accuracy_bonus: float = 0.0

## Temporary bonus to vertical_accuracy while active.
@export var v_accuracy_bonus: float = 0.0

## Temporary override for gaussian_spread while active.
## Lower value = tighter clustering toward aim point during the throw.
## Set to 0.0 to leave gaussian_spread unchanged (0.0 means "no override").
@export_range(0.0, 0.6, 0.01) var gaussian_spread_override: float = 0.0


## Override in subclasses. Return true if this modifier should activate
## for the current throw. Context dictionary contains game state info:
## - "remaining_score": int — current x01 remaining score
## - "target_score": int — the leg's starting target (101, 201, etc.)
## - "darts_this_turn": int — how many darts thrown this turn (0, 1, or 2)
## - "current_turn": int — which turn of the leg (1-based)
## - "current_leg": int — which leg of the run (1-based)
## - "max_turns": int — total turns allowed per leg
func should_activate(context: Dictionary) -> bool:
	return false


## Returns a dictionary of all non-zero stat bonuses for tooltip display.
func get_active_bonuses() -> Dictionary:
	var bonuses: Dictionary = {}
	if h_range_bonus != 0.0:
		bonuses["horizontal_range"] = h_range_bonus
	if v_range_bonus != 0.0:
		bonuses["vertical_range"] = v_range_bonus
	if h_speed_bonus != 0.0:
		bonuses["horizontal_speed"] = h_speed_bonus
	if v_speed_bonus != 0.0:
		bonuses["vertical_speed"] = v_speed_bonus
	if h_accuracy_bonus != 0.0:
		bonuses["horizontal_accuracy"] = h_accuracy_bonus
	if v_accuracy_bonus != 0.0:
		bonuses["vertical_accuracy"] = v_accuracy_bonus
	return bonuses
