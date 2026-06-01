---
Spec date: 2026-05-30
Status: Shipped 2026-05-31
Implementation: Code reflects all four items. `brush_modifier.gd` exists; `color_flip_modifier.gd` deleted with zero remaining `ColorFlip`/`_ColorFlip` references; `ConfigType.PICK_SEGMENT` added; `effective_wedge_colors` is the 4-key per-ring dict (inner_single/triple/outer_single/double); `ModifierRegistry.available_brush_colors` + `main.gd::_sync_brush_affinity()` drive affinity-gated pooling with the weight-override suppression channel; prism is the leg-scoped inverter ("All colors inverted for the leg", `on_leg_start`/`on_leg_end`, no `on_turn_start`).
Notes: All three open decisions resolved as recommended — (1) prism = leg-scoped pair inverter, (2) brush common-tier only, (3) recession keys off `inner_single`. No deferrals. Out-of-scope items (multi-ring brushes, player-chosen color at pick time, rarity palette, cross-run board persistence) remain unbuilt by design.
---

# Color Brushes + Per-Ring Board Color

**Spec date:** 2026-05-30
**Status:** Designed, ready for implementation
**Previous spec:** `specs/2026-05-28-cache-key-hotfix-recursive-prune.md` (shipped 2026-05-29). First feature spec after the late-game perf work — codebase is bug-free as of the 2026-05-30 playtest.

## Why

Red and Green color-streak / color-bonus modifiers are structurally weak. On a standard board, red and green only ever appear on the *multi* rings (doubles/triples) — half the wedges each. Black and white own every single ring. So Red/Green streaks ask you to chain doubles/triples on alternating wedges, which is brutal until very late game; Black/White streaks are easy by comparison because singles are everywhere.

The fix is to let the player **paint the board** toward a color over a run. This turns "color" from a fixed board property into a build resource you sculpt — a strong roguelike loop — and it directly rehabilitates the weak Red/Green color builds. The existing `ColorFlipModifier` (whole-wedge pair flip, common-only, consumable) is the seed of this idea but too blunt; it gets **replaced** by a per-ring brush.

## Summary

| # | Change | Type | Touch | Why |
|---|---|---|---|---|
| 1 | Expand board color model from 2 colors/wedge to 4 (per ring) | Data model | `scoring_modifier_manager.gd`, `dartboard.gd`, bosses, solver target enum | Foundation — engine currently can't represent "triple 20 white, double 20 red" |
| 2 | New `ConfigType.PICK_SEGMENT` (wedge + ring picker) | Config / UI | `scoring_enums.gd`, `dartboard.gd`, `main.gd` | Brushes paint one ring, not a whole wedge |
| 3 | `BrushModifier` (replaces `ColorFlipModifier`) — paints one ring one pre-rolled color | Item | new `brush_modifier.gd`, `modifier_registry.gd`, `color_shop_bias.gd` | The actual board-shaping item |
| 4 | Affinity-gated pooling — a brush color only appears if you own a modifier that cares about that color | Pooling | `modifier_registry.gd` + shop call site | Stone-Joker-style conditional visibility; keeps dead items out of the shop |

Item 1 is the bulk of the work and the real decision (do we want per-ring color in the engine — yes, it unlocks a whole category of future board-shaping items). Items 2–4 are small once the model exists.

---

## 1. Per-ring board color model (foundation)

### Current model

`effective_wedge_colors` is an `Array[Dictionary]` of 20 entries, each `{"single": SegmentColor, "multi": SegmentColor}`. `"single"` covers **both** inner and outer single rings; `"multi"` covers **both** triple and double. The engine literally cannot represent a board where one ring of a wedge differs from another of the same kind.

### New model

Each entry becomes four keys, one per ring:

```gdscript
{
	"inner_single": SegmentColor,
	"triple": SegmentColor,
	"outer_single": SegmentColor,
	"double": SegmentColor,
}
```

`_init_default_board_state()` seeds the standard board: on even wedges `inner_single`/`outer_single` = BLACK and `triple`/`double` = RED; on odd wedges WHITE and GREEN respectively. Bulls remain hardcoded (single bull GREEN, double bull RED) — they are not wedge entries and brushes don't touch them.

### Touchpoints (all confirmed against current code)

