---
Spec date: 2026-05-28
Status: Shipped 2026-05-28
Implementation: Claude Code
Notes: All three fixes landed. Fix #2's pool-exhaustion path had a loop-counter bug — when reroll budget exhausted, the outer `for _n in range(count)` ticked without adding a result, so `generate_distinct` could return a short array and crash the hud at idx 2. Addressed in `specs/2026-05-28-late-game-crash-and-perf-diagnosis.md`.
---

# Pool Dedup + Skew Continuity Fix Pass

**Spec date:** 2026-05-28
**Previous spec:** `specs/2026-05-28-post-1001-playtest-bug-fixes.md` (shipped 2026-05-28).

## Summary

Three fixes from post-playtest notes:

| # | Fix | Type | Touch |
|---|---|---|---|
| 1 | Red-zone skew formula starts at orange→red transition value instead of resetting to 0 | Math | `dart_build.gd` |
| 2 | Modifier pools (shop + post-leg) exclude configs already owned by the player | New filter | `scoring_modifier.gd`, 9 modifier subclasses, `modifier_registry.gd`, `main.gd` |
| 3 | Shop's two offered picks dedup against each other (no identical slot-1 vs slot-2) | Same filter, second exclusion source | `main.gd::_generate_shop_picks`, `_generate_shop_accuracy_pick` |

Fixes 2 and 3 share the same fingerprint mechanism — different exclusion sources feeding one filter.

---

## 1. Skew continuity fix

### Root cause
`dart_build.gd::get_accuracy_skew()` (lines ~100–115) uses two different formulas:
- `orange_red` transition: flat `orange_red_transition_skew` (default **4.0 px**).
- `red`: `clampf(red_amount / max_red, 0.0, 1.0) * max_red_skew_pixels`, where `red_amount = abs_balance - orange_threshold`.

At the boundary, `red_amount ≈ 0`, so red zone returns **≈ 0 px**. Skew jumps 4 → 0 → 30 as balance drifts further. The label flips from "TRANSITION (skew: +4.0 px)" to "RED (skew: +0.0 px)" mid-drag, which reads as a bug.

### Fix
One-line lerp — red zone starts where the transition ended:

```gdscript
var red_amount: float = abs_balance - orange_threshold
var max_red: float = 3.0 - orange_threshold
var skew_fraction: float = clampf(red_amount / max_red, 0.0, 1.0)
var skew: float = lerp(orange_red_transition_skew, max_red_skew_pixels, skew_fraction)
return skew * signf(balance)
```

Result: orange_red holds at 4.0, red boundary starts at 4.0, red climbs to 30.0. Continuous and monotonic. No UI changes — `assembly_screen.gd::_refresh_balance` already reads `get_accuracy_skew()` for both zone labels.

### Acceptance
- Dragging balance from green into deep red, displayed skew never decreases.
- "RED (skew: +X)" label always shows X ≥ `orange_red_transition_skew`.
- Front-heavy and back-heavy sides behave symmetrically (sign flips, magnitude continuous).
- Regression check: green and green→orange zones still report no skew (formula unaffected; early-returns hit first).

---

## 2. Pool dedup against owned modifier configs

### Problem
`ModifierRegistry.generate_distinct_at_rarity` and `generate_distinct` only filter by *type* within a single batch and ignore the player's inventory. A player holding "Common Red Bonus (locked)" can be re-offered the same modifier in a shop slot or post-leg pick — wasted offering space.

### Identity — the "config fingerprint"
A modifier instance is fingerprinted by **(script class, `rarity_tier`, type-specific params, `toggleable`)**. So `Common Red Bonus (locked)` blocks a duplicate `Common Red Bonus (locked)`, but still allows:
- `Common Red Bonus (toggleable)` — different lock state.
- `Common Green Bonus (locked)` — different color.
- `Uncommon Red Bonus (locked)` — different rarity.

### Implementation

**`scoring_modifier.gd` — add virtual method:**

```gdscript
## Override in subclasses to append type-specific config dimensions.
## Base implementation captures class + rarity + lock state.
func get_config_fingerprint() -> String:
	return "%s|%d|%s" % [
		get_script().resource_path,
		rarity_tier,
		"L" if not toggleable else "T",
	]
```

**Each modifier subclass overrides** to append its randomized config. Examples:

- `ColorBonusModifier`: append `target_color` and `bonus_multiplier`.
- `WedgeValueModifier`: append `wedge_index` (and `value_delta` if randomized).
- `WedgeSwapModifier`: append the canonicalized swap pair (sorted so `(A,B)` == `(B,A)`).
- `ColorFlipModifier`: append source/target colors.
- `OddEvenBonusModifier`: append parity target.
- `StreakBonusModifier`, `ColorStreakModifier`, `EvenStreakModifier`, `OddStreakModifier`, `ParityStreakModifier`: append streak-specific config.

The string format is intentionally opaque — only equality matters.

**`modifier_registry.gd` — add owned-exclusion parameter:**

