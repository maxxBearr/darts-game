extends Node2D
## Procedurally drawn dartboard with polar-coordinate scoring system.
## All visual segments use the same constants as scoring, guaranteeing sync.

# --- Ring radius thresholds (normalized: 0.0 = center, 1.0 = board edge) ---
const RING_DOUBLE_BULL_OUTER: float = 0.032
const RING_SINGLE_BULL_OUTER: float = 0.080
const RING_INNER_SINGLE_OUTER: float = 0.480
const RING_TRIPLE_OUTER: float = 0.530
const RING_OUTER_SINGLE_OUTER: float = 0.760
const RING_DOUBLE_OUTER: float = 0.830

# Standard dartboard number order, clockwise from top
const WEDGE_ORDER: Array[int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

# Each wedge spans 18 degrees; offset by -9 so numbers are centered
const WEDGE_ANGLE_DEG: float = 18.0
const WEDGE_OFFSET_DEG: float = -9.0

@export_group("Board Layout")

## Board pixel radius — determines overall size of the dartboard on screen.
@export var board_radius: float = 300.0

## Number of arc points per segment edge for smooth curves.
@export var arc_points: int = 10

@export_group("Wedge Colors")

## Color for even-index wedge single areas (black on a traditional board).
@export var wedge_a_single: Color = Color(0.1, 0.1, 0.1)

## Color for even-index wedge double/triple areas (red on a traditional board).
@export var wedge_a_multi: Color = Color(0.8, 0.1, 0.1)

## Color for odd-index wedge single areas (cream/white on a traditional board).
@export var wedge_b_single: Color = Color(0.95, 0.9, 0.75)

## Color for odd-index wedge double/triple areas (green on a traditional board).
@export var wedge_b_multi: Color = Color(0.0, 0.5, 0.15)

## Single bull (outer bullseye) color.
@export var bull_single_color: Color = Color(0.0, 0.5, 0.15)

## Double bull (inner bullseye) color.
@export var bull_double_color: Color = Color(0.8, 0.1, 0.1)

@export_group("Wire & Surround")

## Wire/border line color between segments.
@export var wire_color: Color = Color(0.7, 0.7, 0.7)

## Wire thickness in pixels.
@export var wire_thickness: float = 1.5

## Surround (off-board) color.
@export var surround_color: Color = Color(0.15, 0.15, 0.15)

## Surround ring outer radius multiplier (relative to board_radius).
@export var surround_outer_multiplier: float = 1.15

@export_group("Numbers")

## Font size for the wedge numbers displayed around the board.
## Adjust based on board_radius — 20 works well for a 300px radius board.
@export var number_font_size: int = 20

## Color of the wedge numbers.
@export var number_color: Color = Color(0.9, 0.9, 0.85)

## Color for wedge numbers that have been modified by upgrades.
## Should stand out from the default number_color so players can spot changes.
@export var modified_number_color: Color = Color(0.2, 1.0, 0.4)

## Color for wedge numbers reduced by a boss (e.g., Recession, Void).
@export var boss_reduced_number_color: Color = Color(1.0, 0.25, 0.2)

@export_group("Hover Highlight")

## Color overlaid on the hovered board segment for highlighting.
@export var hover_highlight_color: Color = Color(1.0, 1.0, 1.0, 0.15)

## Border color for the hovered segment outline.
@export var hover_border_color: Color = Color(1.0, 1.0, 1.0, 0.5)

## Border thickness for the hovered segment outline in pixels.
@export var hover_border_thickness: float = 2.0

@export_group("Checkout Pulse")

## Color of the checkout pulse glow on valid finishing doubles.
@export var checkout_pulse_color: Color = Color(1.0, 0.85, 0.2, 0.8)

## Speed of the checkout pulse animation (higher = faster shimmer).
@export var checkout_pulse_speed: float = 3.0

## Minimum opacity of the checkout pulse (the "dim" part of the cycle).
@export var checkout_pulse_min_alpha: float = 0.15

## Maximum opacity of the checkout pulse (the "bright" part of the cycle).
@export var checkout_pulse_max_alpha: float = 0.7

## Border thickness for checkout pulse outlines.
@export var checkout_border_thickness: float = 3.0

## Normalized radius for number placement. Controls how far from center
## the numbers are drawn. Should be between RING_DOUBLE_OUTER (0.83) and
## surround_outer_multiplier (1.15). Default 0.93 centers them in the surround.
@export var number_radius_multiplier: float = 0.93

@export_group("Segment Flash")

## Color of the segment flash overlay on dart landing (white = bright flash).
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 0.6)

## Duration of the segment flash in seconds.
@export var flash_duration: float = 0.2

## Color of the border drawn around the flashing segment.
@export var flash_border_color: Color = Color(1.0, 1.0, 1.0, 0.9)

## Thickness of the flash border in pixels.
@export var flash_border_thickness: float = 2.0

# Flash state — tracks which segment to highlight and the current flash alpha
var _flash_alpha: float = 0.0
var _flash_ring_name: String = ""
var _flash_wedge_idx: int = -1

## The effective wedge values used for scoring and number display.
## Set by ScoringModifierManager. When empty, falls back to WEDGE_ORDER.
var effective_wedge_values: Array[int] = []

## The effective wedge colors for segment color reporting.
## Set by ScoringModifierManager. Each entry is a dict with per-ring keys:
## "inner_single", "triple", "outer_single", "double".
## When empty, derives colors from wedge index (standard board colors).
var effective_wedge_colors: Array[Dictionary] = []

## Board positions (0-19) flipped by a FlipSignModifier. Set by ScoringModifierManager.
## Flipped wedges draw a "+" suffix on their number (they add instead of subtract).
var flipped_wedges: Array[int] = []

## Hotspot rings, keyed "<wedge_index>:<RingName>" → flat multiplier bonus (int). Set by
## ScoringModifierManager (mirrored via main._sync_board_state). Each hot ring draws a
## persistent, high-contrast indicator with the value baked in — legible *through* recolor
## and boss overlay (the art-direction "legibility through flash" rule). This is the
## code-drawn baseline indicator; the smoky value-baked shader is layered on in-editor.
## Assigning this (mirrored from the manager via main._sync_board_state) rebuilds the smoke
## shader layer and redraws, so the code-drawn baseline and the shader layer stay in sync.
var hotspot_rings: Dictionary = {}:
	set(value):
		hotspot_rings = value
		_rebuild_hotspot_shader_layer()
		queue_redraw()

## Outline color for a hotspot ring's persistent indicator. High-contrast warm tone so it
## reads over any painted ring color or boss overlay.
@export var hotspot_indicator_color: Color = Color(1.0, 0.55, 0.1, 0.95)

## Outline thickness for the hotspot ring indicator.
@export var hotspot_indicator_thickness: float = 3.0

## Font size for the value baked into the hotspot indicator (e.g. "+3").
@export var hotspot_value_font_size: int = 20

## DEV TOGGLE — A/B the hotspot look. When true, hot rings render the smoky shader
## (shaders/hotspot.gdshader) as an additive child layer instead of the code-drawn orange
## outline; the "+N" value label is kept on top in BOTH modes for legibility. Flip in the
## inspector at runtime to compare; off = the original outline indicator. Lets you take a flier
## on the shader and untoggle instantly if you don't like it or it needs debugging.
@export var use_hotspot_shader: bool = false:
	set(value):
		use_hotspot_shader = value
		_rebuild_hotspot_shader_layer()
		queue_redraw()

## Smoke tint for the hotspot shader. The shader leans this toward each ring's painted color so
## the effect enhances the paint rather than overriding it.
@export var hotspot_smoke_color: Color = Color(1.0, 0.55, 0.1, 1.0)

## Preloaded hotspot smoke shader + the child layer hosting one additive Polygon2D and one
## value label per hot ring (only populated while use_hotspot_shader is true).
const _HOTSPOT_SHADER: Shader = preload("res://shaders/hotspot.gdshader")
var _hotspot_shader_layer: Node2D = null

## Shader that makes the "+N" value label drift like smoke (shared across all hotspot labels).
const _HOTSPOT_LABEL_SHADER: Shader = preload("res://shaders/hotspot_label.gdshader")
var _hotspot_label_material: ShaderMaterial = null

## Rotation offset in degrees applied to all wedge angles (rendering + hit detection).
## Set by the Rotation boss. 0.0 = normal orientation.
var board_rotation_offset: float = 0.0

## Scale factor for the double ring width. 1.0 = normal, 0.5 = half width.
## Set by the Narrow Double Ring boss. Moves the inner boundary outward. This is the
## dartboard-side FINAL multiplier, applied AFTER the manager's per-wedge bounds + floors — a
## handicap may legitimately narrow the double below the geometry floor (chosen friction).
var double_ring_width_scale: float = 1.0

## Parity Out checkout restriction for board legibility (geometry spec §9b cond 2): -1 = none,
## 0 = even-valued wedges out, 1 = odd-valued out. A rule change is otherwise invisible on the
## board (unlike narrow-double), so the dead-parity doubles (and triples) get desaturated for the
## race. Mirrored from ScoringModifierManager.checkout_parity by main._sync_board_state — this is
## a VISUAL-ONLY mirror; hit detection / win validity live in the out-rule seam, not here.
var checkout_parity: int = -1

## How far to desaturate a dead-parity double toward grey (0 = unchanged, 1 = fully grey).
@export var dead_parity_desaturation: float = 0.72

# ── GEOMETRY substrate (mirrored from ScoringModifierManager) ─────────────────
# Two copies of the board geometry. The SETTLED copy is the manager's current target and is
# what HIT DETECTION reads (calculate_score / scoring), so a dart landing mid-reflow scores
# against the final geometry — never the tween's in-between. The DRAW copy is tweened toward
# the settled values on a geometry change so the resize reads (an instant snap is illegible);
# all RENDERING + visual hover/picker highlights read it. When not animating the two are equal.
#
# Per-wedge ring bounds: 20 dicts keyed "inner_single"/"triple"/"outer_single"/"double" →
# [inner_norm, outer_norm]. Wedge weights: 20 floats, mean 1.0. Bull radii: {single_bull,
# double_bull}. _wedge_bounds_deg: 21 cumulative wedge boundary degrees (pre-rotation), anchored
# so the 20-wedge (index 0) is centered at the top. Seeded to the canonical board in _ready so a
# dartboard with no geometry pushed to it (mini-boards) renders the standard layout.
var _geo_bounds: Array[Dictionary] = []
var _geo_weights: Array[float] = []
var _geo_bull: Dictionary = {}
var _wedge_bounds_deg: Array[float] = []

var _geo_bounds_draw: Array[Dictionary] = []
var _geo_weights_draw: Array[float] = []
var _geo_bull_draw: Dictionary = {}
var _wedge_bounds_deg_draw: Array[float] = []

# Reflow tween state (start snapshot lerped toward the settled target by _reflow_t).
var _reflow_start_bounds: Array[Dictionary] = []
var _reflow_start_weights: Array[float] = []
var _reflow_start_bull: Dictionary = {}
var _reflow_tween: Tween = null

## Duration of the geometry re-flow tween (a dynamic resize — e.g. a Prism recolor shrinking a
## grown red triple — animates to read; an instant snap is illegible). Hover/scoring read the
## settled values; only the visuals tween.
@export var geometry_reflow_duration: float = 0.6

## TEMP bug-hunt instrumentation (brush ↔ Color Territory resize desync, 2026-06-08). When on,
## set_geometry() logs whether the churn guard SKIPPED an incoming push (thinks it's unchanged) or
## APPLIED it — so a stale overwrite arriving after a fresh paint shows up in the [GEO] sequence.
## Localized 2026-06-08 (resize machinery clean — see tests/repro_brush.tscn); kept off.
@export var debug_geometry_log: bool = false

## Whether hover highlighting is currently enabled. Controlled by main.gd.
var hover_enabled: bool = false

# Hover state — tracks which segment the mouse is currently over
var _hover_wedge_idx: int = -1
var _hover_ring_name: String = ""
var _hover_active: bool = false
var _hover_result: Dictionary = {}

# Checkout highlight state — which segments would win the leg
var _checkout_segments: Array[Dictionary] = []
var _checkout_pulse_active: bool = false
var _checkout_pulse_time: float = 0.0

# Path illumination state — equivalent segments for the selected checkout path step
var _illumination_segments: Array[Dictionary] = []
var _illumination_active: bool = false
var _illumination_pulse_time: float = 0.0
var _illumination_is_finish: bool = false

## The currently declared target segment. Set by main.gd when the player places the aim zone.
## Dictionary with wedge_index, ring_name, is_bull keys. Empty = no target.
var declared_target: Dictionary = {}

## Picker mode state — for interactive wedge selection UI
var picker_mode: bool = false
var _picker_hover_wedge: int = -1
var _picker_selected_wedges: Array[int] = []

## Segment picker mode — for selecting a specific ring on a wedge (brushes)
var segment_picker_mode: bool = false
var _segment_picker_hover_wedge: int = -1
var _segment_picker_hover_ring: String = ""

@export_group("Target & Picker")

## Color of the target segment highlight (shown during throw after placement).
@export var target_highlight_color: Color = Color(1.0, 0.85, 0.2, 0.12)

## Border color for the target segment highlight.
@export var target_highlight_border_color: Color = Color(1.0, 0.85, 0.2, 0.4)

@export var picker_highlight_color: Color = Color(0.2, 0.7, 1.0, 0.25)
@export var picker_selected_color: Color = Color(0.2, 1.0, 0.4, 0.3)
@export var picker_border_color: Color = Color(0.2, 0.7, 1.0, 0.6)

@export_group("Tutorial Highlights")

## Fill color for tutorial-highlighted segments. Bright yellow to distinguish from other highlights.
@export var tutorial_highlight_color: Color = Color(1.0, 0.85, 0.2, 0.4)

## Border color for tutorial-highlighted segments.
@export var tutorial_highlight_border_color: Color = Color(1.0, 1.0, 1.0, 0.7)

## Border thickness for tutorial highlight outlines in pixels.
@export var tutorial_highlight_thickness: float = 2.5

@export_group("Shop Spots — Shader")

## How fast the swirl pattern flows across lit spots.
@export_range(0.1, 3.0, 0.05) var shop_swirl_speed: float = 0.6

## Scale of the noise pattern — lower = larger swirls, higher = finer detail.
@export_range(1.0, 30.0, 0.5) var shop_noise_scale: float = 8.0

## How much domain warping distorts the pattern (more = swirly-er).
@export_range(0.0, 2.0, 0.05) var shop_distortion: float = 0.8

## How much brightness varies across the swirl pattern.
@export_range(0.0, 1.0, 0.05) var shop_contrast: float = 0.5

