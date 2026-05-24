class_name UnlockCondition
extends Resource
## Base class for dart component unlock conditions. Subclass this and override
## is_satisfied() to define a new unlock trigger.

## Player-facing hint shown on locked components in the assembly screen.
@export_multiline var description: String = ""


## Override in subclasses. Return true if the condition is met.
func is_satisfied(_event_name: StringName, _context: Dictionary) -> bool:
	return false
