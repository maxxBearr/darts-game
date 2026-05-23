class_name RulesSlideshow
extends Control
## Modal slideshow walking through x01 dart rules and board layout.
## Side-by-side layout: text column (left) + mini dartboard (right).
## Highlights render on the self-contained mini board, not the main dartboard.
## Includes standard text/highlight slides and one interactive doubles-checkout drill.

signal slideshow_closed

@export_group("Panel")

## Background color of the modal scrim.
@export var scrim_color: Color = Color(0.0, 0.0, 0.0, 0.75)

## Background color of the slide panel.
@export var panel_color: Color = Color(0.08, 0.08, 0.12, 0.95)

## Border color of the slide panel.
@export var panel_border_color: Color = Color(0.4, 0.4, 0.5, 0.6)

## Total width of the slide panel in pixels.
@export var panel_width: float = 720.0

## Maximum height of the slide panel in pixels.
@export var panel_max_height: float = 420.0

## Width of the left text column in pixels.
@export var text_column_width: float = 440.0

## Width of the right mini-board column in pixels.
@export var mini_board_column_width: float = 240.0

@export_group("Text")

## Font size for slide titles.
@export var title_font_size: int = 24

## Color of slide titles.
@export var title_color: Color = Color(1.0, 0.95, 0.85)

## Font size for slide body text.
@export var body_font_size: int = 15

## Color of slide body text.
@export var body_color: Color = Color(0.88, 0.88, 0.88)

## Font size for navigation buttons.
@export var nav_font_size: int = 14

## Font size for drill answer buttons.
@export var drill_font_size: int = 16

## Color for correct drill answer feedback.
@export var drill_correct_color: Color = Color(0.2, 0.85, 0.3)

## Color for wrong drill answer feedback.
@export var drill_wrong_color: Color = Color(0.9, 0.25, 0.2)

@export_group("Mini Board")

## Pixel radius of the mini dartboard.
@export var mini_board_radius: float = 100.0

## Label text above the mini dartboard.
@export var mini_board_label_text: String = "The Board"

## Font size for the mini board label.
@export var mini_board_label_font_size: int = 14

## Even-wedge single color on the mini board.
@export var mini_single_a: Color = Color(0.06, 0.06, 0.06)

## Even-wedge multi (double/triple) color on the mini board.
@export var mini_multi_a: Color = Color(0.35, 0.05, 0.05)

## Odd-wedge single color on the mini board.
@export var mini_single_b: Color = Color(0.4, 0.38, 0.32)

## Odd-wedge multi color on the mini board.
@export var mini_multi_b: Color = Color(0.0, 0.22, 0.06)

## Single bull color on the mini board.
@export var mini_bull_single: Color = Color(0.0, 0.22, 0.06)

## Double bull color on the mini board.
@export var mini_bull_double: Color = Color(0.35, 0.05, 0.05)

## Wire color on the mini board.
@export var mini_wire_color: Color = Color(0.4, 0.4, 0.4, 0.4)

## Surround color on the mini board.
@export var mini_surround_color: Color = Color(0.12, 0.12, 0.12)

## Fill color for highlighted segments on the mini board.
@export var highlight_color: Color = Color(1.0, 0.85, 0.2, 0.4)

## Border color for highlighted segments on the mini board.
@export var highlight_border_color: Color = Color(1.0, 1.0, 1.0, 0.7)

## Border thickness for highlighted segments on the mini board.
@export var highlight_thickness: float = 2.0

## Font size for wedge numbers on the mini board.
@export var mini_number_font_size: int = 10

## Color of wedge numbers on the mini board.
@export var mini_number_color: Color = Color(0.9, 0.9, 0.85)

## Normalized radius for number placement (between RING_DOUBLE and surround edge).
@export var mini_number_radius: float = 0.90

@export_group("")

## Ring radius thresholds (same as dartboard.gd for geometry sync).
const RING_DOUBLE_BULL: float = 0.032
const RING_SINGLE_BULL: float = 0.080
const RING_INNER_SINGLE: float = 0.480
const RING_TRIPLE: float = 0.530
const RING_OUTER_SINGLE: float = 0.760
const RING_DOUBLE: float = 0.830

