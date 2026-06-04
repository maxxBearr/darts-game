extends Node2D
## A simple visual marker representing a dart stuck in the board. While its landing spot is part
## of an active scoring streak it emits a recurring shockwave-style pulse, brightening grey -> white
## the longer the streak (driven by streak_level, set by main._refresh_streak_pulses()).

## Color of the outer ring.
var dart_color: Color = Color(0.9, 0.85, 0.0)

## Color of the inner center dot.
var dart_inner_color: Color = Color(0.2, 0.2, 0.2)

## Radius of this dart marker in pixels.
var dart_size: float = 5.0

## This dart's landing spot (wedge_index, ring_name, segment_color, is_bull) — lets the manager
## decide whether the dart is part of an active streak. Empty for untracked darts (e.g. shop).
var hit_target: Dictionary = {}

## Active streak length this dart belongs to. 0 or 1 = no pulse; >= 2 pulses, brighter with count.
var streak_level: int = 0:
	set(value):
		if value == streak_level:
			return
		streak_level = value
		set_process(streak_level > 1)
		if streak_level <= 1:
			_pulse_phase = 0.0
		queue_redraw()

## Animation phase (0..1) for the looping pulse.
var _pulse_phase: float = 0.0

## Seconds per pulse cycle at the lowest pulsing streak (level 2) — the slow start.
const _PULSE_PERIOD_SLOW: float = 1.5
## Fastest pulse cycle (floor) once the streak is long.
const _PULSE_PERIOD_FAST: float = 0.55
## How much each streak level above 2 shortens the cycle (i.e. speeds the pulse up).
const _PULSE_SPEEDUP_PER_LEVEL: float = 0.13
## How far the pulse ring expands beyond the dart, in pixels.
const _PULSE_REACH: float = 16.0


## Current pulse cycle length: starts slow at streak 2 and ramps faster (toward the floor) the
## longer the streak — so the pulse speeds up alongside the grey -> white brightness ramp.
func _pulse_period() -> float:
	return maxf(_PULSE_PERIOD_SLOW - _PULSE_SPEEDUP_PER_LEVEL * float(streak_level - 2), _PULSE_PERIOD_FAST)


func _ready() -> void:
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_phase += delta / _pulse_period()
	if _pulse_phase >= 1.0:
		_pulse_phase -= 1.0
	queue_redraw()


func _draw() -> void:
	# Recurring streak pulse (drawn under the dart so the marker stays crisp). Two staggered rings
	# read as a continuous pulse; brightness ramps grey (streak 2) toward white (long streak).
	if streak_level > 1:
		var bright: float = clampf(0.45 + 0.12 * float(streak_level - 2), 0.45, 1.0)
		for phase_offset: float in [0.0, 0.5]:
			var p: float = fmod(_pulse_phase + phase_offset, 1.0)
			var radius: float = dart_size + _PULSE_REACH * p
			var alpha: float = (1.0 - p) * 0.8
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(bright, bright, bright, alpha), 2.0, true)

	draw_circle(Vector2.ZERO, dart_size, dart_color)
	draw_circle(Vector2.ZERO, dart_size * 0.4, dart_inner_color)
