---
Spec date: 2026-05-21
Status: Shipped 2026-05-21 — uncommitted on branch `streak-item-system`, pending playtest
Implementation: Claude Code (run by Max during the same Cowork session that wrote this spec)
Notes: All spec items were implemented. Pool weights for ColorStreak / ParityStreak
       (both set to 15) may need tuning after playtest. Streak slot UI behavior should
       be sanity-checked during real runs. Update this status if playtest surfaces
       partial-ship or revisit decisions, and link to any follow-up spec.
---

# Streak Slot Restriction System & New Streak Modifiers

## Overview

Add two new streak modifier types (Color Streak, Even/Odd Streak) alongside the existing Wedge Streak. Introduce a **one-per-category** slot restriction so the player can only have one streak modifier equipped from each of the three categories. When a new streak modifier would conflict with an existing one, the modifier pick card shows a "Would replace: [existing modifier name]" warning, and selecting it automatically swaps the old one out.

Non-streak modifiers (ColorBonusModifier, OddEvenBonusModifier, WedgeValueModifier, WedgeSwapModifier, ColorFlipModifier) are **unaffected** — players can stack as many of those as they want.

---

## Coding Conventions

- Static typing on ALL variables
- Frequent commenting for readability
- `##` doc comments on all `@export` vars describing what they do and what values mean
- `@export` vars liberally for developer control

---

## Streak Categories

Add a new enum to `scoring_enums.gd`:

```gdscript
## Which streak slot category a streak modifier belongs to.
## Only one streak modifier per category can be equipped at a time.
enum StreakCategory {
	NONE,    ## Not a streak modifier — no slot restriction
	WEDGE,   ## Wedge-based streaks (same ring, adjacent, whole wedge)
	COLOR,   ## Color-based streaks (consecutive same-color hits)
	PARITY,  ## Even/odd-based streaks (consecutive same-parity hits)
}
```

---

## Base Class Changes

### `scoring_modifier.gd`

Add a streak category property so the slot system can identify which category a modifier belongs to:

```gdscript
## Which streak slot category this modifier occupies.
## NONE means no slot restriction (non-streak modifiers).
## Streak modifiers set this to their category so the one-per-category rule can be enforced.
@export var streak_category: ScoringEnums.StreakCategory = ScoringEnums.StreakCategory.NONE
```

Also add a base method for getting streak count (for tooltip display). Subclasses override this:

```gdscript
## Get the current streak count for display purposes.
## Override in streak modifier subclasses. Returns 0 for non-streak modifiers.
func get_streak_count() -> int:
	return 0

## Get a short display name for what this streak tracks (e.g., "Ring ×3").
## Override in streak modifier subclasses. Returns "" for non-streak modifiers.
func get_streak_display() -> String:
	return ""
```

---

## Existing Modifier Update

### `streak_bonus_modifier.gd`

Set the streak category in `_init()`:

```gdscript
func _init() -> void:
	modifier_name = "Wedge Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.WEDGE  # <-- Add this line
```

Add the streak display getter (the `get_streak_count()` getter uses the existing `_streak_count` var):

```gdscript
func get_streak_count() -> int:
	return _streak_count

func get_streak_display() -> String:
	if _streak_count <= 0:
		return ""
	var leniency_label: String = ""
	match leniency:
		ScoringEnums.StreakLeniency.SAME_RING:
			leniency_label = "Ring"
		ScoringEnums.StreakLeniency.ADJACENT_SECTIONS:
			leniency_label = "Adj"
		ScoringEnums.StreakLeniency.WHOLE_WEDGE:
			leniency_label = "Wedge"
	return "%s ×%d" % [leniency_label, _streak_count]
```

No other changes to existing wedge streak logic.

---

## New Modifier: ColorStreakModifier

### File: `res://scripts/modifiers/color_streak_modifier.gd`

