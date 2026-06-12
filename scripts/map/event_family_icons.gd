class_name EventFamilyIcons
extends Resource
## Maps an event family id -> its map glyph (the SAME glyph the typed-shop ring will use
## in a later Phase-03 slice — built once, shared). Drop real art into `icons` when ready;
## until then the view falls back to a labelled coloured shape from `fallback_labels` /
## `fallback_colors`. See specs/map/03-events-impl.md §2.
##
## Scaffolded for ALL four families now (exactly like the relics' first-pass icons) so the
## map renders a distinct glyph the moment a family activates. `accuracy`, `brush`, and
## `geometry` are active reward paths; `scoring` remains a placeholder awaiting its
## make-it-a-trade retrofit (§7).

## Real per-family textures (Phase 03 typed-shop slice — art now lives in sprites/Icons/). The
## SAME five icons the typed-shop ring uses (don't build a second set — codex reuses them too).
## A family absent here falls back to the labelled coloured shape below.
@export var icons: Dictionary = {
	&"scoring": preload("res://sprites/Icons/scoringItems.png"),
	&"streak": preload("res://sprites/Icons/streak.png"),
	&"accuracy": preload("res://sprites/Icons/accuracyIcon.png"),
	&"geometry": preload("res://sprites/Icons/geoItems.png"),
	&"brush": preload("res://sprites/Icons/brush.png"),
	&"relic": preload("res://sprites/Icons/boss_reward.png"),  # §6 gold shop relic glyph.
}

## Placeholder swatch colour per family (the grey-box glyph tint when an icon is missing).
@export var fallback_colors: Dictionary = {
	&"accuracy": Color(0.85, 0.70, 0.30),   ## bullseye gold
	&"brush": Color(0.45, 0.70, 0.85),      ## paint blue
	&"geometry": Color(0.55, 0.80, 0.55),   ## shape green
	&"scoring": Color(0.80, 0.55, 0.80),    ## score violet
	&"streak": Color(0.90, 0.55, 0.35),     ## streak amber
	&"relic": Color(1.0, 0.82, 0.20),       ## relic gold (§6)
}

## Placeholder one-glyph label per family (basic shapes, ASCII-safe for the grey rect).
@export var fallback_labels: Dictionary = {
	&"accuracy": "(+)",   ## bullseye
	&"brush": "[B]",      ## brush
	&"geometry": "<>",    ## shape
	&"scoring": "*",      ## score
	&"streak": "S",       ## streak
	&"relic": "(R)",      ## relic (§6)
}


## Map a ScoringEnums.Family enum to its StringName icon key. CHALLENGE nodes carry the family as
## the enum (reward_family: ScoringEnums.Family); EVENT nodes carry it as a StringName already.
## Returns &"" for families with no map icon (NONE / the sidelined PLACEMENT). Challenge draws only
## ever roll SCORING / STREAK (geometry spec §10), but the full mapping is here for completeness.
static func key_for_family(f: ScoringEnums.Family) -> StringName:
	match f:
		ScoringEnums.Family.SCORING:
			return &"scoring"
		ScoringEnums.Family.STREAK:
			return &"streak"
		ScoringEnums.Family.BRUSH:
			return &"brush"
		ScoringEnums.Family.GEOMETRY:
			return &"geometry"
		_:
			return &""


## The texture for a family, or null when only the placeholder exists.
func texture_for(family: StringName) -> Texture2D:
	return icons.get(family, null)


## The placeholder swatch colour for a family (grey fallback if unregistered).
func color_for(family: StringName) -> Color:
	return fallback_colors.get(family, Color(0.5, 0.5, 0.5))


## The placeholder glyph label for a family (its name's first letters if unregistered).
func label_for(family: StringName) -> String:
	return fallback_labels.get(family, "Event")
