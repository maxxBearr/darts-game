class_name Boss
extends RefCounted
## Base class for boss encounter behaviors. Subclass this and override the
## lifecycle hooks to implement a specific boss debuff.
##
## game_state is a Dictionary containing references to game subsystems:
##   "x01_game": Node, "scoring_modifier_manager": Node,
##   "dartboard": Node2D, "hud": CanvasLayer


## Apply per-variant tuning from BossDefinition.tuning dictionary.
## Override in subclasses to read variant-specific values.
func configure(_tuning: Dictionary) -> void:
	pass


## Called when the boss leg starts. Use this to set up persistent state.
func on_leg_start(_game_state: Dictionary) -> void:
	pass


## Called at the start of each turn (between throws).
## Most boss effects mutate state here.
func on_turn_start(_game_state: Dictionary) -> void:
	pass


## Called immediately after a dart has landed and been scored, once per throw.
## Reactive (build-counter) bosses mutate the board here in response to where the
## player hit. The landing dart's own score is already computed from pre-mutation
## state, so changes made here only affect subsequent darts.
## _result is the scored throw dictionary (wedge_index, ring_name, is_bull, etc.).
func on_dart_landed(_result: Dictionary, _game_state: Dictionary) -> void:
	pass


## Called when the boss leg ends (win or loss). Clean up any mutations.
func on_leg_end(_game_state: Dictionary) -> void:
	pass


## Returns a short status string describing the current boss state.
## Shown persistently during the boss leg. Override in subclasses.
func get_status_text() -> String:
	return ""


## Returns visual overlay instructions for the board renderer.
func get_visual_overlay() -> Array:
	return []