```gdscript
class_name ColorStreakModifier
extends ScoringModifier
## Awards cumulative +1x multiplier per consecutive hit on the same segment color.
## First qualifying hit scores normally. Second consecutive gets +1x. Third gets +2x. Etc.
## Tracks which SegmentColor was last hit to maintain the streak.

## The last segment color that was hit (for streak continuity checks).
var _streak_color: int = -1

## Current number of consecutive same-color hits.
var _streak_count: int = 0


func _init() -> void:
	modifier_name = "Color Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.COLOR


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var segment_color: int = result.get("segment_color", -1)

	# No color info (off board, etc.) — break the streak
	if segment_color < 0:
		if not is_preview:
			_reset_streak()
		return result

	# Calculate what the streak would be
	var effective_count: int = _streak_count
	if segment_color == _streak_color:
		effective_count += 1
	else:
		effective_count = 1

	# Update state only for real throws
	if not is_preview:
		_streak_count = effective_count
		_streak_color = segment_color

	# Apply bonus: streak count - 1 extra multipliers
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


func _reset_streak() -> void:
	_streak_color = -1
	_streak_count = 0


func reset_streak_state() -> void:
	_reset_streak()


func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	if _streak_count <= 0:
		return ""
	return "Color ×%d" % _streak_count


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> ColorStreakModifier:
	var mod: ColorStreakModifier = ColorStreakModifier.new()
	mod.rarity_tier = rarity_tier

	# Roll streak scope
	var scopes: Array[ScoringEnums.StreakScope] = [
		ScoringEnums.StreakScope.WITHIN_TURN,
		ScoringEnums.StreakScope.WITHIN_LEG,
	]
	mod.streak_scope = scopes[randi_range(0, scopes.size() - 1)]

	var scope_name: String = "turn" if mod.streak_scope == ScoringEnums.StreakScope.WITHIN_TURN else "leg"

	# All rarities have the same mechanical effect for now
	mod.modifier_name = "Color Streak"
	mod.description = "+1x per consecutive same-color hit (per %s)" % scope_name

	return mod
```

---

## New Modifier: ParityStreakModifier

### File: `res://scripts/modifiers/parity_streak_modifier.gd`

```gdscript
class_name ParityStreakModifier
extends ScoringModifier
## Awards cumulative +1x multiplier per consecutive hit on wedges sharing the same
## parity (all odd or all even face values). First qualifying hit scores normally.
## Second consecutive gets +1x. Third gets +2x. Etc.

## Whether the current streak is tracking odd (true) or even (false).
## Determined by the first hit in a new streak.
var _streak_is_odd: bool = false

## Current number of consecutive same-parity hits.
var _streak_count: int = 0

## Whether a streak is actively being tracked (false at start / after reset).
var _streak_active: bool = false


func _init() -> void:
	modifier_name = "Parity Streak"
	timing = ScoringEnums.ModifierTiming.PER_DART
	config_type = ScoringEnums.ConfigType.NONE
	streak_category = ScoringEnums.StreakCategory.PARITY


func apply(result: Dictionary, context: Dictionary) -> Dictionary:
	var is_preview: bool = context.get("is_preview", false)
	var face_value: int = result.get("face_value", 0)

	# No face value (off board, bull with 25 is odd — that's fine)
	if face_value <= 0:
		if not is_preview:
			_reset_streak()
		return result

	var is_odd: bool = face_value % 2 == 1

	# Calculate what the streak would be
	var effective_count: int = _streak_count
	if not _streak_active:
		# First hit starts a new streak
		effective_count = 1
	elif is_odd == _streak_is_odd:
		# Same parity — continue streak
		effective_count += 1
	else:
		# Different parity — break and restart
		effective_count = 1

	# Update state only for real throws
	if not is_preview:
		_streak_count = effective_count
		_streak_is_odd = is_odd
		_streak_active = true

	# Apply bonus: streak count - 1 extra multipliers
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


func _reset_streak() -> void:
	_streak_is_odd = false
	_streak_count = 0
	_streak_active = false


func reset_streak_state() -> void:
	_reset_streak()


func get_streak_count() -> int:
	return _streak_count


func get_streak_display() -> String:
	if _streak_count <= 0:
		return ""
	var parity_label: String = "Odd" if _streak_is_odd else "Even"
	return "%s ×%d" % [parity_label, _streak_count]


static func get_pool_weight() -> int:
	return 15


static func get_rarity_weights() -> Array[int]:
	return [50, 30, 20]


static func generate(rarity_tier: ScoringEnums.Rarity) -> ParityStreakModifier:
	var mod: ParityStreakModifier = ParityStreakModifier.new()
	mod.rarity_tier = rarity_tier

	# Roll streak scope
	var scopes: Array[ScoringEnums.StreakScope] = [
		ScoringEnums.StreakScope.WITHIN_TURN,
		ScoringEnums.StreakScope.WITHIN_LEG,
	]
	mod.streak_scope = scopes[randi_range(0, scopes.size() - 1)]

	var scope_name: String = "turn" if mod.streak_scope == ScoringEnums.StreakScope.WITHIN_TURN else "leg"

	# All rarities have the same mechanical effect for now
	mod.modifier_name = "Parity Streak"
	mod.description = "+1x per consecutive same-parity hit (per %s)" % scope_name

	return mod
```

