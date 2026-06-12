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

## Fired when the leg-intro fill finishes revealing every fronted row (either
## naturally or via skip_intro_fill). hud.gd awaits this as the rail's intro step.
signal intro_fill_finished

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

@export_group("Fronted Label")
## Header text drawn above the fronted rows (the leg's granted darts). Permanent — drawn
## whenever the leg rail is (shop mode swaps to the simple stack, which omits it).
@export var fronted_label_text: String = "FRONTED DARTS"
## Header text used INSTEAD of fronted_label_text while a challenge wager is active (the
## rail is showing a staked deposit, not granted darts). Swapped in automatically whenever
## a dart budget is set (_dart_budget > 0) and reverts once the budget clears. §Phase 02.
@export var wagered_label_text: String = "WAGERED DARTS"
## Font size of the fronted-darts header. Scales down with the rest of the rail when a
## big bank forces the height-fit shrink.
@export var fronted_label_font_size: int = 12
## Colour of the fronted-darts header (defaults to the SAVED DARTS label's soft white).
@export var fronted_label_color: Color = Color(1.0, 1.0, 1.0, 0.6)
## Vertical gap (px) between the header's text block and the first fronted row.
@export var fronted_label_gap: float = 4.0

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
## Seconds per revealed row during the leg-intro fill (the reverse of the leg-win
## trickle: rows appear top-to-bottom, one move-darts tick each). Total fill time =
## turns × this. The fill is now the intro's FINAL sequential step (hud.play_leg_intro,
## 2026-06-06), so its full duration ADDS to the intro length — kept low (0.12) so a
## 5–6-turn leg's fill stays ≈0.6–0.7 s and the default intro total lands ≤ ~3.5 s.
## Raise for a more drawn-out, ceremonial fill; lower for a snappier trickle.
@export var intro_fill_row_interval: float = 0.12

# --- Leg state ---
## Darts per turn (a set's size). Named _max_darts for the existing hud read path.
var _max_darts: int = 3
var _max_turns: int = 5
var _current_turn: int = 1
var _darts_remaining: int = 3
## turn_number -> true for turns lost to a bust.
var _busted_turns: Dictionary = {}
## Total darts the rail may render across all rows. 0 = legacy: every row is full, so the
## budget is implicitly _max_turns × _max_darts. > 0 (challenge wagers) caps the total, so
## the final row is partial when the wager isn't a clean multiple of darts-per-turn — e.g.
## budget 7, dpt 2 draws rows [2][2][2][1] rather than a phantom 8th dart. See set_dart_budget.
var _dart_budget: int = 0

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
## How many move-to-saved ticks have played this trickle (one per dart crossing).
var _trickle_sound_count: int = 0

# --- Leg-intro fill ---
## Rows revealed so far by the leg-intro fill; -1 = inactive (draw every row normally).
## conceal_for_intro() sets it to 0 (empty rail) and play_intro_fill() trickles it up.
var _intro_rows_shown: int = -1
## The active intro-fill tween, kept so a skip or a leg reset can cancel it mid-trickle.
var _intro_fill_tween: Tween = null

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


## Set the total dart budget the rail may render (a challenge wager). 0 restores legacy
## full-row behaviour (budget = _max_turns × _max_darts). A positive budget caps the total
## so the final row renders partial, and also flips the rail header to wagered_label_text.
func set_dart_budget(count: int) -> void:
	_dart_budget = maxi(count, 0)
	queue_redraw()


## True when a per-cell index is within the active dart budget. Cells fill row-major
## (turn 1's darts first), so cell (turn_number, dart_index) has linear index
## (turn_number − 1) × _max_darts + dart_index. Legacy mode (_dart_budget == 0) draws every
## cell; a wager budget drops cells past the staked total so the last row goes partial.
func _cell_in_budget(turn_number: int, dart_index: int) -> bool:
	if _dart_budget <= 0:
		return true
	var linear: int = (turn_number - 1) * _max_darts + dart_index
	return linear < _dart_budget


