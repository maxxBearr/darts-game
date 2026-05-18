class_name DartComponent
extends Resource
## A single dart part (barrel, shaft, or flight) with stat bonuses and a weight
## value that contributes to the dart's overall balance. Equip one of each in
## the assembly screen before a run.

@export var component_name: String = ""
@export var description: String = ""

## Which slot this part fits in.
@export var component_type: ScoringEnums.ComponentSlot = ScoringEnums.ComponentSlot.BARREL

## Directional balance contribution. Negative = front-heavy, Positive = back-heavy.
@export_range(-1.0, 1.0, 0.01) var weight: float = 0.0

@export var rarity_tier: ScoringEnums.Rarity = ScoringEnums.Rarity.COMMON
@export var unlocked: bool = true
@export var texture: Texture2D

## --- Stat Modifiers (all default 0.0, only non-zero values appear in tooltips) ---
@export var h_range_bonus: float = 0.0
@export var v_range_bonus: float = 0.0
@export var h_speed_bonus: float = 0.0
@export var v_speed_bonus: float = 0.0
@export var h_accuracy_bonus: float = 0.0
@export var v_accuracy_bonus: float = 0.0


var rarity_name: String:
	get:
		return ScoringEnums.RARITY_DATA[rarity_tier]["name"]


var rarity_color: Color:
	get:
		return ScoringEnums.RARITY_DATA[rarity_tier]["color"]


## Build tooltip lines showing only non-zero stat effects, plus weight.
func get_tooltip_lines() -> Array[String]:
	var lines: Array[String] = []
	if h_range_bonus != 0.0:
		lines.append("H Range: %+.0f" % h_range_bonus)
	if v_range_bonus != 0.0:
		lines.append("V Range: %+.0f" % v_range_bonus)
	if h_speed_bonus != 0.0:
		lines.append("H Speed: %+.0f" % h_speed_bonus)
	if v_speed_bonus != 0.0:
		lines.append("V Speed: %+.0f" % v_speed_bonus)
	if h_accuracy_bonus != 0.0:
		lines.append("H Accuracy: %+.0f" % h_accuracy_bonus)
	if v_accuracy_bonus != 0.0:
		lines.append("V Accuracy: %+.0f" % v_accuracy_bonus)
	lines.append("Weight: %+.2f" % weight)
	return lines
