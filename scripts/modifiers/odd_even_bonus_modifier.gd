class_name OddEvenBonusModifier
extends ScoringModifier
## Adds a bonus multiplier when the dart lands on a wedge with an odd or even face value.
## Mirrors ColorBonusModifier but checks face_value % 2 instead of segment_color.

## Whether this modifier targets odd (true) or even (false) face values.
@export var target_odd: bool = true

## How much to add to the multiplier when the parity matches.
@export var bonus_multiplier: int = 1


func _init() -> void:
	modifier_name = "Odd/Even Bonus"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE


func get_config_fingerprint() -> String:
	return "%s|%s" % [super.get_config_fingerprint(), "O" if target_odd else "E"]


func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.ODD_TRIANGLE if target_odd else ScoringEnums.IconShape.EVEN_SQUARE


func apply(result: Dictionary, _context: Dictionary) -> Dictionary:
	var face_value: int = result.get("face_value", 0)
	if face_value <= 0:
		return result

	var is_odd: bool = face_value % 2 == 1
	if is_odd == target_odd:
		for i: int in range(bonus_multiplier):
			var old_mult: int = result["multiplier"]
			result["multiplier"] += 1
			result["total_score"] = result["face_value"] * result["multiplier"]
			_track_modification(result, "multiplier", old_mult, result["multiplier"])
	return result


static func get_pool_weight() -> int:
	return 25


static func get_rarity_weights() -> Array[int]:
	return [65, 25, 10]


static func generate(rarity_tier: ScoringEnums.Rarity) -> OddEvenBonusModifier:
	var mod: OddEvenBonusModifier = OddEvenBonusModifier.new()
	mod.rarity_tier = rarity_tier
	mod.target_odd = randi_range(0, 1) == 1

	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.bonus_multiplier = 1
		ScoringEnums.Rarity.UNCOMMON:
			mod.bonus_multiplier = 2
		ScoringEnums.Rarity.RARE:
			mod.bonus_multiplier = 3

	var parity_name: String = "Odd" if mod.target_odd else "Even"
	mod.modifier_name = "%s Bonus +%dx" % [parity_name, mod.bonus_multiplier]
	mod.description = "+%d multiplier on %s-numbered wedges" % [mod.bonus_multiplier, parity_name.to_lower()]

	mod.roll_toggleable()
	return mod
