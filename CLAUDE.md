# Post-1001-Playtest Bug Fix Pass

**Spec date:** 2026-05-28
**Status:** Designed, ready for implementation
**Scope:** Four targeted fixes surfaced during 1001-level playtest. Three are clean code-locality fixes; one (the 1001 boss leg) needs diagnostic logging to root-cause before patching.

## Summary

Bug pass covering four issues found during 1001 playtest. Bundled into one spec because they're all small targeted fixes that touch independent systems and can ship together.

| # | Bug | Type | Confidence |
|---|---|---|---|
| 1 | Boss leg appears at +200 instead of +100 on 1001+, AND recession-boss board effects don't apply | Wiring | Symptom clear, root cause needs diagnostic pass |
| 2 | No place on screen to see legendary (rule-modifier) rewards earned this run | Missing UI | Spec-level decision, clean to ship |
| 3 | Triple-checkout legendary: the triple that would close the leg doesn't get the gold-pulse outline that doubles get | Renderer gap | Root cause identified |
| 4 | Rotation boss accuracy zone references stale (pre-rotation) target position | Math bug | Root cause identified |

---

## 1. Bug 1 — 1001 boss leg skip + recession not applying

### 1a. Symptoms

Playtest report (1001 level run):
- After clearing leg 4 (target 401), pressed "Next Leg" → boss leg appeared with target **601** (leg 6) instead of **501** (leg 5). Leg 5 was skipped entirely.
- The boss was Recession. Its **HUD background tint, title, and description applied correctly**, but the **dartboard wedge values were not recessed** and scoring did not use recessed values. Recession works correctly on the 501 level — only fails on 1001.

These are likely two separate bugs sharing the same trigger (the boss-leg entry path on longer levels), so the spec treats them together but lands distinct fixes.

### 1b. Symptom A — leg-skip

Code trace under the standard 1001 flow:
- `shop_cadence = 3`, `boss_cadence = 5`, `target_increment = 100`, `starting_target = 101`.
- After leg 4 (target 401): no shop (`4 % 3 != 0`), no boss-just-cleared. Path is `_show_leg_upgrades` → accuracy pick → modifier pick → "Next Leg" button → `_on_next_leg()` → single `advance_leg()` → `is_boss_leg(5)` true → boss starts at 501.
- Observed result instead: boss at 601 (leg 6). Implies a double `advance_leg()` along this path, or a signal firing twice (`hud.next_leg_pressed.connect(_on_next_leg)` could be connected twice in some state), or some other place that increments `current_leg`/`target_score`.

Fix approach is investigative — add `print()` diagnostics to:
- `_on_next_leg` entry (print `current_leg`, `target_score`, `_leg_phase`).
- `_show_leg_upgrades` entry (print same).
- `_end_shop` callback that calls `advance_leg` (print before/after).
- `x01_game.advance_leg()` itself (print before/after, dump call stack via `print_stack()`).
- `hud.next_leg_pressed` emission site(s).

Reproduce on a 1001 run, capture which path double-fires, then land a single-line fix (likely `disconnect()` before `connect()` somewhere, or guarding the second call with a `_just_advanced` flag). Diagnostics removed once fix lands.

### 1c. Symptom B — recession not applying on dartboard

Code trace: `recession_boss.on_leg_start()` does the right work — mutates `smm.effective_wedge_values`, mirrors to `dartboard.effective_wedge_values`, sets `boss_reduced_wedges`, calls `set_boss_recession_wedges()`, `queue_redraw()`.

The fact that the **boss UI applies** (background tint, title, description set via `_update_boss_status()` which runs *after* `start_boss_leg`) confirms `start_boss_leg` did run. So `on_leg_start` ran. Yet the dartboard shows unrecessed values.

Hypothesis: something between `boss.on_leg_start()` and the player's first throw is replacing `effective_wedge_values` back to defaults. Candidates to verify under the same diagnostic pass:
- `_sync_board_and_solver()` is called immediately after `start_boss_leg` (line 756). It calls `_sync_board_state()` which sets `dartboard.effective_wedge_values = scoring_modifier_manager.effective_wedge_values`. If `smm.effective_wedge_values` still has the recession applied, this is a no-op. **But** then it calls `scoring_modifier_manager._build_solver_candidates()` and `invalidate_preferred_remainders()` — verify these don't reset `effective_wedge_values`.
- The hypothesized double-advance (Symptom A) could be the trigger: if a second `advance_leg` flow re-runs and somewhere along the way `_init_default_board_state()` gets called (which *does* reset `effective_wedge_values` to `DEFAULT_WEDGE_ORDER`), the recession is wiped. **This would explain why it correlates with the 1001-only skip bug.** Add `print()` in `_init_default_board_state` and any code that assigns to `effective_wedge_values` directly to catch the offender.

Diagnostics likely show that fixing Symptom A also fixes Symptom B. If not, the second fix is targeted at whatever stale-state-reset path is found.

### 1d. Acceptance

