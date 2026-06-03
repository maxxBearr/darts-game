extends Control
## Left-rail dart tally + saved-dart cache (Darts-as-Currency Phase A).
##
## Replaces the old revolving-three-darts element. Renders the whole fronted-dart
## budget as `max_turns` sets of `darts_per_turn` icons, grouped in threes so "a set
## = a turn" reads spatially. Each icon has four states:
##   bright           = available (a future turn's dart, not yet reached)
##   white outline+pop = active turn (the darts still in hand this turn)
##   dim grey         = spent (already thrown)
##   dim red          = busted (forfeited by a bust — mirrors get_saved_darts folding
##                      busted darts into darts_used_in_leg)
## Set completion plays a one-shot cross-out slash (a transition, not a state).
##
## The saved cache renders banked darts as clusters of three; each completed cluster
## reads as a bonus turn (gold). Every banked dart is drawn — the whole rail scales down
## uniformly to fit large hoards rather than summarising with a "+N" overflow.
##
## Layout here was authored without a live view — every size/colour/gap is an @export
## so the visual pass is a tuning pass, not a rewrite. Drawing is done in _draw() from
## point.png (an existing dart-component PNG, per the "no new art" constraint).
##
## Shop mode is preserved: set_shop_darts()/restore_normal_darts() swap to a simple
## vertical "darts left to throw" stack, exactly as before.

enum DartState { AVAILABLE, ACTIVE, SPENT, BUSTED }

const POINT_TEX: Texture2D = preload("res://sprites/point.png")

@export_group("Rail Layout")
## Target size of each composed-dart icon (wide, short — darts are drawn horizontally,
## point→barrel→shaft→flight). Width is reduced to fit darts_per_turn across the rail;
## height follows from the width to keep the dart's aspect.
@export var icon_size: Vector2 = Vector2(72.0, 22.0)
## Horizontal gap between darts within a set.
@export var dart_gap: float = 4.0
## Vertical gap between sets (turns).
@export var set_gap: float = 6.0
## Top inset before the first set (content is top-aligned so the rail can sit high).
@export var rail_top_margin: float = 4.0
## Vertical gap between the last set and the saved cache that stacks beneath it.
@export var cache_gap: float = 12.0
## Scale multiplier applied to the active turn's icons (the "pop").
@export_range(1.0, 1.5, 0.01) var active_pop_scale: float = 1.12
## Outline thickness (px) drawn around active-turn icons.
@export var active_outline_width: float = 2.0
## Colour of the faint divider between the sets and the cache.
@export var divider_color: Color = Color(1.0, 1.0, 1.0, 0.18)

@export_group("Rail Colours")
@export var color_available: Color = Color(0.95, 0.95, 0.95, 1.0)
@export var color_active: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var color_spent: Color = Color(0.45, 0.45, 0.45, 0.45)
@export var color_busted: Color = Color(0.72, 0.20, 0.16, 0.55)
@export var active_outline_color: Color = Color(1.0, 1.0, 1.0, 0.95)
## Colour of the set-completion slash.
@export var slash_color: Color = Color(0.85, 0.85, 0.85, 0.8)

@export_group("Cache (Saved Darts)")
@export var color_cache: Color = Color(0.45, 0.78, 1.0, 0.95)
## Completed cluster of three = a bonus turn; lit gold.
@export var color_cache_bonus: Color = Color(1.0, 0.82, 0.28, 1.0)
## Colour of the "SAVED DARTS" label above the cache.
@export var cache_label_color: Color = Color(1.0, 1.0, 1.0, 0.6)

@export_group("Composed Dart")
## Per-part size multipliers, applied on top of each component's native texture size
## so the rail dart keeps the same proportions the player assembled. The whole dart is
## then scaled uniformly to fit its icon cell (aspect preserved — never squished).
@export var point_scale: float = 1.0
@export var barrel_scale: float = 0.7
@export var shaft_scale: float = 0.7
@export var flight_scale: float = 0.7

@export_group("Animation")
@export var slash_duration: float = 0.28
@export var trickle_duration: float = 0.6

# --- Leg state ---
## Darts per turn (a set's size). Named _max_darts for the existing hud read path.
var _max_darts: int = 3
var _max_turns: int = 5
var _current_turn: int = 1
var _darts_remaining: int = 3
## turn_number -> true for turns lost to a bust.
var _busted_turns: Dictionary = {}