---

## Slot Restriction System

### `scoring_modifier_manager.gd` Changes

Add a method to check for streak category conflicts and handle replacement:

```gdscript
## Check if adding a modifier would replace an existing streak modifier.
## Returns the existing modifier that would be replaced, or null if no conflict.
func get_streak_conflict(new_modifier: ScoringModifier) -> ScoringModifier:
	if new_modifier.streak_category == ScoringEnums.StreakCategory.NONE:
		return null
	for existing: Resource in active_modifiers:
		if existing.streak_category == new_modifier.streak_category:
			return existing
	return null


## Remove a specific modifier from the active list.
## Used when a streak modifier is being replaced by a new one in the same category.
func remove_modifier(modifier: Resource) -> void:
	var idx: int = active_modifiers.find(modifier)
	if idx >= 0:
		active_modifiers.remove_at(idx)
```

Modify `add_modifier()` to automatically handle streak replacement:

```gdscript
## Register a new modifier. For ON_ACQUIRE modifiers, immediately applies
## board-state changes. config is a Dictionary with modifier-specific settings.
## If the modifier has a streak category that conflicts with an existing modifier,
## the existing one is removed first (replacement).
## Returns the replaced modifier, or null if no replacement occurred.
func add_modifier(modifier: Resource, config: Dictionary) -> Resource:
	# Check for streak slot conflict and remove the existing one
	var replaced: Resource = null
	if modifier is ScoringModifier:
		var conflict: ScoringModifier = get_streak_conflict(modifier as ScoringModifier)
		if conflict != null:
			remove_modifier(conflict)
			replaced = conflict

	active_modifiers.append(modifier)

	# If this is an ON_ACQUIRE modifier, apply its board-state changes now
	if modifier.timing == ScoringEnums.ModifierTiming.ON_ACQUIRE:
		modifier.apply_to_board(effective_wedge_values, effective_wedge_colors, config)

	return replaced
```

**Note:** The return type changes from `void` to `Resource` (returns the replaced modifier or null). All existing call sites in `main.gd` that call `add_modifier()` will need to handle the return value — they can simply ignore it if they don't need it, since the replacement is automatic. However, `main.gd`'s `add_scoring_modifier()` wrapper should use the return value to update the HUD panel (remove the old square, add the new one).

---

## HUD Changes

### Modifier Pick Card: "Would Replace" Warning

When displaying modifier choices, check each offered modifier for streak conflicts with currently equipped modifiers. If a conflict exists, append a warning line to the card text.

In `main.gd`, modify `_on_modifier_selected()` flow — but actually the conflict info needs to be surfaced earlier, during `show_modifier_choices()`. The cleanest approach:

**In `main.gd`, when building the modifier choice display:**

```gdscript
## Player picks an accuracy upgrade card — move to modifier pick phase.
func _on_upgrade_selected(index: int) -> void:
	_apply_upgrade(_current_upgrades[index])
	_update_stats_display()

	_leg_phase = "modifier_pick"
	_current_modifiers = []
	var generated: Array[ScoringModifier] = ModifierRegistry.generate_distinct(3)
	for mod: ScoringModifier in generated:
		_current_modifiers.append(mod)

	# Build replacement info for each modifier choice
	var replacement_info: Array[String] = []
	for mod: ScoringModifier in _current_modifiers:
		var conflict: ScoringModifier = scoring_modifier_manager.get_streak_conflict(mod)
		if conflict != null:
			replacement_info.append("Replaces: %s" % conflict.modifier_name)
		else:
			replacement_info.append("")

	hud.show_modifier_choices_with_replacement(_current_modifiers, replacement_info)
```

