class_name DrunkardBoss
extends Boss
## Attacks the throw mechanic rather than the board (a new boss axis). One unified
## "drunk = loose, wandering aim" fantasy:
##   1. Distorted crosshair — the release marker rides a learnable zigzag track (warped
##      bounce→position mapping), so timing the lock is harder. Learnable, not jitter.
##   2. Enforced minimum meter length — floors the meter half-length to a base plus extra
##      scaled by (100 − range stat) per axis. This claws back the most from a maxed-
##      accuracy player (whose meters would otherwise be tiny) and barely touches a
##      low-stat one — self-balancing — and ensures the wobble has room to bite. The floor
##      is partly eased by Range so investment still matters (DRUNK_FLOOR_RANGE_EASE), and
##      the bounce rate is partly compensated for the stretch so the longer meter doesn't
##      silently inflate marker pixel-speed past the player's Speed Control
##      (DRUNK_SPEED_COMPENSATION) — both live in ThrowMechanic.
##
## Counters maxed accuracy stats. Hooks ThrowMechanic via set_drunk_distortion().
##
## Tuning keys (all scale wobble + floor by difficulty tier):
##   "warp_amp"    (float, default 0.18): zigzag depth (fraction of meter half-length).
##   "freq"        (float, default 3.0):  zigzag lobe count along the meter.
##   "perp_amp"    (float, default 22.0): visual squiggle width in px.
##   "floor_base"  (float, default 130.0): base enforced meter half-length in px.
##   "floor_scale" (float, default 90.0):  extra floor scaled by (100 − range).

var warp_amp: float = 0.18
var freq: float = 3.0
var perp_amp: float = 22.0
var floor_base: float = 130.0
var floor_scale: float = 90.0


func configure(tuning: Dictionary) -> void:
	warp_amp = tuning.get("warp_amp", 0.18)
	freq = tuning.get("freq", 3.0)
	perp_amp = tuning.get("perp_amp", 22.0)
	floor_base = tuning.get("floor_base", 130.0)
	floor_scale = tuning.get("floor_scale", 90.0)


func on_leg_start(game_state: Dictionary) -> void:
	var throw_mechanic: Node2D = game_state["throw_mechanic"]
	throw_mechanic.set_drunk_distortion(warp_amp, freq, perp_amp, floor_base, floor_scale)


func on_leg_end(game_state: Dictionary) -> void:
	var throw_mechanic: Node2D = game_state["throw_mechanic"]
	throw_mechanic.clear_drunk_distortion()


func get_status_text() -> String:
	return "Your aim wanders — the meters won't shrink"