# --- Cache state ---
var _banked_darts: int = 0
## Animated value the cache actually draws (lets savings trickle in).
var _displayed_bank: float = 0.0

# --- Animation state ---
## turn_number -> slash progress (0..1) while a set-completion slash plays.
var _slash_progress: Dictionary = {}
## Set index briefly highlighted when a bailout funds a new turn.
var _flyin_pulse: float = 0.0

# --- Leg-win trickle ---
## Front cells [{t, d}] banked this leg, ordered last-turn-first so they drain toward
## the cache. Stays populated AFTER the animation so the moved darts remain hidden up
## top until the next leg rebuilds the rail (cleared on leg reset).
var _trickle_cells: Array = []
## How many cells have moved so far (animated 0 → _trickle_cells.size()).
var _trickle_moved: float = 0.0
## Bank count before this leg's savings (the cache count the trickle starts from).
var _trickle_base_bank: int = 0
## The active trickle tween, kept so a new leg can cancel it mid-flight.
var _trickle_tween: Tween = null

# --- Mode / shop ---
var _mode: String = "leg"  # "leg" or "shop"
var _shop_total: int = 0
var _shop_remaining: int = 0

# Equipped components — the rail composes the player's actual dart from these.
var _barrel_component: DartComponent
var _shaft_component: DartComponent
var _flight_component: DartComponent

# Per-draw cache of the composed-dart part list and its natural (unscaled) size,
# rebuilt at the top of each _draw() so all icons share one aspect computation.
var _parts: Array = []
var _nat: Vector2 = Vector2(1.0, 1.0)


# =====================================================================================
# Public API (used by hud.gd / main.gd)
# =====================================================================================

## Set how many darts make up one turn (one set). Triggers a redraw.
func set_max_darts(count: int) -> void:
	_max_darts = maxi(count, 1)
	queue_redraw()


## How many darts are still in hand this turn (drives spent vs. active within the set).
func set_darts_remaining(count: int) -> void:
	_darts_remaining = clampi(count, 0, _max_darts)
	queue_redraw()


## Current turn / turn ceiling. Detects leg resets (clears busts) and set completions
## (plays the slash on the turn that just finished) so main.gd needs no extra calls.
func set_turn(current_turn: int, max_turns: int) -> void:
	var prev_turn: int = _current_turn
	_max_turns = maxi(max_turns, 1)

	# Leg reset: turn counter dropped back toward 1 — fresh front, clear bust tints and
	# restore any darts that were hidden by the leg-win trickle.
	if current_turn < prev_turn:
		_busted_turns.clear()
		_slash_progress.clear()
		_cancel_trickle_tween()
		_trickle_cells = []
		_trickle_moved = 0.0
		_displayed_bank = float(_banked_darts)
	elif current_turn > prev_turn:
		# The turn we just left is fully spent — slash it (unless it busted; a bust
		# already reads as red and shouldn't also be "completed").
		if not _busted_turns.has(prev_turn):
			play_set_complete_slash(prev_turn)

	_current_turn = maxi(current_turn, 1)
	queue_redraw()


## Mark a turn's darts as busted (dim red). Called by main when a bust occurs.
func mark_turn_busted(turn_number: int) -> void:
	_busted_turns[turn_number] = true
	queue_redraw()


## Set the banked-dart cache count instantly (no trickle).
func set_banked_darts(count: int) -> void:
	_banked_darts = maxi(count, 0)
	_displayed_bank = float(_banked_darts)
	queue_redraw()


## Leg-win beat: the leg's unused front darts fly into the cache. Each banked dart
## appears in the saved section as the matching front dart is erased, so it reads as
## the darts moving down rather than being copied.
func play_leg_win_trickle(saved: int, new_bank: int) -> void:
	_banked_darts = maxi(new_bank, 0)
	_cancel_trickle_tween()
	_trickle_cells = []
	if saved <= 0 or not is_visible_in_tree():
		_trickle_moved = 0.0
		_displayed_bank = float(_banked_darts)
		queue_redraw()
		return

	_trickle_base_bank = maxi(new_bank - saved, 0)
	_trickle_cells = _bankable_front_cells()
	# Trim to what we actually bank so the persistent erased set matches the count.
	var total: int = mini(saved, _trickle_cells.size())
	if _trickle_cells.size() > total:
		_trickle_cells.resize(total)
	_trickle_moved = 0.0
	_displayed_bank = float(_trickle_base_bank)

	_trickle_tween = create_tween()
	_trickle_tween.tween_method(_set_trickle_moved, 0.0, float(total), trickle_duration)\
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	# On finish, snap to fully-moved and KEEP _trickle_cells so the banked darts stay
	# hidden up top — the next leg's set_turn() reset is what restores a full rail.
	_trickle_tween.tween_callback(func() -> void:
		_trickle_moved = float(total)
		_displayed_bank = float(_banked_darts)
		queue_redraw())


