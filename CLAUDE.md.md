Upgrade System Spec for Claude Code

OVERVIEW:
After winning a leg, before advancing to the next leg, the player is presented with 3 upgrade cards. Each card boosts one of 4 throw stats by a random amount determined by rarity. Player picks one, it's applied, then the next leg begins. All 3 cards must be distinct stats (no duplicates in a single offering).

UPGRADE TYPES (4 total):
Display NameThrowMechanic PropertyScaleCapAim Accuracyaim_accuracy1-100100Vertical Accuracyvertical_accuracy1-100100Release Accuracyrelease_accuracy1-100100Release Controlrelease_speed1.0-5.05.0
Release Control scaling: The displayed value uses the same 5-15 integer range as other stats, but internally maps to the 1.0-5.0 scale. Conversion: internal_boost = displayed_value * (4.0 / 15.0) — so a displayed +15 gives roughly +4.0 internal, and a displayed +5 gives roughly +1.33. This keeps the player-facing numbers consistent across all upgrade types. Apply with throw_mechanic.release_speed = minf(throw_mechanic.release_speed + internal_boost, 5.0).
RARITY TIERS:
RarityValue RangeProbabilityDisplay ColorCommon5-865%Grey (Color(0.6, 0.6, 0.6))Uncommon9-1225%Blue (Color(0.3, 0.5, 1.0))Rare13-1510%Purple (Color(0.7, 0.3, 0.9))
Each of the 3 cards rolls its rarity independently. Value is rolled uniformly within the rarity's range using randi_range().

GENERATION LOGIC (in main.gd):
New constants:
gdscriptconst UPGRADE_TYPES: Array[Dictionary] = [
    {"name": "Aim Accuracy", "property": "aim_accuracy", "scale": "direct"},
    {"name": "Vertical Accuracy", "property": "vertical_accuracy", "scale": "direct"},
    {"name": "Release Accuracy", "property": "release_accuracy", "scale": "direct"},
    {"name": "Release Control", "property": "release_speed", "scale": "speed"},
]

const RARITY_TABLE: Array[Dictionary] = [
    {"name": "Common", "min_value": 5, "max_value": 8, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
    {"name": "Uncommon", "min_value": 9, "max_value": 12, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
    {"name": "Rare", "min_value": 13, "max_value": 15, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]
New state vars:
gdscriptvar _base_aim_accuracy: float = 0.0
var _base_vertical_accuracy: float = 0.0
var _base_release_accuracy: float = 0.0
var _base_release_speed: float = 0.0
var _current_upgrades: Array[Dictionary] = []  ## The 3 generated upgrade choices
New method _snapshot_base_stats() -> void:

Called at start of run. Saves throw_mechanic.aim_accuracy, throw_mechanic.vertical_accuracy, throw_mechanic.release_accuracy, throw_mechanic.release_speed into the _base_* vars.

New method _restore_base_stats() -> void:

Called on new run. Restores throw_mechanic properties from _base_* vars.

New method _generate_upgrades() -> Array[Dictionary]:

Shuffle or randomly sample 3 distinct indices from UPGRADE_TYPES (4 types, pick 3, no repeats)
For each, roll rarity using weighted random: generate randi_range(1, 100), if <= 65 → Common, elif <= 90 → Uncommon, else → Rare
Roll value using randi_range(rarity.min_value, rarity.max_value)
Return array of 3 dictionaries, each containing:

gdscript{
    "name": upgrade_type["name"],          # "Aim Accuracy"
    "property": upgrade_type["property"],  # "aim_accuracy"
    "scale": upgrade_type["scale"],        # "direct" or "speed"
    "rarity": rarity["name"],              # "Uncommon"
    "color": rarity["color"],              # Color(0.3, 0.5, 1.0)
    "value": rolled_value,                 # 11
}
New method _apply_upgrade(upgrade: Dictionary) -> void:

If upgrade["scale"] == "direct": get current value from throw_mechanic.get(upgrade["property"]), add upgrade["value"], clamp to 100.0, set back with throw_mechanic.set(upgrade["property"], clamped_value)
If upgrade["scale"] == "speed": convert displayed value to internal: internal_boost = float(upgrade["value"]) * (4.0 / 15.0). Get current throw_mechanic.release_speed, add internal_boost, clamp to 5.0, set back.


FLOW CHANGES IN main.gd:
_on_new_run() changes:

Call _restore_base_stats() before x01_game.start_run()

_ready() changes:

Call _snapshot_base_stats() at the end, after everything is initialized
Connect new HUD signal: upgrade_selected (passes index int)

Leg-won flow change:

When response["is_leg_won"] is true in _on_throw_completed:

Generate upgrades: _current_upgrades = _generate_upgrades()
Show leg complete message AND upgrade choices: hud.show_leg_complete_with_upgrades(response["current_leg"], response["target_score"], response["current_turn"], _current_upgrades)
Set _awaiting_next_leg = true
Do NOT show NextLegButton yet — player must pick an upgrade first



New callback _on_upgrade_selected(index: int) -> void:

_apply_upgrade(_current_upgrades[index])
Then show NextLegButton (or auto-advance to next leg, whichever — I'd say show the button so they see the result of their choice briefly)
Update HUD to reflect new stat values if you want (optional for now)


HUD CHANGES (scripts/hud.gd):
New signal:

upgrade_selected(index: int)

New nodes (children of HUD CanvasLayer):

UpgradeContainer: HBoxContainer — holds the 3 upgrade buttons side by side, hidden by default
UpgradeButton1: Button — child of UpgradeContainer
UpgradeButton2: Button — child of UpgradeContainer
UpgradeButton3: Button — child of UpgradeContainer

New method show_leg_complete_with_upgrades(leg: int, target: int, turns_used: int, upgrades: Array[Dictionary]) -> void:

Show leg complete message (same as before)
Populate upgrade buttons with text and color from the upgrades array
Button text format: "[Rarity]\n[Name]\n+[Value]" — e.g. "Uncommon\nAim Accuracy\n+11"
Set each button's font color or modulate to the rarity color
Show UpgradeContainer, hide NextLegButton

Button callbacks:

Each upgrade button emits upgrade_selected.emit(index) where index is 0, 1, or 2
After an upgrade is selected: hide UpgradeContainer, show NextLegButton

_ready() changes:

Connect upgrade button signals
Hide UpgradeContainer initially


SCENE TREE ADDITIONS:
HUD (CanvasLayer)
├── ... (existing nodes)
├── UpgradeContainer (HBoxContainer)
│   ├── UpgradeButton1 (Button)
│   ├── UpgradeButton2 (Button)
│   └── UpgradeButton3 (Button)

NO CHANGES to: dartboard.gd, throw_mechanic.gd, dart_marker.gd, x01_game.gd