## Standard dartboard number order, clockwise from top.
const WEDGE_ORDER: Array[int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

const RING_BOUNDS: Dictionary = {
	"Inner Single": [RING_SINGLE_BULL, RING_INNER_SINGLE],
	"Triple": [RING_INNER_SINGLE, RING_TRIPLE],
	"Outer Single": [RING_TRIPLE, RING_OUTER_SINGLE],
	"Double": [RING_OUTER_SINGLE, RING_DOUBLE],
}

## Slide data.
var _slides: Array[Dictionary] = []

## Current slide index.
var _current_slide: int = 0

## Reference to the main dartboard — used only for defensive cleanup on open/close.
var dartboard: Node2D = null

## Active highlights for the mini board (set per-slide).
var _active_highlights: Array[Dictionary] = []

## Whether the mini board is in drill click mode (accepting segment clicks).
var _drill_click_active: bool = false

## The correct segment for the current board drill {wedge_index, ring_name}.
var _drill_correct_segment: Dictionary = {}

## Temporary highlight for drill feedback (green/red on clicked segment).
var _drill_feedback_highlight: Dictionary = {}

## Currently hovered segment on the mini board during drill {wedge_index, ring_name}, or empty.
var _drill_hover_segment: Dictionary = {}

# UI references
var _scrim: ColorRect
var _panel: Panel
var _title_label: Label
var _body_label: RichTextLabel
var _prev_button: Button
var _next_button: Button
var _close_button: Button
var _skip_link: Button
var _slide_counter: Label
var _drill_container: VBoxContainer
var _drill_feedback: Label
var _drill_answered_correctly: bool = false
var _mini_board: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_slides()
	_build_ui()
	visible = false


## Show the slideshow starting from slide 0.
func show_slideshow() -> void:
	_current_slide = 0
	_drill_answered_correctly = false
	visible = true
	# Defensive cleanup — clear any stale highlights on the main board
	if dartboard != null:
		dartboard.clear_tutorial_highlight()
	_display_current_slide()


## Hide the slideshow and clean up.
func hide_slideshow() -> void:
	visible = false
	_active_highlights.clear()
	if dartboard != null:
		dartboard.clear_tutorial_highlight()


func _build_slides() -> void:
	_slides = [
		{
			"type": "text",
			"title": "The Board",
			"body": "20 wedges, numbered 1-20, arranged in a specific order to punish missing your target. Standard around the world.",
			"highlight": [],
		},
		{
			"type": "text",
			"title": "Wedges and Rings",
			"body": "Each wedge has the same number value, but different rings on it score differently.",
			"highlight": [{"type": "single_wedge_all", "wedge_index": 0}],
		},
		{
			"type": "text",
			"title": "Singles",
			"body": "The big body of a wedge is a single — face value x 1. A single 20 = 20 points.",
			"highlight": [
				{"type": "all_wedges_ring", "ring_name": "Inner Single"},
				{"type": "all_wedges_ring", "ring_name": "Outer Single"},
			],
		},
		{
			"type": "text",
			"title": "Doubles",
			"body": "The thin outer ring is the double — face value x 2. A double 20 = 40 points. [b]Important — you'll need this in a moment.[/b]",
			"highlight": [{"type": "all_wedges_ring", "ring_name": "Double"}],
		},
		{
			"type": "text",
			"title": "Triples",
			"body": "The thin inner ring is the triple — face value x 3. A triple 20 = 60 points. [b]The highest single-dart score is triple 20.[/b]",
			"highlight": [{"type": "all_wedges_ring", "ring_name": "Triple"}],
		},
		{
			"type": "text",
			"title": "The Bullseye",
			"body": "Outer bull = 25 points. Inner bull (double bull) = 50 points. [b]Double bull counts as a double[/b] for checkout purposes.",
			"highlight": [{"type": "bullseye", "which": "both"}],
		},
		{
			"type": "text",
			"title": "x01 Scoring",
			"body": "You start each leg at a target score (101, 201, 301, etc.). Every dart subtracts its score from your remaining. Get to exactly 0 to win the leg.",
			"highlight": [],
		},
		{
			"type": "text",
			"title": "The Doubles Rule",
			"body": "There's a catch — your [b]last dart[/b] has to land on a [b]double[/b] (or the double bull). Hitting 0 with anything else = [b]bust[/b]. Going below 0 = [b]bust[/b]. Leaving 1 remaining = [b]bust[/b] (because no double sums to 1).",
			"highlight": [{"type": "all_wedges_ring", "ring_name": "Double"}],
		},
		{
			"type": "drill",
			"title": "Quick Check",
			"body": "You have 32 remaining. Click the segment on the board that wins the leg.",
			"correct_wedge_index": 13,
			"correct_ring_name": "Double",
			"correct_text": "Correct! Double 16 = 32. That's a checkout.",
			"wrong_text": "Not quite — you need a double that equals 32. Try again!",
			"highlight": [],
		},
		{
			"type": "text",
			"title": "That's the Basics",
			"body": "The game throws scoring modifiers and dart customization on top, but the throwing and counting always work this way.",
			"highlight": [],
		},
	]


func _build_ui() -> void:
	var viewport_size: Vector2 = Vector2(1280.0, 720.0)

	# Scrim
	_scrim = ColorRect.new()
	_scrim.color = scrim_color
	_scrim.size = viewport_size
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)

	# Panel
	_panel = Panel.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = panel_border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.size = Vector2(panel_width, panel_max_height)
	_panel.position = (viewport_size - _panel.size) / 2.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	# Two-column layout: text left, mini board right
	var columns: HBoxContainer = HBoxContainer.new()
	columns.position = Vector2(24.0, 24.0)
	columns.size = Vector2(panel_width - 48.0, panel_max_height - 48.0)
	columns.add_theme_constant_override("separation", 16)
	_panel.add_child(columns)

	# ── Left column: text content ──
	var text_col: VBoxContainer = VBoxContainer.new()
	text_col.custom_minimum_size = Vector2(text_column_width, 0.0)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 12)
	columns.add_child(text_col)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.add_theme_font_size_override("font_size", title_font_size)
	_title_label.add_theme_color_override("font_color", title_color)
	text_col.add_child(_title_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size = Vector2(text_column_width, 60.0)
	_body_label.add_theme_font_size_override("normal_font_size", body_font_size)
	_body_label.add_theme_font_size_override("bold_font_size", body_font_size)
	_body_label.add_theme_color_override("default_color", body_color)
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_body_label)

	_drill_container = VBoxContainer.new()
	_drill_container.add_theme_constant_override("separation", 8)
	_drill_container.visible = false
	text_col.add_child(_drill_container)

	_drill_feedback = Label.new()
	_drill_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_drill_feedback.add_theme_font_size_override("font_size", 14)
	_drill_feedback.visible = false
	text_col.add_child(_drill_feedback)

	# Nav row
	var nav_row: HBoxContainer = HBoxContainer.new()
	nav_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	nav_row.add_theme_constant_override("separation", 12)
	text_col.add_child(nav_row)

	_prev_button = Button.new()
	_prev_button.text = "Previous"
	_prev_button.add_theme_font_size_override("font_size", nav_font_size)
	_prev_button.custom_minimum_size = Vector2(90.0, 32.0)
	_prev_button.pressed.connect(_go_previous)
	nav_row.add_child(_prev_button)

	_slide_counter = Label.new()
	_slide_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slide_counter.add_theme_font_size_override("font_size", 12)
	_slide_counter.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_slide_counter.custom_minimum_size = Vector2(60.0, 0.0)
	nav_row.add_child(_slide_counter)

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.add_theme_font_size_override("font_size", nav_font_size)
	_next_button.custom_minimum_size = Vector2(90.0, 32.0)
	_next_button.pressed.connect(_go_next)
	nav_row.add_child(_next_button)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.add_theme_font_size_override("font_size", nav_font_size)
	_close_button.custom_minimum_size = Vector2(90.0, 32.0)
	_close_button.pressed.connect(_close)
	_close_button.visible = false
	nav_row.add_child(_close_button)

	# ── Right column: mini dartboard ──
	var board_col: VBoxContainer = VBoxContainer.new()
	board_col.custom_minimum_size = Vector2(mini_board_column_width, 0.0)
	board_col.add_theme_constant_override("separation", 6)
	board_col.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(board_col)

	var board_label: Label = Label.new()
	board_label.text = mini_board_label_text
	board_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board_label.add_theme_font_size_override("font_size", mini_board_label_font_size)
	board_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.6))
	board_col.add_child(board_label)

	_mini_board = Control.new()
	_mini_board.custom_minimum_size = Vector2(mini_board_radius * 2.2, mini_board_radius * 2.2)
	_mini_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_board.draw.connect(_draw_mini_board)
	_mini_board.gui_input.connect(_on_mini_board_input)
	board_col.add_child(_mini_board)

	# Skip link (top-right of panel)
	_skip_link = Button.new()
	_skip_link.text = "Skip to end"
	_skip_link.flat = true
	_skip_link.add_theme_font_size_override("font_size", 11)
	_skip_link.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	_skip_link.position = Vector2(panel_width - 100.0, 4.0)
	_skip_link.pressed.connect(_go_to_last)
	_panel.add_child(_skip_link)