func _cancel_trickle_tween() -> void:
	if _trickle_tween != null and _trickle_tween.is_valid():
		_trickle_tween.kill()
	_trickle_tween = null


## The unused (bankable) front darts, ordered last-turn-first so they appear to drain
## downward into the cache. Excludes already-thrown darts in the winning turn.
func _bankable_front_cells() -> Array:
	var cells: Array = []
	var used_in_current: int = _max_darts - _darts_remaining
	for t: int in range(_max_turns, _current_turn - 1, -1):
		for d: int in range(_max_darts - 1, -1, -1):
			if t == _current_turn and d < used_in_current:
				continue  # already thrown this turn — stays as a spent dart
			cells.append({"t": t, "d": d})
	return cells


## Bailout beat: a cluster leaves the cache to fund a new turn. Grows the rail by the
## new turn and animates the cache dropping by `spent`.
func play_bailout_flyin(spent: int, banked_left: int, new_max_turns: int) -> void:
	_max_turns = maxi(new_max_turns, 1)
	_banked_darts = maxi(banked_left, 0)
	_flyin_pulse = 1.0
	var start_val: float = float(banked_left + spent)
	_displayed_bank = start_val
	if is_visible_in_tree():
		var tw: Tween = create_tween()
		tw.set_parallel(true)
		tw.tween_method(_set_displayed_bank, start_val, float(_banked_darts), trickle_duration)
		tw.tween_method(_set_flyin_pulse, 1.0, 0.0, trickle_duration * 1.4)
	else:
		_displayed_bank = float(_banked_darts)
		_flyin_pulse = 0.0
	queue_redraw()


## Play the cross-out slash across a completed set.
func play_set_complete_slash(turn_number: int) -> void:
	if not is_visible_in_tree():
		return
	_slash_progress[turn_number] = 0.0
	var tw: Tween = create_tween()
	tw.tween_method(_set_slash_progress.bind(turn_number), 0.0, 1.0, slash_duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		_slash_progress.erase(turn_number)
		queue_redraw())


## Store equipped components (kept for API parity; the rail glyph is point.png).
func set_dart_components(barrel: DartComponent, shaft: DartComponent, flight: DartComponent) -> void:
	_barrel_component = barrel
	_shaft_component = shaft
	_flight_component = flight
	queue_redraw()


## Enter shop mode: show a simple vertical stack of `total` darts, `remaining` bright.
func set_shop_darts(total: int, remaining: int) -> void:
	_mode = "shop"
	_shop_total = maxi(total, 0)
	_shop_remaining = clampi(remaining, 0, _shop_total)
	queue_redraw()


## Leave shop mode and restore the leg rail.
func restore_normal_darts() -> void:
	_mode = "leg"
	queue_redraw()


# =====================================================================================
# Animation setters (driven by tween_method; each just nudges a var + redraws)
# =====================================================================================

func _set_displayed_bank(v: float) -> void:
	_displayed_bank = v
	queue_redraw()


func _set_flyin_pulse(v: float) -> void:
	_flyin_pulse = v
	queue_redraw()


func _set_slash_progress(v: float, turn_number: int) -> void:
	_slash_progress[turn_number] = v
	queue_redraw()


func _set_trickle_moved(v: float) -> void:
	_trickle_moved = v
	# Cache fills in lockstep with the front erasing.
	_displayed_bank = float(_trickle_base_bank) + v
	queue_redraw()


# =====================================================================================
# Drawing
# =====================================================================================

func _draw() -> void:
	_rebuild_parts()
	if _mode == "shop":
		_draw_shop()
	else:
		_draw_rail()


## Per-icon state for the leg rail.
func _icon_state(turn_number: int, dart_index: int) -> DartState:
	if _busted_turns.has(turn_number):
		return DartState.BUSTED
	if turn_number < _current_turn:
		return DartState.SPENT
	if turn_number == _current_turn:
		var used: int = _max_darts - _darts_remaining
		return DartState.SPENT if dart_index < used else DartState.ACTIVE
	return DartState.AVAILABLE


