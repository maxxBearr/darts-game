class_name EvenStreakModifier
extends ParityStreakModifier
## Awards cumulative +1x multiplier per consecutive hit on even-valued wedges.
## First qualifying hit scores normally. Second consecutive gets +1x. Third gets +2x. Etc.
## Odd hits break the streak.


func _init() -> void:
	super._init()
	modifier_name = "Even Streak"
	target_is_odd = false


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> EvenStreakModifier:
	var mod: EvenStreakModifier = EvenStreakModifier.new()
	mod.rarity_tier = rarity_tier

	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_TURN
		ScoringEnums.Rarity.UNCOMMON:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_LEG
		ScoringEnums.Rarity.RARE:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_RUN

	const SCOPE_NAMES: Dictionary = {
		ScoringEnums.StreakScope.WITHIN_TURN: "turn",
		ScoringEnums.StreakScope.WITHIN_LEG: "leg",
		ScoringEnums.StreakScope.WITHIN_RUN: "run",
	}
	var scope_name: String = SCOPE_NAMES[mod.streak_scope]

	mod.modifier_name = "Even Streak"
	mod.description = "+%dx per consecutive even hit (per %s)" % [mod.bonus_per_hit, scope_name]

	return mod
