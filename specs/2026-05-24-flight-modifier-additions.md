---
Spec date: 2026-05-24
Status: Shipped 2026-05-24. All 8 implementation steps landed; both flights (Momentum Marksman, Color Connoisseur) live in `resources/dart_components/flights/`.
Implementation: Claude Code single pass against this spec. Verified post-ship: `MomentumMarksmanModifier.get_active_bonuses` reads `declared_target` + `active_streak_modifiers` from context; `ShopBias` base + `ColorShopBias` subclass shipped in `scripts/shop_biases/`; `ThrowModifier.get_active_bonuses(_context)` accepts the optional context dict with default `{}`.
Notes: Streak-stacking rule shipped as **sum** per the design call — flag for revisit if playtest shows it scales too aggressively (revert to max is a one-line tuning change inside `_get_total_streak_count`). Three deferred future hooks remain as documented: retrigger flier (needs a `ScoringHook` sibling resource), shop spot-spawning bias (extends `ShopBias` with a new override method), per-color Color Connoisseur variants.
---

# Two New Flight Modifiers + Reusable Ability Hooks

**Spec date:** 2026-05-24
**Status:** Designed, ready for implementation
**Scope:** Add two new flight components — **Momentum Marksman** and **Color Connoisseur** — each unlocking a new build archetype. Along the way, formalize two reusable extension points: a second evaluation pass for throw modifiers (target-aware bonuses) and a generic `ShopBias` resource attached to dart components.

## Summary

The flight slot is the single archetype-defining slot in a run — one flight equipped, no mid-run swaps. Every new flight should justify itself as a "this run is about X" choice, not just a stat tweak. Two new ones:

- **Momentum Marksman** — accuracy that scales linearly with active streak count, but only when aiming at a streak-continuing target. Rewards committing to a streak deck and aiming inside the streak. Pure-offensive flier, but the offense comes from skill expression: you have to keep the streak alive to keep the bonus growing.
- **Color Connoisseur** — primer for the color archetype. Biases the shop's modifier roll toward color-flavored types (`ColorBonusModifier`, `ColorStreakModifier`, `ColorFlipModifier`) by a configurable multiplier. Does not score directly; instead shapes what the player sees in the shop, channeling them toward a color-heavy deck over time.

Both fliers are intended as harder unlocks per the unlock-condition philosophy that build-defining slots warrant tougher entry costs.

## Design Context

The two fliers were chosen as a pair after discarding earlier candidates:

- A "cache-able rethrow" flier was dropped — rethrow verbs create an incentive to intentionally miss (e.g., aim for a double, miss, get a free retry off-streak). The exploit can't be patched cleanly without hollowing out the verb.
- A "retrigger color modifiers on doubles/triples" flier is deferred — likely too strong without per-color scoping, better revisited once Color Connoisseur surfaces how color-heavy decks actually play.

The remaining pair complements well: Momentum is an *in-play* effect with a hover-bar moment; Color Connoisseur is a *shop-time* effect with a long-tail run-shaping payoff. Different feedback loops, different verbs, no overlap.

Color Connoisseur is also the foreseen "item-specific shop interaction" hook called out in the deferred section of `specs/2026-05-21-shop-system.md`. Building the generic `ShopBias` resource for it (rather than a one-off field) means future shop-shaping fliers can reuse the same hook.

## Momentum Marksman

**Effect:** While a streak is active and the player's declared target would continue that streak, apply an accuracy bonus that scales with the streak count.

**Formula:** `h_accuracy_bonus = v_accuracy_bonus = accuracy_per_streak * total_streak_count` where `accuracy_per_streak` is an exported tuning value (default `2.0`).

**Stacking across streaks:** If multiple active streak modifiers would *each* be continued by the target, their streak counts **sum** into `total_streak_count`. This is intentional — encourages multi-streak builds for big payoffs. May feel too strong in playtest; revert to taking the *max* if so. Either rule is one tuning change.

**Cap:** The bonus is added to `horizontal_accuracy` / `vertical_accuracy` on the throw mechanic. These stats are already clamped to 1-100 inside `_get_horizontal_accuracy_half` / `_get_vertical_accuracy_half`, so no Momentum-specific cap is needed — the bonus naturally tops out at 100.

**Hover feedback:** Because the bonus only applies once the player has placed their aim ellipse and declared a target, the ghost accuracy preview drawn during `VERTICAL_RELEASE` / `HORIZONTAL_RELEASE` will already reflect the bonus if we re-evaluate throw modifiers at aim placement (see Architectural Changes below). This gives the "bars fill up when aiming at a streak target" feel for free — no extra UI work needed beyond the re-evaluation hook.