## How many darts the given turn (1-based) actually renders under the active budget — the
## full _max_darts for every row except a partial final one. Used for the active outline and
## the set-completion slash so they span only the cells that exist.
func _darts_in_turn(turn_number: int) -> int:
	if _dart_budget <= 0:
		return _max_darts
	var before: int = (turn_number - 1) * _max_darts
	return clampi(_dart_budget - before, 0, _max_darts)


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
		# Also drop any stale intro-fill state so the fresh rail draws complete.
		_cancel_intro_fill_tween()
		_intro_rows_shown = -1
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
	# Fresh trickle: ticks start from base pitch and climb again.
	_trickle_sound_count = 0
	AuidoManager.reset_move_darts_pitch()
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
			if not _cell_in_budget(t, d):
				continue  # phantom cell past a wager budget — nothing to bank
			if t == _current_turn and d < used_in_current:
				continue  # already thrown this turn — stays as a spent dart
			cells.append({"t": t, "d": d})
	return cells


## Leg-intro: hide every fronted row so play_intro_fill() can reveal them one by one.
## Call while the board is off-screen — the rail redraws empty immediately.
func conceal_for_intro() -> void:
	_cancel_intro_fill_tween()
	_intro_rows_shown = 0
	queue_redraw()


## Leg-intro fill: reveal the fronted rows top-to-bottom, one move-darts tick per row —
## the leg-win trickle in reverse (darts arriving up top instead of draining down). Total
## time = turns × intro_fill_row_interval, so it scales with the leg's budget. Emits
## intro_fill_finished when every row is visible (immediately if the rail is hidden).
## Safe without a prior conceal_for_intro() — it starts from zero rows regardless.
func play_intro_fill() -> void:
	_cancel_intro_fill_tween()
	# Hidden rail (shop flows, hidden HUD): skip the animation and finish at once.
	if not is_visible_in_tree() or _max_turns <= 0:
		_intro_rows_shown = -1
		queue_redraw()
		intro_fill_finished.emit()
		return
	_intro_rows_shown = 0
	queue_redraw()
	# Same sound contract as the leg-win trickle: pitch resets, then climbs per tick.
	AuidoManager.reset_move_darts_pitch()
	_intro_fill_tween = create_tween()
	for i: int in range(_max_turns):
		_intro_fill_tween.tween_callback(_reveal_intro_row)
		_intro_fill_tween.tween_interval(intro_fill_row_interval)
	_intro_fill_tween.tween_callback(func() -> void:
		_intro_rows_shown = -1
		queue_redraw()
		intro_fill_finished.emit())


## True while the leg-intro fill is mid-trickle (rows still hidden up top).
func is_intro_fill_active() -> bool:
	return _intro_rows_shown >= 0


## Fast-forward the leg-intro fill: show every row at once and finish. Used by the HUD's
## per-step click-skip. No-op when no fill is active.
func skip_intro_fill() -> void:
	if _intro_rows_shown < 0:
		return
	_cancel_intro_fill_tween()
	_intro_rows_shown = -1
	queue_redraw()
	intro_fill_finished.emit()


## Reveal the next fronted row during the intro fill (one chaining tick sound per row).
func _reveal_intro_row() -> void:
	_intro_rows_shown = mini(_intro_rows_shown + 1, _max_turns)
	AuidoManager.play_move_darts_to_saved()
	queue_redraw()