func _display_current_slide() -> void:
	var slide: Dictionary = _slides[_current_slide]
	_title_label.text = slide["title"]
	_body_label.text = slide["body"]

	# Navigation
	_prev_button.visible = _current_slide > 0
	var is_last: bool = _current_slide == _slides.size() - 1
	var is_drill: bool = slide["type"] == "drill"

	if is_drill:
		_next_button.visible = not is_last
		_next_button.disabled = not _drill_answered_correctly
	else:
		_next_button.visible = not is_last
		_next_button.disabled = false

	_close_button.visible = is_last
	_slide_counter.text = "%d / %d" % [_current_slide + 1, _slides.size()]

	# Drill UI — board click mode instead of text buttons
	_drill_feedback.visible = false
	_drill_answered_correctly = false
	_drill_feedback_highlight = {}
	_drill_hover_segment = {}
	_drill_click_active = false
	_drill_correct_segment = {}
	_mini_board.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_drill:
		_drill_click_active = true
		_drill_correct_segment = {
			"wedge_index": slide.get("correct_wedge_index", 0),
			"ring_name": slide.get("correct_ring_name", "Double"),
		}
		_mini_board.mouse_filter = Control.MOUSE_FILTER_STOP

	# Update mini board highlights
	var highlights: Array = slide.get("highlight", [])
	_active_highlights.clear()
	for h: Dictionary in highlights:
		_active_highlights.append(h)
	_mini_board.queue_redraw()