**In `hud.gd`, add a new display function (or modify the existing one):**

```gdscript
## Show 3 modifier cards with optional replacement warnings.
## replacement_info is an Array[String] of length 3. Empty string = no warning.
## Non-empty string = warning text shown on the card (e.g., "Replaces: Wedge Streak").
func show_modifier_choices_with_replacement(modifiers: Array, replacement_info: Array[String]) -> void:
	_modifier_mode = true
	score_label.text = "Choose a scoring modifier!"
	var buttons: Array[Button] = [upgrade_button_1, upgrade_button_2, upgrade_button_3]
	for i: int in range(3):
		var modifier: Resource = modifiers[i]
		var button_text: String = "%s\n%s\n%s" % [modifier.rarity, modifier.modifier_name, modifier.description]
		if replacement_info[i] != "":
			button_text += "\n⚠ %s" % replacement_info[i]
		buttons[i].text = button_text
		var color: Color = modifier.rarity_color
		buttons[i].self_modulate = Color(color.r, color.g, color.b, 1.0)
		buttons[i].tooltip_text = modifier.description
	upgrade_container.visible = true
	next_leg_button.visible = false
```

The existing `show_modifier_choices()` can remain for backward compatibility or be replaced entirely — either approach works. The debug start-of-game modifier pick also needs to use the replacement-aware version.

### Modifier Panel: Swap Visual

When a streak modifier is replaced, the old modifier's square needs to be removed from the HUD panel and the new one added. Update `main.gd`'s `add_scoring_modifier()`:

```gdscript
## Add a scoring modifier to the game. Handles replacement, manager, and HUD panel.
func add_scoring_modifier(modifier: Resource, config: Dictionary) -> void:
	var replaced: Resource = scoring_modifier_manager.add_modifier(modifier, config)

	# If a modifier was replaced, remove its panel square
	if replaced != null:
		hud.remove_modifier_from_panel(replaced)

	hud.add_modifier_to_panel(modifier)
	_sync_board_state()
	_update_checkout_highlights()
```

**In `hud.gd`, add the removal function:**

```gdscript
## Remove a modifier square from the panel by matching the modifier reference.
## Called when a streak modifier is replaced by a new one in the same category.
func remove_modifier_from_panel(modifier: Resource) -> void:
	for child: Node in modifier_panel.get_children():
		if child.has_meta("modifier") and child.get_meta("modifier") == modifier:
			child.queue_free()
			break
```

---

## Modifier Registry Changes

### `modifier_registry.gd`

Add the two new modifier types to the registry:

```gdscript
const _ColorStreak = preload("res://scripts/modifiers/color_streak_modifier.gd")
const _ParityStreak = preload("res://scripts/modifiers/parity_streak_modifier.gd")

const MODIFIER_TYPES: Array = [
	_ColorBonus,
	_WedgeValue,
	_StreakBonus,
	_WedgeSwap,
	_OddEvenBonus,
	_ColorFlip,
	_ColorStreak,    # <-- New
	_ParityStreak,   # <-- New
]
```

No other changes needed — the existing weighted random selection and `generate_distinct()` logic automatically incorporates new types via their `get_pool_weight()` values.

### Pool Weight Tuning

All three streak types have `get_pool_weight() -> int: return 15`. This means each streak type has roughly equal chance of appearing relative to each other. Compared to the existing modifiers:

- ColorBonus: 30 (most common)
- OddEvenBonus: 25
- WedgeValue: weight from its class (check existing)
- WedgeSwap: weight from its class (check existing)
- ColorFlip: weight from its class (check existing)
- StreakBonus (Wedge): 15
- ColorStreak: 15
- ParityStreak: 15

This gives streak modifiers moderate representation. The weights are all defined as static functions on each class, so they can be tuned independently via code without touching any config files. In the future when a shop exists, these weights become shop stock probabilities.

---

## Streak Reset Behavior

The new streak modifiers follow the same reset pattern as the existing wedge streak:

