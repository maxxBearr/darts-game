class_name BossDefinition
extends Resource
## Holds boss-specific tuning and a reference to its behavior script.
## One BossDefinition per boss type; boss_pool arrays in LevelDefinition
## reference these.

## Unique stable identifier for this boss. Used in save data and analytics.
@export var boss_id: StringName

## Display name shown on the boss-start notification.
@export var display_name: String = "The Void"

## One-line description of the debuff, shown on the boss-start notification.
@export var description: String = "5 random wedges become voids."

## The boss behavior script. Must be a subclass of Boss.
@export var boss_script: GDScript

## Per-variant tuning values passed to the boss instance via configure().
## Keys and types depend on the boss script. E.g., {"void_count": 6} for Void.
@export var tuning: Dictionary = {}

## Difficulty tier for this variant. Documentation/sorting field; the active
## pool comes from LevelDefinition.boss_pool, which is manually curated.
## Values by convention: &"easy", &"medium", &"hard".
@export var difficulty_tier: StringName = &"easy"

@export_group("Visual Theme")

## Color of the boss name in the announcement and status label.
@export var title_color: Color = Color(0.9, 0.2, 0.2)

## Color of the description text in the announcement popup.
@export var description_color: Color = Color(0.85, 0.75, 0.65)

## Color of the persistent status text shown during the boss leg.
@export var status_color: Color = Color(0.9, 0.2, 0.2)

## Background tint overlaid on the game area during the boss leg.
## Use low alpha (0.05-0.15) for a subtle mood shift.
@export var background_tint: Color = Color(0.0, 0.0, 0.0, 0.0)
