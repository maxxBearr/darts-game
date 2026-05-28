# Checkout Helper — Suggestion Refinement

**Spec date:** 2026-05-27
**Status:** Designed, ready for implementation
**Scope:** Tighten `get_setup_recommendation()` in `scoring_modifier_manager.gd` and the corresponding `update_setup_display()` in `hud.gd` so the suggestion line gives useful advice across the full range of remaining scores. Solver itself (`solve_checkout`) and the per-throw path display are untouched. Builds on the shipped checkout helper (`specs/2026-05-22-checkout-helper.md`).

## Summary

The checkout solver itself works well. The setup recommendation — the single-line suggestion shown when no checkout exists this turn — does not, in two distinct ways:

- **Far-from-checkout states** (e.g., turn 1 dart 1 of a 401 leg) currently fall through to the off-board preservation fallback. Off-board is recommended whenever no scoring dart can land the player at a remainder inside `_preferred_remainders`. That cache only covers 2..180, so any state above ~240 triggers the fallback even when scoring is unambiguously the right call.
- **Mid-zone states** (e.g., 166, where no 3-dart checkout exists but the player should be reducing toward one) ranking can pick a small fat single (S1 → 165) over a high-scoring trip (T20 → 106). Within-tier tiebreaks today are `this_throw_fatness` then `-new_remaining`, both of which bias toward "play safe and keep the remainder high" — the opposite of what setup is supposed to do.

Refactor the recommendation into four explicitly named modes, each with its own trigger condition, ranker, and display string. Modes are evaluated in order; first match wins.

---

## 1. Mode Taxonomy

The solver already covers "can finish this turn." When `solve_checkout()` returns paths, that path display continues unchanged. When it returns empty, the suggestion line picks one of four modes:

| # | Mode | Trigger | Output |
|---|---|---|---|
| 2 | Endgame setup | A scoring dart can land the player at a 1-dart-finishable remainder next turn (Tier 0 today) | Concrete target + resulting remainder |
| 3 | Score-reduction | Even the best scoring dart cannot reach `_preferred_remainders` | Generic "score more points" line — no target |
| 4 | Mid-zone setup | Some scoring dart reaches `_preferred_remainders` (but no 1-dart finish next turn) | Concrete target + resulting remainder |
| 5 | Off-board preservation | Every scoring dart would strictly worsen the state (bust irrecoverably or push to remaining=1) | "Aim off-board — any scoring dart busts" |

The numbering preserves the existing Tier 0 / Tier 1 terminology where it maps cleanly: Mode 2 is current Tier 0. Mode 4 is current Tier 1 with corrected tiebreaks. Modes 3 and 5 are new (or refactored from the existing fallback).

---

## 2. Mode 3 — Score-Reduction

The missing mode. Fires when the player is far enough from checkout that no setup-style recommendation is honest.

### 2a. Trigger

Compute, once per modifier-state change, `_max_single_dart_score` — the highest `total_score` produced by any scoring candidate through `process_score(synth, true)` under turn-fresh streak state. Cached on `ScoringModifierManager` alongside `_preferred_remainders` and `_one_dart_finishable`, invalidated by the same `invalidate_preferred_remainders()` call.

Also cache `_max_preferred_remainder` = `_preferred_remainders.max()` (or 0 if empty). Cheap.

Mode 3 trigger:

```
remaining - _max_single_dart_score > _max_preferred_remainder
```

When true, no scoring dart this throw can reach a 3-dart-finishable next-turn remainder. The 82-candidate sweep is skipped entirely — the trigger is O(1) once the two cached values exist.

### 2b. Display

Single-line suggestion, no target named:

> Score more points to enter checkout range