- On a fresh 1001 run, beating leg 4 advances to leg 5 at target 501.
- Boss leg at leg 5 (501) applies Recession to the dartboard: affected color wedges show reduced values, scoring uses reduced values, recession indicator visible.
- Diagnostic prints removed in the same commit as the fix.
- Bug not reproducible on 1001 *or* 1501 (test both).
- 501 boss leg unaffected (regression check).

---

## 2. Bug 2 — Legendary rewards display

### 2a. Problem

`_active_rewards` (the rule-modifier rewards earned from boss defeats — Triple Outs, Glass Cannon, Extra Dart, Extra Turn, Streak Slot Extension, Pool Widener, Frequent Shopping, Lucky Eye) is tracked in `main.gd` line 826 but never surfaced anywhere in the HUD outside the reward picker itself. Players forget what legendaries they've banked across a long run.

### 2b. Display

A new "Legendaries" panel in the HUD:

- **Placement:** Adjacent to the existing modifier strip, separated by a subtle divider. Recommended location: directly **right of** the modifier strip (or below it if horizontal space is tight — `hud.gd` layout dictates). Gold-tinted background tile to set it apart from the scoring modifier strip.
- **Icon style:** Gold diamond-shaped tiles, sized to match `modifier_square_size`. Diamond shape (45°-rotated square) is the visual differentiator — communicates "rare/run-defining" without needing per-reward art.
- **Per-icon content:** Gold-tinted background, reward's icon glyph or first-letter monogram if no icon resource exists. Reward classes don't currently carry icons — V1 ships with monogram-style placeholder (`T` for Triple Outs, `G` for Glass Cannon, etc.) and a TODO for proper iconography. Acceptable tradeoff: per-feedback memory, deferring polish to land function first.
- **Hover tooltip:** Shows reward `display_name` + `description`. Matches the existing modifier-strip tooltip behavior.
- **Empty state:** Panel hidden until at least one reward earned. Once earned, panel becomes visible and persists for the rest of the run.

### 2c. Implementation

- New scene/control `legendary_icon.gd` (or extend `modifier_icon.gd` with a `display_style` enum: `MODIFIER_SQUARE` vs `LEGENDARY_DIAMOND`). Recommend new file — modifier and legendary semantics are distinct enough that mixing them muddies the API.
- New `HBoxContainer` `LegendaryPanel` added to `hud.tscn` next to `ModifierPanel`.
- `hud.gd` exports tuning vars (per project convention — static-typed, hover descriptions):
  - `legendary_diamond_size: int = 40`
  - `legendary_panel_spacing: int = 6`
  - `legendary_tint_color: Color = Color(1.0, 0.85, 0.2, 1.0)` (gold)
- `hud.gd` gets `add_legendary(reward: RuleModifierReward)` method. Called from `main.gd::_on_reward_selected` after `_active_rewards.append(reward)`.
- On run end (`_reset_run_state`), HUD clears the legendary panel (alongside the existing modifier strip clear).

### 2d. Display strings

`RuleModifierReward` already exposes `display_name` and `description` per the existing reward picker — reuse those directly. No new strings needed.

### 2e. Out of scope

- Per-reward icon art (placeholder monogram for V1).
- Click-to-inspect or drag-to-reorder.
- Showing legendaries on the game-over / victory screen.

---

## 3. Bug 3 — Triple-checkout gold outline + Glass Cannon

### 3a. Problem

When Triple Outs is active, doubles get the gold pulse outline correctly for double-checkouts, but the **triple that would close the leg does not** get the same outline. Same gap exists for Glass Cannon's "any segment closes."

### 3b. Root cause

Two-spot bug in the renderer/state-check layer:

**Spot 1: `dartboard.gd::_draw_checkout_pulses()` (line ~1015)** only handles segment types `"double_bull"` and `"wedge"` (double). The segment types `"triple_wedge"` (emitted by `calculate_checkout_segments` when `allow_triple_checkout`) and `"single_wedge"` (emitted when `glass_cannon_active`) reach the loop but fall through the `match`/`if-elif` and never render.

**Spot 2: `main.gd::_is_checkout_segment()` (line ~1887)** only matches `ring_name == "Double"`. Triple checkouts and Glass Cannon checkouts don't get the score-display gold treatment.

### 3c. Fix

**`_draw_checkout_pulses`:** add cases for `"triple_wedge"` and `"single_wedge"`. Border radii for each:
- `triple_wedge`: `inner = RING_INNER_SINGLE_OUTER`, `outer = RING_TRIPLE_OUTER`
- `single_wedge`: `inner = RING_TRIPLE_OUTER`, `outer = _effective_double_inner()` (outer single)

Same `pulse_color` and `checkout_border_thickness` as doubles.

For Glass Cannon, multiple ring types can be valid finishers simultaneously (any ring closes). All eligible segments for the current remainder should pulse. The existing `calculate_checkout_segments` already enumerates them — renderer just needs to draw all returned types.

**`_is_checkout_segment`:** broaden to recognize Triple (when `allow_triple_checkout`) and any ring (when `glass_cannon_active`). Use `x01_game.allow_triple_checkout` and `x01_game.glass_cannon_active` as the gates so behavior follows the actual game state, not a snapshot.

### 3d. Acceptance

