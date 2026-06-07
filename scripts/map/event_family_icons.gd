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

## Real per-family textures, dropped in by Max later. Empty ⇒ the view uses the fallback.
@export var icons: Dictionary = {}            ## StringName family -> Texture2D

## Placeholder swatch colour per family (the grey-box glyph tint until art lands).
@export var fallback_colors: Dictionary = {
	&"accuracy": Color(0.85, 0.70, 0.30),   ## bullseye gold
	&"brush": Color(0.45, 0.70, 0.85),      ## paint blue
	&"geometry": Color(0.55, 0.80, 0.55),   ## shape green (inactive)
	&"scoring": Color(0.80, 0.55, 0.80),    ## score violet (inactive)
}

## Placeholder one-glyph label per family (basic shapes, ASCII-safe for the grey rect).
@export var fallback_labels: Dictionary = {
	&"accuracy": "(+)",   ## bullseye
	&"brush": "[B]",      ## brush
	&"geometry": "<>",    ## shape
	&"scoring": "*",      ## score
}


## The texture for a family, or null when only the placeholder exists.
func texture_for(family: StringName) -> Texture2D:
	return icons.get(family, null)


## The placeholder swatch colour for a family (grey fallback if unregistered).
func color_for(family: StringName) -> Color:
	return fallback_colors.get(family, Color(0.5, 0.5, 0.5))


## The placeholder glyph label for a family (its name's first letters if unregistered).
func label_for(family: StringName) -> String:
	return fallback_labels.get(family, "Event")
