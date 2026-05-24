# Unlock Condition Recipes

A cookbook for setting up every unlock condition from the original design list. Each recipe maps one design intent to a specific `UnlockCondition` subclass and the inspector field values to enter.

For the broader system architecture, see `DartComponentGuide.md`. For the end-to-end component setup workflow, see section 10 of that doc.

## Where these files live

Recommended location: `res://resources/unlock_conditions/`, flat (no subfolders). Conditions are not inherently tied to one component — the same `RunConstraintCondition` could be referenced by both a barrel and a flight if you want shared progression. Keeping them flat makes that reuse easy.

If the folder grows past ~15 files and starts to feel unwieldy, group by subclass: `unlock_conditions/leg_wins/`, `unlock_conditions/career_counts/`, etc.

## Standard workflow per recipe

1. Right-click the unlock_conditions folder → **New Resource...**
2. Search for the subclass listed in the recipe (e.g., `LegWinHitCondition`).
3. Save with the suggested filename.
4. In the inspector, set the listed field values. Anything not listed stays at its default.
5. Set the `description` field — this is the grey hint shown under the silhouette on the assembly screen. Keep it short and directive, written in second person.
6. Open the component `.tres` you want to gate, drag this condition into the `unlock_condition` field.

---

## 1. Win a leg on a double bullseye

**Subclass:** `LegWinHitCondition`
**Suggested filename:** `bullseye_finisher.tres`

| Field | Value |
|-------|-------|
| `required_ring` | `"Double Bull"` |
| `description` | `"Win a leg on a double bullseye."` |

All other fields stay at default.

---

## 2. Checkout from over 100

**Subclass:** `LegStatCondition`
**Suggested filename:** `ton_plus_checkout.tres`

| Field | Value |
|-------|-------|
| `min_checkout_total` | `101` |
| `description` | `"Check out from a remaining score over 100."` |

Note: `min_checkout_total` is the sum of all dart scores in the winning turn. So a 101-checkout means the winning turn's combined score was ≥ 101 — same as starting that turn with > 100 remaining.

---

## 3. Win a leg on your final dart

**Subclass:** `LegWinHitCondition`
**Suggested filename:** `clutch_finisher.tres`

| Field | Value |
|-------|-------|
| `final_dart_mode` | `Must be final` (enum index 1) |
| `description` | `"Win a leg on the final possible dart of the leg."` |

This triggers only when the winning dart is the third dart of the final allowed turn — i.e., the very last dart you'd be allowed to throw before the leg ends in a loss. The "Must be final" flag handles this automatically; you don't need to compute turn or dart indices manually.

---

## 4. Win 501

**Subclass:** `LegStatCondition`
**Suggested filename:** `win_501.tres`

| Field | Value |
|-------|-------|
| `required_target_score` | `501` |
| `description` | `"Win a 501 leg."` |

Note: by default, the run starts at 101 and increments by 100 per leg, so 501 is the 5th leg of any run. If `starting_target` or `target_increment` on `x01_game.gd` ever change, this milestone moves with them — the condition itself just checks for an exact 501 target.

---

## 5. Acquire 10 items during a single shop

**Subclass:** `ShopAcquisitionCondition`
**Suggested filename:** `shop_spree.tres`

| Field | Value |
|-------|-------|
| `min_items_acquired` | `10` |
| `description` | `"Acquire 10 items in a single shop visit."` |

Note: this triggers on shop close. If the shop economy ever caps acquisitions below 10 per visit, this becomes unreachable — keep the cap in mind when tuning.

---

## 6. Win a leg on a streak-modified double

**Subclass:** `LegWinHitCondition`
**Suggested filename:** `streak_finisher.tres`

| Field | Value |
|-------|-------|
| `required_ring` | `"Double"` |
| `required_modifier_category` | `"streak"` |
| `description` | `"Win on a double that was modified by an active streak."` |

How it works: the leg-win context tracks which scoring modifier categories were active on the winning dart. If any modifier with a non-`NONE` `streak_category` was firing on that dart, the `"streak"` category is added to the list. This condition checks for its presence.

Note: this requires the streak modifier to have actually modified the dart's score on the winning throw. A streak modifier present but not firing on the final dart (e.g., the streak wasn't met yet) does NOT count.

---

