---
Spec date: 2026-05-31
Status: Handed to Claude Code for implementation 2026-05-31 (Bug 1 + Bug 3 ready; Bug 2 deferred pending repro)
Implementation: Claude Code
Notes: Bug 1 (recession color match) and Bug 3 (ring-accurate checkout highlight + bust guard) are the implementation targets. Bug 2 (-x% reveal speed) is blocked on a repro and was not implemented. The checkout-helper UX direction (gated inner/outer text + path illumination) was split into the follow-up spec specs/2026-05-31-checkout-path-illumination.md.
---

# Spec: Post-Color-Brush Bug Fixes (Recession + Checkout/Bust Trust)

Three bugs surfaced in 501/1001 playtests after the Color Brushes + Per-Ring Board Color feature shipped (2026-05-31, archived at `specs/2026-05-30-color-brushes-per-ring-color.md`). Two have confirmed root causes and are ready to implement. One needs a repro before it can be fixed. This spec was produced by two independent diagnostic passes (this one + a parallel Claude Code pass); where they disagreed, the reconciliation is noted.

## Bug 1 — Recession boss does nothing ~50% of the time (CONFIRMED, ready)

**Symptom:** Recession boss announced its debuff ("Red wedges -25% for the leg") but the board and scoring were unaffected on the 501 encounter; on a later 1001 encounter the same boss worked.

**Root cause:** `scripts/bosses/recession_boss.gd`. The boss rolls `_affected_color` from all four colors — RED, GREEN, BLACK, WHITE (line 22-28) — but the wedge-matching loop only compares against each wedge's **`inner_single`** color (line 34):

```gdscript
if wedge_color.get("inner_single", -1) == _affected_color:
```

On a standard board, `inner_single` is only ever BLACK (even wedges) or WHITE (odd wedges) — RED and GREEN live exclusively on the `triple`/`double` rings (`scoring_modifier_manager.gd:_init_default_board_state`). So whenever recession rolls RED or GREEN (50%), zero wedges match, `_affected_wedge_indices` stays empty, nothing is reduced — yet `get_status_text()` still announces the debuff. The "501 vs 1001" difference is pure RNG on the color roll, not level-specific.

**Both diagnostic passes agree on this.** The two passes proposed different fixes:
- (A) Restrict the roll pool to BLACK/WHITE only.
- (B) Match if the affected color appears on **any** ring of the wedge, and/or roll the affected color only from colors actually present on the board.

**Decision: go with (B).** Restricting to BLACK/WHITE (A) would make recession permanently blind to brushed boards, where the Color Brush feature means any ring can now be any color — that directly contradicts the feature that just shipped. (B) is the forward-compatible fix.

**Implementation notes:**
- Recession reduces `effective_wedge_values[idx]`, which is a **per-wedge** value affecting all four rings of that wedge — that part is correct and unchanged. Only the *match condition* (which wedges count as "this color") is wrong.
- Change the match to: a wedge qualifies if `_affected_color` appears on any of its four ring keys (`inner_single`, `outer_single`, `triple`, `double`).
- Belt-and-suspenders: build the roll pool from colors actually present in `effective_wedge_colors` so a fully-brushed-away color can never be rolled into a guaranteed no-op.
- Keep `get_status_text()` honest — if (defensively) no wedges match, it should not announce a reduction.

## Bug 2 — `-x%` recession reveal speed (NEEDS REPRO, do not implement yet)

**Reported:** the `-x%` scoring animation should play at a static speed, unaffected by the per-turn scoring-speed ramp.

**Status:** Could not reproduce from code in either pass. The only speed ramp is the multi-trigger pip acceleration in `_spawn_trigger_animation` (`main.gd:2569-2571`), and it is explicitly reset with `tween.set_speed_scale.bind(1.0)` at line 2591 — **before** the recession `-x%` reveal block (line 2599). The no-trigger path (`_spawn_simple_floating_score`) builds its own fresh tween at base speed. So as written the reveal already plays at base speed in both paths. No global animation-speed setting was found affecting it.

**Open question for Max:** does the `-x%` still look fast on a *plain* recession single (no `+x` triggers), or only on a dart that first plays a long multi-trigger combo? If the latter, the reveal is base-speed but chained immediately after the sped-up combo — fixable by giving the reveal its **own dedicated tween** so it structurally cannot inherit `speed_scale`. Hold implementation until the repro distinguishes these.

## Bug 3 — Checkout helper / gold highlight pointed at a segment that busts (CONFIRMED, CRITICAL, ready)

**Symptom:** Gold highlight + checkout helper suggested "S18" as a finish; the hover tooltip correctly warned it was a bust; the throw busted. With Glass Cannon active, the bust ended the run. Players must be able to trust the help — this is the highest-priority fix.

**Root cause — ring granularity lost in the checkout path (this requires the per-ring color feature to manifest):**