## Extra glow intensity at bright spots in the pattern.
@export_range(0.0, 2.0, 0.1) var shop_glow_strength: float = 0.8

@export_group("Shop Spots — Colors")

## Fill color for common lit spots.
@export var shop_color_common: Color = Color(0.95, 0.88, 0.65, 0.8)

## Fill color for uncommon lit spots.
@export var shop_color_uncommon: Color = Color(0.3, 0.5, 1.0, 0.8)

## Fill color for rare lit spots.
@export var shop_color_rare: Color = Color(0.7, 0.3, 0.9, 0.8)

## Fill color for GEOMETRY (rarity-less trade) lit spots — the geo UI green (matches
## EventFamilyIcons / geo option cards). Rarity-less, so the ring signals nothing; the colour +
## icon carry the family identity. (Bespoke kaleidoscope shader is a visual-polish follow-up.)
@export var shop_color_geometry: Color = Color(0.45, 0.72, 0.45, 0.8)

## Fill color for BRUSH (rarity-less trade) lit spots — greenish-teal painted tint. (Bespoke
## painted shader is a visual-polish follow-up.)
@export var shop_color_brush: Color = Color(0.30, 0.68, 0.62, 0.8)

## Pixel size of the family icon drawn centered on each lit spot (scaled down for thin rings).
@export var shop_icon_size: float = 26.0

## Base fill opacity for lit spot segments (before shader processing).
@export_range(0.3, 1.0, 0.05) var shop_fill_alpha: float = 0.7

## Border opacity for lit spot outlines.
@export_range(0.3, 1.0, 0.05) var shop_border_alpha: float = 0.9

## Border thickness for shop lit-spot outlines.
@export var shop_border_thickness: float = 2.5

@export_group("")

# Tutorial highlight state — segments to highlight during rules slideshow
var _tutorial_highlights: Array[Dictionary] = []
var _tutorial_highlight_active: bool = false

# Shop lit-spot state
var _shop_spots: Array[Dictionary] = []
var _shop_active: bool = false

## Ring name to inner/outer normalized radii mapping for segment drawing.
const RING_BOUNDS: Dictionary = {
	"Inner Single": [RING_SINGLE_BULL_OUTER, RING_INNER_SINGLE_OUTER],
	"Triple": [RING_INNER_SINGLE_OUTER, RING_TRIPLE_OUTER],
	"Outer Single": [RING_TRIPLE_OUTER, RING_OUTER_SINGLE_OUTER],
	"Double": [RING_OUTER_SINGLE_OUTER, RING_DOUBLE_OUTER],
}

## Display ring names inside-out — a stable iteration order for overlay draws that previously
## iterated RING_BOUNDS (Dictionary key order is insertion order, but this is explicit).
const RING_ORDER_DISPLAY: Array[String] = ["Inner Single", "Triple", "Outer Single", "Double"]

## Child node for shop spot rendering — lets a shader apply to just the spots.
var _shop_overlay: Node2D

## Child node for a single shop spot dissolving after being hit.
var _shop_dissolve_overlay: Node2D

## Dissolve animation state.
var _shop_dissolve_active: bool = false
var _shop_dissolve_time: float = 0.0
var _shop_dissolve_spot: Dictionary = {}
var _shop_dissolve_center: Vector2 = Vector2.ZERO

## Child node for boss visual overlays (voids, etc.).
var _boss_overlay: Node2D

## Child node for recession damage overlay (separate shader from voids).
var _recession_overlay: Node2D

## Child node for hit shockwave overlay.
var _shockwave_overlay: Node2D

## Shockwave animation state.
var _shockwave_active: bool = false
var _shockwave_time: float = 0.0
var _shockwave_hit_point: Vector2 = Vector2.ZERO
var _shockwave_ring_name: String = ""
var _shockwave_wedge_idx: int = -1

## Wedge indices currently voided by a boss (drawn as dark segments).
var _boss_void_wedges: Array[int] = []

## Wedge indices that were voided last turn (fading out).
var _boss_void_wedges_prev: Array[int] = []

## Transition progress for void overlay (0 = old state, 1 = new state).
var _void_transition_t: float = 1.0

## Individually-voided rings on partially-void wedges (Void boss drift). Keyed
## "<wedge_index>:<RingName>" (ring names as produced by calculate_score, e.g.
## "3:Inner Single"). Whole-wedge voids stay in _boss_void_wedges; these are the
## drifted rings that landed on otherwise-hittable wedges.
var _boss_void_rings: Dictionary = {}

## Previous drifted-ring set (fading out during the migration tween).
var _boss_void_rings_prev: Dictionary = {}

## Drift migration state (Void boss two-phase reveal). During phase 2 each entry
## {"from": int, "to": int, "ring": String} is drawn sliding from its source wedge
## to its neighbor; _drift_t (0→1) is the migration progress. Empty when idle.
var _drift_moves: Array[Dictionary] = []
var _drift_t: float = 1.0

## Final steady-state void sets + pending moves, stashed between the two phases.
var _void_final_whole: Array[int] = []
var _void_final_rings: Dictionary = {}
var _void_pending_moves: Array[Dictionary] = []

## Active void-sequence tweens, killed if a new turn starts mid-animation.
var _void_fill_tween: Tween = null
var _void_drift_tween: Tween = null

## Wedge indices with boss-reduced values (shown in red instead of green).
var boss_reduced_wedges: Array[int] = []

## Wedge indices affected by recession boss (drawn with scuff/damage overlay).
var _boss_recession_wedges: Array[int] = []

## Progress of a color transition tween (0 = old, 1 = new). 1.0 = no transition.
var _color_transition_t: float = 1.0

## Previous wedge colors for blending during transition.
var _prev_wedge_colors: Array[Dictionary] = []

## Prism recolor burst (per-hit, radiates outward from the hit ring). Keyed
## "<wedge>:<ring_key>" (ring_key = inner_single/triple/outer_single/double).
## _prism_burst_prev holds each ring's pre-recolor SegmentColor; _prism_burst_delay
## holds its reveal delay as a fraction of the burst clock _prism_burst_t (0→1).
var _prism_burst_active: bool = false
var _prism_burst_t: float = 1.0
var _prism_burst_prev: Dictionary = {}
var _prism_burst_delay: Dictionary = {}
var _prism_burst_tween: Tween = null

@export_group("Void Overlay")

## Duration of the void transition animation (cross-turn fade of whole-wedge voids).
@export var void_transition_duration: float = 0.3

## Void two-phase reveal (medium/hard with drift): phase 1 fades the freshly-chosen
## whole wedges in (matching the easy version), then phase 2 slides the drifted rings
## from their source wedge to the neighbor. Sequenced — phase 2 starts after phase 1.
@export var void_fill_duration: float = 0.45
@export var void_drift_duration: float = 0.6

## Duration for color transition animations (Prism boss).
@export var color_transition_duration: float = 0.35

## Prism recolor burst: total time for the radiating recolor of all affected rings,
## and the per-ring fade window (as a fraction of the total) — the hit ring fades at
## the start, the outermost affected rings finish by the end.
@export var prism_recolor_duration: float = 0.5
@export var prism_recolor_fade: float = 0.35

## Color used to draw voided wedge segments (base color under the swirl shader).
@export var void_fill_color: Color = Color(0.05, 0.02, 0.1, 0.88)

## Border color for voided wedge segments.
@export var void_border_color: Color = Color(0.3, 0.1, 0.45, 0.7)

## Border thickness for voided wedge segments.
@export var void_border_thickness: float = 1.5

## Swirl animation speed for void overlay.
@export var void_swirl_speed: float = 0.4

## Noise scale for void swirl pattern.
@export var void_noise_scale: float = 10.0

## Distortion amount for void swirl.
@export var void_distortion: float = 0.9

## Contrast for void swirl pattern.
@export var void_contrast: float = 0.6

## Glow strength for void swirl highlights.
@export var void_glow_strength: float = 0.5

@export_group("Hit Shockwave")

## Duration of the shockwave animation in seconds.
@export_range(0.1, 2.0, 0.05) var shockwave_duration: float = 0.45

## How far the wave travels in normalized board units (0–1).
@export_range(0.05, 1.0, 0.01) var shockwave_reach: float = 0.35

## Width of the bright leading edge band.
@export_range(0.01, 0.2, 0.005) var shockwave_edge_width: float = 0.06

## Width of the softer glow trail behind the edge.
@export_range(0.01, 0.4, 0.01) var shockwave_trail_width: float = 0.12

## Peak brightness of the leading edge (additive).
@export_range(0.0, 3.0, 0.1) var shockwave_edge_intensity: float = 1.8

## Brightness of the trail glow.
@export_range(0.0, 2.0, 0.1) var shockwave_trail_intensity: float = 0.6

## Tint color for the shockwave wave (normal hits).
@export var shockwave_color: Color = Color(1.0, 0.95, 0.8, 1.0)

## Tint color for the shockwave on a winning (leg-closing) dart.
@export var shockwave_win_color: Color = Color(1.0, 0.85, 0.2, 1.0)

## Tint color for the shockwave on a bust.
@export var shockwave_bust_color: Color = Color(1.0, 0.15, 0.1, 1.0)

@export_group("Path Illumination")

## Color of the path illumination outline on qualifying segments.
@export var illumination_color: Color = Color(0.2, 0.5, 1.0, 0.8)

## Speed of the illumination pulse animation.
@export var illumination_pulse_speed: float = 2.5

## Minimum opacity of the illumination pulse.
@export var illumination_pulse_min_alpha: float = 0.2

## Maximum opacity of the illumination pulse.
@export var illumination_pulse_max_alpha: float = 0.7

## Border thickness for illumination outlines.
@export var illumination_border_thickness: float = 3.0

## Alpha multiplier applied to the gold checkout pulse when illumination is active.
@export var checkout_pulse_dimming: float = 0.3

@export_group("Recession Overlay")

## Base color of the recession damage overlay polygons (fed to the recession shader).
@export var recession_overlay_color: Color = Color(0.15, 0.05, 0.05, 0.35)

## Drift speed of the recession scuff pattern.
@export_range(0.0, 0.5, 0.01) var recession_noise_speed: float = 0.1

## Noise frequency — higher values give finer grit.
@export_range(5.0, 40.0, 0.5) var recession_noise_scale: float = 20.0

## How pronounced the dark scuff patches are.
@export_range(0.0, 1.0, 0.05) var recession_roughness: float = 0.65

## Overall darkening strength of the recession effect.
@export_range(0.0, 1.0, 0.05) var recession_intensity: float = 0.5

@export_group("")


## Board-rule reminder studs on the surround (one per active geometry rule). Child of the board.
var _board_studs: Node2D = null
const _BOARD_STUDS_SCRIPT: Script = preload("res://scripts/board_studs.gd")


func _ready() -> void:
	# Seed canonical geometry so a board nobody pushes state to renders/scoring as standard.
	_seed_default_geometry()

	# Geometry rule studs on the surround. Created here so the dartboard owns its surround art.
	_board_studs = _BOARD_STUDS_SCRIPT.new()
	add_child(_board_studs)

	_shop_overlay = Node2D.new()
	_shop_overlay.draw.connect(_draw_shop_overlay)
	var shader: Shader = load("res://shaders/shop_spot.gdshader")
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	_sync_shop_shader(mat)
	_shop_overlay.material = mat
	add_child(_shop_overlay)

	# Child layer for the optional hotspot smoke shader (one Polygon2D + label per hot ring).
	# Built lazily from hotspot_rings; empty while the dev toggle is off.
	_hotspot_shader_layer = Node2D.new()
	add_child(_hotspot_shader_layer)
	_hotspot_label_material = ShaderMaterial.new()
	_hotspot_label_material.shader = _HOTSPOT_LABEL_SHADER
	_rebuild_hotspot_shader_layer()

	_shop_dissolve_overlay = Node2D.new()
	_shop_dissolve_overlay.draw.connect(_draw_shop_dissolve_overlay)
	var dissolve_shader: Shader = load("res://shaders/shop_spot_dissolve.gdshader")
	var dissolve_mat: ShaderMaterial = ShaderMaterial.new()
	dissolve_mat.shader = dissolve_shader
	_sync_shop_shader(dissolve_mat)
	_shop_dissolve_overlay.material = dissolve_mat
	add_child(_shop_dissolve_overlay)

	_boss_overlay = Node2D.new()
	_boss_overlay.draw.connect(_draw_boss_overlay)
	var boss_shader: Shader = load("res://shaders/shop_spot.gdshader")
	var boss_mat: ShaderMaterial = ShaderMaterial.new()
	boss_mat.shader = boss_shader
	boss_mat.set_shader_parameter("board_radius", board_radius)
	boss_mat.set_shader_parameter("speed", void_swirl_speed)
	boss_mat.set_shader_parameter("noise_scale", void_noise_scale)
	boss_mat.set_shader_parameter("distortion", void_distortion)
	boss_mat.set_shader_parameter("contrast", void_contrast)
	boss_mat.set_shader_parameter("glow_strength", void_glow_strength)
	_boss_overlay.material = boss_mat
	add_child(_boss_overlay)

	_recession_overlay = Node2D.new()
	_recession_overlay.draw.connect(_draw_recession_overlay_cb)
	var recession_shader: Shader = load("res://shaders/recession_overlay.gdshader")
	var recession_mat: ShaderMaterial = ShaderMaterial.new()
	recession_mat.shader = recession_shader
	recession_mat.set_shader_parameter("board_radius", board_radius)
	recession_mat.set_shader_parameter("speed", recession_noise_speed)
	recession_mat.set_shader_parameter("noise_scale", recession_noise_scale)
	recession_mat.set_shader_parameter("roughness", recession_roughness)
	recession_mat.set_shader_parameter("intensity", recession_intensity)
	_recession_overlay.material = recession_mat
	add_child(_recession_overlay)

	_shockwave_overlay = Node2D.new()
	_shockwave_overlay.draw.connect(_draw_shockwave_overlay)
	var sw_shader: Shader = load("res://shaders/hit_shockwave.gdshader")
	var sw_mat: ShaderMaterial = ShaderMaterial.new()
	sw_mat.shader = sw_shader
	_sync_shockwave_shader(sw_mat)
	_shockwave_overlay.material = sw_mat
	add_child(_shockwave_overlay)


