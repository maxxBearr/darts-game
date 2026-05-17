Upgrade System Spec for Claude Code

OVERVIEW:
After winning a leg, the player chooses 1 of 3 randomly generated stat upgrades before advancing. 6 upgrade types exist: 4 are pure buffs, 2 are tradeoffs. All 3 offered upgrades must be distinct stat types.

CODING CONVENTIONS:

Static typing on ALL variables
Frequent comments explaining logic
## doc comments on all @export vars
@export vars wherever useful for developer tweaking


STARTING STAT VALUES (update defaults in throw_mechanic.gd):
Leave these unchanged:

aim_accuracy = 20.0
vertical_accuracy = 10.0
vertical_speed = 3.0
horizontal_speed = 3.0

Update these to start worse (lower = bigger variance zone = less accurate):

vertical_consistency = 20.0 (was 50.0)
horizontal_consistency = 20.0 (was 50.0)


UPGRADE TYPE DEFINITIONS (in main.gd):
gdscriptconst UPGRADE_TYPES: Array[Dictionary] = [
    {
        "name": "Aim Accuracy",
        "property": "aim_accuracy",
        "scale": "direct",
        "tradeoff": false,
    },
    {
        "name": "Vertical Accuracy",
        "property": "vertical_accuracy",
        "scale": "direct",
        "tradeoff": false,
    },
    {
        "name": "Vertical Speed",
        "property": "vertical_speed",
        "scale": "speed",
        "tradeoff": false,
    },
    {
        "name": "Horizontal Speed",
        "property": "horizontal_speed",
        "scale": "speed",
        "tradeoff": false,
    },
    {
        "name": "Vertical Consistency",
        "property": "vertical_consistency",
        "scale": "direct",
        "tradeoff": true,
        "penalty_property": "horizontal_consistency",
        "penalty_name": "Horizontal Consistency",
        "penalty_amount": 3,
    },
    {
        "name": "Horizontal Consistency",
        "property": "horizontal_consistency",
        "scale": "direct",
        "tradeoff": true,
        "penalty_property": "vertical_consistency",
        "penalty_name": "Vertical Consistency",
        "penalty_amount": 3,
    },
]