# ── Mini dartboard drawing ────────────────────────────────────────────────

func _draw_mini_board() -> void:
	var center: Vector2 = _mini_board.size / 2.0
	var r: float = mini_board_radius

	# Surround
	_mini_board.draw_circle(center, r * 0.93, mini_surround_color)

	# Wedges
	for wedge_idx: int in range(20):
		var start_deg: float = wedge_idx * 18.0 - 9.0
		var end_deg: float = start_deg + 18.0
		var is_even: bool = wedge_idx % 2 == 0
		var sc: Color = mini_single_a if is_even else mini_single_b
		var mc: Color = mini_multi_a if is_even else mini_multi_b

		_draw_mini_segment(center, start_deg, end_deg, r * RING_DOUBLE, r * RING_OUTER_SINGLE, mc)
		_draw_mini_segment(center, start_deg, end_deg, r * RING_OUTER_SINGLE, r * RING_TRIPLE, sc)
		_draw_mini_segment(center, start_deg, end_deg, r * RING_TRIPLE, r * RING_INNER_SINGLE, mc)
		_draw_mini_segment(center, start_deg, end_deg, r * RING_INNER_SINGLE, r * RING_SINGLE_BULL, sc)

	# Bull
	_mini_board.draw_circle(center, r * RING_SINGLE_BULL, mini_bull_single)
	_mini_board.draw_circle(center, r * RING_DOUBLE_BULL, mini_bull_double)

	# Wire rings
	for ring_r: float in [RING_DOUBLE_BULL, RING_SINGLE_BULL, RING_INNER_SINGLE, RING_TRIPLE, RING_OUTER_SINGLE, RING_DOUBLE]:
		_draw_mini_ring(center, r * ring_r)

	# Wedge boundary wires
	for wedge_idx: int in range(20):
		var angle_rad: float = deg_to_rad(wedge_idx * 18.0 - 9.0)
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		_mini_board.draw_line(center + direction * r * RING_SINGLE_BULL, center + direction * r * RING_DOUBLE, mini_wire_color, 1.0)

	# Wedge numbers in the surround ring
	var font: Font = ThemeDB.fallback_font
	for wedge_idx: int in range(20):
		var angle_deg: float = wedge_idx * 18.0
		var angle_rad: float = deg_to_rad(angle_deg)
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		var pos: Vector2 = center + direction * r * mini_number_radius
		var number_text: String = str(WEDGE_ORDER[wedge_idx])
		var text_width: float = font.get_string_size(number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, mini_number_font_size).x
		var draw_pos: Vector2 = Vector2(pos.x - text_width / 2.0, pos.y + mini_number_font_size / 2.0)
		_mini_board.draw_string(font, draw_pos, number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, mini_number_font_size, mini_number_color)

	# Draw highlights on top
	_draw_mini_highlights(center, r)

	# Draw hover highlight during drill (subtle white overlay like the main dartboard)
	if _drill_click_active and not _drill_hover_segment.is_empty() and not _drill_answered_correctly:
		var hv_wedge: int = _drill_hover_segment.get("wedge_index", -1)
		var hv_ring: String = _drill_hover_segment.get("ring_name", "")
		var hover_fill: Color = Color(1.0, 1.0, 1.0, 0.15)
		var hover_border: Color = Color(1.0, 1.0, 1.0, 0.5)
		if hv_ring == "Double Bull":
			_mini_board.draw_circle(center, r * RING_DOUBLE_BULL, hover_fill)
			_draw_mini_ring_highlight(center, r * RING_DOUBLE_BULL)
		elif hv_ring == "Single Bull":
			_mini_board.draw_circle(center, r * RING_SINGLE_BULL, hover_fill)
			_draw_mini_ring_highlight(center, r * RING_SINGLE_BULL)
		elif hv_wedge >= 0 and RING_BOUNDS.has(hv_ring):
			var hv_bounds: Array = RING_BOUNDS[hv_ring]
			var hv_start: float = hv_wedge * 18.0 - 9.0
			var hv_end: float = hv_start + 18.0
			_draw_mini_segment(center, hv_start, hv_end, r * hv_bounds[1], r * hv_bounds[0], hover_fill)
			_draw_mini_segment_border(center, hv_start, hv_end, r * hv_bounds[1], r * hv_bounds[0])

	# Draw drill feedback highlight (green/red on clicked segment)
	if not _drill_feedback_highlight.is_empty():
		var fb_wedge: int = _drill_feedback_highlight["wedge_index"]
		var fb_ring: String = _drill_feedback_highlight["ring_name"]
		var fb_color: Color = _drill_feedback_highlight["color"]
		if RING_BOUNDS.has(fb_ring):
			var bounds: Array = RING_BOUNDS[fb_ring]
			var start_deg: float = fb_wedge * 18.0 - 9.0
			var end_deg: float = start_deg + 18.0
			_draw_mini_segment(center, start_deg, end_deg, r * bounds[1], r * bounds[0], fb_color)
			_draw_mini_segment_border(center, start_deg, end_deg, r * bounds[1], r * bounds[0])