func _draw() -> void:
	# Draw surround ring (off-board area)
	draw_circle(Vector2.ZERO, board_radius * surround_outer_multiplier, surround_color)

	# Draw each wedge's rings from outermost to innermost
	for wedge_idx: int in range(20):
		var start_angle_deg: float = _wedge_start_deg(wedge_idx)
		var end_angle_deg: float = _wedge_end_deg(wedge_idx)

		var double_color: Color
		var outer_single_color: Color
		var triple_color: Color
		var inner_single_color: Color
		if effective_wedge_colors.size() == 20:
			var entry: Dictionary = effective_wedge_colors[wedge_idx]
			double_color = _segment_color_to_render(entry["double"])
			outer_single_color = _segment_color_to_render(entry["outer_single"])
			triple_color = _segment_color_to_render(entry["triple"])
			inner_single_color = _segment_color_to_render(entry["inner_single"])
			if _color_transition_t < 1.0 and _prev_wedge_colors.size() == 20:
				var prev: Dictionary = _prev_wedge_colors[wedge_idx]
				double_color = _segment_color_to_render(prev["double"]).lerp(double_color, _color_transition_t)
				outer_single_color = _segment_color_to_render(prev["outer_single"]).lerp(outer_single_color, _color_transition_t)
				triple_color = _segment_color_to_render(prev["triple"]).lerp(triple_color, _color_transition_t)
				inner_single_color = _segment_color_to_render(prev["inner_single"]).lerp(inner_single_color, _color_transition_t)
		else:
			var is_even: bool = wedge_idx % 2 == 0
			inner_single_color = wedge_a_single if is_even else wedge_b_single
			outer_single_color = inner_single_color
			triple_color = wedge_a_multi if is_even else wedge_b_multi
			double_color = triple_color

		# Prism recolor burst: each affected ring fades from its old colour to the new
		# one on a delay that radiates outward from the hit ring.
		if _prism_burst_active:
			inner_single_color = _apply_prism_burst(wedge_idx, "inner_single", inner_single_color)
			triple_color = _apply_prism_burst(wedge_idx, "triple", triple_color)
			outer_single_color = _apply_prism_burst(wedge_idx, "outer_single", outer_single_color)
			double_color = _apply_prism_burst(wedge_idx, "double", double_color)

		# Parity Out legibility (§9b cond 2): grey out the DOUBLE of dead-parity wedges so the
		# halved out-set reads at a glance. Only the double — it is the universal finish ring;
		# triples never out under standard play, so dimming them would mislead.
		if _is_dead_parity_wedge(wedge_idx):
			double_color = _desaturate_dead(double_color)

		# Each ring band reads THIS wedge's draw bounds (Ring Trade / Color Territory reshape
		# them per wedge; double_ring_width_scale folds in via _band_draw).
		var d_band: Array = _band_draw(wedge_idx, "double")
		var os_band: Array = _band_draw(wedge_idx, "outer_single")
		var t_band: Array = _band_draw(wedge_idx, "triple")
		var is_band: Array = _band_draw(wedge_idx, "inner_single")

		# Double ring (inner boundary narrows when Narrow Double Ring boss is active)
		_draw_segment(start_angle_deg, end_angle_deg, d_band[1], d_band[0], double_color)
		# Outer single (expands outward to fill the gap when the double ring is narrowed)
		_draw_segment(start_angle_deg, end_angle_deg, os_band[1], os_band[0], outer_single_color)
		# Triple ring
		_draw_segment(start_angle_deg, end_angle_deg, t_band[1], t_band[0], triple_color)
		# Inner single
		_draw_segment(start_angle_deg, end_angle_deg, is_band[1], is_band[0], inner_single_color)

	# Bullseyes drawn on top as filled circles (draw radii so they re-flow with Bigger Bull)
	draw_circle(Vector2.ZERO, board_radius * _single_bull_draw(), bull_single_color)
	draw_circle(Vector2.ZERO, board_radius * _double_bull_draw(), bull_double_color)

	# Wires: the bull rings are concentric (full circles, still valid). The ring-band boundaries
	# now vary per wedge, so they're drawn as per-wedge arcs + radial spokes at the weighted
	# wedge boundaries (a full-circle wire would no longer track a resized ring).
	_draw_ring_wire(_double_bull_draw())
	_draw_ring_wire(_single_bull_draw())
	_draw_ring_wire(RING_DOUBLE_OUTER)
	for wedge_idx: int in range(20):
		var ws: float = _wedge_start_deg(wedge_idx)
		var we: float = _wedge_end_deg(wedge_idx)
		# Per-wedge boundary arcs at the three internal ring boundaries.
		_draw_boundary_arc(ws, we, _band_draw(wedge_idx, "inner_single")[1])
		_draw_boundary_arc(ws, we, _band_draw(wedge_idx, "triple")[1])
		_draw_boundary_arc(ws, we, _effective_double_inner_w(wedge_idx))
		# Radial spoke along the wedge's start boundary.
		var angle_rad: float = deg_to_rad(ws)
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		var inner_point: Vector2 = direction * board_radius * _single_bull_draw()
		var outer_point: Vector2 = direction * board_radius * RING_DOUBLE_OUTER
		draw_line(inner_point, outer_point, wire_color, wire_thickness)

	# Draw target segment highlight (declared target during throw)
	if not declared_target.is_empty():
		_draw_target_highlight()

	# Draw hover highlight on the segment under the mouse (if active)
	if _hover_active and _hover_ring_name != "":
		_draw_hover_segment()

	# Draw picker highlights for interactive wedge selection
	if picker_mode:
		_draw_picker_highlights()

	# Draw segment picker highlight for brush/ring selection
	if segment_picker_mode and _segment_picker_hover_ring != "" and _segment_picker_hover_wedge >= 0:
		_draw_segment_picker_highlight()

	# Draw checkout pulse on valid finishing double segments
	if _checkout_pulse_active and _checkout_segments.size() > 0:
		_draw_checkout_pulses()

	# Draw path illumination outlines (selected checkout path step equivalents)
	if _illumination_active and _illumination_segments.size() > 0:
		_draw_illumination_outlines()

	# Draw tutorial highlights (rules slideshow / tutorial callouts)
	if _tutorial_highlight_active:
		_draw_tutorial_highlights()

	# Shop spots are drawn on the overlay child (shader handles animation)

	# Draw wedge numbers around the board in the surround ring
	# Uses effective_wedge_values if available, so modified values are shown
	var font: Font = ThemeDB.fallback_font
	for wedge_idx: int in range(20):
		# Center angle of this wedge (weighted center — Parity Shift varies wedge widths — with
		# the rotation offset applied for the Rotation boss).
		var angle_deg: float = _wedge_center_deg(wedge_idx)
		var angle_rad: float = deg_to_rad(angle_deg)
		# Position along that angle at the number radius
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		var pos: Vector2 = direction * board_radius * number_radius_multiplier

		# Look up effective value (may differ from original if modifiers applied)
		var effective_value: int = WEDGE_ORDER[wedge_idx]
		var is_modified: bool = false
		if effective_wedge_values.size() == 20:
			effective_value = effective_wedge_values[wedge_idx]
			is_modified = effective_value != WEDGE_ORDER[wedge_idx]

		var number_text: String = str(effective_value)
		# Flipped wedges score upward — mark them with a "+" suffix.
		if flipped_wedges.has(wedge_idx):
			number_text += "+"
		# Calculate text offset for centering
		var text_width: float = font.get_string_size(number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, number_font_size).x
		var draw_pos: Vector2 = Vector2(pos.x - text_width / 2.0, pos.y + number_font_size / 2.0)

		var text_color: Color = number_color
		if boss_reduced_wedges.has(wedge_idx):
			text_color = boss_reduced_number_color
		elif is_modified:
			text_color = modified_number_color
		draw_string(font, draw_pos, number_text, HORIZONTAL_ALIGNMENT_CENTER, -1, number_font_size, text_color)

	# Draw hotspot indicators on top of segments/numbers so they survive recolor + overlay.
	# In shader mode the smoke + label live in _hotspot_shader_layer (child nodes), so skip the
	# code-drawn outline here.
	if not hotspot_rings.is_empty() and not use_hotspot_shader:
		_draw_hotspot_indicators(font)

	# Draw flash overlay on the hit segment (if active)
	if _flash_alpha > 0.0:
		var flash_col: Color = Color(flash_color, _flash_alpha)
		_draw_flash_segment(flash_col)
		var border_col: Color = Color(flash_border_color, _flash_alpha)
		_draw_flash_border(border_col)


## Trigger a flash on the segment at the given global hit position.
## Call this after scoring to highlight where the dart landed.
## Pass is_winning_dart = true for the leg-closing dart (gold shockwave),
## or is_bust = true for a bust (red shockwave).
func flash_segment(global_hit_position: Vector2, is_winning_dart: bool = false, is_bust: bool = false) -> void:
	var relative: Vector2 = global_hit_position - global_position

	# Determine which ring was hit (draw geometry — the flash should match the rendered board).
	_flash_ring_name = _classify_ring_key_draw(relative)
	if _flash_ring_name == "":
		return  # Off board — no flash.

	# Determine which wedge index (not needed for bullseyes)
	if _flash_ring_name != "double_bull" and _flash_ring_name != "single_bull":
		_flash_wedge_idx = _get_wedge_index_draw(relative)

	# Animate the flash: start bright, tween alpha to 0
	_flash_alpha = flash_color.a
	var tween: Tween = create_tween()
	tween.tween_property(self, "_flash_alpha", 0.0, flash_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(queue_redraw)

	# Trigger shockwave on the same segment
	_shockwave_hit_point = relative / board_radius
	_shockwave_ring_name = _flash_ring_name
	_shockwave_wedge_idx = _flash_wedge_idx
	_shockwave_time = 0.0
	_shockwave_active = true
	var sw_mat2: ShaderMaterial = _shockwave_overlay.material as ShaderMaterial
	_sync_shockwave_shader(sw_mat2)
	var tint: Color = shockwave_win_color if is_winning_dart else (shockwave_bust_color if is_bust else shockwave_color)
	sw_mat2.set_shader_parameter("wave_color", tint)
	sw_mat2.set_shader_parameter("hit_point", _shockwave_hit_point)
	sw_mat2.set_shader_parameter("progress", 0.0)
	_shockwave_overlay.queue_redraw()

	# Redraw every frame during the tween
	set_process(true)


func _process(delta: float) -> void:
	var needs_redraw: bool = false

	if _flash_alpha > 0.0:
		needs_redraw = true

	if _checkout_pulse_active:
		_checkout_pulse_time += delta
		needs_redraw = true

	if _illumination_active:
		_illumination_pulse_time += delta
		needs_redraw = true

	if _shockwave_active:
		_shockwave_time += delta
		var progress: float = clampf(_shockwave_time / shockwave_duration, 0.0, 1.0)
		var sw_mat: ShaderMaterial = _shockwave_overlay.material as ShaderMaterial
		sw_mat.set_shader_parameter("progress", progress)
		_shockwave_overlay.queue_redraw()
		if progress >= 1.0:
			_shockwave_active = false
		else:
			needs_redraw = true

	if _shop_dissolve_active:
		_shop_dissolve_time += delta
		var dissolve_progress: float = clampf(_shop_dissolve_time / shockwave_duration, 0.0, 1.0)
		var d_mat: ShaderMaterial = _shop_dissolve_overlay.material as ShaderMaterial
		d_mat.set_shader_parameter("dissolve_progress", dissolve_progress)
		_shop_dissolve_overlay.queue_redraw()
		if dissolve_progress >= 1.0:
			_shop_dissolve_active = false
			_shop_dissolve_spot = {}
		else:
			needs_redraw = true

	if needs_redraw:
		queue_redraw()
	elif not _checkout_pulse_active and not _illumination_active:
		set_process(false)


## Draw the flash overlay for the currently flashing segment (draw geometry).
func _draw_flash_segment(color: Color) -> void:
	if _flash_ring_name == "double_bull":
		draw_circle(Vector2.ZERO, board_radius * _double_bull_draw(), color)
		return
	if _flash_ring_name == "single_bull":
		draw_circle(Vector2.ZERO, board_radius * _single_bull_draw(), color)
		return
	var band: Array = _band_draw_by_name(_flash_wedge_idx, _flash_ring_name)
	if band[1] <= 0.0:
		return
	var start_deg: float = _wedge_start_deg(_flash_wedge_idx)
	var end_deg: float = _wedge_end_deg(_flash_wedge_idx)
	_draw_segment(start_deg, end_deg, band[1], band[0], color)


## Draw a border outline around the currently flashing segment (draw geometry).
func _draw_flash_border(color: Color) -> void:
	if _flash_ring_name == "double_bull":
		draw_polyline(_make_circle_points(_double_bull_draw()), color, flash_border_thickness)
		return
	if _flash_ring_name == "single_bull":
		draw_polyline(_make_circle_points(_single_bull_draw()), color, flash_border_thickness)
		return
	var band: Array = _band_draw_by_name(_flash_wedge_idx, _flash_ring_name)
	if band[1] <= 0.0:
		return
	var start_deg: float = _wedge_start_deg(_flash_wedge_idx)
	var end_deg: float = _wedge_end_deg(_flash_wedge_idx)
	_draw_segment_border(start_deg, end_deg, band[1], band[0], color, flash_border_thickness)


## Draw a single arc segment (wedge slice of a ring).
func _draw_segment(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_r: float = board_radius * outer_norm
	var inner_r: float = board_radius * inner_norm

	# Outer arc from start to end
	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * outer_r)

	# Inner arc from end back to start
	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * inner_r)

	draw_colored_polygon(points, color)


## Draw a wire arc at a normalized radius spanning a single wedge's angular range. Used for the
## ring-band boundaries that now vary per wedge (a full-circle wire would not track a resized ring).
func _draw_boundary_arc(start_deg: float, end_deg: float, normalized_radius: float) -> void:
	var r: float = board_radius * normalized_radius
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var a: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		pts.append(Vector2(sin(a), -cos(a)) * r)
	draw_polyline(pts, wire_color, wire_thickness)


## Draw a circular wire line at a given normalized radius.
func _draw_ring_wire(normalized_radius: float) -> void:
	var r: float = board_radius * normalized_radius
	var points: PackedVector2Array = PackedVector2Array()
	var num_points: int = 64
	for i: int in range(num_points + 1):
		var angle: float = TAU * float(i) / float(num_points)
		points.append(Vector2(cos(angle), sin(angle)) * r)
	draw_polyline(points, wire_color, wire_thickness)


