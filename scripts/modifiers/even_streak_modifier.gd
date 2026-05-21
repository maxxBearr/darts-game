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

	# Roll streak scope
	var scopes: Array[ScoringEnums.StreakScope] = [
		ScoringEnums.StreakScope.WITHIN_TURN,
		ScoringEnums.StreakScope.WITHIN_LEG,
	]
	mod.streak_scope = scopes[randi_range(0, scopes.size() - 1)]

	var scope_name: String = "turn" if mod.streak_scope == ScoringEnums.StreakScope.WITHIN_TURN else "leg"

	mod.modifier_name = "Even Streak"
	mod.description = "+1x per consecutive even hit (per %s)" % scope_name

	return mod