- **`dartboard.gd::_lookup_segment_color(wedge_idx, is_multi)`** → change signature to take `ring_name: String` and index the per-ring dict. `calculate_score()` already knows the exact ring at each branch (it sets `ring_name`), so the call sites pass it directly — no inference needed.
- **`dartboard.gd::_draw()` (~line 379)** currently draws one `single_color` and one `multi_color` per wedge. Now draw four rings independently, each from its own key. The per-ring draw radii already exist (see `_draw_flash_segment`). `_prev_wedge_colors` color-transition animation (~line 382, `animate_color_transition`) must duplicate and lerp all four keys.
- **`dartboard.gd::_segment_color_to_render()`** unchanged (still maps a `SegmentColor` enum → render `Color`).
- **`scoring_modifier_manager.gd::get_effective_color(wedge_index, is_multi)`** → make ring-aware (`ring_name`). Update callers (main.gd preview text; solver target enumeration below).
- **Solver target enumeration** (`scoring_modifier_manager.gd` ~lines 375–420 in `_recompute_max_single_dart_score`/precompute, and ~700 in `compute_preferred_remainders`): currently reads `single`/`multi` to stamp `segment_color` on speculative targets. Switch to the matching per-ring key (inner_single/triple/outer_single/double). **Note:** color never affects face value or multiplier, so the checkout *math* and perf are untouched — this only keeps color-streak *previews* accurate.
- **`scoring_modifier_manager.gd::_init_default_board_state()`** — build the 4-key dict.

### Bosses