## Calculate the score for a dart landing at the given global pixel position.
## Returns an enriched dictionary with: face_value, multiplier, total_score,
## ring_name, wedge_index, segment_color, is_bull.
## Uses effective_wedge_values for face value lookup if available.
## Uses effective_wedge_colors for segment color if available.
func calculate_score(global_hit_position: Vector2) -> Dictionary:
	# Convert to board-relative coordinates
	var relative: Vector2 = global_hit_position - global_position
	var distance: float = relative.length()
	var normalized_distance: float = distance / board_radius

	# Determine ring
	var ring_name: String = ""
	var multiplier: int = 0
	var face_value: int = 0
	var wedge_index: int = -1
	var segment_color: int = -1
	var is_bull: bool = false

	# Bull checks first (concentric, read the settled bull radii), THEN the wedge index, THEN
	# the ring classification against THAT wedge's settled bounds (per-wedge bounds invert the
	# old ring-first order). Scoring reads the settled geometry, never the reflow tween.
	if normalized_distance <= _double_bull_settled():
		ring_name = "Double Bull"
		face_value = 25
		multiplier = 2
		is_bull = true
		segment_color = ScoringEnums.SegmentColor.RED
	elif normalized_distance <= _single_bull_settled():
		ring_name = "Single Bull"
		face_value = 25
		multiplier = 1
		is_bull = true
		segment_color = ScoringEnums.SegmentColor.GREEN
	else:
		wedge_index = _get_wedge_index(relative)
		var inner_single_outer: float = _band_raw_settled(wedge_index, "inner_single")[1]
		var triple_outer: float = _band_raw_settled(wedge_index, "triple")[1]
		var double_inner: float = _effective_double_inner_settled(wedge_index)
		if normalized_distance <= inner_single_outer:
			ring_name = "Inner Single"
			multiplier = 1
			face_value = _lookup_wedge_value(wedge_index)
			segment_color = _lookup_segment_color(wedge_index, "inner_single")
		elif normalized_distance <= triple_outer:
			ring_name = "Triple"
			multiplier = 3
			face_value = _lookup_wedge_value(wedge_index)
			segment_color = _lookup_segment_color(wedge_index, "triple")
		elif normalized_distance <= double_inner:
			ring_name = "Outer Single"
			multiplier = 1
			face_value = _lookup_wedge_value(wedge_index)
			segment_color = _lookup_segment_color(wedge_index, "outer_single")
		elif normalized_distance <= RING_DOUBLE_OUTER:
			ring_name = "Double"
			multiplier = 2
			face_value = _lookup_wedge_value(wedge_index)
			segment_color = _lookup_segment_color(wedge_index, "double")
		else:
			ring_name = "Off Board"
			face_value = 0
			multiplier = 0
			wedge_index = -1

	# Boss voids: a whole-void wedge already scores 0 (its value is zeroed), but a
	# drifted ring void sits on a wedge with a live value, so zero it here.
	var seg_voided: bool = false
	if wedge_index >= 0 and ring_name != "Off Board":
		if _boss_void_wedges.has(wedge_index):
			seg_voided = true
		elif _boss_void_rings.has("%d:%s" % [wedge_index, ring_name]):
			seg_voided = true

	var total_score: int = 0 if seg_voided else face_value * multiplier
	return {
		"face_value": face_value,
		"multiplier": multiplier,
		"total_score": total_score,
		"ring_name": ring_name,
		"wedge_index": wedge_index,
		"segment_color": segment_color,
		"is_bull": is_bull,
		"is_void": seg_voided,
	}


## Determine which wedge index (0-19) a board-relative position falls in, using the SETTLED
## weighted wedge boundaries (so scoring agrees with the final geometry, not a mid-reflow tween).
func _get_wedge_index(relative: Vector2) -> int:
	return _wedge_index_from(relative, _wedge_bounds_deg)


## As above but against the DRAW boundaries — for visual highlights that should match the
## currently-rendered (possibly tweening) board.
func _get_wedge_index_draw(relative: Vector2) -> int:
	return _wedge_index_from(relative, _wedge_bounds_deg_draw)


## Core: which wedge interval [bounds_deg[i], bounds_deg[i+1]) the position's angle falls in.
## Boundaries vary in width (Parity Shift), so this walks them rather than dividing by 18°.
func _wedge_index_from(relative: Vector2, bounds_deg: Array[float]) -> int:
	# atan2(x, -y) gives angle from 12 o'clock, clockwise positive.
	var angle_deg: float = rad_to_deg(atan2(relative.x, -relative.y))
	# Undo the board rotation so the angle is in the same frame as bounds_deg.
	angle_deg -= board_rotation_offset
	if bounds_deg.size() != 21:
		# Fallback: uniform division (matches the legacy layout).
		angle_deg = fmod(angle_deg - WEDGE_OFFSET_DEG, 360.0)
		if angle_deg < 0.0:
			angle_deg += 360.0
		return int(angle_deg / WEDGE_ANGLE_DEG) % 20
	# Shift the angle into [bounds_deg[0], bounds_deg[0] + 360) so the walk below resolves it.
	var lo: float = bounds_deg[0]
	while angle_deg < lo:
		angle_deg += 360.0
	while angle_deg >= lo + 360.0:
		angle_deg -= 360.0
	for i: int in range(20):
		if angle_deg < bounds_deg[i + 1]:
			return i
	return 19


## Look up the effective face value for a wedge index.
## Uses effective_wedge_values if populated, otherwise falls back to WEDGE_ORDER.
func _lookup_wedge_value(wedge_idx: int) -> int:
	if effective_wedge_values.size() == 20:
		return effective_wedge_values[wedge_idx]
	return WEDGE_ORDER[wedge_idx]


## Map a SegmentColor enum value to the actual render Color used for drawing.
func _segment_color_to_render(seg_color: ScoringEnums.SegmentColor) -> Color:
	match seg_color:
		ScoringEnums.SegmentColor.BLACK:
			return wedge_a_single
		ScoringEnums.SegmentColor.WHITE:
			return wedge_b_single
		ScoringEnums.SegmentColor.RED:
			return wedge_a_multi
		ScoringEnums.SegmentColor.GREEN:
			return wedge_b_multi
	return wedge_a_single


## Look up the segment color for a wedge index and ring.
## ring_key is one of "inner_single", "triple", "outer_single", "double".
## Uses effective_wedge_colors if populated, otherwise derives from wedge index.
func _lookup_segment_color(wedge_idx: int, ring_key: String) -> ScoringEnums.SegmentColor:
	if effective_wedge_colors.size() == 20:
		return effective_wedge_colors[wedge_idx][ring_key]
	var is_even: bool = wedge_idx % 2 == 0
	if ring_key == "triple" or ring_key == "double":
		return ScoringEnums.SegmentColor.RED if is_even else ScoringEnums.SegmentColor.GREEN
	else:
		return ScoringEnums.SegmentColor.BLACK if is_even else ScoringEnums.SegmentColor.WHITE


## Compute the global-space centroid of a board segment identified by wedge_index and ring_name.
## For bullseyes, returns the board center. For wedge segments, returns the midpoint
## of the arc segment (center angle of the wedge, midpoint radius of the ring).
func get_segment_centroid(wedge_index: int, ring_name: String) -> Vector2:
	if ring_name == "Double Bull" or ring_name == "double_bull":
		return global_position
	if ring_name == "Single Bull" or ring_name == "single_bull":
		return global_position

	# For wedge segments, aim at the wedge's weighted CENTER angle and the ring's midpoint radius
	# (both track the live geometry, so auto-aim follows a resized/widened wedge).
	var center_angle_rad: float = deg_to_rad(_wedge_center_deg(wedge_index))
	var direction: Vector2 = Vector2(sin(center_angle_rad), -cos(center_angle_rad))
	var band: Array = _band_draw_by_name(wedge_index, ring_name)
	var mid_r: float = board_radius * (float(band[0]) + float(band[1])) / 2.0
	return global_position + direction * mid_r


## Set the declared target segment for visual highlighting.
func set_declared_target(target: Dictionary) -> void:
	declared_target = target
	queue_redraw()


## Clear the declared target highlight.
func clear_declared_target() -> void:
	declared_target = {}
	queue_redraw()


## Update hover state based on the current global mouse position.
## Call this from main.gd during hover-active game states.
## Returns the score dictionary for the hovered segment (for tooltip display),
## or an empty dictionary if the mouse is off the board.
func update_hover(global_mouse_pos: Vector2) -> Dictionary:
	if not hover_enabled:
		_clear_hover()
		return {}

	var relative: Vector2 = global_mouse_pos - global_position

	# Determine which ring the mouse is in (draw geometry — the highlight tracks the rendered board).
	var new_ring_name: String = _classify_ring_key_draw(relative)
	if new_ring_name == "":
		# Off board — clear hover
		_clear_hover()
		return {}

	# Determine wedge index (not needed for bullseyes)
	var new_wedge_idx: int = -1
	if new_ring_name != "double_bull" and new_ring_name != "single_bull":
		new_wedge_idx = _get_wedge_index_draw(relative)

	# Only redraw if the hovered segment actually changed
	if new_ring_name != _hover_ring_name or new_wedge_idx != _hover_wedge_idx:
		_hover_ring_name = new_ring_name
		_hover_wedge_idx = new_wedge_idx
		_hover_active = true
		# Calculate score for this segment using effective values
		_hover_result = calculate_score(global_mouse_pos)
		queue_redraw()

	return _hover_result


## Clear hover state — call when hover should be disabled.
func clear_hover() -> void:
	_clear_hover()


## Internal clear hover and trigger redraw if needed.
func _clear_hover() -> void:
	if _hover_active:
		_hover_ring_name = ""
		_hover_wedge_idx = -1
		_hover_active = false
		_hover_result = {}
		queue_redraw()


## Draw a subtle highlight on the currently hovered segment.
func _draw_hover_segment() -> void:
	if _hover_ring_name == "double_bull":
		draw_circle(Vector2.ZERO, board_radius * _double_bull_draw(), hover_highlight_color)
		draw_polyline(_make_circle_points(_double_bull_draw()), hover_border_color, hover_border_thickness)
		return
	if _hover_ring_name == "single_bull":
		draw_circle(Vector2.ZERO, board_radius * _single_bull_draw(), hover_highlight_color)
		draw_polyline(_make_circle_points(_single_bull_draw()), hover_border_color, hover_border_thickness)
		draw_polyline(_make_circle_points(_double_bull_draw()), hover_border_color, hover_border_thickness)
		return
	var band: Array = _band_draw_by_name(_hover_wedge_idx, _hover_ring_name)
	if band[1] <= 0.0:
		return
	var start_deg: float = _wedge_start_deg(_hover_wedge_idx)
	var end_deg: float = _wedge_end_deg(_hover_wedge_idx)
	_draw_segment(start_deg, end_deg, band[1], band[0], hover_highlight_color)
	_draw_segment_border(start_deg, end_deg, band[1], band[0], hover_border_color, hover_border_thickness)


## Draw a highlight on the declared target segment.
func _draw_target_highlight() -> void:
	var ring_name: String = declared_target.get("ring_name", "")
	var is_bull: bool = declared_target.get("is_bull", false)
	var wedge_idx: int = declared_target.get("wedge_index", -1)

	if is_bull:
		if ring_name == "Double Bull":
			draw_circle(Vector2.ZERO, board_radius * _double_bull_draw(), target_highlight_color)
			draw_polyline(_make_circle_points(_double_bull_draw()), target_highlight_border_color, hover_border_thickness)
		elif ring_name == "Single Bull":
			draw_circle(Vector2.ZERO, board_radius * _single_bull_draw(), target_highlight_color)
			draw_polyline(_make_circle_points(_single_bull_draw()), target_highlight_border_color, hover_border_thickness)
			draw_polyline(_make_circle_points(_double_bull_draw()), target_highlight_border_color, hover_border_thickness)
	elif wedge_idx >= 0:
		var start_deg: float = _wedge_start_deg(wedge_idx)
		var end_deg: float = _wedge_end_deg(wedge_idx)
		var band: Array = _band_draw_by_name(wedge_idx, ring_name)
		if band[1] > 0.0:
			_draw_segment(start_deg, end_deg, band[1], band[0], target_highlight_color)
			_draw_segment_border(start_deg, end_deg, band[1], band[0], target_highlight_border_color, hover_border_thickness)


## Draw (inner, outer) radii for a wedge ring by display name. Returns ZERO for an unknown ring.
## Shared by the hotspot indicator; reads the wedge's draw bounds so the indicator tracks resizes.
func _ring_norms(wedge_idx: int, ring_name: String) -> Vector2:
	var band: Array = _band_draw_by_name(wedge_idx, ring_name)
	if band[1] <= 0.0:
		return Vector2.ZERO
	return Vector2(band[0], band[1])


## Draw a persistent, high-contrast indicator on every hotspot ring with its bonus value
## baked in (e.g. "+3"). Drawn on top of segment fills and numbers so the hot ring stays
## legible through recolor and boss overlay. This is the code-drawn baseline; the smoky
## value-in-the-smoke shader (an in-editor ShaderMaterial pass) layers over it later.
func _draw_hotspot_indicators(font: Font) -> void:
	for key: Variant in hotspot_rings:
		var bonus: int = hotspot_rings[key]
		if bonus <= 0:
			continue
		var parts: PackedStringArray = String(key).split(":")
		if parts.size() != 2:
			continue
		var wedge_idx: int = int(parts[0])
		if wedge_idx < 0 or wedge_idx >= 20:
			continue
		var norms: Vector2 = _ring_norms(wedge_idx, parts[1])
		if norms == Vector2.ZERO:
			continue

		var start_deg: float = _wedge_start_deg(wedge_idx)
		var end_deg: float = _wedge_end_deg(wedge_idx)

		# Persistent outline so the hot ring's location reads at a glance.
		_draw_segment_border(start_deg, end_deg, norms.y, norms.x, hotspot_indicator_color, hotspot_indicator_thickness)

		# Value baked at the ring's mid-radius / mid-angle (weighted wedge center).
		var mid_norm: float = (norms.x + norms.y) * 0.5
		var mid_rad: float = deg_to_rad(_wedge_center_deg(wedge_idx))
		var direction: Vector2 = Vector2(sin(mid_rad), -cos(mid_rad))
		var center: Vector2 = direction * board_radius * mid_norm
		var label: String = "+%d" % bonus
		var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, hotspot_value_font_size)
		var text_pos: Vector2 = center - Vector2(text_size.x * 0.5, -text_size.y * 0.25)
		# Dark backing pass for contrast over any ring color, then the warm value on top.
		draw_string(font, text_pos + Vector2(1.0, 1.0), label, HORIZONTAL_ALIGNMENT_CENTER, -1, hotspot_value_font_size, Color(0.0, 0.0, 0.0, 0.8))
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, hotspot_value_font_size, hotspot_indicator_color)