func _draw_mini_highlights(center: Vector2, r: float) -> void:
	for spec: Dictionary in _active_highlights:
		var h_type: String = spec.get("type", "")
		match h_type:
			"all_wedges_ring":
				var ring_name: String = spec.get("ring_name", "")
				if RING_BOUNDS.has(ring_name):
					var bounds: Array = RING_BOUNDS[ring_name]
					for wedge_idx: int in range(20):
						var start_deg: float = wedge_idx * 18.0 - 9.0
						var end_deg: float = start_deg + 18.0
						_draw_mini_segment(center, start_deg, end_deg, r * bounds[1], r * bounds[0], highlight_color)
						_draw_mini_segment_border(center, start_deg, end_deg, r * bounds[1], r * bounds[0])

			"single_wedge_all":
				var wedge_idx: int = spec.get("wedge_index", 0)
				var start_deg: float = wedge_idx * 18.0 - 9.0
				var end_deg: float = start_deg + 18.0
				_draw_mini_segment(center, start_deg, end_deg, r * RING_DOUBLE, r * RING_SINGLE_BULL, highlight_color)
				_draw_mini_segment_border(center, start_deg, end_deg, r * RING_DOUBLE, r * RING_SINGLE_BULL)

			"single_segment":
				var wedge_idx: int = spec.get("wedge_index", 0)
				var ring_name: String = spec.get("ring_name", "")
				if RING_BOUNDS.has(ring_name):
					var bounds: Array = RING_BOUNDS[ring_name]
					var start_deg: float = wedge_idx * 18.0 - 9.0
					var end_deg: float = start_deg + 18.0
					_draw_mini_segment(center, start_deg, end_deg, r * bounds[1], r * bounds[0], highlight_color)
					_draw_mini_segment_border(center, start_deg, end_deg, r * bounds[1], r * bounds[0])

			"bullseye":
				var which: String = spec.get("which", "both")
				if which == "inner" or which == "both":
					_mini_board.draw_circle(center, r * RING_DOUBLE_BULL, highlight_color)
					_draw_mini_ring_highlight(center, r * RING_DOUBLE_BULL)
				if which == "outer" or which == "both":
					_mini_board.draw_circle(center, r * RING_SINGLE_BULL, highlight_color)
					_draw_mini_ring_highlight(center, r * RING_SINGLE_BULL)