**Why this design works as a class pick:** A defensive/insurance verb (the original "streak saver" rethrow idea) doesn't pull its weight as the sole archetype-defining flier. Momentum is fully proactive — it rewards the playstyle it cares about (consistent aim into streak-continuing targets) rather than insuring against failure. Players who don't build a streak deck never see the bonus, which is correct: that's the cost of committing to the wrong flight.

## Color Connoisseur

**Effect:** When the shop generates its 2-of-2 picks, the relative weight of color-flavored modifier types is multiplied by `color_weight_multiplier` (default `2.0`).

**Affected modifier types:** `ColorBonusModifier`, `ColorStreakModifier`, `ColorFlipModifier`. These are the three that have color-pair semantics today.

**No in-play effect:** The flier does nothing during throws. It does not boost any stat. The entire payoff is shop-time. This is unusual for the flight slot but appropriate: the color archetype needs material to build with, and this flier produces that material at the source.

**Why shop-shaping, not on-board synergy:** The retrigger alternative was tempting but risked being either over-strong (more colors = always more multipliers stacking) or boring (a passive scoring tax). Shaping the shop instead respects the existing scoring loop, doesn't compound on top of natural double/triple multipliers, and gives the player visible *acquisition* moments they can connect to the flier choice ("oh, another color bonus showed up").

**Why colors specifically tolerate shop-shaping but streaks wouldn't:** Streak modifiers cap at one per category (WEDGE / COLOR / PARITY), so biasing the shop toward streaks would quickly produce dead picks once all three slots are filled. Color modifiers have no such cap — more is always more. Shop-shaping a saturating type would create "stop showing me these" fatigue; shop-shaping an uncapped type does not.

## Architectural Changes

### 1. Second throw-modifier evaluation pass at aim placement

The current `evaluate_throw_modifiers` flow in `main.gd._start_new_throw` runs at throw start, before the player has placed their aim ellipse. Momentum needs to know `declared_target`, which is only known after `throw_mechanic._place_aim_ellipse()` fires.

**Change:** Run a second evaluation pass when the throw mechanic transitions to `VERTICAL_RELEASE` (i.e., immediately after aim placement). Existing modifiers (Ice Veins, Nervous Sweater) still evaluate at throw start; the second pass overlays target-dependent bonuses on top.

**Context additions:** Extend the context dictionary passed to throw modifiers with:
- `declared_target: Dictionary` — populated only in the second pass; empty in the first.
- `active_streak_modifiers: Array` — pulled from `scoring_modifier_manager.get_active_streak_modifiers()` so target-aware modifiers don't have to thread their own reference.

**`ThrowModifier` base class change:** Refactor `get_active_bonuses()` to `get_active_bonuses(context: Dictionary = {})` so subclasses can compute dynamic bonus values from context. Default behavior (returning exported flat fields) preserved for Ice Veins and Nervous Sweater — no migration needed.

**Visual reapplication:** After the second-pass evaluation, `_temp_throw_bonuses` and `_apply_temp_bonuses` are re-run, mutating `throw_mechanic.horizontal_accuracy` / `vertical_accuracy`. The ghost preview redraws naturally because `_draw_vertical_release` / `_draw_horizontal_release` recompute the accuracy ellipse on every `_process` tick.

### 2. Streak continuation hook on `ScoringModifier`

Add a virtual method to the `ScoringModifier` base class:

```gdscript
## Override in streak modifier subclasses. Return true if hitting this target
## would continue the modifier's current streak. Non-streak modifiers return false.
## target is the declared_target dictionary from the throw mechanic — same shape
## as the dartboard.calculate_score result (face_value, multiplier, ring_name,
## wedge_index, segment_color, is_bull).
func would_continue_streak(target: Dictionary) -> bool:
	return false
```

Each streak subclass overrides:
- `ColorStreakModifier`: `_streak_count > 0 and target["segment_color"] == target_color`
- `WedgeStreakModifier` (if/once it exists, or whichever modifier tracks wedge streaks): wedge match
- `ParityStreakModifier`: parity match
- `EvenStreakModifier` / `OddStreakModifier`: face value parity match

Momentum Marksman iterates active streak modifiers, sums `_streak_count` values for those returning true, and uses the sum to compute its bonus.

### 3. Reusable `ShopBias` resource on `DartComponent`

A new sibling slot for non-throw passive abilities, separate from `throw_modifier`. Sets the pattern for future passive abilities (a `ScoringHook` resource could be added later for the deferred retrigger flier without touching this one).

**Base class:** `class_name ShopBias extends Resource`. Exposes:

```gdscript
## Override to return a {ScriptType: float_multiplier} dictionary that the
## ModifierRegistry multiplies into pool weights at shop generation time.
## Keys are the modifier type scripts; values multiply the base get_pool_weight().
func get_weight_overrides() -> Dictionary:
	return {}
```