## 7. Win a leg on a double scoring higher than 50

**Subclass:** `LegWinHitCondition`
**Suggested filename:** `big_finish_50.tres`

| Field | Value |
|-------|-------|
| `required_ring` | `"Double"` |
| `min_winning_dart_score` | `51` |
| `description` | `"Win on a double scoring more than 50."` |

`min_winning_dart_score` is checked AFTER scoring modifiers, so a base D20 (40) plus modifier bonuses pushing it above 50 will qualify. A plain D-Bull (50) is exactly 50, so it does NOT count — use 51 for strictly-greater. If you want "50 or more," use 50.

---

## 8. Win a leg on a double scoring higher than 100

**Subclass:** `LegWinHitCondition`
**Suggested filename:** `big_finish_100.tres`

| Field | Value |
|-------|-------|
| `required_ring` | `"Double"` |
| `min_winning_dart_score` | `101` |
| `description` | `"Win on a double scoring more than 100."` |

Same rules as recipe 7 — modifier-applied score, strictly greater than 100. This is much harder than recipe 7 since base double values max at D20 (40), so it requires significant modifier amplification.

---

## 9. Hold at least 6 relic items at once

**Subclass:** `RelicCountCondition`
**Suggested filename:** `relic_hoarder.tres`

| Field | Value |
|-------|-------|
| `min_relic_count` | `6` |
| `description` | `"Have 6 or more relic items active at the same time."` |

How it works: `RelicCountCondition` listens on `item_acquired` and checks how many RELIC-kind modifiers are currently active. RELIC modifiers are the persistent ones in your inventory panel — board mutations (wedge swaps, color flips, wedge value changes) fire on acquire and don't count toward the total.

The condition fires the moment you acquire the modifier that pushes the active relic count to 6. It does not check on shop close, so adding multiple modifiers in one shop checks after each acquisition.

If the run-economy ever caps active relics below 6, this becomes unreachable. Worth keeping the threshold lower than any soft cap you eventually add.

---

## 10. Fill all streak slots

**Subclass:** `SlotsFilledCondition`
**Suggested filename:** `all_streak_slots.tres`

| Field | Value |
|-------|-------|
| `description` | `"Equip a streak modifier in all three streak categories."` |

The three streak categories are `WEDGE`, `COLOR`, and `PARITY`. When one streak modifier from each category is active simultaneously, the condition fires immediately (on the modifier-add event that completes the set). No fields to configure beyond the description — the condition is single-purpose.

---

## 11. Win 5 legs (lifetime)

**Subclass:** `CareerCountCondition`
**Suggested filename:** `five_legs.tres`

| Field | Value |
|-------|-------|
| `stat_name` | `&"legs_won"` |
| `threshold` | `5` |
| `description` | `"Win 5 legs total."` |

This is a lifetime counter — wins from any run accumulate. The `legs_won` stat is auto-incremented by `UnlockManager.on_leg_won()` and persists in `user://progress.tres`.

`CareerCountCondition` checks on every event, so an unlock fires on the very leg-win that pushes the counter to 5.

---

## 12. Win 10 legs (lifetime)

**Subclass:** `CareerCountCondition`
**Suggested filename:** `ten_legs.tres`

| Field | Value |
|-------|-------|
| `stat_name` | `&"legs_won"` |
| `threshold` | `10` |
| `description` | `"Win 10 legs total."` |

Same mechanic as recipe 11, different threshold. You could keep going with 25, 50, etc. for higher-tier components — just copy this recipe with new thresholds.

---

## 13. Win 5 legs with only common items (single run)

**Subclass:** `RunConstraintCondition`
**Suggested filename:** `commoner_five.tres`

| Field | Value |
|-------|-------|
| `legs_won_this_run_threshold` | `5` |
| `required_run_flag` | `&"only_commons_acquired_this_run"` |
| `description` | `"Win 5 legs in a single run without acquiring any uncommon or rare items."` |

How the flag works: `UnlockManager.on_run_started()` sets `only_commons_acquired_this_run = true` at the start of every run (optimistic default). The first time the player acquires an item with rarity > COMMON, the flag flips to `false` for the rest of the run. The condition checks both: legs won this run ≥ 5 AND the flag is still true.

