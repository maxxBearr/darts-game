class_name LevelClearedCondition
extends UnlockCondition
## Unlock condition that requires a specific level to have been cleared.
## Used for gating higher levels behind lower-level completions.

## Resource path of the LevelDefinition that must be cleared.
@export var required_level_path: String = ""


func is_satisfied(_event_name: StringName, _context: Dictionary) -> bool:
	return PlayerProgress.is_level_cleared(required_level_path)