- With Triple Outs active and a remainder ≤ 60 finishable on a triple (e.g. 60 → T20, 57 → T19): the corresponding triple ring segment renders the same gold pulse outline as doubles.
- With Glass Cannon active and any reachable remainder: all eligible segments pulse.
- Score readout in main.gd uses gold-checkout treatment for triple-closing throws when triple checkout is active.
- Regression check: with neither modifier, only doubles pulse (current behavior preserved).

---

## 4. Bug 4 — Rotation boss accuracy zone references stale target

### 4a. Problem

When the rotation boss rotates the dartboard at turn start, the throw mechanic's accuracy-zone distance check measures against the wedge's *pre-rotation* position. Hitting the visually-correct target reports a worse-than-expected accuracy.

### 4b. Root cause

`dartboard.gd::get_segment_centroid()` (line 728–757) computes:

```gdscript
var center_angle_deg: float = wedge_index * WEDGE_ANGLE_DEG
```

Missing both `WEDGE_OFFSET_DEG` and `board_rotation_offset`. Compare `_wedge_text_angle_deg()` at line 1264 which correctly returns:

```gdscript
return wedge_idx * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG + board_rotation_offset
```

Caller path: `throw_mechanic.gd::_place_aim_crosshair()` line 489 caches `_target_centroid = dartboard.get_segment_centroid(...)` when the player commits the aim. Distance check `pos.distance_to(_target_centroid)` then runs against this stale position. Under rotation boss, the actual wedge has rotated but the cached centroid hasn't.

### 4c. Fix

Single-line patch in `get_segment_centroid`:

```gdscript
var center_angle_deg: float = wedge_index * WEDGE_ANGLE_DEG + WEDGE_OFFSET_DEG + board_rotation_offset
```

This is the same correction `_wedge_text_angle_deg` makes. The `direction` vector flows through `sin`/`-cos` of the corrected angle, landing the centroid in the rotated wedge's actual position.

Note: this also fixes a latent off-by-WEDGE_OFFSET_DEG bug that affects non-rotation-boss gameplay too. The bug is small in absolute terms (offset is typically 9° for 20-wedge boards), so it may have been imperceptible without rotation amplifying it. Verify the non-boss accuracy zone still feels right after the fix — if `WEDGE_OFFSET_DEG` is intentionally excluded for some reason (e.g. the throw mechanic compensates elsewhere), drop just the offset and keep the rotation term.

### 4d. Acceptance

- Rotation boss leg: hitting the visually-targeted segment after rotation registers as "on target" in the accuracy zone (compare to a non-rotation-boss leg).
- Regression check: non-boss leg accuracy zone feels identical to before the fix (or, if `WEDGE_OFFSET_DEG` was being deliberately omitted, drop it back and keep only the rotation term).

---

## 5. Implementation Order

Suggested sequence:

1. **Bug 4** first — single-line fix, smallest blast radius, easy to verify.
2. **Bug 3** next — two-spot renderer/check fix, isolated to checkout-highlight code.
3. **Bug 2** — new UI element, slightly larger but contained to `hud.gd` + new icon script.
4. **Bug 1** last — needs diagnostic pass; do this with a 1001 playtest in the loop. If the diagnostic shows the leg-skip is in a particularly tricky path, defer the recession-not-applying piece to confirm it's downstream of the same root cause vs. independent.

Diagnostic prints in Bug 1 are removed in the same commit as the fix.

---

## Out of Scope / Deferred

- **Per-reward iconography for the legendary panel.** V1 ships monogram placeholders; proper icons are art-pass work for a later spec.
- **Game-over / victory screen showing earned legendaries.** Run-end summary improvements deferred.
- **Wider checkout-segment polish** beyond closing the triple/single render gaps. Animations, color theming, etc. unchanged.
- **Rotation-boss target re-acquisition on rotation change** beyond the centroid fix. If playtest reveals the stale centroid is also referenced elsewhere (e.g., projectile tracking), follow up; current scope is the accuracy zone distance check.

---

## Workflow Notes

`CLAUDE.md` holds the **single active spec** — the feature currently being designed or implemented. It auto-loads into every Claude conversation in this repo, so it should stay lean and focused on one thing at a time.

When a feature ships (or work moves on to a new spec), the previous one gets archived:

1. Move everything above this "Workflow Notes" section into `specs/YYYY-MM-DD-feature-slug.md`.
2. Add a status header at the top of the archived file:
   ```
   ---
   Spec date: YYYY-MM-DD
   Status: Shipped YYYY-MM-DD | Partially shipped | Superseded by specs/X
   Implementation: Where the implementation pass ran (Claude Code, manual, etc.)
   Notes: What shipped vs deferred, links to follow-up specs that revisit anything here.
   ---
   ```
3. Reset the spec section in `CLAUDE.md` to this placeholder (or replace it with the next spec).

The archive is for design context, not implementation reference. Code lives in code; the archived spec exists to remind future-Max (and future-Claude) *why* a system was built a certain way, what alternatives were considered, and what the design assumptions were. When making changes that touch an existing system, scan `specs/` for any prior decision that constrains the new work.
