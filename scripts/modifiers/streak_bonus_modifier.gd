class_name StreakBonusModifier
extends ScoringModifier
## Awards cumulative +1x multiplier per consecutive qualifying hit on the same wedge.
## First qualifying hit scores normally. Second consecutive gets +1x. Third gets +2x. Etc.
## Leniency tier determines how strict the ring matching is.

## How strict the ring matching is for maintaining the streak.
@export var leniency: ScoringEnums.StreakLeniency = ScoringEnums.StreakLeniency.WHOLE_WEDGE

var _streak_wedge_index: int = -1
var _streak_ring: String = ""
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Wedge Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.WEDGE


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var wedge_index: int = result.get("wedge_index", -1)
	var ring_name: String = result.get("ring_name", "")

	if wedge_index < 0 or result.get("is_bull", false):
		if not is_preview:
			_reset_streak()
		return result

	var ring_zone: String = _ring_name_to_zone(ring_name)
	if ring_zone.is_empty():
		if not is_preview:
			_reset_streak()
		return result

	# Calculate what the streak would be without mutating state during preview
	var effective_count: int = _streak_count
	var qualifies: bool = _is_qualifying_hit(wedge_index, ring_zone)

	if qualifies:
		effective_count += 1
	else:
		effective_count = 1

	if not is_preview:
		_streak_count = effective_count
		_streak_wedge_index = wedge_index
		_streak_ring = ring_zone

	var bonus: int = effective_count - 1
	if bonus > 0:
		for i: int in range(bonus):
			var old_mult: int = result["multiplier"]
			result["multiplier"] += 1
			result["total_score"] = result["face_value"] * result["multiplier"]
			_track_modification(result, "multiplier", old_mult, result["multiplier"])
		result["streak_triggered"] = true
		result["streak_name"] = modifier_name
		result["streak_count"] = effective_count

	return result


func _is_qualifying_hit(wedge_index: int, ring_zone: String) -> bool:
	if _streak_wedge_index < 0:
		return true
	if wedge_index != _streak_wedge_index:
		return false

	match leniency:
		ScoringEnums.StreakLeniency.WHOLE_WEDGE:
			return true
		ScoringEnums.StreakLeniency.SAME_RING:
			return ring_zone == _streak_ring
		ScoringEnums.StreakLeniency.ADJACENT_SECTIONS:
			if ring_zone == _streak_ring:
				return true
			var adjacent: Array = ScoringEnums.RING_ADJACENCY.get(_streak_ring, [])
			return ring_zone in adjacent

	return false


func _ring_name_to_zone(ring_name: String) -> String:
	match ring_name:
		"Inner Single":
			return "inner_single"
		"Triple":
			return "triple"
		"Outer Single":
			return "outer_single"
		"Double":
			return "double"
	return ""


func _reset_streak() -> void:
	_streak_wedge_index = -1
	_streak_ring = ""
	_streak_count = 0


func reset_streak_state() -> void:
	_reset_streak()


func save_streak_state() -> Dictionary:
	return {"wedge_index": _streak_wedge_index, "ring": _streak_ring, "count": _streak_count}


func restore_streak_state_from(snapshot: Dictionary) -> void:
	_streak_wedge_index = snapshot.get("wedge_index", -1)
	_streak_ring = snapshot.get("ring", "")
	_streak_count = snapshot.get("count", 0)


## Get the current streak count for display purposes.
func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	var leniency_label: String = ""
	match leniency:
		ScoringEnums.StreakLeniency.SAME_RING:
			leniency_label = "Ring"
		ScoringEnums.StreakLeniency.ADJACENT_SECTIONS:
			leniency_label = "Adj"
		ScoringEnums.StreakLeniency.WHOLE_WEDGE:
			leniency_label = "Wedge"
	return "%s ×%d" % [leniency_label, _streak_count]


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> StreakBonusModifier:
	var mod: StreakBonusModifier = StreakBonusModifier.new()
	mod.rarity_tier = rarity_tier

	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.leniency = ScoringEnums.StreakLeniency.SAME_RING
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_TURN
		ScoringEnums.Rarity.UNCOMMON:
			mod.leniency = ScoringEnums.StreakLeniency.ADJACENT_SECTIONS
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_LEG
		ScoringEnums.Rarity.RARE:
			mod.leniency = ScoringEnums.StreakLeniency.WHOLE_WEDGE
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_RUN

	const SCOPE_NAMES: Dictionary = {
		ScoringEnums.StreakScope.WITHIN_TURN: "turn",
		ScoringEnums.StreakScope.WITHIN_LEG: "leg",
		ScoringEnums.StreakScope.WITHIN_RUN: "run",
	}
	var scope_name: String = SCOPE_NAMES[mod.streak_scope]

	const LENIENCY_NAMES: Dictionary = {
		ScoringEnums.StreakLeniency.SAME_RING: "Same Ring",
		ScoringEnums.StreakLeniency.ADJACENT_SECTIONS: "Adjacent",
		ScoringEnums.StreakLeniency.WHOLE_WEDGE: "Whole Wedge",
	}

	var leniency_name: String = LENIENCY_NAMES[mod.leniency]
	mod.modifier_name = "Wedge Streak (%s)" % leniency_name
	mod.description = "+1x per consecutive hit on the same wedge (per %s)" % scope_name

	mod.roll_toggleable()
	return mod
