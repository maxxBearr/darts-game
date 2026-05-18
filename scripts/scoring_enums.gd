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
}

## Which slot a dart component fits in.
enum ComponentSlot {
	BARREL,
	SHAFT,
	FLIGHT,
}

## Item rarity tiers. Determines value ranges and visual presentation.
enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
}

## Display data for each rarity tier: name string and card tint color.
const RARITY_DATA: Dictionary = {
	Rarity.COMMON: {"name": "Common", "color": Color(0.6, 0.6, 0.6)},
	Rarity.UNCOMMON: {"name": "Uncommon", "color": Color(0.3, 0.5, 1.0)},
	Rarity.RARE: {"name": "Rare", "color": Color(0.7, 0.3, 0.9)},
}
