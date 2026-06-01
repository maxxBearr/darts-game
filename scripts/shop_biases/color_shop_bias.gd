class_name ColorShopBias
extends ShopBias
## Biases the shop modifier pool toward color-flavored modifier types.

@export var color_weight_multiplier: float = 2.0

const _ColorBonus = preload("res://scripts/modifiers/color_bonus_modifier.gd")
const _ColorStreak = preload("res://scripts/modifiers/color_streak_modifier.gd")
const _Brush = preload("res://scripts/modifiers/brush_modifier.gd")


func get_weight_overrides() -> Dictionary:
	return {
		_ColorBonus: color_weight_multiplier,
		_ColorStreak: color_weight_multiplier,
		_Brush: color_weight_multiplier,
	}
