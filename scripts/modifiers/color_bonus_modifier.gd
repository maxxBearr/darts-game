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
		var old_multiplier: int = result["multiplier"]
		result["multiplier"] += bonus_multiplier
		result["total_score"] = result["face_value"] * result["multiplier"]
		_track_modification(result, "multiplier", old_multiplier, result["multiplier"])
	return result