Both `generate_distinct_at_rarity` and `generate_distinct` take an optional `excluded_fingerprints: Array[String] = []`. After rolling a modifier, compute its fingerprint; if it's in the excluded set, reject and reroll. **Reroll budget: 8 attempts per slot** (ColorBonus alone has 4 colors × 2 lock states = 8 variants per rarity — more than enough headroom).

If the budget exhausts (player owns every config of the rolled type at the rolled rarity), **drop that type from `available_indices` for this slot and re-enter the type-roll loop**. If all types are exhausted, fall back to allowing a duplicate as graceful degradation. Practically unreachable in a single run.

**Lock-state handling (Q3 from design discussion):** Pure reject-reroll, no targeted lock flip. Preserves the 35/65 lock distribution per [[project-modifier-lock-system]]. Cheaper to implement and stays aligned with existing design philosophy.

**Caller wiring in `main.gd`:**

- `_generate_shop_picks` (line ~1075): collect fingerprints from `scoring_modifier_manager.modifiers`. Pass into the modifier roll.
- Post-leg modifier pick (lines ~1529 and ~1554): same — collect inventory fingerprints, pass into `generate_distinct`.

Add a small helper in `main.gd` (or `ScoringModifierManager`):
```gdscript
func get_owned_fingerprints() -> Array[String]:
    var result: Array[String] = []
    for mod: ScoringModifier in scoring_modifier_manager.modifiers:
        result.append(mod.get_config_fingerprint())
    return result
```

### Scope note on accuracy upgrades
Accuracy upgrades aren't modifiers and don't enter the modifier inventory — they're not part of *owned* dedup. They are part of intra-shop dedup (Fix 3).

### Acceptance
- Player holds `Common Red Bonus (locked)`. Across 20 common-tier shop offerings, the same fingerprint never appears.
- `Common Red Bonus (toggleable)` can still appear (different fingerprint).
- `Common Green Bonus (locked)` can still appear (different color).
- Regression: a fresh run with no modifiers shows the same diversity as before (no behavior change when exclusion list is empty).

---

## 3. Shop intra-batch dedup

### Problem
`_generate_shop_picks` calls `generate_distinct_at_rarity(1, ...)` twice in a loop (line ~1082–1091), each call independent. Two slots can land on the same modifier config. Same for accuracy upgrades: `_generate_shop_accuracy_pick` rolls a fresh `randi_range` each call.

### Fix
Thread a running "already-offered" exclusion set through the two-slot loop.

**Modifiers:** Same `excluded_fingerprints` parameter from Fix 2. After generating slot 1's modifier, append its fingerprint to the exclusion list passed into slot 2's roll. The inventory-owned fingerprints and slot-1's fingerprint go into the same list — one filter, two sources.

**Accuracy upgrades:** Extend `_generate_shop_accuracy_pick(rarity, forbidden_keys: Array[String] = [])`. Fingerprint for an accuracy pick is `"<stat_key>|<rarity>"` (e.g., `"h_accuracy|rare"`). If the rolled upgrade type's key+rarity is in `forbidden_keys`, reroll the upgrade type. Reuse the 8-attempt budget; graceful fall-through if exhausted (rare — there are enough upgrade types).

Updated loop shape:
```gdscript
var offered_mod_fingerprints: Array[String] = owned_fingerprints.duplicate()
var offered_accuracy_keys: Array[String] = []

for _i: int in range(2):
	if not all_in_active and randi_range(0, 1) == 0:
		var pick = _generate_shop_accuracy_pick(rarity, offered_accuracy_keys)
		offered_accuracy_keys.append(pick.fingerprint_key)
		picks.append(pick)
	else:
		var mods = ModifierRegistry.generate_distinct_at_rarity(1, rarity, weight_overrides, offered_mod_fingerprints)
		if mods.size() > 0:
			offered_mod_fingerprints.append(mods[0].get_config_fingerprint())
			picks.append({"type": "modifier", "data": mods[0]})
		else:
			picks.append(_generate_shop_accuracy_pick(rarity, offered_accuracy_keys))
```

### Acceptance
- Across many shop visits, the two presented slots never carry identical fingerprints in any combination (mod/mod, accuracy/accuracy).
- Regression: 50/50 modifier vs accuracy mix preserved.

---

## 4. Out of scope

- Dedup against modifiers the player previously **discarded/swapped out**. Only currently active inventory counts.
- Reward-pool (rule-modifier) dedup — bosses can't repeat in a run, so the reward path already side-steps this.
- New UI hints like "you already own a variant" — this spec only removes duplicates from the pool.
- Re-fingerprinting after toggle state changes — fingerprint reflects state at acquisition; player toggling a modifier on/off doesn't change its fingerprint.

---

## 5. Implementation order

1. **Fix 1** first — single line, smallest blast radius, easy to eyeball.
2. **Fix 2** next — virtual `get_config_fingerprint`, 9 subclass overrides, registry parameter, two `main.gd` call sites + the `get_owned_fingerprints` helper.
3. **Fix 3** last — short loop change in `_generate_shop_picks`, accuracy-key exclusion in `_generate_shop_accuracy_pick`. Reuses Fix 2's plumbing.