No "leaves you at N" suffix — irrelevant when N is hundreds away from checkout. No target name — picking one is just noise (player knows what to throw when there's no setup constraint), and skipping the target computation is the perf win.

Title bar above the line remains `— Setup —` for consistency with the other modes' panel layout.

### 2c. Why no recommended target

Per design call: when the situation calls for "just score," any recommendation beyond that is either obvious (T20) or actively confusing if modifiers have shifted top scoring (the player will read the wrong message into a "T18" recommendation under a swapped-value board). Better to stay silent on the specific target.

---

## 3. Mode 4 — Mid-Zone Setup

Triggered when Mode 2 has no candidate but at least one scoring dart lands `new_remaining` inside `_preferred_remainders`. Logic and candidate sweep are the existing Tier 1 — what changes is the ranking.

### 3a. Ranking change

Current key: `[tier, next_turn_fatness, this_throw_fatness, -new_remaining]`.

New key: `[next_turn_fatness, new_remaining]`. (Lower wins; `tier` was redundant because mode selection already gates this.)

Two deletions:

- **Drop `this_throw_fatness`.** It was rewarding small singles because they're "fat targets." But the recommended *this-throw target* doesn't need to be fat — it needs to set up a fat *finishing* dart next turn. `next_turn_fatness` already captures that.
- **Flip `-new_remaining` to `new_remaining`.** Lower remainder = closer to checkout = better setup, all else equal. The original `-new_remaining` direction was the same "higher remainder is more dart slack" misconception the V1 setup logic already corrected away from at the Tier 0/1 boundary.

`next_turn_fatness` stays as the primary tiebreak — that's still about how reliably next turn finishes, which is the real definition of setup quality.

### 3b. Setup quality metric upgrade — explicitly deferred

A richer metric (count of 3-dart paths from `new_remaining`, or whether 2-dart-finishable beats 3-dart-finishable) was considered. Deferred for perf reasons: it would require running the full `solve_checkout` on every candidate's resulting remainder, multiplying solver work by ~80 per recommendation call. The two-deletion change above is expected to fix the observed bug at near-zero cost. Revisit only if playtest still finds bad mid-zone suggestions.

---

## 4. Mode 5 — Off-Board Preservation, Tightened

Today, off-board fires whenever Mode 2 and Mode 4 are both empty. That's the source of the 401 bug — it's a fallback, not a condition.

New trigger, evaluated only after Modes 2/3/4 have all been ruled out:

```
For every scoring candidate, new_remaining is < 2 or scored > remaining (bust)
```

In practice this happens at very low remainings where the only legal scoring options would bust without recovery, or push to remaining=1.

If Mode 5 fires, the display string sharpens to reflect that scoring is *actively harmful*, not just suboptimal:

> Aim off-board — any scoring dart busts

(Compared to the current `"Aim off-board -> preserves remaining (N)"`, which reads as a generic strategy. Post-refactor, off-board should feel like a last resort, not a routine recommendation.)

---

## 5. Display Strings

All four mode strings exported on `hud.gd` for tuning (per project convention). Current `update_setup_display()` branches on `target.ring_name == "Off Board"`; new branching is on a mode enum passed from `main.gd`:

| Mode | String template |
|---|---|
| 2, 4 | `"Aim %s -> leaves you at %d"` (unchanged) |
| 3 | `"Score more points to enter checkout range"` |
| 5 | `"Aim off-board — any scoring dart busts"` |

The `Dictionary` returned from `get_setup_recommendation()` grows a `mode` key (enum: `ENDGAME_SETUP`, `SCORE_REDUCTION`, `MID_ZONE_SETUP`, `OFF_BOARD_PRESERVE`). `update_setup_display()` reads `mode` and picks the template. Target/remainder fields are populated only for modes that need them.

---

## 6. Performance Notes

Max flagged buffering during late-game turns. The refactor should be perf-positive on average:

- **Mode 3 short-circuit.** For every turn where `remaining > _max_preferred_remainder + _max_single_dart_score`, the 82-candidate sweep (each with a `speculative_score` call) is skipped entirely. In a 501 leg this covers most of turns 1–2 and frequently turn 3. In a 1001 leg, more.
- **`_max_single_dart_score` is cached** alongside the existing `_preferred_remainders` / `_one_dart_finishable` caches and invalidated by the same `invalidate_preferred_remainders()` entry point — no new invalidation hooks.
- **Mode 4 deletes work, doesn't add it.** Two fewer fields in the sort key.
- **Setup quality metric upgrade is explicitly deferred** to avoid the per-candidate `solve_checkout` cost.

No new precompute. No new caches beyond the single `int` for `_max_single_dart_score`.

---

## Deferred / Out of Scope

- **Setup quality metric upgrade for Mode 4** (counting paths, 2-dart vs 3-dart preference). Held back for perf; revisit only if the simpler tiebreak fix still produces bad mid-zone suggestions in playtest.
- **Multi-dart setup planning.** V1 still recommends one dart at a time; same scope boundary as the original spec.
- **Streak-aware preferred remainder list (V2).** Carried forward unchanged from the original spec's deferred list.
- **Mode 3 displaying a soft target hint.** Considered "Score points — aim T20 (60)" hybrid. Rejected: Max's call is silence on target in Mode 3, both for clarity and perf.

---

## Implementation Notes

- Mode enum on `ScoringModifierManager` (or a small adjacent script): `ENDGAME_SETUP = 0`, `SCORE_REDUCTION = 1`, `MID_ZONE_SETUP = 2`, `OFF_BOARD_PRESERVE = 3`. Static-typed throughout per project convention.
- `get_setup_recommendation()` rewritten to evaluate modes in priority order (Mode 2 first, Mode 3 trigger check second so the candidate loop can be skipped, Mode 4 third, Mode 5 last). Return dict grows a `mode` key.
- `_max_single_dart_score: int` and `_max_preferred_remainder: int` cached on `ScoringModifierManager`. Computed during the same pass as `_compute_one_dart_finishable()` to share the candidate sweep. Both invalidated by `invalidate_preferred_remainders()`.
- `_max_preferred_remainder` derived as the last element of `_preferred_remainders` (already sorted ascending by the 2..180 loop in `compute_preferred_remainders`).
- `update_setup_display()` in `hud.gd` reads `recommendation["mode"]` and picks the string template. Existing `Off Board` ring-name branch goes away — mode is now the dispatch field.
- All four template strings exported with hover descriptions per project convention. Mode 3 string default: `"Score more points to enter checkout range"`. Mode 5 string default: `"Aim off-board — any scoring dart busts"`.
- `main.gd` `_update_checkout_helper()` is unchanged — it still calls `get_setup_recommendation()` and passes the dict straight to the HUD.
- Spec follow-up after ship: update `DesignNotes.md` § "Setup recommendation" to reflect the four-mode model (currently documents the two-tier model from the original spec).

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