Strategic note: this is the only single-run constraint condition in the list. Players have to deliberately avoid better items to get it. Worth being upfront in the description.

---

## 14. Complete a 3-dart checkout (all darts must score)

**Subclass:** `LegStatCondition`
**Suggested filename:** `three_dart_perfect.tres`

| Field | Value |
|-------|-------|
| `require_three_scoring_darts` | `true` |
| `description` | `"Win a leg in 3 darts with every dart scoring."` |

> **Known ambiguity.** The current implementation in `main.gd` computes the underlying flag as `_turn_darts_scored == x01_game.darts_this_turn` — meaning "every dart you threw this turn scored." This passes for a 1-dart finish (1 == 1) or a 2-dart finish (2 == 2) where the scoring darts all scored. If your intent is strictly "win on dart 3 with all three darts having scored," the condition won't be that strict until the flag computation in `main.gd` (around line 549) is changed to also require `darts_this_turn == 3`.
>
> If you want the strict reading, edit `main.gd` line 549 from:
> ```
> "winning_turn_all_darts_scored": _turn_darts_scored == x01_game.darts_this_turn,
> ```
> to:
> ```
> "winning_turn_all_darts_scored": _turn_darts_scored == 3 and x01_game.darts_this_turn == 3,
> ```

---

## 15. Hit a double for the win without it being your target

**Subclass:** `LegWinHitCondition`
**Suggested filename:** `lucky_finisher.tres`

| Field | Value |
|-------|-------|
| `required_ring` | `"Double"` |
| `target_mode` | `Must be off-target` (enum index 1) |
| `description` | `"Win on a double in a wedge you weren't aiming at."` |

How "on-target" is determined: when the player declares their aim (via `throw_mechanic._declared_target`), the wedge index is recorded. After the dart lands, the actual hit wedge is compared against the declared one. If they differ, `was_winning_dart_on_target = false` and this condition fires.

Edge case: if no target was declared (e.g., free-fire mode or some debug path), the default is `was_on_target = true`, so this condition wouldn't trip. Confirm with one playthrough that target declaration always happens during normal play.

---

## Quick reference table

| Recipe | Subclass | Suggested filename |
|--------|----------|-------------------|
| 1. Double bullseye win | `LegWinHitCondition` | `bullseye_finisher.tres` |
| 2. Checkout over 100 | `LegStatCondition` | `ton_plus_checkout.tres` |
| 3. Win on final dart | `LegWinHitCondition` | `clutch_finisher.tres` |
| 4. Win 501 | `LegStatCondition` | `win_501.tres` |
| 5. 10 items in one shop | `ShopAcquisitionCondition` | `shop_spree.tres` |
| 6. Streak-modified double | `LegWinHitCondition` | `streak_finisher.tres` |
| 7. Double > 50 | `LegWinHitCondition` | `big_finish_50.tres` |
| 8. Double > 100 | `LegWinHitCondition` | `big_finish_100.tres` |
| 9. Hold 6+ relics at once | `RelicCountCondition` | `relic_hoarder.tres` |
| 10. All streak slots | `SlotsFilledCondition` | `all_streak_slots.tres` |
| 11. 5 legs lifetime | `CareerCountCondition` | `five_legs.tres` |
| 12. 10 legs lifetime | `CareerCountCondition` | `ten_legs.tres` |
| 13. 5 legs commons-only | `RunConstraintCondition` | `commoner_five.tres` |
| 14. 3-dart all-scoring checkout | `LegStatCondition` | `three_dart_perfect.tres` *(see ambiguity note)* |
| 15. Off-target double win | `LegWinHitCondition` | `lucky_finisher.tres` |

---

## After you create the condition files

Link each one to the component it gates: open the component `.tres`, drag the condition resource into the `unlock_condition` field. Then drag the component into `DartComponentRegistry`'s appropriate array on `scenes/main.tscn`.

When running the game, watch the debugger console for any `DartComponentRegistry:` push_error lines. If you see one, the most likely cause is:
- Empty `id` on the component (set it before registering).
- `default_unlocked = false` with `unlock_condition = null` (link the condition before registering).
- Duplicate `id` somewhere across all three slot arrays (rename the offender).

Until the component is in the registry array, it doesn't render on the assembly screen and unlock conditions don't evaluate against it — registration is the "this is live" switch.
