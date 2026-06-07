class_name ColorStreakModifier
extends ScoringModifier
## The COLOR streak — the multiplicative scaling axis for hitting the same segment color
## repeatedly (colors cluster by ring and are paintable). Capacity-gated by the barrel.
## First qualifying hit scores normally (×1). Each further consecutive same-color hit
## raises the multiplicative factor: factor = 1 + (count - 1) × streak_growth, applied to
## the whole additive baseline (face × (ring + hotspot)) as the LAST scoring step.
## Each instance tracks a fixed target_color rolled at generation.

## Which SegmentColor this streak tracks.
@export var target_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED

## Streak growth slope (per consecutive hit) for the multiplicative factor. The headline
## tuning dial: 1 = linear-in-count (×streak_count), the spec's recommended sweet spot;
## higher values ramp faster.
@export var streak_growth: int = 1

## Current number of consecutive target-color hits.
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Color Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.COLOR
	# STREAK family (geometry spec §10): the tag exists so the challenge draw can roll streaks as an
	# earned prize — it does NOT enroll them in the board-item steering story (capacity-gated axis).
	family = ScoringEnums.Family.STREAK


func get_streak_state_hash() -> int:
	return _streak_count


func get_config_fingerprint() -> String:
	return "%s|%d" % [super.get_config_fingerprint(), target_color]


func get_icon_shape() -> ScoringEnums.IconShape:
	return ScoringEnums.IconShape.COLOR_CIRCLE


## Report this color streak's contribution to the combined streak factor. Runs the
## continue/break logic and updates state (only on real throws), but does NOT mutate the
## score — the manager sums all streaks into one factor and applies it once.
func streak_contribution(result: Dictionary, context: Dictionary) -> int:
	var is_preview: bool = context.get("is_preview", false)
	var segment_color: int = result.get("segment_color", -1)

	# No color info (off board, etc.) — break the streak
	if segment_color < 0:
		if not is_preview:
			_reset_streak()
		return 0

	var effective_count: int = _streak_count
	if segment_color == target_color:
		effective_count += 1
	else:
		effective_count = 0

	# Update state only for real throws
	if not is_preview:
		_streak_count = effective_count

	if effective_count <= 1:
		return 0
	return (effective_count - 1) * streak_growth


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


## Current bonus into the combined factor: (count − 1) × growth, floored at 0.
func get_streak_bonus() -> int:
	return maxi(0, _streak_count - 1) * streak_growth


## Bonus if the next dart continues the streak (count + 1 → count × growth).
func get_next_streak_bonus() -> int:
	return _streak_count * streak_growth


## Bonus-language display ("Red +2" = next-hit contribution) — see
## StreakBonusModifier.get_streak_display for why bonuses, not factors.
func get_streak_display() -> String:
	var color_name: String = COLOR_NAMES.get(target_color, "Color")
	return "%s +%d" % [color_name, get_next_streak_bonus()]


const COLOR_NAMES: Dictionary = {
	ScoringEnums.SegmentColor.RED: "Red",
	ScoringEnums.SegmentColor.GREEN: "Green",
	ScoringEnums.SegmentColor.BLACK: "Black",
	ScoringEnums.SegmentColor.WHITE: "White",
}


static func get_pool_weight() -> int:
	# Raised off the old vestigial 4 — color streak is now a first-class scaling axis
	# (the barrel-gated multiplicative lever), on par with the wedge streak.
	return 15


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
	mod.description = "×streak multiplier per consecutive %s hit (per %s)" % [color_name.to_lower(), scope_name]

	return mod