func _state_color(state: DartState) -> Color:
	match state:
		DartState.AVAILABLE: return color_available
		DartState.ACTIVE: return color_active
		DartState.SPENT: return color_spent
		DartState.BUSTED: return color_busted
	return color_available


## Texture for an equipped component, or null when nothing is equipped there.
func _tex(comp: DartComponent) -> Texture2D:
	if comp != null and comp.texture != null:
		return comp.texture
	return null


## Rebuild the composed-dart part list (point → barrel → shaft → flight) at each part's
## NATIVE texture size times its per-part multiplier, so aspect ratios are preserved.
## Also caches the natural composite size so every icon shares one fit computation.
func _rebuild_parts() -> void:
	_parts = []
	var defs: Array = [
		[POINT_TEX, point_scale],
		[_tex(_barrel_component), barrel_scale],
		[_tex(_shaft_component), shaft_scale],
		[_tex(_flight_component), flight_scale],
	]
	var total_w: float = 0.0
	var max_h: float = 0.0
	for d: Array in defs:
		var tex: Texture2D = d[0]
		if tex == null:
			continue
		var ts: Vector2 = tex.get_size()
		var m: float = d[1] as float
		var w: float = ts.x * m
		var h: float = ts.y * m
		_parts.append({"tex": tex, "w": w, "h": h})
		total_w += w
		max_h = maxf(max_h, h)
	_nat = Vector2(maxf(total_w, 1.0), maxf(max_h, 1.0))


## Draw the composed dart to fill `rect`'s WIDTH, preserving every part's aspect ratio
## (uniform scale, vertically centred). Never stretches a component.
func _draw_dart(rect: Rect2, col: Color) -> void:
	if _parts.is_empty():
		return
	var k: float = rect.size.x / _nat.x
	var draw_h: float = _nat.y * k
	var top: float = rect.position.y + (rect.size.y - draw_h) * 0.5
	var x: float = rect.position.x
	for p: Dictionary in _parts:
		var w: float = (p["w"] as float) * k
		var h: float = (p["h"] as float) * k
		var y: float = top + (draw_h - h) * 0.5
		draw_texture_rect(p["tex"], Rect2(Vector2(x, y), Vector2(w, h)), false, col)
		x += w


## Icon width fit to darts_per_turn across the rail; height follows the dart's aspect.
func _draw_rail() -> void:
	var cols: int = maxi(_max_darts, 1)
	var aspect: float = _nat.y / _nat.x

	# Width-fit each dart to darts_per_turn across the rail.
	var iw: float = minf(icon_size.x, (size.x - (cols - 1) * dart_gap) / float(cols))
	iw = maxf(iw, 8.0)
	var ih: float = iw * aspect
	var sgap: float = set_gap
	var cgap: float = cache_gap
	var tmarg: float = rail_top_margin
	var dgap: float = dart_gap
	var fsize: float = maxf(float(get_theme_default_font_size()), 12.0)

	# Then height-fit: shrink the WHOLE rail uniformly if the sets plus every cache
	# cluster would overflow the control, so all saved darts stay visible (no "+N").
	var bank: int = int(round(_displayed_bank))
	var cache_rows: int = int(ceil(float(bank) / 3.0)) if bank > 0 else 0
	var label_block: float = fsize * 1.4 if bank > 0 else 0.0
	var div_block: float = cgap if bank > 0 else 0.0
	var content_h: float = tmarg + (_max_turns + cache_rows) * (ih + sgap) + div_block + label_block
	if content_h > size.y and content_h > 0.0:
		var sc: float = size.y / content_h
		iw *= sc
		ih *= sc
		sgap *= sc
		cgap *= sc
		tmarg *= sc
		dgap *= sc
		fsize *= sc

	var row_h: float = ih + sgap

	# Cells banked by the leg-win trickle stay hidden up top (during the animation only
	# the first floor(_trickle_moved) are gone; after it finishes all of them are, until
	# the next leg resets). Build a quick (turn, dart) skip lookup.
	var erased: Dictionary = {}
	if not _trickle_cells.is_empty():
		var moved: int = mini(int(floor(_trickle_moved)), _trickle_cells.size())
		for i: int in range(moved):
			var c: Dictionary = _trickle_cells[i]
			erased[Vector2i(c["t"], c["d"])] = true

	# Top-aligned: the first set sits near the control's top so the whole rail reads
	# high on the screen and the cache can stack beneath it.
	for t: int in range(_max_turns):
		var turn_number: int = t + 1
		var y: float = tmarg + t * row_h

		for d: int in range(_max_darts):
			if erased.has(Vector2i(turn_number, d)):
				continue
			var x: float = d * (iw + dgap)
			var rect: Rect2 = Rect2(Vector2(x, y), Vector2(iw, ih))
			var state: DartState = _icon_state(turn_number, d)
			var col: Color = _state_color(state)

			if state == DartState.ACTIVE:
				# Pop: grow the icon about its centre and ring it.
				var grown: Vector2 = Vector2(iw, ih) * active_pop_scale
				var prect: Rect2 = Rect2(rect.get_center() - grown * 0.5, grown)
				_draw_dart(prect, col)
				draw_rect(prect.grow(1.0), active_outline_color, false, active_outline_width)
			else:
				_draw_dart(rect, col)

		# Set-completion slash (one-shot transition).
		if _slash_progress.has(turn_number):
			var p: float = _slash_progress[turn_number]
			var set_w: float = _max_darts * (iw + dgap) - dgap
			var sy: float = y + ih * 0.5
			var start: Vector2 = Vector2(0.0, sy + ih * 0.4)
			var cur_end: Vector2 = start.lerp(Vector2(set_w, sy - ih * 0.4), p)
			draw_line(start, cur_end, slash_color, maxf(ih * 0.14, 2.0), true)

	var cache_y0: float = tmarg + _max_turns * row_h + cgap
	_draw_cache(iw, ih, row_h, dgap, cgap, fsize, cache_y0)