RARITY TABLE:
For standard stats (Aim Accuracy, Vertical Accuracy, Vertical Consistency, Horizontal Consistency):
gdscriptconst STANDARD_RARITY_TABLE: Array[Dictionary] = [
    {"name": "Common", "min_value": 5, "max_value": 8, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
    {"name": "Uncommon", "min_value": 9, "max_value": 12, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
    {"name": "Rare", "min_value": 13, "max_value": 15, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]
For speed stats (Vertical Speed, Horizontal Speed):
gdscriptconst SPEED_RARITY_TABLE: Array[Dictionary] = [
    {"name": "Common", "min_value": 2, "max_value": 4, "weight": 65, "color": Color(0.6, 0.6, 0.6)},
    {"name": "Uncommon", "min_value": 5, "max_value": 7, "weight": 25, "color": Color(0.3, 0.5, 1.0)},
    {"name": "Rare", "min_value": 8, "max_value": 10, "weight": 10, "color": Color(0.7, 0.3, 0.9)},
]
Use SPEED_RARITY_TABLE when the upgrade type's scale == "speed", otherwise use STANDARD_RARITY_TABLE.

RARITY DISTRIBUTION (same for all 6 types):
Roll randi_range(1, 100): if <= 65 → Common, elif <= 90 → Uncommon, else → Rare.

GENERATION LOGIC (_generate_upgrades() -> Array[Dictionary]):

Create an array of indices [0, 1, 2, 3, 4, 5] representing the 6 upgrade types
Shuffle the array
Take the first 3 — these are the 3 distinct upgrade types offered
For each:

Look up the upgrade type from UPGRADE_TYPES
Select the rarity table: SPEED_RARITY_TABLE if scale == "speed", else STANDARD_RARITY_TABLE
Roll rarity using weighted random
Roll value using randi_range(rarity.min_value, rarity.max_value)
Build the upgrade dictionary:



gdscript{
    "name": upgrade_type["name"],
    "property": upgrade_type["property"],
    "scale": upgrade_type["scale"],
    "rarity": rarity["name"],
    "color": rarity["color"],
    "value": rolled_value,
    "tradeoff": upgrade_type["tradeoff"],
    "penalty_property": upgrade_type.get("penalty_property", ""),
    "penalty_name": upgrade_type.get("penalty_name", ""),
    "penalty_amount": upgrade_type.get("penalty_amount", 0),
}

APPLY LOGIC (_apply_upgrade(upgrade: Dictionary) -> void):
gdscriptfunc _apply_upgrade(upgrade: Dictionary) -> void:
    # Apply the main boost
    if upgrade["scale"] == "direct":
        var current: float = throw_mechanic.get(upgrade["property"])
        var new_value: float = minf(current + float(upgrade["value"]), 100.0)
        throw_mechanic.set(upgrade["property"], new_value)
    elif upgrade["scale"] == "speed":
        var internal_boost: float = float(upgrade["value"]) * (4.0 / 15.0)
        var current: float = throw_mechanic.get(upgrade["property"])
        var new_value: float = minf(current + internal_boost, 5.0)
        throw_mechanic.set(upgrade["property"], new_value)

    # Apply tradeoff penalty if applicable
    if upgrade["tradeoff"]:
        var penalty_current: float = throw_mechanic.get(upgrade["penalty_property"])
        var new_penalty_value: float = penalty_current - float(upgrade["penalty_amount"])
        throw_mechanic.set(upgrade["penalty_property"], new_penalty_value)
No floor clamping on the penalty for now.

BASE STAT SNAPSHOT (in main.gd):
New state vars:
gdscriptvar _base_aim_accuracy: float = 0.0
var _base_vertical_accuracy: float = 0.0
var _base_vertical_consistency: float = 0.0
var _base_horizontal_consistency: float = 0.0
var _base_vertical_speed: float = 0.0
var _base_horizontal_speed: float = 0.0
_snapshot_base_stats() -> void:

Save all 6 stats from throw_mechanic into the _base_* vars
Called once in _ready() after everything is initialized

_restore_base_stats() -> void:

Restore all 6 stats on throw_mechanic from the _base_* vars
Called in _on_new_run() before x01_game.start_run()


UPGRADE FLOW IN main.gd:
When response["is_leg_won"] is true in _on_throw_completed:

Generate upgrades: _current_upgrades = _generate_upgrades()
Call hud.show_leg_complete_with_upgrades(response["current_leg"], response["target_score"], response["current_turn"], _current_upgrades)
Set _awaiting_next_leg = true

_on_upgrade_selected(index: int) callback:

Call _apply_upgrade(_current_upgrades[index])
HUD hides upgrade cards, shows NextLegButton

_on_next_leg() callback:

Proceeds as before (clear darts, advance leg, start throwing)


HUD CHANGES (scripts/hud.gd):
New signal:

upgrade_selected(index: int)

New nodes (children of HUD CanvasLayer):

UpgradeContainer: HBoxContainer — holds the 3 upgrade buttons, hidden by default
UpgradeButton1: Button — child of UpgradeContainer
UpgradeButton2: Button — child of UpgradeContainer
UpgradeButton3: Button — child of UpgradeContainer

show_leg_complete_with_upgrades(leg: int, target: int, turns_used: int, upgrades: Array[Dictionary]) -> void:

Show leg complete message in ScoreLabel
For each of the 3 upgrade buttons, set the text:

For pure buff stats: "[Rarity]\n[Name]\n+[Value]"
For tradeoff stats: "[Rarity]\n[Name]\n+[Value]\n-[Penalty Amount] [Penalty Name]"


Set button text color or modulate to the rarity color
For tradeoff stats, ideally the penalty line is red (Color(0.9, 0.2, 0.2)). If styling individual lines within a Button is too complex, append the penalty text and accept uniform coloring for now — visual polish can come later.
Show UpgradeContainer
Hide NextLegButton (player must pick an upgrade first)

Upgrade button callbacks:

UpgradeButton1 pressed → upgrade_selected.emit(0)
UpgradeButton2 pressed → upgrade_selected.emit(1)
UpgradeButton3 pressed → upgrade_selected.emit(2)
After emitting: hide UpgradeContainer, show NextLegButton

_ready() additions:

Connect all 3 upgrade buttons
Hide UpgradeContainer


SCENE TREE ADDITIONS:
HUD (CanvasLayer)
├── ... (existing nodes)
├── UpgradeContainer (HBoxContainer)
│   ├── UpgradeButton1 (Button)
│   ├── UpgradeButton2 (Button)
│   └── UpgradeButton3 (Button)

NO CHANGES to: dartboard.gd, throw_mechanic.gd (other than the starting value changes noted above), dart_marker.gd, x01_game.gd