## Rebuild the optional smoke-shader layer from the current hotspot_rings. Clears and repopulates
## one additive Polygon2D (the ring-slice smoke, shaders/hotspot.gdshader) plus a "+N" value label
## per hot ring. No-op (layer left empty) when the dev toggle is off, so _draw_hotspot_indicators'
## code-drawn outline takes over. Called on hotspot_rings change, toggle change, and _ready.
func _rebuild_hotspot_shader_layer() -> void:
	if _hotspot_shader_layer == null:
		return
	for child: Node in _hotspot_shader_layer.get_children():
		child.queue_free()
	if not use_hotspot_shader or hotspot_rings.is_empty():
		return

	for key: Variant in hotspot_rings:
		var bonus: int = hotspot_rings[key]
		if bonus <= 0:
			continue
		var parts: PackedStringArray = String(key).split(":")
		if parts.size() != 2:
			continue
		var wedge_idx: int = int(parts[0])
		if wedge_idx < 0 or wedge_idx >= 20:
			continue
		var ring_name: String = parts[1]
		var norms: Vector2 = _ring_norms(wedge_idx, ring_name)
		if norms == Vector2.ZERO:
			continue

		var start_deg: float = _wedge_start_deg(wedge_idx)
		var end_deg: float = _wedge_end_deg(wedge_idx)

		# Smoke polygon shaped exactly to the ring slice (same geometry as the segment fills).
		var poly: Polygon2D = Polygon2D.new()
		poly.polygon = _build_segment_points(start_deg, end_deg, norms.y, norms.x)
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = _HOTSPOT_SHADER
		var ring_key: String = ring_name.to_lower().replace(" ", "_")
		var seg_color: ScoringEnums.SegmentColor = _lookup_segment_color(wedge_idx, ring_key)
		var render_col: Color = _segment_color_to_render(seg_color)
		# Multi-tone smoke in the wedge's OWN color family: a darker and a lighter shade the shader
		# mixes between, so green rings show several greens, red several reds, black greys-into-black,
		# white shades of cream. Normal alpha blend (in the shader) keeps it legible on every wedge.
		mat.set_shader_parameter("color_a", render_col.darkened(0.40))
		mat.set_shader_parameter("color_b", render_col.lightened(0.50))
		# Higher-tier hotspots read denser/more opaque (+1 -> 0.66, +2 -> 0.78, +3 -> 0.90).
		mat.set_shader_parameter("opacity", minf(0.54 + 0.12 * float(bonus), 0.92))
		poly.material = mat
		_hotspot_shader_layer.add_child(poly)

		# "+N" value label, kept above the smoke (z_index) so the number stays legible.
		var mid_norm: float = (norms.x + norms.y) * 0.5
		var mid_rad: float = deg_to_rad(_wedge_center_deg(wedge_idx))
		var direction: Vector2 = Vector2(sin(mid_rad), -cos(mid_rad))
		var center: Vector2 = direction * board_radius * mid_norm
		var lbl: Label = Label.new()
		lbl.text = "+%d" % bonus
		lbl.add_theme_font_size_override("font_size", hotspot_value_font_size)
		lbl.add_theme_color_override("font_color", hotspot_indicator_color)
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.size = Vector2(48.0, 36.0)
		lbl.position = center - lbl.size * 0.5
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.z_index = 1
		# Smokify the number so it drifts instead of looking pasted on.
		lbl.material = _hotspot_label_material
		_hotspot_shader_layer.add_child(lbl)


## Draw a border outline around a wedge segment.
## Used for hover highlighting and checkout pulse effects.
func _draw_segment_border(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float, color: Color, thickness: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_r: float = board_radius * outer_norm
	var inner_r: float = board_radius * inner_norm

	# Outer arc from start to end
	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * outer_r)

	# Inner arc from end back to start
	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * inner_r)

	# Close the polygon outline
	points.append(points[0])
	draw_polyline(points, color, thickness)


## Generate circle points for a border at a given normalized radius.
func _make_circle_points(normalized_radius: float) -> PackedVector2Array:
	var r: float = board_radius * normalized_radius
	var points: PackedVector2Array = PackedVector2Array()
	var num_points: int = 64
	for i: int in range(num_points + 1):
		var angle: float = TAU * float(i) / float(num_points)
		points.append(Vector2(cos(angle), sin(angle)) * r)
	return points


## Set which segments should pulse as valid checkouts.
func set_checkout_segments(segments: Array[Dictionary]) -> void:
	_checkout_segments = segments
	_checkout_pulse_active = segments.size() > 0
	if _checkout_pulse_active:
		set_process(true)
	queue_redraw()


## Clear all checkout highlights.
func clear_checkout_segments() -> void:
	_checkout_segments.clear()
	_checkout_pulse_active = false
	queue_redraw()


## Set which segments should be illuminated for the selected checkout path step.
## is_finish: true if this step IS the checkout (1-dart path) — draws gold instead of blue.
func set_illumination_segments(segments: Array[Dictionary], is_finish: bool = false) -> void:
	_illumination_segments = segments
	_illumination_active = segments.size() > 0
	_illumination_is_finish = is_finish
	if _illumination_active:
		set_process(true)
	queue_redraw()


## Clear path illumination highlights.
func clear_illumination() -> void:
	_illumination_segments.clear()
	_illumination_active = false
	queue_redraw()


## Enable/disable picker mode for interactive wedge selection.
func set_picker_mode(enabled: bool) -> void:
	picker_mode = enabled
	_picker_hover_wedge = -1
	_picker_selected_wedges.clear()
	if enabled:
		hover_enabled = false
	queue_redraw()


## Get the wedge index at a global position, or -1 if off the wedge area (draw geometry).
func get_wedge_at_position(global_pos: Vector2) -> int:
	var relative: Vector2 = global_pos - global_position
	var normalized: float = relative.length() / board_radius
	if normalized > RING_DOUBLE_OUTER or normalized < _single_bull_draw():
		return -1
	return _get_wedge_index_draw(relative)


## Classify a board-relative position into {wedge_index, ring_key} for the segment picker, using
## the DRAW geometry. Returns {} when off the wedge band area (inside the bull or off-board).
func _segment_at_draw(relative: Vector2) -> Dictionary:
	var nd: float = relative.length() / board_radius
	if nd <= _single_bull_draw() or nd > RING_DOUBLE_OUTER:
		return {}
	var w: int = _get_wedge_index_draw(relative)
	var ring_key: String = "double"
	if nd <= _band_draw(w, "inner_single")[1]:
		ring_key = "inner_single"
	elif nd <= _band_draw(w, "triple")[1]:
		ring_key = "triple"
	elif nd <= _effective_double_inner_w(w):
		ring_key = "outer_single"
	return {"wedge_index": w, "ring_key": ring_key}


## Update picker hover and return the hovered wedge index.
func update_picker_hover(global_pos: Vector2) -> int:
	var wedge: int = get_wedge_at_position(global_pos)
	if wedge != _picker_hover_wedge:
		_picker_hover_wedge = wedge
		queue_redraw()
	return wedge


## Set which wedges are visually selected in picker mode.
func set_picker_selected(wedges: Array[int]) -> void:
	_picker_selected_wedges = wedges
	queue_redraw()


## Enable/disable segment picker mode for interactive ring+wedge selection.
func set_segment_picker_mode(enabled: bool) -> void:
	segment_picker_mode = enabled
	_segment_picker_hover_wedge = -1
	_segment_picker_hover_ring = ""
	if enabled:
		hover_enabled = false
	queue_redraw()


## Update segment picker hover and return {wedge_index, ring_key} or empty dict.
func update_segment_picker_hover(global_pos: Vector2) -> Dictionary:
	var relative: Vector2 = global_pos - global_position
	var seg: Dictionary = _segment_at_draw(relative)
	if seg.is_empty():
		if _segment_picker_hover_ring != "":
			_segment_picker_hover_wedge = -1
			_segment_picker_hover_ring = ""
			queue_redraw()
		return {}

	var wedge: int = seg["wedge_index"]
	var ring_key: String = seg["ring_key"]
	if wedge != _segment_picker_hover_wedge or ring_key != _segment_picker_hover_ring:
		_segment_picker_hover_wedge = wedge
		_segment_picker_hover_ring = ring_key
		queue_redraw()

	return seg


## Get the segment at a global position for segment picker click. Returns same format as hover.
func get_segment_at_position(global_pos: Vector2) -> Dictionary:
	return _segment_at_draw(global_pos - global_position)


## Draw picker highlights — selected wedges and hovered wedge.
func _draw_picker_highlights() -> void:
	for wedge_idx: int in _picker_selected_wedges:
		_draw_full_wedge_highlight(wedge_idx, picker_selected_color, picker_border_color)
	if _picker_hover_wedge >= 0 and _picker_hover_wedge not in _picker_selected_wedges:
		_draw_full_wedge_highlight(_picker_hover_wedge, picker_highlight_color, picker_border_color)


## Draw a highlight overlay covering all rings of a single wedge.
func _draw_full_wedge_highlight(wedge_idx: int, fill_color: Color, border_col: Color) -> void:
	var start_deg: float = _wedge_start_deg(wedge_idx)
	var end_deg: float = _wedge_end_deg(wedge_idx)
	_draw_segment(start_deg, end_deg, RING_DOUBLE_OUTER, _single_bull_draw(), fill_color)
	_draw_segment_border(start_deg, end_deg, RING_DOUBLE_OUTER, _single_bull_draw(), border_col, hover_border_thickness)


## Draw a highlight on the segment under the cursor in segment picker mode.
func _draw_segment_picker_highlight() -> void:
	var band: Array = _band_draw(_segment_picker_hover_wedge, _segment_picker_hover_ring)
	if band[1] <= 0.0:
		return
	var start_deg: float = _wedge_start_deg(_segment_picker_hover_wedge)
	var end_deg: float = _wedge_end_deg(_segment_picker_hover_wedge)
	_draw_segment(start_deg, end_deg, band[1], band[0], picker_highlight_color)
	_draw_segment_border(start_deg, end_deg, band[1], band[0], picker_border_color, hover_border_thickness)


## Map a per-ring dict key to the RING_BOUNDS display name.
static func _ring_key_to_display(ring_key: String) -> String:
	match ring_key:
		"inner_single":
			return "Inner Single"
		"triple":
			return "Triple"
		"outer_single":
			return "Outer Single"
		"double":
			return "Double"
	return ""


## Draw pulsing border outlines on all valid checkout segments.
func _draw_checkout_pulses() -> void:
	var t: float = sin(_checkout_pulse_time * checkout_pulse_speed)
	var alpha: float = lerpf(checkout_pulse_min_alpha, checkout_pulse_max_alpha, (t + 1.0) / 2.0)
	if _illumination_active and not _illumination_is_finish:
		alpha *= checkout_pulse_dimming
	var pulse_color: Color = Color(checkout_pulse_color, alpha)

	for segment: Dictionary in _checkout_segments:
		_draw_descriptor_border(segment, pulse_color, checkout_border_thickness)


## Draw pulsing border outlines for path illumination (selected checkout step equivalents).
func _draw_illumination_outlines() -> void:
	var base_color: Color = checkout_pulse_color if _illumination_is_finish else illumination_color
	var t: float = sin(_illumination_pulse_time * illumination_pulse_speed)
	var alpha: float = lerpf(illumination_pulse_min_alpha, illumination_pulse_max_alpha, (t + 1.0) / 2.0)
	var pulse_color: Color = Color(base_color, alpha)

	for segment: Dictionary in _illumination_segments:
		_draw_descriptor_border(segment, pulse_color, illumination_border_thickness)


## Draw a border outline for a segment DESCRIPTOR ({type, wedge_idx, ring_key}) using the draw
## geometry. Shared by the checkout pulse + path illumination passes. Segment types match the
## solver's _candidate_to_segment_descriptor output (double_bull / single_bull / wedge /
## triple_wedge / single_wedge).
func _draw_descriptor_border(segment: Dictionary, color: Color, thickness: float) -> void:
	var segment_type: String = segment["type"]
	if segment_type == "double_bull":
		draw_polyline(_make_circle_points(_double_bull_draw()), color, thickness)
		return
	if segment_type == "single_bull":
		draw_polyline(_make_circle_points(_single_bull_draw()), color, thickness)
		return
	var wedge_idx: int = segment["wedge_idx"]
	var ring_key: String = "double"
	if segment_type == "triple_wedge":
		ring_key = "triple"
	elif segment_type == "single_wedge":
		ring_key = segment.get("ring_key", "outer_single")
	var band: Array = _band_draw(wedge_idx, ring_key)
	if band[1] <= 0.0:
		return
	var start_deg: float = _wedge_start_deg(wedge_idx)
	var end_deg: float = _wedge_end_deg(wedge_idx)
	_draw_segment_border(start_deg, end_deg, band[1], band[0], color, thickness)


# ── Tutorial highlight API ──────────────────────────────────────────────────

## Set tutorial highlight segments. Each entry specifies a highlight type:
## {type: "all_wedges_ring", ring_name: "Triple"} — highlight that ring on every wedge.
## {type: "single_wedge_all", wedge_index: 0} — highlight every ring of a single wedge.
## {type: "single_segment", wedge_index: 0, ring_name: "Triple"} — highlight one segment.
## {type: "bullseye", which: "inner"|"outer"|"both"} — highlight bullseye region(s).
func set_tutorial_highlight(highlights: Array[Dictionary]) -> void:
	_tutorial_highlights = highlights
	_tutorial_highlight_active = highlights.size() > 0
	queue_redraw()


## Clear all tutorial highlights.
func clear_tutorial_highlight() -> void:
	_tutorial_highlights.clear()
	_tutorial_highlight_active = false
	queue_redraw()