## Draw the saved-dart cache as clusters of three stacked UNDER the rail, in the same
## per-row format as a turn (so a completed cluster lines up like a bonus turn). A thin
## divider and a "SAVED DARTS" label separate fronted darts from banked ones. Every
## banked dart is drawn — the rail scales to fit them all (see _draw_rail).
func _draw_cache(iw: float, ih: float, row_h: float, dgap: float, cgap: float, fsize: float, y0: float) -> void:
	var bank: int = int(round(_displayed_bank))
	if bank <= 0:
		return

	var set_w: float = _max_darts * (iw + dgap) - dgap

	# Divider between the front and the bank.
	draw_line(Vector2(0.0, y0 - cgap * 0.5), Vector2(set_w, y0 - cgap * 0.5),
		divider_color, 1.0, true)

	# "SAVED DARTS" label above the cache, then the clusters start beneath it.
	var font: Font = get_theme_default_font()
	var fs: int = maxi(int(fsize), 8)
	draw_string(font, Vector2(0.0, y0 + fs), "SAVED DARTS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cache_label_color)
	var clusters_y0: float = y0 + fsize * 1.4

	var cluster_size: int = 3
	var rows: int = int(ceil(float(bank) / float(cluster_size)))
	var completed_clusters: int = bank / cluster_size
	var drawn: int = 0
	for r: int in range(rows):
		var cluster_complete: bool = (r + 1) * cluster_size <= bank
		var col: Color = color_cache_bonus if cluster_complete else color_cache
		# Pulse the just-completed cluster during a bailout fly-out.
		if _flyin_pulse > 0.0 and r == completed_clusters:
			col = col.lerp(Color(1.0, 1.0, 1.0, 1.0), _flyin_pulse * 0.6)
		var y: float = clusters_y0 + r * row_h
		for i: int in range(cluster_size):
			if drawn >= bank:
				break
			var x: float = i * (iw + dgap)
			_draw_dart(Rect2(Vector2(x, y), Vector2(iw, ih)), col)
			drawn += 1


## Shop mode: top-aligned vertical stack of composed darts; bright = still to throw.
func _draw_shop() -> void:
	var count: int = maxi(_shop_total, 1)
	var iw: float = minf(icon_size.x, size.x)
	var ih: float = iw * (_nat.y / _nat.x)
	var gap: float = 4.0
	var total_h: float = count * (ih + gap) - gap
	if total_h > size.y:
		var s: float = size.y / total_h
		iw *= s
		ih *= s
		gap *= s
	for i: int in range(count):
		var rect: Rect2 = Rect2(Vector2(0.0, i * (ih + gap)), Vector2(iw, ih))
		var col: Color = color_available if i < _shop_remaining else color_spent
		_draw_dart(rect, col)
