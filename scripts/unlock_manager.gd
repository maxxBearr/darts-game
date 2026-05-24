extends Node
## Central unlock coordinator. Listens for game events, evaluates each locked
## component's UnlockCondition, and grants unlocks via PlayerProgress.

var _legs_won_this_run: int = 0
var _run_flags: Dictionary = {}
var _items_acquired_this_shop: int = 0

var registry: DartComponentRegistry


## Assign the registry so we can walk locked components.
func bind_registry(r: DartComponentRegistry) -> void:
	registry = r


## Called by main.gd when is_leg_won == true.
func on_leg_won(leg_context: Dictionary) -> void:
	_legs_won_this_run += 1
	PlayerProgress.increment_stat(&"legs_won", 1)

	var checkout_total: int = leg_context.get("checkout_total", 0)
	if checkout_total > 0:
		PlayerProgress.set_stat_max(&"max_checkout_ever", checkout_total)

	var context: Dictionary = leg_context.duplicate()
	context["legs_won_this_run"] = _legs_won_this_run

	_evaluate(&"leg_won", context)


## Called when the player acquires any item (modifier or component).
func on_item_acquired(item_context: Dictionary) -> void:
	_items_acquired_this_shop += 1

	var rarity: int = item_context.get("rarity", ScoringEnums.Rarity.COMMON)
	if rarity != ScoringEnums.Rarity.COMMON:
		_run_flags[&"only_commons_acquired_this_run"] = false

	_evaluate(&"item_acquired", item_context)


## Called when the shop opens.
func on_shop_opened() -> void:
	_items_acquired_this_shop = 0


## Called when the shop closes.
func on_shop_closed() -> void:
	var context: Dictionary = {
		"items_acquired_this_shop": _items_acquired_this_shop,
	}
	_evaluate(&"shop_closed", context)


## Called when streak slot state or modifier slot state changes.
func on_slots_state_changed(slot_context: Dictionary) -> void:
	_evaluate(&"slots_state_changed", slot_context)


## Called by main.gd at the start of every run.
func on_run_started() -> void:
	_legs_won_this_run = 0
	_run_flags.clear()
	_run_flags[&"only_commons_acquired_this_run"] = true


## Read a run-scoped flag. Returns false if never set.
func get_run_flag(flag_name: StringName) -> bool:
	return _run_flags.get(flag_name, false)


func _evaluate(event_name: StringName, context: Dictionary) -> void:
	if registry == null:
		return

	var locked: Array[DartComponent] = registry.get_locked_components()
	for component: DartComponent in locked:
		if component.unlock_condition == null:
			continue
		if component.unlock_condition.is_satisfied(event_name, context):
			PlayerProgress.unlock(component)
