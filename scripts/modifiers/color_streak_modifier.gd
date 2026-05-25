class_name ColorStreakModifier
extends ScoringModifier
## Awards cumulative multiplier bonus per consecutive hit on the target segment color.
## First qualifying hit scores normally. Second consecutive gets +bonus_per_hit x.
## Third gets +2*bonus_per_hit x. Etc.
## Each instance tracks a fixed target_color rolled at generation.

## Which SegmentColor this streak tracks.
@export var target_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED

## Multiplier added per consecutive same-color hit.
@export var bonus_per_hit: int = 1

## Current number of consecutive target-color hits.
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Color Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.COLOR


func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.COLOR_CIRCLE


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var segment_color: int = result.get("segment_color", -1)

	# No color info (off board, etc.) — break the streak
	if segment_color < 0:
		if not is_preview:
			_reset_streak()
		return result

	var effective_count: int = _streak_count
	if segment_color == target_color:
		effective_count += 1
	else:
		effective_count = 0

	# Update state only for real throws
	if not is_preview:
		_streak_count = effective_count

	# Apply bonus: streak count - 1 extra multipliers scaled by bonus_per_hit
	var bonus: int = effective_count - 1
	if bonus > 0:
		for i: int in range(bonus * bonus_per_hit):
			var old_mult: int = result["multiplier"]
			result["multiplier"] += 1
			result["total_score"] = result["face_value"] * result["multiplier"]
			_track_modification(result, "multiplier", old_mult, result["multiplier"])
		result["streak_triggered"] = true
		result["streak_name"] = modifier_name
		result["streak_count"] = effective_count

	return result


func would_continue_streak(target: Dictionary) -> bool:
	return _streak_count > 0 and target.get("segment_color", -1) == target_color


func _reset_streak() -> void:
	_streak_count = 0


func reset_streak_state() -> void:
	_reset_streak()


func save_streak_state() -> Dictionary:
	return {"count": _streak_count}


func restore_streak_state_from(snapshot: Dictionary) -> void:
	_streak_count = snapshot.get("count", 0)


func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	var color_name: String = COLOR_NAMES.get(target_color, "Color")
	return "%s ×%d" % [color_name, _streak_count]


const COLOR_NAMES: Dictionary = {
	ScoringEnums.SegmentColor.RED: "Red",
	ScoringEnums.SegmentColor.GREEN: "Green",
	ScoringEnums.SegmentColor.BLACK: "Black",
	ScoringEnums.SegmentColor.WHITE: "White",
}


static func get_pool_weight() -> int:
	return 4


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> ColorStreakModifier:
	var mod: ColorStreakModifier = ColorStreakModifier.new()
	mod.rarity_tier = rarity_tier

	match rarity_tier:
		ScoringEnums.Rarity.COMMON:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_TURN
		ScoringEnums.Rarity.UNCOMMON:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_LEG
		ScoringEnums.Rarity.RARE:
			mod.streak_scope = ScoringEnums.StreakScope.WITHIN_RUN

	var colors: Array[ScoringEnums.SegmentColor] = [
		ScoringEnums.SegmentColor.RED,
		ScoringEnums.SegmentColor.GREEN,
		ScoringEnums.SegmentColor.BLACK,
		ScoringEnums.SegmentColor.WHITE,
	]
	mod.target_color = colors[randi_range(0, colors.size() - 1)]

	const SCOPE_NAMES: Dictionary = {
		ScoringEnums.StreakScope.WITHIN_TURN: "turn",
		ScoringEnums.StreakScope.WITHIN_LEG: "leg",
		ScoringEnums.StreakScope.WITHIN_RUN: "run",
	}
	var scope_name: String = SCOPE_NAMES[mod.streak_scope]
	var color_name: String = COLOR_NAMES[mod.target_color]

	mod.modifier_name = "%s Streak" % color_name
	mod.description = "+%dx per consecutive %s hit (per %s)" % [mod.bonus_per_hit, color_name.to_lower(), scope_name]

	mod.roll_toggleable()
	return mod
