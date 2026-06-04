class_name DartComponent
extends Resource
## A single dart part (barrel, shaft, or flight) with stat bonuses and a weight
## value that contributes to the dart's overall balance. Equip one of each in
## the assembly screen before a run.

## Stable identity for save data and unlock tracking. Slot-prefixed snake_case.
## MUST be non-empty and unique across all components. NEVER change after release.
@export var id: StringName = &""

@export var component_name: String = ""
@export var description: String = ""

## Which slot this part fits in.
@export var component_type: ScoringEnums.ComponentSlot = ScoringEnums.ComponentSlot.BARREL

## Directional balance contribution. Negative = front-heavy, Positive = back-heavy.
@export_range(-1.0, 1.0, 0.01) var weight: float = 0.0

@export var rarity_tier: ScoringEnums.Rarity = ScoringEnums.Rarity.COMMON

## Whether this component is unlocked from the start of a new save file.
## Set to false for progression-locked components — pair with an unlock_condition.
@export var default_unlocked: bool = true

## How the player earns this component if default_unlocked is false.
## Leave null for default-unlocked components.
@export var unlock_condition: UnlockCondition

@export var texture: Texture2D

## --- Stat Modifiers (all default 0.0, only non-zero values appear in tooltips) ---
@export var h_range_bonus: float = 0.0
@export var v_range_bonus: float = 0.0
@export var h_speed_bonus: float = 0.0
@export var v_speed_bonus: float = 0.0
@export var h_accuracy_bonus: float = 0.0
@export var v_accuracy_bonus: float = 0.0

## How many streak slots this component grants, on top of the base 1 per category.
## On a SHAFT → wedge-streak slots (precision/repetition synergy). On a BARREL →
## color-streak slots (the paintable scoring-engine axis). Ignored on FLIGHTS.
## Keep this small (0–2) so it reads at a glance and doesn't overload the assembly pick.
@export var streak_slot_grant: int = 0

## Optional throw modifier ability. When this component is equipped,
## this modifier is evaluated before each throw. Leave null for
## components with no conditional ability.
@export var throw_modifier: ThrowModifier

## Optional shop-bias passive. Evaluated by the shop when generating picks.
## Leave null for components with no shop influence.
@export var shop_bias: ShopBias

## Dart marker outer ring color (used by flights to theme the on-board dart).
@export var dart_outer_color: Color = Color(0.9, 0.85, 0.0)

## Dart marker inner dot color (used by flights to theme the on-board dart).
@export var dart_inner_color: Color = Color(0.2, 0.2, 0.2)


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
		lines.append("H Speed Control: %+.0f" % h_speed_bonus)
	if v_speed_bonus != 0.0:
		lines.append("V Speed Control: %+.0f" % v_speed_bonus)
	if h_accuracy_bonus != 0.0:
		lines.append("H Accuracy: %+.0f" % h_accuracy_bonus)
	if v_accuracy_bonus != 0.0:
		lines.append("V Accuracy: %+.0f" % v_accuracy_bonus)
	var streak_line: String = _streak_slot_tooltip_line()
	if streak_line != "":
		lines.append(streak_line)
	lines.append("Weight: %+.2f" % weight)
	return lines


## Tooltip line describing this part's streak-slot grant, phrased by slot. Empty when
## the grant is 0 or the part is a flight (flights don't grant streak capacity).
func _streak_slot_tooltip_line() -> String:
	if streak_slot_grant == 0:
		return ""
	match component_type:
		ScoringEnums.ComponentSlot.SHAFT:
			return "Wedge-streak slots: %+d" % streak_slot_grant
		ScoringEnums.ComponentSlot.BARREL:
			return "Color-streak slots: %+d" % streak_slot_grant
	return ""


## Build BBCode tooltip with positive stats in green and negative in red-orange.
func get_bbcode_tooltip() -> String:
	var lines: Array[String] = []
	var stats: Array[Array] = [
		["H Range", h_range_bonus],
		["V Range", v_range_bonus],
		["H Speed Control", h_speed_bonus],
		["V Speed Control", v_speed_bonus],
		["H Accuracy", h_accuracy_bonus],
		["V Accuracy", v_accuracy_bonus],
	]
	for entry: Array in stats:
		var val: float = entry[1]
		if val == 0.0:
			continue
		var color_hex: String = "#8ad68a" if val > 0.0 else "#d6886a"
		lines.append("[color=%s]%s: %+.0f[/color]" % [color_hex, entry[0], val])
	var streak_line: String = _streak_slot_tooltip_line()
	if streak_line != "":
		lines.append("[color=#c79bff]%s[/color]" % streak_line)
	var weight_color: String = "#aaaaaa"
	lines.append("[color=%s]Weight: %+.2f[/color]" % [weight_color, weight])
	return "\n".join(lines)