- Both `ColorStreakModifier` and `ParityStreakModifier` implement `reset_streak_state()`.
- `ScoringModifierManager._reset_modifier_streaks(scope)` already iterates all active modifiers and calls `reset_streak_state()` on those matching the given scope. This works automatically for the new types since they set `streak_scope` during generation.
- `WITHIN_TURN` streaks reset at the start of each new turn.
- `WITHIN_LEG` streaks reset at the start of each new leg.

No changes needed to the reset logic in `scoring_modifier_manager.gd` — it's already generic.

---

## Files Affected

### New Files
- `res://scripts/modifiers/color_streak_modifier.gd` — ColorStreakModifier class (full implementation above)
- `res://scripts/modifiers/parity_streak_modifier.gd` — ParityStreakModifier class (full implementation above)

### `scoring_enums.gd` — Minor addition
- Add `StreakCategory` enum (NONE, WEDGE, COLOR, PARITY)

### `scoring_modifier.gd` — Minor additions
- Add `streak_category` export var (default NONE)
- Add `get_streak_count()` base method (returns 0)
- Add `get_streak_display()` base method (returns "")

### `streak_bonus_modifier.gd` — Minor additions
- Set `streak_category = ScoringEnums.StreakCategory.WEDGE` in `_init()`
- Add `get_streak_count()` override
- Add `get_streak_display()` override

### `scoring_modifier_manager.gd` — Moderate changes
- Add `get_streak_conflict()` method
- Add `remove_modifier()` method
- Modify `add_modifier()` to handle streak replacement and return replaced modifier
- **Return type of `add_modifier()` changes from `void` to `Resource`** — all call sites must be checked

### `modifier_registry.gd` — Minor addition
- Add `_ColorStreak` and `_ParityStreak` to `MODIFIER_TYPES` array

### `main.gd` — Moderate changes
- Update `add_scoring_modifier()` to handle replacement return value and update HUD panel
- Update `_on_upgrade_selected()` to build replacement info for modifier cards
- Update `_on_modifier_selected()` — no logic change needed since `add_scoring_modifier` handles replacement automatically
- Update debug modifier pick flow to use replacement-aware display
- All other places that call `scoring_modifier_manager.add_modifier()` directly (check for any) need to handle the new return type

### `hud.gd` — Moderate changes
- Add `show_modifier_choices_with_replacement()` function (or modify existing `show_modifier_choices()`)
- Add `remove_modifier_from_panel()` function
- Existing `show_modifier_choices()` can remain as a backward-compatible wrapper that passes empty replacement strings

---

## Testing Checklist

- [ ] ColorStreakModifier awards +1x on second consecutive same-color hit
- [ ] ColorStreakModifier awards +2x on third consecutive same-color hit
- [ ] ColorStreakModifier resets when a different color is hit
- [ ] ParityStreakModifier awards +1x on second consecutive same-parity hit
- [ ] ParityStreakModifier tracks odd vs even correctly (bull = 25 = odd)
- [ ] ParityStreakModifier resets when parity changes
- [ ] Both new streaks respect streak_scope (WITHIN_TURN resets on new turn, WITHIN_LEG on new leg)
- [ ] Equipping a second wedge streak replaces the first
- [ ] Equipping a color streak when one exists replaces it
- [ ] Equipping a parity streak when one exists replaces it
- [ ] Non-streak modifiers are unaffected by slot restriction (can stack freely)
- [ ] Picking a streak modifier that conflicts shows "⚠ Replaces: [name]" on the card
- [ ] Picking a streak modifier with no conflict shows no warning
- [ ] Replaced modifier square is removed from HUD panel
- [ ] New modifier square appears in HUD panel after replacement
- [ ] Replaced modifier is fully removed from scoring pipeline (no ghost effects)
- [ ] Both new types appear in the modifier pool during post-leg picks
- [ ] Pool weights produce reasonable distribution (streaks aren't too dominant or too rare)
- [ ] Preview mode (hover tooltip) works correctly with new streak types
- [ ] `get_streak_count()` returns correct values for tooltip display
- [ ] `get_streak_display()` formats correctly for each streak type
- [ ] Streak info only appears in target tooltip when a streak modifier is equipped
- [ ] New run clears all streak modifiers and resets slots
