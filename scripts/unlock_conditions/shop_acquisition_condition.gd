class_name ShopAcquisitionCondition
extends UnlockCondition
## Triggered on shop_closed. Checks how many items the player acquired during
## the just-closed shop visit.

@export var min_items_acquired: int = 1


func is_satisfied(event_name: StringName, context: Dictionary) -> bool:
	if event_name != &"shop_closed":
		return false
	var count: int = context.get("items_acquired_this_shop", 0)
	return count >= min_items_acquired
