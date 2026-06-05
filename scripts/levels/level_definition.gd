class_name LevelDefinition
extends Resource
## Configuration for a single selectable run level. Each level defines a score
## cap, boss count, and unlock requirements.

## The maximum score target for this level — the final leg's target.
## Player wins the run by clearing the leg at this cap.
## Must be a multiple of target_increment + starting_target (e.g. 501, 1001).
@export var max_score_target: int = 501

## How many boss encounters appear during this run.
## Bosses are scheduled at every-5-legs intervals.
@export var boss_count: int = 1

## Pool of boss types this level draws from.
## Earlier levels should use softer bosses; later levels include brutal ones.
@export var boss_pool: Array[Resource] = []

## Rarity weight shift applied to all modifier rolls during this run.
## Negative shifts toward common; positive shifts toward rare.
## Recommended: -0.025 for 501, 0.0 for 1001, +0.025 for 1501.
@export var rarity_weight_shift: float = 0.0

## Display name shown on the level select screen.
@export var display_name: String = "501"

## Unlock condition for this level. Null means always unlocked (starter level).
@export var unlock_condition: UnlockCondition

## Map generation tuning for this level (lanes, column counts, shop mix/spacing,
## fork chance, dart budget). Null falls back to MapGenConfig's defaults. The run
## map's act count is taken from boss_count, not from here.
@export var map_gen_config: MapGenConfig