## Draw all active tutorial highlights.
func _draw_tutorial_highlights() -> void:
	for spec: Dictionary in _tutorial_highlights:
		var highlight_type: String = spec.get("type", "")
		match highlight_type:
			"all_wedges_ring":
				var ring_name: String = spec.get("ring_name", "")
				for wedge_idx: int in range(20):
					var band: Array = _band_draw_by_name(wedge_idx, ring_name)
					if band[1] <= 0.0:
						continue
					var start_deg: float = _wedge_start_deg(wedge_idx)
					var end_deg: float = _wedge_end_deg(wedge_idx)
					_draw_segment(start_deg, end_deg, band[1], band[0], tutorial_highlight_color)
					_draw_segment_border(start_deg, end_deg, band[1], band[0], tutorial_highlight_border_color, tutorial_highlight_thickness)

			"single_wedge_all":
				var wedge_idx: int = spec.get("wedge_index", 0)
				_draw_full_wedge_highlight(wedge_idx, tutorial_highlight_color, tutorial_highlight_border_color)

			"single_segment":
				var wedge_idx: int = spec.get("wedge_index", 0)
				var ring_name: String = spec.get("ring_name", "")
				var band: Array = _band_draw_by_name(wedge_idx, ring_name)
				if band[1] > 0.0:
					var start_deg: float = _wedge_start_deg(wedge_idx)
					var end_deg: float = _wedge_end_deg(wedge_idx)
					_draw_segment(start_deg, end_deg, band[1], band[0], tutorial_highlight_color)
					_draw_segment_border(start_deg, end_deg, band[1], band[0], tutorial_highlight_border_color, tutorial_highlight_thickness)

			"bullseye":
				var which: String = spec.get("which", "both")
				if which == "inner" or which == "both":
					draw_circle(Vector2.ZERO, board_radius * _double_bull_draw(), tutorial_highlight_color)
					draw_polyline(_make_circle_points(_double_bull_draw()), tutorial_highlight_border_color, tutorial_highlight_thickness)
				if which == "outer" or which == "both":
					draw_circle(Vector2.ZERO, board_radius * _single_bull_draw(), tutorial_highlight_color)
					draw_polyline(_make_circle_points(_single_bull_draw()), tutorial_highlight_border_color, tutorial_highlight_thickness)