**Subclass:** `ColorShopBias` returns the three color modifier scripts mapped to an exported `color_weight_multiplier: float = 2.0`.

**`DartComponent` addition:**
```gdscript
## Optional shop-bias passive. Evaluated by the shop when generating picks.
## Leave null for components with no shop influence.
@export var shop_bias: ShopBias
```

**`ModifierRegistry` extension:** Add an optional `weight_overrides: Dictionary = {}` parameter to `generate_distinct_at_rarity(count, rarity, weight_overrides)`. Inside the weighted-roll loop, multiply each candidate's `get_pool_weight()` by the override (default 1.0) before adding to the cumulative roll.

**`main.gd._generate_shop_picks`:** Pull `dart_build.equipped_flight.shop_bias` (null-safe), call `get_weight_overrides()` if present, pass the dict to the registry call.

## Implementation Steps

Suggested order — each step should leave the game runnable:

1. Add `would_continue_streak(target)` to `ScoringModifier` base + override in the 5 existing streak modifier subclasses. Pure additive, no behavior change yet.
2. Refactor `ThrowModifier.get_active_bonuses()` to accept context (default empty dict). Update `DartBuild.evaluate_throw_modifiers` to pass the context through. Existing modifiers still work unchanged.
3. Wire the second-evaluation pass: connect `throw_mechanic.state_changed` in `main.gd` to a new `_on_aim_placed` handler that rebuilds context (with `declared_target` and `active_streak_modifiers`), re-runs evaluation, and reapplies temp bonuses.
4. Create `MomentumMarksmanModifier` script, `.tres` resource, and the new flight component `.tres`. Wire its `throw_modifier` field. Tune `accuracy_per_streak` in inspector after a playtest.
5. Create `ShopBias` base + `ColorShopBias` subclass. Add `shop_bias` exported field to `DartComponent`.
6. Extend `ModifierRegistry.generate_distinct_at_rarity` with `weight_overrides`. Update `main.gd._generate_shop_picks` to thread the bias through.
7. Create `color_bias.tres` and the Color Connoisseur flight component `.tres`.
8. Add unlock conditions for both flights — pick something tougher than the easy fliers per the build-defining-equals-harder-unlock principle.

After implementation, archive this spec per the workflow notes below and update `DesignNotes.md` if the architectural changes (second eval pass, `ShopBias` pattern) deserve canonical mention.

## Open Future Hooks (intentionally not in this spec)

- **Retrigger flier** (deferred from this conversation). Would need a third extension point — probably a `ScoringHook` sibling resource on `DartComponent` that fires inside `ScoringModifierManager.process_score`. Worth designing alongside any other on-score effects so the hook shape covers multiple use cases.
- **Tunable shop spot-spawning bias.** `ShopBias` currently affects only the item *pool*. A future flier could bias *where* lit spots spawn (e.g., more doubles, more bullseye-region). Same resource shape, new override method.
- **Per-color Color Connoisseur variants.** If colors-in-general feels too generic, future versions of this flier could roll a single target color (like `ColorStreakModifier` does) and only bias that color's modifiers.
- **`would_continue_streak` for non-streak modifiers.** Some non-streak modifiers might also reward "good aim" (e.g., a "lucky streaks" relic). The hook is generic enough to extend.

## Files Affected

**New files:**
- `scripts/throw_modifiers/momentum_marksman_modifier.gd`
- `scripts/shop_biases/shop_bias.gd` (base class)
- `scripts/shop_biases/color_shop_bias.gd`
- `resources/throw_modifiers/momentum_marksman.tres`
- `resources/shop_biases/color_bias.tres`
- `resources/dart_components/flights/<momentum_marksman_flight>.tres`
- `resources/dart_components/flights/<color_connoisseur_flight>.tres`

**Modified files:**
- `scripts/throw_modifiers/throw_modifier.gd` — `get_active_bonuses(context)` signature change.
- `scripts/dart_build.gd` — pass context through to `get_active_bonuses`.
- `scripts/scoring_modifier.gd` — add `would_continue_streak(target)` virtual.
- `scripts/modifiers/color_streak_modifier.gd` — override `would_continue_streak`.
- `scripts/modifiers/even_streak_modifier.gd` — override.
- `scripts/modifiers/odd_streak_modifier.gd` — override.
- `scripts/modifiers/parity_streak_modifier.gd` — override.
- `scripts/modifiers/streak_bonus_modifier.gd` — override (or confirm not a wedge-streak first).
- `scripts/dart_components/dart_component.gd` — add `shop_bias` exported field.
- `scripts/modifier_registry.gd` — add `weight_overrides` parameter.
- `scripts/main.gd` — add `_on_aim_placed` second-eval handler; thread shop bias through `_generate_shop_picks`.