The bonus modifiers are deterministic and per-segment: `ColorBonusModifier`/`ColorStreakModifier` trigger on `result["segment_color"]`; `OddEvenBonusModifier`/`ParityStreakModifier` trigger on `face_value % 2`. They are run identically by both the highlight path and the hover/throw path, so streak/preview timing is **not** the cause (ruled out — both use the same preview pipeline and streak state).

The break is that the checkout systems collapse a wedge's two single rings into one ring-agnostic answer:

1. `calculate_checkout_segments()` (`scoring_modifier_manager.gd:902-941`) enumerates **inner single and outer single as separate candidates**, each with its own ring color, but emits a single ring-agnostic marker `{type:"single_wedge", wedge_idx}` (line 941) if *either* qualifies. It does not record which ring finished.
2. `dartboard.gd:_draw_checkout_pulses()` draws the `single_wedge` marker **only over the outer-single ring** (line 1258-1262: `_effective_double_inner()`→`RING_TRIPLE_OUTER`). So if only the **inner** single finishes, the gold ring is painted on the **outer** single — i.e. on a different segment than the one that actually finishes.
3. The checkout helper's `get_target_display_name()` (`scoring_modifier_manager.gd:586-602`) labels both singles as plain `"S18"` with no inner/outer distinction.

On a vanilla board both singles share color and value, so they always score identically and nothing diverges. **Per-ring color brushing breaks that invariant:** inner-S18 (color A, no bonus) = 18 = remaining → emits the wedge marker; outer-S18 (color B) triggers a Color/Parity bonus → 36 → overshoot → bust. The board paints gold on the outer (busting) ring, and the helper says "S18". The hover tooltip is correct because `_is_checkout_segment` gates on `total_score == remaining` for the *actually hovered* segment (`main.gd:2037`) and `_would_bust` re-evaluates the hovered segment exactly.

So the highlight/helper and the real throw + bust-check are separate code paths that diverge the moment one ring of a wedge carries a per-ring color/parity bonus the other ring doesn't. This is glass-cannon-amplified because singles only become checkout-eligible under Glass Cannon (and a bust there ends the run), but the mismatch exists for any single-ring finish whenever the two single rings differ.

**Note on the parallel pass:** the Claude Code pass hypothesized a `speculative_score`/solver-cache coherence issue (`is_preview:false`, hash collisions). That is the wrong tree for this symptom: the **gold board highlight** comes from `calculate_checkout_segments()`, which never touches the solver or its cache — so a cache problem is physically incapable of corrupting the gold highlight the user reported. The `is_preview:false` in `speculative_score` is intentional (dart-2 must see dart-1's streak state) and the streak-hash is collision-safe in practice. That pass's *paranoia guard* idea is still worth keeping as defense-in-depth (see below).

**Implementation — make the help authoritative and ring-accurate:**

1. **Thread ring identity through the marker.** In `calculate_checkout_segments()`, when a single ring finishes, emit the specific ring, e.g. `{type:"single_wedge", wedge_idx, ring_key:"inner_single"|"outer_single"}`, evaluating each single ring independently. Only emit the ring(s) that actually finish.
2. **Draw the correct ring.** In `dartboard.gd:_draw_checkout_pulses()`, branch the `single_wedge` case on `ring_key` and draw the inner-single band (`RING_INNER_SINGLE_OUTER`→`RING_SINGLE_BULL_OUTER`) or outer-single band accordingly. Update `_is_checkout_segment` (`main.gd:2052`) to match on the specific ring rather than accepting either.
3. **Disambiguate the helper label.** `get_target_display_name()` should distinguish inner vs outer single (e.g. "S18 (inner)") so the text can't point at the wrong ring. (Superseded by the follow-up illumination spec, which gates this text behind score divergence and reformats it to "Inner S18" / "Outer S18".)
4. **Defense-in-depth guard (from the parallel pass).** As a final safety net, before publishing any checkout highlight/helper entry, re-run the exact segment through the same evaluation the real throw + `_would_bust` use; if it would bust, drop it. This guarantees the help can never point at a busting segment even if a future modifier introduces another divergence. Authoritative re-validation is the durable fix; ring-threading (1-3) fixes the specific visual.

**Acceptance for Bug 3:** on a brushed board where one single ring of a wedge carries a color/parity bonus and the other doesn't, with the remaining score equal to the un-bonused single's value: only the finishing ring is painted gold, the helper labels that exact ring, and hovering the busting ring still warns bust. No highlighted/suggested segment may ever bust when thrown.

## Suggested order
Bug 1 (small, isolated, high confidence) → Bug 3 (critical, multi-file: `scoring_modifier_manager.gd`, `dartboard.gd`, `main.gd`) → Bug 2 (blocked on repro). A verification pass should cover: recession rolling each of the 4 colors reduces the right wedges; a Glass Cannon brushed-board checkout where inner/outer singles diverge highlights only the finishing ring and never suggests a bust.