## Draw a single arc segment on the mini board.
func _draw_mini_segment(center: Vector2, start_deg: float, end_deg: float, outer_r: float, inner_r: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var arc_pts: int = 6
	for i: int in range(arc_pts + 1):
		var t: float = float(i) / float(arc_pts)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(center + direction * outer_r)
	for i: int in range(arc_pts + 1):
		var t: float = float(i) / float(arc_pts)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(center + direction * inner_r)
	_mini_board.draw_colored_polygon(points, color)


## Draw a segment border outline on the mini board.
func _draw_mini_segment_border(center: Vector2, start_deg: float, end_deg: float, outer_r: float, inner_r: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var arc_pts: int = 6
	for i: int in range(arc_pts + 1):
		var t: float = float(i) / float(arc_pts)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(center + direction * outer_r)
	for i: int in range(arc_pts + 1):
		var t: float = float(i) / float(arc_pts)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(center + direction * inner_r)
	points.append(points[0])
	_mini_board.draw_polyline(points, highlight_border_color, highlight_thickness)


## Draw a circular wire on the mini board.
func _draw_mini_ring(center: Vector2, radius: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var num_pts: int = 48
	for i: int in range(num_pts + 1):
		var angle: float = TAU * float(i) / float(num_pts)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_mini_board.draw_polyline(points, mini_wire_color, 1.0)


## Draw a highlight ring on the mini board.
func _draw_mini_ring_highlight(center: Vector2, radius: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var num_pts: int = 48
	for i: int in range(num_pts + 1):
		var angle: float = TAU * float(i) / float(num_pts)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_mini_board.draw_polyline(points, highlight_border_color, highlight_thickness)


# ── Mini board click handling ─────────────────────────────────────────────

## Handle input on the mini board during drill slides (hover + click).
func _on_mini_board_input(event: InputEvent) -> void:
	if not _drill_click_active:
		return

	# Hover tracking
	if event is InputEventMouseMotion:
		if _drill_answered_correctly:
			return
		var hover_hit: Dictionary = _get_mini_board_segment(event.position)
		if hover_hit != _drill_hover_segment:
			_drill_hover_segment = hover_hit
			_mini_board.queue_redraw()
		return

	# Click handling
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _drill_answered_correctly:
		return

	var local_pos: Vector2 = event.position
	var hit: Dictionary = _get_mini_board_segment(local_pos)
	if hit.is_empty():
		return

	var is_correct: bool = hit["wedge_index"] == _drill_correct_segment["wedge_index"] and hit["ring_name"] == _drill_correct_segment["ring_name"]
	var slide: Dictionary = _slides[_current_slide]

	if is_correct:
		_drill_answered_correctly = true
		_drill_feedback.text = slide.get("correct_text", "Correct!")
		_drill_feedback.add_theme_color_override("font_color", drill_correct_color)
		_drill_feedback.visible = true
		_next_button.disabled = false
		_drill_feedback_highlight = {"wedge_index": hit["wedge_index"], "ring_name": hit["ring_name"], "color": Color(0.15, 0.7, 0.25, 0.5)}
		_drill_hover_segment = {}
	else:
		_drill_feedback.text = slide.get("wrong_text", "Not quite — try again!")
		_drill_feedback.add_theme_color_override("font_color", drill_wrong_color)
		_drill_feedback.visible = true
		_drill_feedback_highlight = {"wedge_index": hit["wedge_index"], "ring_name": hit["ring_name"], "color": Color(0.7, 0.15, 0.15, 0.5)}

	_mini_board.queue_redraw()


## Determine which segment a local click position falls on in the mini board.
## Returns {wedge_index, ring_name} or empty dict if off-board.
func _get_mini_board_segment(local_pos: Vector2) -> Dictionary:
	var center: Vector2 = _mini_board.size / 2.0
	var relative: Vector2 = local_pos - center
	var distance: float = relative.length()
	var normalized: float = distance / mini_board_radius

	# Determine ring
	var ring_name: String = ""
	if normalized <= RING_DOUBLE_BULL:
		return {"wedge_index": -1, "ring_name": "Double Bull"}
	elif normalized <= RING_SINGLE_BULL:
		return {"wedge_index": -1, "ring_name": "Single Bull"}
	elif normalized <= RING_INNER_SINGLE:
		ring_name = "Inner Single"
	elif normalized <= RING_TRIPLE:
		ring_name = "Triple"
	elif normalized <= RING_OUTER_SINGLE:
		ring_name = "Outer Single"
	elif normalized <= RING_DOUBLE:
		ring_name = "Double"
	else:
		return {}

	# Determine wedge index
	var angle_rad: float = atan2(relative.x, -relative.y)
	var angle_deg: float = rad_to_deg(angle_rad)
	if angle_deg < 0.0:
		angle_deg += 360.0
	angle_deg = fmod(angle_deg + 9.0, 360.0)
	if angle_deg < 0.0:
		angle_deg += 360.0
	var wedge_index: int = int(angle_deg / 18.0) % 20

	return {"wedge_index": wedge_index, "ring_name": ring_name}


# ── Drill logic (legacy text buttons — kept for future multi-option drills) ──

func _on_drill_answer(index: int) -> void:
	var slide: Dictionary = _slides[_current_slide]
	var correct_index: int = slide["correct_index"]

	if index == correct_index:
		_drill_answered_correctly = true
		_drill_feedback.text = slide["correct_text"]
		_drill_feedback.add_theme_color_override("font_color", drill_correct_color)
		_drill_feedback.visible = true
		_next_button.disabled = false

		var btn: Button = _drill_container.get_child(index) as Button
		if btn != null:
			var correct_style: StyleBoxFlat = StyleBoxFlat.new()
			correct_style.bg_color = Color(0.1, 0.35, 0.15, 0.9)
			correct_style.border_color = drill_correct_color
			correct_style.set_border_width_all(2)
			correct_style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", correct_style)
	else:
		_drill_feedback.text = slide["wrong_text"]
		_drill_feedback.add_theme_color_override("font_color", drill_wrong_color)
		_drill_feedback.visible = true

		var btn: Button = _drill_container.get_child(index) as Button
		if btn != null:
			var wrong_style: StyleBoxFlat = StyleBoxFlat.new()
			wrong_style.bg_color = Color(0.35, 0.1, 0.1, 0.9)
			wrong_style.border_color = drill_wrong_color
			wrong_style.set_border_width_all(2)
			wrong_style.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", wrong_style)


# ── Navigation ───────────────────────────────────────────────────────────

func _go_next() -> void:
	if _current_slide < _slides.size() - 1:
		_current_slide += 1
		_display_current_slide()


func _go_previous() -> void:
	if _current_slide > 0:
		_current_slide -= 1
		_display_current_slide()


func _go_to_last() -> void:
	_current_slide = _slides.size() - 1
	_display_current_slide()


func _close() -> void:
	hide_slideshow()
	slideshow_closed.emit()


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_RIGHT, KEY_SPACE:
				_go_next()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_go_previous()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_close()
				get_viewport().set_input_as_handled()
