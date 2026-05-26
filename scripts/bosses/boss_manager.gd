class_name BossManager
extends Node
## Manages boss scheduling and lifecycle within a run. Tracks which bosses
## have been fought, rolls boss types from the level's pool, and drives
## the active boss's turn/leg hooks.

## Emitted when a boss leg begins. UI should show the announcement.
signal boss_leg_started(boss_definition: BossDefinition)

## Emitted when a boss leg ends (win or loss).
signal boss_leg_ended(boss_definition: BossDefinition, player_won: bool)

## How many legs between boss encounters.
@export var boss_cadence: int = 5

var _current_level: LevelDefinition
var _active_boss: Boss = null
var _active_boss_definition: BossDefinition = null
var _boss_legs_completed: int = 0


## Set up the manager for a new run at the given level.
func configure_for_level(level: LevelDefinition) -> void:
	_current_level = level
	_boss_legs_completed = 0
	_active_boss = null
	_active_boss_definition = null


## Whether the given leg number should be a boss encounter.
func is_boss_leg(leg_number: int) -> bool:
	if _current_level == null or _current_level.boss_pool.is_empty():
		return false
	if _boss_legs_completed >= _current_level.boss_count:
		return false
	return leg_number % boss_cadence == 0


## Roll a boss from the level pool and start the boss leg.
func start_boss_leg(game_state: Dictionary) -> BossDefinition:
	var pool: Array[Resource] = _current_level.boss_pool
	var def: BossDefinition = pool[randi_range(0, pool.size() - 1)] as BossDefinition
	_active_boss_definition = def
	_active_boss = def.boss_script.new() as Boss
	_active_boss.configure(def.tuning)
	_active_boss.on_leg_start(game_state)
	boss_leg_started.emit(def)
	return def


## Forward turn-start to the active boss.
func on_turn_start(game_state: Dictionary) -> void:
	if _active_boss != null:
		_active_boss.on_turn_start(game_state)


## End the current boss leg. Increments completion counter on win.
func end_boss_leg(game_state: Dictionary, player_won: bool) -> void:
	if _active_boss == null:
		return
	_active_boss.on_leg_end(game_state)
	boss_leg_ended.emit(_active_boss_definition, player_won)
	if player_won:
		_boss_legs_completed += 1
	_active_boss = null
	_active_boss_definition = null


## Whether a boss is currently active (mid-boss-leg).
func is_boss_active() -> bool:
	return _active_boss != null


## Get the currently active boss instance, or null.
func get_active_boss() -> Boss:
	return _active_boss


## Get the definition of the currently active boss, or null.
func get_active_boss_definition() -> BossDefinition:
	return _active_boss_definition
