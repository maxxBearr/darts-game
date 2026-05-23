class_name ColorBonusModifier
extends ScoringModifier
## Adds a bonus multiplier when the dart lands on a segment of the target color.
## Example: "Red segments get +1 multiplier" makes a double (x2) into x3,
## and a triple (x3) into x4, but only on red-colored segments.
## Does not affect segments of other colors.

## Which SegmentColor triggers the bonus.
@export var target_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED

## How much to add to the multiplier when the color matches.
@export var bonus_multiplier: int = 1


func _init() -> void:
	modifier_name = "Color Bonus"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE


## Checks segment_color in the result. If it matches target_color, adds the bonus
## to the multiplier and recalculates total_score.
func apply(result: Dictionary, _context: Dictionary) -> Dictionary:
	if result.get("segment_color", -1) == target_color:
		for i: int in range(bonus_multiplier):
			var old_mult: int = result["multiplier"]
			result["multiplier"] += 1
			result["total_score"] = result["face_value"] * result["multiplier"]
			_track_modification(result, "multiplier", old_mult, result["multiplier"])
	return result


func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.COLOR_CIRCLE


const COLOR_NAMES: Dictionary = {
	ScoringEnums.SegmentColor.RED: "Red",
	ScoringEnums.SegmentColor.GREEN: "Green",
	ScoringEnums.SegmentColor.BLACK: "Black",
	ScoringEnums.SegmentColor.WHITE: "White",
}


static func get_pool_weight() -> int:
	return 30


static func get_rarity_weights() -> Array[int]:
	return [65, 25, 10]


static func generate(rarity_tier: ScoringEnums.Rarity) -> ColorBonusModifier:
	var mod: ColorBonusModifier = ColorBonusModifier.new()
	mod.rarity_tier = rarity_tier

	var colors: Array[ScoringEnums.SegmentColor] = [
		ScoringEnums.SegmentColor.RED,
		ScoringEnums.SegmentColor.GREEN,
		ScoringEnums.SegmentColor.BLACK,
		ScoringEnums.SegmentColor.WHITE,
	]
	mod.target_color = colors[randi_range(0, colors.size() - 1)]

	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.bonus_multiplier = 1
		ScoringEnums.Rarity.UNCOMMON:
			mod.bonus_multiplier = 2
		ScoringEnums.Rarity.RARE:
			mod.bonus_multiplier = 3

	var color_name: String = COLOR_NAMES[mod.target_color]
	mod.modifier_name = "%s Bonus +%dx" % [color_name, mod.bonus_multiplier]
	mod.description = "+%d multiplier on %s segments" % [mod.bonus_multiplier, color_name]

	mod.roll_toggleable()
	return mod
