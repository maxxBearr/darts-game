class_name OddStreakModifier
extends ParityStreakModifier
## Awards cumulative +1x multiplier per consecutive hit on odd-valued wedges.
## First qualifying hit scores normally. Second consecutive gets +1x. Third gets +2x. Etc.
## Even hits break the streak.


func _init() -> void:
	super._init()
	modifier_name = "Odd Streak"
	target_is_odd = true


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> OddStreakModifier:
	var mod: OddStreakModifier = OddStreakModifier.new()
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

	mod.modifier_name = "Odd Streak"
	mod.description = "+%dx per consecutive odd hit (per %s)" % [mod.bonus_per_hit, scope_name]

	mod.roll_toggleable()
	return mod