- **Recession boss** (`recession_boss.gd`) — *no behavioral change* (per Max). It reduces the *value* of one color's wedges; it currently keys "is this wedge color X?" off the old `single` key. Map that to **`inner_single`** as the wedge's representative single color. Value reduction still applies to the whole wedge. Flagging the representative-ring choice as a minor open decision below.
- **Prism boss** (`prism_boss.gd`) — **changing from a per-turn color *shuffle* to a leg-scoped pair *inverter*** (decision #1, resolved). New behavior: at `on_leg_start`, invert every ring of every wedge to its color pair (red↔green, black↔white); hold for the whole leg; restore at `on_leg_end`. Drop the per-turn `on_turn_start` reshuffle and the `reshuffle_interval` cadence — inversion is applied once and held, not re-rolled each turn. Inversion is an involution (its own inverse), so the existing `on_leg_start` snapshot + `on_leg_end` restore preserves brush paint cleanly; the restore can either replay the inversion or restore from the snapshot (snapshot is more robust if a brush is acquired mid-leg). With per-ring color this inverts all four ring keys per wedge. Rationale and the pitfall it avoids are in decision #1.

---

## 2. `ConfigType.PICK_SEGMENT`

Add to `scoring_enums.gd::ConfigType`:

```gdscript
PICK_SEGMENT, ## Player picks one specific ring on one wedge (wedge + ring_name)
```

Picker flow mirrors the existing `PICK_WEDGE` path in `main.gd` (`_leg_phase = "wedge_picker"`, `dartboard.set_picker_mode(true)`), but the dartboard highlights and reports a single **ring**, not the whole wedge. The dartboard already computes `ring_name` on hover inside `calculate_score()` and already has per-ring fill/border draw primitives (`_draw_flash_segment`, `_draw_segment_border`), so the highlight is a matter of routing hover → single-ring highlight and click → `{wedge_index, ring_name}`.

`main.gd::_update_picker_prompt()` gets a `PICK_SEGMENT` branch: header "Paint a segment <Color>", live prompt like "Paint Triple 20 <Color>? Click to confirm, Escape to cancel." `config` passed to `apply_to_board` is `{"wedge_index": int, "ring_name": String}`.

---

## 3. `BrushModifier` (replaces `ColorFlipModifier`)

New `scripts/modifiers/brush_modifier.gd`:

- `timing = ON_ACQUIRE`, `kind = BOARD_MUTATION`, `config_type = PICK_SEGMENT`. Consumable — one ring per item, no panel presence (same lifecycle as the old ColorFlip).
- `@export var target_color: ScoringEnums.SegmentColor` — the color this brush paints, **pre-rolled at generation** (like `ColorStreakModifier` rolls its `target_color`). No second config step for the player; they only pick the segment.
- `modifier_name = "Brush: <Color>"`, e.g. "Brush: Red". `description` like "Paint any one segment <color>."
- `apply_to_board(_values, wedge_colors, config)`: `wedge_colors[config.wedge_index][config.ring_name] = target_color`. That's the whole effect.
- `get_config_fingerprint()` includes `target_color` so the shop dedup treats different-color brushes as distinct.

**Remove** `ColorFlipModifier` from `modifier_registry.gd::MODIFIER_TYPES` and `ColorShopBias`, add `BrushModifier` in its place. Delete `color_flip_modifier.gd` (+ `.uid`) and the `ColorFlipModifier` special-cases in `main.gd` (picker header/prompt at ~1200, ~1642, ~2194). Scan for any other `ColorFlipModifier` / `_ColorFlip` references first.

### Rarity

Recommendation: **brush is common-tier only** (`get_rarity_weights()` → `[100, 0, 0]`, like the old ColorFlip), rarity is flavor/price only. The affinity gate (item 4) does all the interesting gating, which supersedes the original common=white/black / rare=red/green palette idea — see open decision #2. The `generate(rarity)` signature stays uniform with the registry; brush ignores the forced rarity and stamps COMMON.

---

## 4. Affinity-gated pooling (Stone Joker model)

**Goal:** a `Brush: <Color>` only appears in the shop if the player owns a modifier that *cares about* that color — i.e. a `ColorStreakModifier` or `ColorBonusModifier` whose `target_color` matches. No color modifier → no brushes at all. Own a Green Streak → Green brushes can appear.

This also organically resolves the Red/Green timing concern: red/green brushes surface exactly when you're building red/green, regardless of rarity.

### Mechanism

The registry's generation is **static and stateless** — it has no access to `active_modifiers`. Mirror the existing `ModifierRegistry.current_rarity_shift` static-var pattern:

- Add `static var available_brush_colors: Array[ScoringEnums.SegmentColor] = []` on the registry (or on `BrushModifier`).
- The **shop call site** (wherever `generate_distinct_at_rarity` is invoked) computes the affinity set before generating:

  ```gdscript
  var colors: Array = []
  for m in active_modifiers:
      if (m is ColorStreakModifier or m is ColorBonusModifier) and not m.target_color in colors:
          colors.append(m.target_color)
  ModifierRegistry.available_brush_colors = colors
  ```

- `BrushModifier.generate(rarity)` rolls `target_color` from `available_brush_colors`.
- **Weight gating** uses the existing `weight_overrides` channel (already plumbed for `ColorShopBias`): when `available_brush_colors` is empty, set the brush's override to `0.0` so it can't be selected; otherwise leave it at its base weight (or a small bump — Max suggested bumping its weight when a color build is online). `get_pool_weight()` stays a normal nonzero base so the multiplier channel can both suppress (×0) and bump (×>1).

Note the brush is intentionally conditional — with no color modifier it does nothing (color never touches face value/multiplier), so gating it out of the pool when it's dead is correct, not just cosmetic. `ColorShopBias` should fold brushes into its color-flavored bias so they show up when a color build is forming.

---

## 5. Out of scope

- ~~Prism becoming a pair-inverter~~ — now **in scope** (decision #1 resolved; see the Prism bullet under item 1). Re-cadencing prism to leg-scoped is part of this spec.
- Multi-ring or whole-wedge brushes, or letting the player choose the color at pick time. One ring, pre-rolled color, per Max.
- A rarity-driven palette (common=white/black, rare=red/green). Superseded by the affinity gate unless decision #2 says otherwise.
- Saving/serializing painted board state beyond the current run (board resets on `reset_for_run`, persists across legs — unchanged).

---

## 6. Open decisions (resolve before/at implementation)

1. **Prism: leg-scoped pair inverter (RESOLVED 2026-05-30).** Prism becomes a **leg-scoped color-pair inverter**, replacing the current per-turn shuffle. Invert every ring to its pair (red↔green, black↔white) at `on_leg_start`, hold all leg, restore at `on_leg_end`. **Why over the old shuffle:** the shuffle merely *relocated* intact uniform wedges, preserving each color's count — a mild "re-aim" disruption that barely touches a paint-the-board color build. Inversion *attacks the color itself* (your painted green segments all become red), which is the sharper, thematically coherent counter to the brush meta. **Why leg-scoped, not per-turn:** a per-turn inversion is an involution and would just *toggle* (turn 1 inverted, turn 2 back to normal), leaving half the turns free. Applying it once at leg start and holding it gives a stable challenge with no oscillation, and it's actually simpler than the per-turn permute. **Not** per-ring randomization — that would shred the board into incoherent noise; inversion preserves board structure, only swapping colors to their pairs.
2. **Brush rarity role.** Recommendation: common-only, affinity gate does the work. Alternative: keep a rarity-palette (cheap white/black vs premium red/green) on top of the affinity gate. **Resolved: common-only.**
3. **Recession representative ring.** With per-ring color, "wedge of color X" needs one representative ring for recession's match test. Recommendation: `inner_single` (closest successor to the old `single` key). Minor. **Resolved: `inner_single`.**

---

## 7. Implementation order

1. **Per-ring color model (item 1)** first — it's the foundation everything else sits on. Land it with the board rendering four ring colors and the standard board looking identical to today (default seeding produces the same two-tone look). Verify scoring, hover, and recession still behave. **Rework prism to the leg-scoped inverter here** (decision #1) — it depends on the per-ring model and is a natural part of touching the color system; verify it inverts at leg start, holds, and restores brush paint at leg end.
2. **`PICK_SEGMENT` config + picker (item 2)**.
3. **`BrushModifier` replacing ColorFlip (item 3)**.
4. **Affinity-gated pooling (item 4)** last — it's the smallest piece and depends on the brush existing.

Update `DesignNotes.md` once the shape is confirmed.
