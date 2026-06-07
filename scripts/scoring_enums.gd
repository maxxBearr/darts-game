class_name ScoringEnums
## Shared enums used by the scoring modifier system.
## Centralized here so both Resource scripts (ScoringModifier and subclasses)
## and Node scripts (ScoringModifierManager, dartboard) can reference them
## with full type safety instead of raw ints.

## The four segment colors on a standard dartboard.
## Even-index wedges: BLACK (singles), RED (doubles/triples).
## Odd-index wedges: WHITE (singles), GREEN (doubles/triples).
## Bulls: GREEN (single bull), RED (double bull).
enum SegmentColor {
	RED,
	GREEN,
	BLACK,
	WHITE,
}

## When a modifier fires in the scoring pipeline.
enum ModifierTiming {
	ON_ACQUIRE,  ## Fires once when the modifier is added (e.g., wedge value changes)
	PER_DART,    ## Fires every dart through the scoring pipeline
}

## How long streak history persists before resetting.
enum StreakScope {
	NONE,         ## Not a streak-based modifier
	WITHIN_TURN,  ## History resets every 3-dart turn
	WITHIN_LEG,   ## History resets when a new leg starts
	WITHIN_RUN,   ## History persists the entire run
}

## Whether the player needs to configure the modifier after acquiring it.
enum ConfigType {
	NONE,            ## Activates immediately, no player input needed
	PICK_WEDGE,      ## Player picks one wedge on the board to target
	PICK_TWO_WEDGES, ## Player picks two wedges (for swaps, etc.)
	PICK_SEGMENT,    ## Player picks one specific ring on one wedge (wedge + ring_name)
}

## How strict streak matching is for consecutive hit modifiers.
enum StreakLeniency {
	SAME_RING,          ## Must hit the exact same ring on the exact same wedge
	ADJACENT_SECTIONS,  ## Same wedge, ring must be same or directly adjacent
	WHOLE_WEDGE,        ## Any ring on the same wedge number counts
}

## Ring adjacency for ADJACENT_SECTIONS leniency checks.
## Order from inside out: inner_single ↔ triple ↔ outer_single ↔ double.
const RING_ADJACENCY: Dictionary = {
	"inner_single": ["triple"],
	"triple": ["inner_single", "outer_single"],
	"outer_single": ["triple", "double"],
	"double": ["outer_single"],
}

## Which streak slot category a streak modifier belongs to.
## Capacity is per-category and sourced from the equipped components
## (shaft → WEDGE slots, barrel → COLOR slots). See DartBuild.get_streak_capacity().
enum StreakCategory {
	NONE,    ## Not a streak modifier — no slot restriction
	WEDGE,   ## Wedge-based streaks (same ring, adjacent, whole wedge). Capacity from the shaft.
	COLOR,   ## Color-based streaks (consecutive same-color hits). Capacity from the barrel.
	PARITY,  ## RETIRED — even/odd streaks were cut (anti-spatial). Value kept for save-data safety; nothing populates it.
}

## Player-facing taxonomy for board-modifying items, used by the shop / reward pool
## to steer offers (e.g. surface one of each). Distinct from ModifierKind, which is
## about behavior (RELIC vs BOARD_MUTATION).
enum Family {
	NONE,       ## Not a board item (legacy/sidelined modifiers).
	SCORING,    ## Moves the face-value axis: Hotspot, Wedge Value.
	PLACEMENT,  ## SIDELINED (geometry spec §9a) — its only item, Wedge Swap, was cut from the
	            ## pool (fake trade + can't honor earned rarity). Enum value kept for save-data
	            ## safety and the dormant class. Nothing in the live pool reports this family.
	            ## Tier grammar (geometry spec §10): SCORING + STREAK = laddered (challenges + shop);
	            ## GEOMETRY + BRUSH = rarity-less trades (events + shop); ACCURACY = component-stat
	            ## trades (events). The family boundary IS the tier boundary.
	BRUSH,      ## Recolor: Brush. Its own utility family because color drives color-streak builds.
	GEOMETRY,   ## Board-wide, rarity-less, zero-sum reshapes of the physical layout: Ring Trade,
	            ## Color Territory, Parity Shift. NOT Placement — geometry reshapes the whole board's
	            ## risk profile (the family identity); Placement is single-target. See the geometry spec.
	STREAK,     ## Wedge / Color streaks. Geometry spec §10 amends the 2026-06-03 "streaks excluded
	            ## from the family taxonomy" decision: streaks stay OUT of the board-item *steering*
	            ## story conceptually (they live on the separate multiplicative axis, acquired into
	            ## component-gated slots — the shop never family-steers them). The value exists purely
	            ## because the CHALLENGE draw filters by family, so streaks need a tag to be rollable
	            ## as an earned prize. Plumbing, not taxonomy.
}

## Which slot a dart component fits in.
enum ComponentSlot {
	BARREL,
	SHAFT,
	FLIGHT,
}

## Whether a modifier persists in the player's inventory (relic panel) or
## is a one-time effect that mutates the board and then disappears.
enum ModifierKind {
	RELIC,           ## Persistent — shown in modifier panel, has an icon, contributes to live scoring per dart.
	BOARD_MUTATION,  ## One-time — applied at acquisition, no panel presence afterward.
}

## Visual icon category — drives ModifierIcon's shape dispatch.
enum IconShape {
	NONE,           ## Default / fallback.
	COLOR_CIRCLE,   ## Color Bonus, per-color Streak.
	EVEN_SQUARE,    ## Even Bonus, Even Streak.
	ODD_TRIANGLE,   ## Odd Bonus, Odd Streak.
	WEDGE_SECTOR,   ## Wedge Streak.
}

## Item rarity tiers. Determines value ranges and visual presentation.
enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
}

## Which mode the setup recommendation is operating in.
## Evaluated in priority order by get_setup_recommendation().
enum SetupMode {
	ENDGAME_SETUP,     ## Scoring dart lands at a 1-dart-finishable remainder
	SCORE_REDUCTION,   ## Too far from checkout range — just score points
	MID_ZONE_SETUP,    ## Scoring dart lands in preferred remainders (3-dart-finishable)
	OFF_BOARD_PRESERVE, ## Every scoring dart busts or leaves remainder=1
}

## Display data for each rarity tier: name string and card tint color.
const RARITY_DATA: Dictionary = {
	Rarity.COMMON: {"name": "Common", "color": Color(0.6, 0.6, 0.6)},
	Rarity.UNCOMMON: {"name": "Uncommon", "color": Color(0.3, 0.5, 1.0)},
	Rarity.RARE: {"name": "Rare", "color": Color(0.7, 0.3, 0.9)},
}