## Push exported shader values into the ShaderMaterial.
func _sync_shop_shader(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("board_radius", board_radius)
	mat.set_shader_parameter("speed", shop_swirl_speed)
	mat.set_shader_parameter("noise_scale", shop_noise_scale)
	mat.set_shader_parameter("distortion", shop_distortion)
	mat.set_shader_parameter("contrast", shop_contrast)
	mat.set_shader_parameter("glow_strength", shop_glow_strength)


## The five family icons the typed shop draws on its lit spots — the SAME art the map nodes use.
## Self-contained here (the dartboard doesn't know about families otherwise); keyed by the spot's
## "family" StringName. Trade families have no rarity, so the spot's colour + this icon carry the
## family read.
const _SHOP_FAMILY_ICONS: Dictionary = {
	&"scoring": preload("res://sprites/Icons/scoringItems.png"),
	&"streak": preload("res://sprites/Icons/streak.png"),
	&"accuracy": preload("res://sprites/Icons/accuracyIcon.png"),
	&"geometry": preload("res://sprites/Icons/geoItems.png"),
	&"brush": preload("res://sprites/Icons/brush.png"),
}


## Look up the exported rarity color for a shop spot.
func _get_shop_rarity_color(rarity: int) -> Color:
	match rarity:
		ScoringEnums.Rarity.UNCOMMON:
			return shop_color_uncommon
		ScoringEnums.Rarity.RARE:
			return shop_color_rare
		_:
			return shop_color_common


## The base fill colour for a typed shop spot: rarity families (scoring/streak/accuracy) read by
## rarity tier; trade families (geometry/brush) read by their fixed family tint (rarity-less).
func _shop_spot_color(spot: Dictionary) -> Color:
	var family: StringName = spot.get("family", &"")
	if family == &"geometry":
		return shop_color_geometry
	if family == &"brush":
		return shop_color_brush
	return _get_shop_rarity_color(spot.get("rarity", ScoringEnums.Rarity.COMMON))


## Draw the spot's family icon centered on its ring slice (the icon "on the spot"). Scaled to fit
## the band thickness so it stays inside thin rings. Reads DRAW geometry, so it tracks reflows.
func _draw_shop_icon(overlay: Node2D, spot: Dictionary, inner_norm: float, outer_norm: float) -> void:
	var family: StringName = spot.get("family", &"")
	var tex: Texture2D = _SHOP_FAMILY_ICONS.get(family, null)
	if tex == null:
		return
	var wedge_idx: int = spot["wedge_index"]
	var mid_norm: float = (inner_norm + outer_norm) * 0.5
	var mid_rad: float = deg_to_rad(_wedge_center_deg(wedge_idx))
	var direction: Vector2 = Vector2(sin(mid_rad), -cos(mid_rad))
	var center: Vector2 = direction * board_radius * mid_norm
	# Cap the icon to the band's radial thickness so it never overflows a thin single/triple.
	var band_px: float = board_radius * (outer_norm - inner_norm)
	var sz: float = minf(shop_icon_size, maxf(band_px * 0.9, 8.0))
	overlay.draw_texture_rect(tex, Rect2(center - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)


## Set lit spots for the shop. Each entry: {wedge_index, ring_name, rarity, active}.
func set_shop_spots(spots: Array[Dictionary]) -> void:
	_shop_spots = spots
	_shop_active = spots.size() > 0
	# Re-sync shader params in case exports were tweaked in the inspector
	if _shop_overlay.material is ShaderMaterial:
		_sync_shop_shader(_shop_overlay.material as ShaderMaterial)
	_shop_overlay.queue_redraw()
	queue_redraw()


## Clear all shop lit spots.
func clear_shop_spots() -> void:
	_shop_spots.clear()
	_shop_active = false
	_shop_dissolve_active = false
	_shop_dissolve_spot = {}
	_shop_overlay.queue_redraw()
	_shop_dissolve_overlay.queue_redraw()
	queue_redraw()


## Check if a hit position lands on an active shop spot.
## Returns the spot index if hit, or -1 if no active spot was hit.
func check_shop_hit(global_hit_position: Vector2) -> int:
	var result: Dictionary = calculate_score(global_hit_position)
	var ring_name: String = result.get("ring_name", "")
	var wedge_index: int = result.get("wedge_index", -1)

	for i: int in range(_shop_spots.size()):
		var spot: Dictionary = _shop_spots[i]
		if not spot.get("active", false):
			continue
		if spot["wedge_index"] == wedge_index and spot["ring_name"] == ring_name:
			return i

	return -1


## Deactivate a shop spot after it's been hit — triggers dissolve animation.
func deactivate_shop_spot(index: int, hit_position: Vector2 = Vector2.ZERO) -> void:
	if index < 0 or index >= _shop_spots.size():
		return
	var spot: Dictionary = _shop_spots[index]
	_shop_spots[index]["active"] = false
	_shop_overlay.queue_redraw()

	# Start dissolve animation on the hit spot
	_shop_dissolve_spot = spot.duplicate()
	var relative: Vector2 = hit_position - global_position if hit_position != Vector2.ZERO else Vector2.ZERO
	_shop_dissolve_center = relative / board_radius
	_shop_dissolve_time = 0.0
	_shop_dissolve_active = true

	var d_mat: ShaderMaterial = _shop_dissolve_overlay.material as ShaderMaterial
	_sync_shop_shader(d_mat)
	d_mat.set_shader_parameter("dissolve_center", _shop_dissolve_center)
	d_mat.set_shader_parameter("dissolve_progress", 0.0)
	d_mat.set_shader_parameter("dissolve_reach", shockwave_reach)
	_shop_dissolve_overlay.queue_redraw()
	set_process(true)


## Draw shop spot segments on the overlay child (shader applies to this geometry).
func _draw_shop_overlay() -> void:
	for spot: Dictionary in _shop_spots:
		if not spot.get("active", false):
			continue

		# Typed shop (Phase 03): fill colour reads by family — rarity tier for scoring/streak/
		# accuracy, fixed family tint for the rarity-less geometry/brush trades.
		var base_color: Color = _shop_spot_color(spot)
		var fill_color: Color = Color(base_color.r, base_color.g, base_color.b, shop_fill_alpha)
		var border_color: Color = Color(base_color.r, base_color.g, base_color.b, shop_border_alpha)

		var ring_name: String = spot["ring_name"]
		var wedge_idx: int = spot["wedge_index"]

		var band: Array = _band_draw_by_name(wedge_idx, ring_name)
		if band[1] <= 0.0:
			continue
		var inner_norm: float = band[0]
		var outer_norm: float = band[1]
		var start_deg: float = _wedge_start_deg(wedge_idx)
		var end_deg: float = _wedge_end_deg(wedge_idx)

		# Build segment polygon and draw on the overlay
		var points: PackedVector2Array = _build_segment_points(start_deg, end_deg, outer_norm, inner_norm)
		_shop_overlay.draw_colored_polygon(points, fill_color)

		# Border
		var border_points: PackedVector2Array = _build_segment_border_points(start_deg, end_deg, outer_norm, inner_norm)
		_shop_overlay.draw_polyline(border_points, border_color, shop_border_thickness)

		# Family icon "melted" onto the spot (re-derived here so it tracks reflows, §4a).
		_draw_shop_icon(_shop_overlay, spot, inner_norm, outer_norm)


## Draw the dissolving shop spot on its own overlay (separate shader with dissolve uniforms).
func _draw_shop_dissolve_overlay() -> void:
	if not _shop_dissolve_active or _shop_dissolve_spot.is_empty():
		return

	var base_color: Color = _shop_spot_color(_shop_dissolve_spot)
	var fill_color: Color = Color(base_color.r, base_color.g, base_color.b, shop_fill_alpha)
	var border_color: Color = Color(base_color.r, base_color.g, base_color.b, shop_border_alpha)

	var ring_name: String = _shop_dissolve_spot["ring_name"]
	var wedge_idx: int = _shop_dissolve_spot["wedge_index"]

	var band: Array = _band_draw_by_name(wedge_idx, ring_name)
	if band[1] <= 0.0:
		return
	var inner_norm: float = band[0]
	var outer_norm: float = band[1]
	var start_deg: float = _wedge_start_deg(wedge_idx)
	var end_deg: float = _wedge_end_deg(wedge_idx)

	var points: PackedVector2Array = _build_segment_points(start_deg, end_deg, outer_norm, inner_norm)
	_shop_dissolve_overlay.draw_colored_polygon(points, fill_color)

	var border_points: PackedVector2Array = _build_segment_border_points(start_deg, end_deg, outer_norm, inner_norm)
	_shop_dissolve_overlay.draw_polyline(border_points, border_color, shop_border_thickness)


## Set the wedge indices that should be drawn as voids by the boss overlay.
## Animates the transition from old voids to new voids.
func set_boss_void_wedges(wedges: Array[int]) -> void:
	_boss_void_wedges_prev = _boss_void_wedges.duplicate()
	_boss_void_wedges = wedges
	boss_reduced_wedges = wedges.duplicate()
	_void_transition_t = 0.0
	var tween: Tween = create_tween()
	tween.tween_method(_set_void_transition, 0.0, 1.0, void_transition_duration)

func _set_void_transition(t: float) -> void:
	_void_transition_t = t
	_boss_overlay.queue_redraw()
	queue_redraw()


## Set the individually-voided drifted rings (Void boss medium/hard). Each entry is
## a Dictionary {"wedge": int, "ring": String} where ring is a calculate_score ring
## name. Does not start its own tween — call this BEFORE set_boss_void_wedges so the
## shared _void_transition_t fades the whole-wedge voids and drifted rings together.
func set_boss_void_rings(rings: Array) -> void:
	_boss_void_rings_prev = _boss_void_rings.duplicate()
	_boss_void_rings = {}
	for entry: Dictionary in rings:
		_boss_void_rings["%d:%s" % [entry["wedge"], entry["ring"]]] = true
	_boss_overlay.queue_redraw()


## Drive a full Void turn with the two-phase reveal. Phase 1 fades in every freshly-
## chosen whole wedge (drift sources still shown whole, for continuity with easy);
## phase 2 then slides the drifted rings from source → neighbor. `initial_wedges` are
## the wedges shown whole in phase 1; `final_whole`/`final_rings` are the steady state
## after drift; `drift_moves` are {"from","to","ring"} entries. With no drift this is
## just the phase-1 fade. Supersedes the per-set set_boss_void_* path for Void.
func play_void_turn(initial_wedges: Array[int], final_whole: Array[int], final_rings: Array[Dictionary], drift_moves: Array[Dictionary]) -> void:
	if _void_fill_tween != null and _void_fill_tween.is_valid():
		_void_fill_tween.kill()
	if _void_drift_tween != null and _void_drift_tween.is_valid():
		_void_drift_tween.kill()

	# Cross-turn fade-out of the previous turn's voids.
	_boss_void_wedges_prev = _boss_void_wedges.duplicate()
	_boss_void_rings_prev = _boss_void_rings.duplicate()

	# Stash the steady state for phase 2.
	_void_final_whole = final_whole.duplicate()
	_void_final_rings = {}
	for entry: Dictionary in final_rings:
		_void_final_rings["%d:%s" % [entry["wedge"], entry["ring"]]] = true
	_void_pending_moves = drift_moves.duplicate()

	# Phase 1: show all initial whole wedges fading in; no separated rings yet.
	_boss_void_wedges = initial_wedges.duplicate()
	boss_reduced_wedges = initial_wedges.duplicate()
	_boss_void_rings = {}
	_drift_moves.clear()
	_drift_t = 1.0
	_void_transition_t = 0.0

	_void_fill_tween = create_tween()
	_void_fill_tween.tween_method(_set_void_transition, 0.0, 1.0, void_fill_duration)
	if not _void_pending_moves.is_empty():
		_void_fill_tween.tween_callback(_start_void_drift)


## Phase 2: drift sources drop to partial; their migrating ring slides to the neighbor.
func _start_void_drift() -> void:
	_boss_void_wedges = _void_final_whole.duplicate()
	boss_reduced_wedges = _void_final_whole.duplicate()
	# Static rings shown during the slide = final rings minus the arriving (to,ring)
	# entries, which are represented by the in-flight migrating rings until t = 1.
	_boss_void_rings = _void_final_rings.duplicate()
	for move: Dictionary in _void_pending_moves:
		_boss_void_rings.erase("%d:%s" % [move["to"], move["ring"]])
	_boss_void_rings_prev = {}
	_drift_moves = _void_pending_moves.duplicate()
	_drift_t = 0.0
	_void_transition_t = 1.0

	_void_drift_tween = create_tween()
	_void_drift_tween.tween_method(_set_drift_t, 0.0, 1.0, void_drift_duration)
	_void_drift_tween.tween_callback(_finish_void_drift)


func _set_drift_t(t: float) -> void:
	_drift_t = t
	_boss_overlay.queue_redraw()
	queue_redraw()


## Migration done: the arrived rings join the steady set; drop the in-flight overlay.
func _finish_void_drift() -> void:
	_boss_void_rings = _void_final_rings.duplicate()
	_drift_moves.clear()
	_drift_t = 1.0
	_boss_overlay.queue_redraw()
	queue_redraw()


## Clear all boss visual overlays and reset boss-specific board modifications.
func clear_boss_overlays() -> void:
	if _void_fill_tween != null and _void_fill_tween.is_valid():
		_void_fill_tween.kill()
	if _void_drift_tween != null and _void_drift_tween.is_valid():
		_void_drift_tween.kill()
	_boss_void_wedges.clear()
	_boss_void_wedges_prev.clear()
	_boss_void_rings.clear()
	_boss_void_rings_prev.clear()
	_drift_moves.clear()
	_drift_t = 1.0
	_void_final_whole.clear()
	_void_final_rings.clear()
	_void_pending_moves.clear()
	if _prism_burst_tween != null and _prism_burst_tween.is_valid():
		_prism_burst_tween.kill()
	_prism_burst_active = false
	_prism_burst_prev.clear()
	_prism_burst_delay.clear()
	_void_transition_t = 1.0
	_color_transition_t = 1.0
	_prev_wedge_colors.clear()
	boss_reduced_wedges.clear()
	_boss_recession_wedges.clear()
	_boss_overlay.queue_redraw()
	_recession_overlay.queue_redraw()
	board_rotation_offset = 0.0
	double_ring_width_scale = 1.0


## Duration of the rotation animation in seconds.
@export var rotation_anim_duration: float = 0.4

## Animate the board rotation to a new offset. Used by Rotation boss.
func set_board_rotation(offset_deg: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_method(_apply_rotation, board_rotation_offset, offset_deg, rotation_anim_duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


func _apply_rotation(deg: float) -> void:
	board_rotation_offset = deg
	queue_redraw()
	_boss_overlay.queue_redraw()


## Animate a color transition from current colors to new colors (Prism boss).
## Call this BEFORE updating effective_wedge_colors on the dartboard.
func animate_color_transition() -> void:
	_prev_wedge_colors.clear()
	for c: Dictionary in effective_wedge_colors:
		_prev_wedge_colors.append(c.duplicate())
	_color_transition_t = 0.0
	var tween: Tween = create_tween()
	tween.tween_method(func(t: float) -> void:
		_color_transition_t = t
		queue_redraw()
	, 0.0, 1.0, color_transition_duration)


## Play a Prism recolor burst. `segments` is an array of
## {"wedge": int, "ring": String (ring_key), "prev_color": int (SegmentColor),
## "dist": int (rings away from the hit ring)}. effective_wedge_colors must already
## hold the new colors; this animates the reveal radiating outward by `dist`.
func play_prism_recolor(segments: Array[Dictionary]) -> void:
	if _prism_burst_tween != null and _prism_burst_tween.is_valid():
		_prism_burst_tween.kill()
	_prism_burst_prev.clear()
	_prism_burst_delay.clear()
	var max_dist: int = 0
	for s: Dictionary in segments:
		max_dist = maxi(max_dist, int(s["dist"]))
	for s: Dictionary in segments:
		var key: String = "%d:%s" % [s["wedge"], s["ring"]]
		_prism_burst_prev[key] = int(s["prev_color"])
		var frac: float = (float(s["dist"]) / float(max_dist)) if max_dist > 0 else 0.0
		_prism_burst_delay[key] = frac * (1.0 - prism_recolor_fade)
	_prism_burst_active = true
	_prism_burst_t = 0.0
	_prism_burst_tween = create_tween()
	_prism_burst_tween.tween_method(_set_prism_burst_t, 0.0, 1.0, prism_recolor_duration)
	_prism_burst_tween.tween_callback(func() -> void:
		_prism_burst_active = false
		queue_redraw())


func _set_prism_burst_t(t: float) -> void:
	_prism_burst_t = t
	queue_redraw()


## Blend a ring's target colour from its pre-recolor colour based on the burst clock,
## so closer rings reveal first. Returns target_color unchanged if not in the burst.
func _apply_prism_burst(wedge_idx: int, ring_key: String, target_color: Color) -> Color:
	var key: String = "%d:%s" % [wedge_idx, ring_key]
	if not _prism_burst_prev.has(key):
		return target_color
	var delay: float = float(_prism_burst_delay.get(key, 0.0))
	var local_t: float = clampf((_prism_burst_t - delay) / maxf(prism_recolor_fade, 0.001), 0.0, 1.0)
	var prev_render: Color = _segment_color_to_render(_prism_burst_prev[key])
	return prev_render.lerp(target_color, local_t)


## Set the double ring width scale with a smooth tween. Used by Narrow Double Ring boss.
func set_double_ring_scale(scale: float, animate: bool = true) -> void:
	if not animate or is_equal_approx(double_ring_width_scale, scale):
		double_ring_width_scale = scale
		queue_redraw()
		return
	var tw: Tween = create_tween()
	tw.tween_method(func(val: float) -> void:
		double_ring_width_scale = val
		queue_redraw()
	, double_ring_width_scale, scale, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


## Push the active geometry rules to the surround studs (one reminder per rule).
func set_geometry_studs(rules: Array[Dictionary]) -> void:
	if _board_studs != null:
		_board_studs.set_rules(rules)


## Set the Parity Out checkout restriction for board dimming (§9b). Visual only; -1 = none.
func set_checkout_parity(parity: int) -> void:
	if checkout_parity == parity:
		return
	checkout_parity = parity
	queue_redraw()


## True if `wedge_idx`'s double/triple is a DEAD finish under the live Parity Out rule (wrong
## parity), so _draw desaturates it. False when no rule is active or the wedge matches.
func _is_dead_parity_wedge(wedge_idx: int) -> bool:
	if checkout_parity == -1:
		return false
	if wedge_idx < 0 or wedge_idx >= effective_wedge_values.size():
		return false
	var face_even: bool = (effective_wedge_values[wedge_idx] % 2) == 0
	var want_even: bool = checkout_parity == 0
	return face_even != want_even


## Desaturate a finish-ring color toward grey to mark a dead-parity (un-outable) wedge.
func _desaturate_dead(color: Color) -> Color:
	var grey: float = color.get_luminance()
	return color.lerp(Color(grey, grey, grey, color.a), dead_parity_desaturation)


## Seed the geometry substrate (both settled + draw copies) to the canonical board. Called in
## _ready so a dartboard nobody pushes geometry to (mini-boards, fresh boot) renders standard.
func _seed_default_geometry() -> void:
	var bounds: Array[Dictionary] = []
	var weights: Array[float] = []
	for _i: int in range(20):
		weights.append(1.0)
		bounds.append({
			"inner_single": [RING_SINGLE_BULL_OUTER, RING_INNER_SINGLE_OUTER],
			"triple": [RING_INNER_SINGLE_OUTER, RING_TRIPLE_OUTER],
			"outer_single": [RING_TRIPLE_OUTER, RING_OUTER_SINGLE_OUTER],
			"double": [RING_OUTER_SINGLE_OUTER, RING_DOUBLE_OUTER],
		})
	var bull: Dictionary = {"single_bull": RING_SINGLE_BULL_OUTER, "double_bull": RING_DOUBLE_BULL_OUTER}
	_geo_weights = weights
	_geo_bounds = bounds
	_geo_bull = bull
	_geo_weights_draw = weights.duplicate()
	_geo_bounds_draw = _dup_bounds(bounds)
	_geo_bull_draw = bull.duplicate()
	_wedge_bounds_deg = _compute_wedge_bounds_deg(_geo_weights)
	_wedge_bounds_deg_draw = _wedge_bounds_deg.duplicate()


## Deep-duplicate a per-wedge bounds array (each ring band is its own [inner, outer] array).
func _dup_bounds(src: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in src:
		var d: Dictionary = {}
		for k: String in entry:
			d[k] = [float(entry[k][0]), float(entry[k][1])]
		out.append(d)
	return out


## Receive new board geometry from the manager (via main._sync_board_state). Updates the SETTLED
## copy immediately (hit detection reads it), and re-flows the DRAW copy toward it — animated when
## `animate` and the change is real, snapped otherwise (run/leg init).
func set_geometry(weights: Array[float], bounds: Array[Dictionary], bull: Dictionary, animate: bool = true) -> void:
	if weights.size() != 20 or bounds.size() != 20:
		return
	# Drive-by churn guard: _sync_board_state pushes geometry on every sync (boss turns, toggles,
	# etc.), almost always unchanged. Skip the kill/create-Tween + redraw when the incoming
	# settled geometry already matches the current settled target AND nothing is mid-reflow.
	if not _geometry_changed(weights, bounds, bull) and (_reflow_tween == null or not _reflow_tween.is_valid()):
		if debug_geometry_log:
			print("[GEO] dartboard.set_geometry SKIP (churn guard: incoming bounds == current settled)")
		return
	if debug_geometry_log:
		# Sample a couple of double-band widths so a stale overwrite is visible in the call sequence.
		var w0: float = float(bounds[0]["double"][1]) - float(bounds[0]["double"][0]) if bounds[0].has("double") else -1.0
		print("[GEO] dartboard.set_geometry APPLY (animate=%s, w0 double=%.4f)" % [str(animate), w0])
	_geo_weights = weights.duplicate()
	_geo_bounds = _dup_bounds(bounds)
	_geo_bull = bull.duplicate()
	_wedge_bounds_deg = _compute_wedge_bounds_deg(_geo_weights)

	if _reflow_tween != null and _reflow_tween.is_valid():
		_reflow_tween.kill()

	if not animate or _geo_bounds_draw.size() != 20:
		_geo_weights_draw = _geo_weights.duplicate()
		_geo_bounds_draw = _dup_bounds(_geo_bounds)
		_geo_bull_draw = _geo_bull.duplicate()
		_wedge_bounds_deg_draw = _wedge_bounds_deg.duplicate()
		queue_redraw()
		return

	# Snapshot the current draw state as the tween's start, then lerp toward the settled target.
	_reflow_start_weights = _geo_weights_draw.duplicate()
	_reflow_start_bounds = _dup_bounds(_geo_bounds_draw)
	_reflow_start_bull = _geo_bull_draw.duplicate()
	_reflow_tween = create_tween()
	_reflow_tween.tween_method(_apply_reflow, 0.0, 1.0, geometry_reflow_duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


## The geometry re-flow tween if one is currently animating, else null. Lets a caller (the
## geometry-event beat in main) await the board reshape before moving on. Returns null when the
## last set_geometry produced no visible change (the churn guard skipped the tween) so the caller
## never strands itself awaiting a finish that won't come.
func get_active_reflow_tween() -> Tween:
	if _reflow_tween != null and _reflow_tween.is_valid() and _reflow_tween.is_running():
		return _reflow_tween
	return null


## Lerp the draw geometry from the start snapshot toward the settled target by t∈[0,1].
func _apply_reflow(t: float) -> void:
	if _reflow_start_weights.size() != 20 or _geo_weights.size() != 20:
		return
	var w: Array[float] = []
	for i: int in range(20):
		w.append(lerpf(_reflow_start_weights[i], _geo_weights[i], t))
	_geo_weights_draw = w

	var b: Array[Dictionary] = []
	for i: int in range(20):
		var d: Dictionary = {}
		var start_d: Dictionary = _reflow_start_bounds[i]
		var tgt_d: Dictionary = _geo_bounds[i]
		for k: String in tgt_d:
			var s0: float = float(start_d[k][0]) if start_d.has(k) else float(tgt_d[k][0])
			var s1: float = float(start_d[k][1]) if start_d.has(k) else float(tgt_d[k][1])
			d[k] = [lerpf(s0, float(tgt_d[k][0]), t), lerpf(s1, float(tgt_d[k][1]), t)]
		b.append(d)
	_geo_bounds_draw = b

	_geo_bull_draw = {
		"single_bull": lerpf(float(_reflow_start_bull.get("single_bull", RING_SINGLE_BULL_OUTER)), float(_geo_bull.get("single_bull", RING_SINGLE_BULL_OUTER)), t),
		"double_bull": lerpf(float(_reflow_start_bull.get("double_bull", RING_DOUBLE_BULL_OUTER)), float(_geo_bull.get("double_bull", RING_DOUBLE_BULL_OUTER)), t),
	}
	_wedge_bounds_deg_draw = _compute_wedge_bounds_deg(_geo_weights_draw)
	queue_redraw()
	if _boss_overlay != null:
		_boss_overlay.queue_redraw()
	# §4a live geometry tracking (typed-shop spec): every REGION-attached visual is a function of
	# the DRAW geometry, so re-derive it on each reflow tick instead of caching build-time polygons.
	# Without this the hotspot smoke / shop spots stay at their pre-resize size during a reflow
	# (Prism recolor mid-leg, geo item mid-shop) and visibly desync from the resized ring. ~20 polys
	# per tick is cheap. Hotspot smoke is real Polygon2D children → rebuild them; the shop overlays
	# rebuild their polygons in their _draw callbacks, so a queue_redraw suffices.
	if use_hotspot_shader and not hotspot_rings.is_empty():
		_rebuild_hotspot_shader_layer()
	if _shop_overlay != null:
		_shop_overlay.queue_redraw()
	if _shop_dissolve_overlay != null:
		_shop_dissolve_overlay.queue_redraw()


## Whether incoming geometry differs from the current SETTLED target (beyond float noise). Used
## to skip needless reflow tweens when _sync_board_state pushes unchanged geometry.
func _geometry_changed(weights: Array[float], bounds: Array[Dictionary], bull: Dictionary) -> bool:
	if _geo_weights.size() != 20 or _geo_bounds.size() != 20:
		return true
	if not is_equal_approx(float(bull.get("single_bull", RING_SINGLE_BULL_OUTER)), float(_geo_bull.get("single_bull", RING_SINGLE_BULL_OUTER))):
		return true
	if not is_equal_approx(float(bull.get("double_bull", RING_DOUBLE_BULL_OUTER)), float(_geo_bull.get("double_bull", RING_DOUBLE_BULL_OUTER))):
		return true
	for i: int in range(20):
		if not is_equal_approx(weights[i], _geo_weights[i]):
			return true
		var nb: Dictionary = bounds[i]
		var cb: Dictionary = _geo_bounds[i]
		for rk: String in nb:
			if not cb.has(rk):
				return true
			if not is_equal_approx(float(nb[rk][0]), float(cb[rk][0])) or not is_equal_approx(float(nb[rk][1]), float(cb[rk][1])):
				return true
	return false


## Cumulative wedge boundary degrees (size 21, pre-rotation) from per-wedge angular weights.
## Each wedge's width = weight × 18° after renormalizing the weights to a 360° total; the walk is
## anchored so wedge 0 (the 20) is centered at the top (its start = −width₀/2), generalizing the
## old uniform WEDGE_OFFSET_DEG of −9°.
func _compute_wedge_bounds_deg(weights: Array[float]) -> Array[float]:
	var widths: Array[float] = []
	var total: float = 0.0
	for i: int in range(20):
		var wd: float = weights[i] * WEDGE_ANGLE_DEG
		widths.append(wd)
		total += wd
	if total > 0.0:
		for i: int in range(20):
			widths[i] = widths[i] * 360.0 / total
	var bounds: Array[float] = []
	bounds.resize(21)
	bounds[0] = -widths[0] / 2.0
	for i: int in range(20):
		bounds[i + 1] = bounds[i] + widths[i]
	return bounds


## Compute the effective inner boundary of the double ring for a wedge (draw geometry), applying
## the dartboard-side double_ring_width_scale handicap AFTER the manager's bounds.
func _effective_double_inner_w(wedge_idx: int) -> float:
	var b: Array = _band_raw_draw(wedge_idx, "double")
	return RING_DOUBLE_OUTER - (RING_DOUBLE_OUTER - b[0]) * double_ring_width_scale


## Raw [inner, outer] band for a wedge from the DRAW bounds (no scale handicap). Falls back to
## base constants if geometry isn't seeded yet.
func _band_raw_draw(wedge_idx: int, ring_key: String) -> Array:
	if wedge_idx >= 0 and wedge_idx < _geo_bounds_draw.size() and _geo_bounds_draw[wedge_idx].has(ring_key):
		var e: Array = _geo_bounds_draw[wedge_idx][ring_key]
		return [float(e[0]), float(e[1])]
	return _base_band(ring_key)


## Raw [inner, outer] band for a wedge from the SETTLED bounds (no scale handicap), for hit
## detection. Falls back to base constants if geometry isn't seeded yet.
func _band_raw_settled(wedge_idx: int, ring_key: String) -> Array:
	if wedge_idx >= 0 and wedge_idx < _geo_bounds.size() and _geo_bounds[wedge_idx].has(ring_key):
		var e: Array = _geo_bounds[wedge_idx][ring_key]
		return [float(e[0]), float(e[1])]
	return _base_band(ring_key)


func _base_band(ring_key: String) -> Array:
	match ring_key:
		"inner_single":
			return [RING_SINGLE_BULL_OUTER, RING_INNER_SINGLE_OUTER]
		"triple":
			return [RING_INNER_SINGLE_OUTER, RING_TRIPLE_OUTER]
		"outer_single":
			return [RING_TRIPLE_OUTER, RING_OUTER_SINGLE_OUTER]
		"double":
			return [RING_OUTER_SINGLE_OUTER, RING_DOUBLE_OUTER]
	return [0.0, 0.0]


## DRAW band [inner, outer] for a wedge ring, with the double_ring_width_scale handicap folded in
## (double inner moves out, outer single extends to fill). Used by all rendering + visual hover.
func _band_draw(wedge_idx: int, ring_key: String) -> Array:
	var b: Array = _band_raw_draw(wedge_idx, ring_key)
	if ring_key == "double":
		return [_effective_double_inner_w(wedge_idx), b[1]]
	if ring_key == "outer_single":
		return [b[0], _effective_double_inner_w(wedge_idx)]
	return b


## SETTLED double inner for a wedge (scale handicap applied). For hit detection.
func _effective_double_inner_settled(wedge_idx: int) -> float:
	var b: Array = _band_raw_settled(wedge_idx, "double")
	return RING_DOUBLE_OUTER - (RING_DOUBLE_OUTER - b[0]) * double_ring_width_scale


## Single-bull outer radius for hit detection (settled) / rendering (draw).
func _single_bull_settled() -> float:
	return float(_geo_bull.get("single_bull", RING_SINGLE_BULL_OUTER)) if not _geo_bull.is_empty() else RING_SINGLE_BULL_OUTER


func _double_bull_settled() -> float:
	return float(_geo_bull.get("double_bull", RING_DOUBLE_BULL_OUTER)) if not _geo_bull.is_empty() else RING_DOUBLE_BULL_OUTER


func _single_bull_draw() -> float:
	return float(_geo_bull_draw.get("single_bull", RING_SINGLE_BULL_OUTER)) if not _geo_bull_draw.is_empty() else RING_SINGLE_BULL_OUTER


func _double_bull_draw() -> float:
	return float(_geo_bull_draw.get("double_bull", RING_DOUBLE_BULL_OUTER)) if not _geo_bull_draw.is_empty() else RING_DOUBLE_BULL_OUTER


## Angle (deg, rotation applied) of a wedge's start / end / center boundary, using DRAW weights
## for rendering. Wedge widths vary, so callers must use _wedge_end_deg(i) instead of
## start + WEDGE_ANGLE_DEG.
func _wedge_start_deg(wedge_idx: int) -> float:
	if _wedge_bounds_deg_draw.size() == 21:
		return _wedge_bounds_deg_draw[wedge_idx] + board_rotation_offset
	return wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG + board_rotation_offset


func _wedge_end_deg(wedge_idx: int) -> float:
	if _wedge_bounds_deg_draw.size() == 21:
		return _wedge_bounds_deg_draw[wedge_idx + 1] + board_rotation_offset
	return wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG + WEDGE_ANGLE_DEG + board_rotation_offset


func _wedge_center_deg(wedge_idx: int) -> float:
	return (_wedge_start_deg(wedge_idx) + _wedge_end_deg(wedge_idx)) * 0.5


## DRAW [inner, outer] band for a wedge by DISPLAY ring name ("Inner Single"/"Triple"/...).
## Convenience for the overlay/highlight draws that key off display names. Returns ZERO-width
## for unknown names.
func _band_draw_by_name(wedge_idx: int, ring_name: String) -> Array:
	match ring_name:
		"Inner Single", "inner_single":
			return _band_draw(wedge_idx, "inner_single")
		"Triple", "triple":
			return _band_draw(wedge_idx, "triple")
		"Outer Single", "outer_single":
			return _band_draw(wedge_idx, "outer_single")
		"Double", "double":
			return _band_draw(wedge_idx, "double")
	return [0.0, 0.0]


## Classify a board-relative position into a ring KEY using the DRAW geometry (for visual
## highlights / flash that should match the rendered board). Returns one of double_bull /
## single_bull / inner_single / triple / outer_single / double, or "" when off-board.
func _classify_ring_key_draw(relative: Vector2) -> String:
	var nd: float = relative.length() / board_radius
	if nd <= _double_bull_draw():
		return "double_bull"
	if nd <= _single_bull_draw():
		return "single_bull"
	var w: int = _get_wedge_index_draw(relative)
	if nd <= _band_draw(w, "inner_single")[1]:
		return "inner_single"
	if nd <= _band_draw(w, "triple")[1]:
		return "triple"
	if nd <= _effective_double_inner_w(w):
		return "outer_single"
	if nd <= RING_DOUBLE_OUTER:
		return "double"
	return ""


## Draw boss overlay effects (voided wedges with transition support).
func _draw_boss_overlay() -> void:
	# Draw fading-out previous voids
	if _void_transition_t < 1.0:
		var fade_alpha: float = 1.0 - _void_transition_t
		for wedge_idx: int in _boss_void_wedges_prev:
			if _boss_void_wedges.has(wedge_idx):
				continue
			_draw_void_wedge(wedge_idx, fade_alpha)

	# Draw current voids (fading in if transitioning)
	var new_alpha: float = _void_transition_t
	for wedge_idx: int in _boss_void_wedges:
		_draw_void_wedge(wedge_idx, new_alpha)

	# Drifted single-ring voids on partially-void wedges (Void boss medium/hard).
	# These migrate as the reveal: prev rings fade out, current rings fade in.
	if _void_transition_t < 1.0:
		var ring_fade: float = 1.0 - _void_transition_t
		for key: String in _boss_void_rings_prev:
			if _boss_void_rings.has(key):
				continue
			_draw_void_ring_from_key(key, ring_fade)
	for key: String in _boss_void_rings:
		_draw_void_ring_from_key(key, new_alpha)

	# Phase 2: drifted rings sliding from their source wedge to the neighbor.
	for move: Dictionary in _drift_moves:
		var from_idx: int = move["from"]
		var to_idx: int = move["to"]
		var delta: int = to_idx - from_idx
		if delta == 19:
			delta = -1
		elif delta == -19:
			delta = 1
		var cur_start: float = _wedge_start_deg(from_idx) + _drift_t * float(delta) * WEDGE_ANGLE_DEG
		_draw_void_ring_segment(cur_start, move["ring"], 1.0)


func _draw_void_wedge(wedge_idx: int, alpha: float) -> void:
	var start_deg: float = _wedge_start_deg(wedge_idx)
	var end_deg: float = _wedge_end_deg(wedge_idx)
	var fill: Color = Color(void_fill_color.r, void_fill_color.g, void_fill_color.b, void_fill_color.a * alpha)
	var border: Color = Color(void_border_color.r, void_border_color.g, void_border_color.b, void_border_color.a * alpha)

	for ring_name: String in RING_ORDER_DISPLAY:
		var band: Array = _band_draw_by_name(wedge_idx, ring_name)
		if band[1] <= 0.0:
			continue
		var points: PackedVector2Array = _build_segment_points(start_deg, end_deg, band[1], band[0])
		_boss_overlay.draw_colored_polygon(points, fill)

		var border_pts: PackedVector2Array = _build_segment_border_points(start_deg, end_deg, band[1], band[0])
		_boss_overlay.draw_polyline(border_pts, border, void_border_thickness)


## Draw a single voided ring from a "<wedge>:<RingName>" key (Void boss drift), using that
## wedge's angular span + ring band (so it tracks any geometry resize).
func _draw_void_ring_from_key(key: String, alpha: float) -> void:
	var sep: int = key.find(":")
	if sep < 0:
		return
	var wedge_idx: int = key.substr(0, sep).to_int()
	var ring_name: String = key.substr(sep + 1)
	var band: Array = _band_draw_by_name(wedge_idx, ring_name)
	if band[1] <= 0.0:
		return
	_draw_void_ring_band(_wedge_start_deg(wedge_idx), _wedge_end_deg(wedge_idx), band, alpha)


## Draw one void ring band sliding at an arbitrary angular start (the drift phase, where the
## ring migrates between wedges so there's no fixed wedge index). Uses base band widths and the
## canonical 18° span — a transient sliding visual, so an approximation is acceptable.
func _draw_void_ring_segment(start_deg: float, ring_name: String, alpha: float) -> void:
	if not RING_BOUNDS.has(ring_name):
		return
	_draw_void_ring_band(start_deg, start_deg + WEDGE_ANGLE_DEG, RING_BOUNDS[ring_name], alpha)


## Fill + border a single void ring band given explicit start/end degrees and an [inner, outer]
## normalized band. Shared by the static keyed rings and the sliding drift rings.
func _draw_void_ring_band(start_deg: float, end_deg: float, band: Array, alpha: float) -> void:
	var inner_norm: float = band[0]
	var outer_norm: float = band[1]
	var fill: Color = Color(void_fill_color.r, void_fill_color.g, void_fill_color.b, void_fill_color.a * alpha)
	var border: Color = Color(void_border_color.r, void_border_color.g, void_border_color.b, void_border_color.a * alpha)

	var points: PackedVector2Array = _build_segment_points(start_deg, end_deg, outer_norm, inner_norm)
	_boss_overlay.draw_colored_polygon(points, fill)

	var border_pts: PackedVector2Array = _build_segment_border_points(start_deg, end_deg, outer_norm, inner_norm)
	_boss_overlay.draw_polyline(border_pts, border, void_border_thickness)


## Set the wedge indices affected by the Recession boss (scuff/damage overlay).
func set_boss_recession_wedges(wedges: Array[int]) -> void:
	_boss_recession_wedges = wedges
	_recession_overlay.queue_redraw()
	queue_redraw()


## Draw callback for the recession shader overlay node.
func _draw_recession_overlay_cb() -> void:
	for wedge_idx: int in _boss_recession_wedges:
		var start_deg: float = _wedge_start_deg(wedge_idx)
		var end_deg: float = _wedge_end_deg(wedge_idx)
		for ring_name: String in RING_ORDER_DISPLAY:
			var band: Array = _band_draw_by_name(wedge_idx, ring_name)
			if band[1] <= 0.0:
				continue
			var points: PackedVector2Array = _build_segment_points(start_deg, end_deg, band[1], band[0])
			_recession_overlay.draw_colored_polygon(points, recession_overlay_color)


## Build a segment polygon (same geometry as _draw_segment but returns points).
func _build_segment_points(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_r: float = board_radius * outer_norm
	var inner_r: float = board_radius * inner_norm

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * outer_r)

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * inner_r)

	return points


## Build a segment border polyline (closed loop).
func _build_segment_border_points(start_deg: float, end_deg: float, outer_norm: float, inner_norm: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var outer_r: float = board_radius * outer_norm
	var inner_r: float = board_radius * inner_norm

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * outer_r)

	for i: int in range(arc_points + 1):
		var t: float = float(i) / float(arc_points)
		var angle_rad: float = deg_to_rad(lerpf(end_deg, start_deg, t))
		var direction: Vector2 = Vector2(sin(angle_rad), -cos(angle_rad))
		points.append(direction * inner_r)

	points.append(points[0])
	return points


## Push exported shockwave values into the ShaderMaterial.
func _sync_shockwave_shader(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("board_radius", board_radius)
	mat.set_shader_parameter("wave_reach", shockwave_reach)
	mat.set_shader_parameter("edge_width", shockwave_edge_width)
	mat.set_shader_parameter("trail_width", shockwave_trail_width)
	mat.set_shader_parameter("edge_intensity", shockwave_edge_intensity)
	mat.set_shader_parameter("trail_intensity", shockwave_trail_intensity)
	mat.set_shader_parameter("wave_color", shockwave_color)


## Draw callback for the shockwave shader overlay node.
func _draw_shockwave_overlay() -> void:
	if not _shockwave_active:
		return

	var base_color: Color = Color(0.0, 0.0, 0.0, 1.0)

	if _shockwave_ring_name == "double_bull":
		_shockwave_overlay.draw_circle(Vector2.ZERO, board_radius * _double_bull_draw(), base_color)
		return
	if _shockwave_ring_name == "single_bull":
		_shockwave_overlay.draw_circle(Vector2.ZERO, board_radius * _single_bull_draw(), base_color)
		return
	var band: Array = _band_draw_by_name(_shockwave_wedge_idx, _shockwave_ring_name)
	if band[1] <= 0.0:
		return
	var start_deg: float = _wedge_start_deg(_shockwave_wedge_idx)
	var end_deg: float = _wedge_end_deg(_shockwave_wedge_idx)
	var points: PackedVector2Array = _build_segment_points(start_deg, end_deg, band[1], band[0])
	_shockwave_overlay.draw_colored_polygon(points, base_color)