func _cancel_intro_fill_tween() -> void:
	if _intro_fill_tween != null and _intro_fill_tween.is_valid():
		_intro_fill_tween.kill()
	_intro_fill_tween = null


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
	# One move-to-saved tick per dart as it crosses into the cache (chaining,
	# rising-pitch), fired off integer crossings of the animated value.
	var moved_now: int = int(floor(v))
	while _trickle_sound_count < moved_now:
		AuidoManager.play_move_darts_to_saved()
		_trickle_sound_count += 1
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
	# Fronted-darts header sizing (drawn above the first set; see _draw_rail's header).
	var flsize: float = maxf(float(fronted_label_font_size), 8.0)
	var flgap: float = fronted_label_gap

	# Then height-fit: shrink the WHOLE rail uniformly if the header plus the sets plus
	# every cache cluster would overflow the control, so all saved darts stay visible (no "+N").
	var bank: int = int(round(_displayed_bank))
	var cache_rows: int = int(ceil(float(bank) / 3.0)) if bank > 0 else 0
	var label_block: float = fsize * 1.4 if bank > 0 else 0.0
	var div_block: float = cgap if bank > 0 else 0.0
	var front_block: float = flsize * 1.2 + flgap
	var content_h: float = tmarg + front_block + (_max_turns + cache_rows) * (ih + sgap) + div_block + label_block
	if content_h > size.y and content_h > 0.0:
		var sc: float = size.y / content_h
		iw *= sc
		ih *= sc
		sgap *= sc
		cgap *= sc
		tmarg *= sc
		dgap *= sc
		fsize *= sc
		flsize *= sc
		flgap *= sc
		front_block = flsize * 1.2 + flgap

	var row_h: float = ih + sgap

	# Header above the rail (the SAVED DARTS label's sibling) — names the leg's granted dart
	# budget normally, or the staked wager during a challenge race (when _dart_budget is set).
	var header_text: String = wagered_label_text if _dart_budget > 0 else fronted_label_text
	draw_string(get_theme_default_font(), Vector2(0.0, tmarg + flsize), header_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(flsize), 8), fronted_label_color)

	# Sets start below the header block.
	var rows_y0: float = tmarg + front_block

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
		# Leg-intro fill: rows past the reveal front stay hidden until their tick lands.
		if _intro_rows_shown >= 0 and t >= _intro_rows_shown:
			continue
		var y: float = rows_y0 + t * row_h

		# Bounding box of the turn's still-in-hand darts, so the active set gets a
		# SINGLE white outline rather than one box per dart (which doubled up the line
		# between neighbouring active darts).
		var active_rect: Rect2 = Rect2()
		var has_active: bool = false
		for d: int in range(_max_darts):
			# Past the wager budget there is no dart here (partial final row) — skip it.
			if not _cell_in_budget(turn_number, d):
				continue
			if erased.has(Vector2i(turn_number, d)):
				continue
			var x: float = d * (iw + dgap)
			var rect: Rect2 = Rect2(Vector2(x, y), Vector2(iw, ih))
			var state: DartState = _icon_state(turn_number, d)
			var col: Color = _state_color(state)

			if state == DartState.ACTIVE:
				# Pop: grow the icon about its centre; the outline is drawn once below.
				var grown: Vector2 = Vector2(iw, ih) * active_pop_scale
				var prect: Rect2 = Rect2(rect.get_center() - grown * 0.5, grown)
				_draw_dart(prect, col)
				active_rect = prect if not has_active else active_rect.merge(prect)
				has_active = true
			else:
				_draw_dart(rect, col)

		if has_active:
			draw_rect(active_rect.grow(2.0), active_outline_color, false, active_outline_width)

		# Set-completion slash (one-shot transition).
		if _slash_progress.has(turn_number):
			var p: float = _slash_progress[turn_number]
			# Span only the darts that exist this row (partial final row under a wager).
			var set_w: float = _darts_in_turn(turn_number) * (iw + dgap) - dgap
			var sy: float = y + ih * 0.5
			var start: Vector2 = Vector2(0.0, sy + ih * 0.4)
			var cur_end: Vector2 = start.lerp(Vector2(set_w, sy - ih * 0.4), p)
			draw_line(start, cur_end, slash_color, maxf(ih * 0.14, 2.0), true)

	var cache_y0: float = rows_y0 + _max_turns * row_h + cgap
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
