# Checkout Helper

**Spec date:** 2026-05-22
**Status:** Designed, ready for implementation
**Scope:** New always-on (toggleable visibility) helper that surfaces valid checkout paths and setup-target recommendations, accounting for all active scoring modifiers including live streak state. Builds on the existing `calculate_checkout_segments` function in `scoring_modifier_manager.gd` and the established preview-mode scoring pipeline. Replaces the implicit "the player figures it out" assumption that breaks down once 5+ modifiers are stacked.

## Summary

At low modifier counts the player can mentally compute checkout paths from the standard x01 chart. By the time 5+ modifiers are stacked — especially with mid-turn streak modifiers (wedge / color / parity) that mutate state per-dart — the math becomes effectively impossible to do by hand. The helper closes that gap with a solver that runs the actual scoring pipeline in simulation, surfaces valid paths in a text panel, and recommends setup targets when no checkout is available.

Six parts to the spec:

1. The solver — recursive simulation, candidate target set, speculative state save/restore.
2. The setup solver — recommended throws when no checkout exists, using a precomputed preferred-remainder list.
3. The display — right-side text panel with annotated paths and progressive narrowing.
4. The toggle button — visibility control, gated by checkout availability.
5. The modifier-toggle soft hint — passive nudge to experiment with toggling modifiers.
6. Edge cases — off-board preservation, off-script throws, hopeless states.

---

## 1. The Solver

The solver answers: "given my current remaining, darts left this turn, active modifiers, and live streak state — what darts can I throw to land at exactly 0 with a double on the finishing dart?"

### 1a. Approach

Recursive simulation, not a lookup table. The existing `process_score(raw_result, is_preview)` pipeline in `scoring_modifier_manager.gd` already handles modifier application correctly for single darts. The solver wraps that pipeline in a multi-dart recursive search:

```
func solve_checkout(remaining, darts_left) -> Array[CheckoutPath]:
    paths = []
    for target in candidate_targets:
        snapshot = snapshot_streak_state()
        result = speculative_score(synthesize_result(target))
        if is_finishing_dart(target) and result.total_score == remaining:
            paths.append([target])
        elif result.total_score < remaining and darts_left > 1:
            for sub_path in solve_checkout(remaining - result.total_score, darts_left - 1):
                paths.append([target] + sub_path)
        restore_streak_state(snapshot)
    return paths
```

Only doubles (including double bull) can be the finishing dart per x01 rules.

### 1b. Candidate target set

Each dart's candidate target list:

- **40 single hits** (20 inner singles + 20 outer singles). Per the existing modifier code, inner and outer singles share face value but differ in ring zone — important for wedge-streak modifiers with `SAME_RING` or `ADJACENT_SECTIONS` leniency. Solver treats them as distinct candidates; the display layer collapses them to `S{wedge}` with the larger-area outer single preferred for tie-breaks.
- **20 doubles**
- **20 triples**
- **Single bull** (face 25, multiplier 1)
- **Double bull** (face 25, multiplier 2)
- **One "deliberate non-scoring" candidate** — represents an intentional off-board throw. Scores 0 face value, no multiplier, `wedge_index = -1`, `segment_color = -1`. By construction it resets all currently active streaks (each streak modifier's reset condition fires on this input). Required for finding paths that involve strategic streak-breaking.

Total: 83 candidates per dart.

Note: the deliberate non-scoring candidate covers off-board-style streak-breaking. Streak-breaking via a low-value scoring hit (e.g., single 4 to break an odd streak while still adding 4 to the total) is already covered by the normal scoring candidates — no separate candidate type needed.

### 1c. Speculative state save/restore

The current `is_preview=true` mode deliberately does *not* mutate streak state. That's correct for hover tooltips. For multi-dart recursion, dart-2's simulation must see the streak state dart-1 would have created — so a new mutating-but-restorable "speculative" mode is required.

**`ScoringModifier` base class additions:**

- `func save_streak_state() -> Dictionary` — returns a snapshot of all internal streak fields (default returns empty dict for non-streak modifiers).
- `func restore_streak_state(snapshot: Dictionary) -> void` — restores from a snapshot.

Each streak modifier subclass (`StreakBonusModifier`, `ColorStreakModifier`, `ParityStreakModifier`) overrides these to snapshot/restore their member vars (`_streak_count`, `_streak_wedge_index`, `_streak_ring`, `_streak_color`).

**`ScoringModifierManager` additions:**

- `func snapshot_all_streak_state() -> Array[Dictionary]` — calls `save_streak_state` on each active modifier, in order.
- `func restore_all_streak_state(snapshots: Array[Dictionary]) -> void` — restores in matching order.
- `func speculative_score(raw_result: Dictionary) -> Dictionary` — runs the same pipeline as `process_score`, mutates streak state, does *not* append to hit history.

The solver wraps each candidate dart in a snapshot/restore around the recursive sub-call. Hit history (turn/leg/run) is similarly preserved by not appending during speculative simulation.

### 1d. Result ranking

Returns the top N paths (default 5, exported tuning var `max_displayed_paths`) ranked by:

1. **Fewest darts first** — finish in 1 > finish in 2 > finish in 3.
2. **Fattest reliable segment** within the same dart count — larger singles (outer) > smaller singles (inner) > doubles > triples (variance heuristic; rewards consistent play). Bulls rank between doubles and triples by physical size.
3. **Fewest deliberate-non-scoring darts** as final tie-breaker — paths that fully use their darts rank above paths that include intentional skips.

### 1e. Performance

Worst case ~83³ ≈ 570k leaves per turn, computed at turn start and again after each throw. Trivially fast in GDScript at frame-time scales. Within a single `solve_checkout` call, cache by `(remaining, darts_left, streak_state_hash)` to dedupe identical sub-problems. No cross-turn caching needed.

---

## 2. The Setup Solver

When `solve_checkout` returns zero valid paths, the helper switches to setup mode and recommends a single dart target that leaves the player at a remainder with known good checkouts next turn.

### 2a. Preferred remainder list (precomputed)

For the current modifier configuration, precompute the set of remainders that have at least one valid checkout in 3 darts (assuming a turn-fresh streak state for V1):

```
func compute_preferred_remainders() -> Array[int]:
    preferred = []
    for r in range(2, 181):
        if solve_checkout(r, 3).size() > 0:
            preferred.append(r)
    return preferred
```

This runs once when modifier state changes — acquire, sell, swap, toggle, leg reset — and is cached on `ScoringModifierManager`. Roughly 179 solver runs; the work is spread across an event rather than a throw, so per-throw cost is just a set membership check.

### 2b. Setup recommendation

When no checkout exists this turn, for each candidate dart target:

1. Speculatively simulate the throw; observe the resulting remainder.
2. Score this target by where its resulting remainder ranks in the preferred-remainder list. Higher preferred remainders (more dart slack next turn) outrank lower ones.

Pick the single best setup target. Display: `"Aim {target} → leaves you at {remainder}"`.

V1 always recommends one dart at a time, even when called early in the turn. The recommendation updates after each throw. Multi-dart setup planning is deferred.

### 2c. Off-board preservation

If every scoring candidate would push the remaining below 0 (bust) or into a non-checkout-eligible state with no recoverable setup, the solver's deliberate non-scoring candidate naturally wins by being the only target that preserves the remaining. The display string in this case reads `"Aim off-board → preserves remaining ({remaining})"` rather than the default setup phrasing.

This emerges naturally from the solver; no special code path needed beyond the display layer recognizing the deliberate-non-scoring target and labeling it as preservation.

### 2d. V2 streak-aware preferred list (deferred)

V1 assumes turn-fresh streak state when computing the preferred-remainder list. This is correct for `WITHIN_TURN` streak modifiers (they reset at turn end) but potentially inaccurate for `WITHIN_LEG` modifiers that carry an active streak into next turn. Upgrade only if playtest shows the setup recommendations giving bad advice in carry-over scenarios.

---

## 3. Display

### 3a. Location

Right-side panel, below the current stats readout. Permanent UI region — same panel slot whether the helper is visible or hidden. Position, panel background, font sizes, text colors, and spacing all exported with hover descriptions per project conventions.

### 3b. Path display format

When the helper is visible and checkouts exist, show the top N paths as an ordered list. Each path renders as a single line:

```
Dart 1 → Dart 2 → Dart 3
```

With segment names spelled out (`T20`, `S5`, `D20`, `Bull`, `D-Bull`). For dart targets with notable modifier interactions, append a parenthetical annotation:

```
0 (break Odd ×2) → D5 (10)
T20 (60) → T20 (Wedge ×2: 90) → D-Bull (50)
```

Annotation rules:

- **Deliberate non-scoring dart:** always annotate with the streak being broken: `(break {streak_name} ×{count_before_break})`. If multiple streaks are being broken by this dart, list them comma-separated.
- **Dart triggering a streak bonus:** `({streak_name} ×{N}: {effective_score})`.
- **Vanilla dart with no streak interaction:** `({score})`.

All annotation string templates exported so wording can be tweaked without code changes.

### 3c. Progressive narrowing on throws

After the player throws a dart:

1. Determine which displayed paths started with that exact dart target.
2. Keep those paths visible; the first-dart portion of the label highlights in green to indicate the committed step.
3. Filter out paths that did not start with the actual hit.
4. If zero displayed paths remain (player went off-script, missed, or the throw scored differently due to modifier RNG), full recompute from new remainder and display the new top N.

This preserves player intent — the helper does not snap to a different optimal path the player wasn't planning to follow.

### 3d. No board markup

The dartboard itself receives no new visual treatment from the helper. Existing checkout-double highlights (the `calculate_checkout_segments` overlay) remain as-is. No path arrows, numbered overlays, or aim indicators on the board. All helper information is textual in the side panel.

---

## 4. Toggle Button

A single button controls helper visibility. Three states:

- **Disabled (greyed):** No valid checkout exists this turn. Button is non-pressable. The setup recommendation (when relevant) is shown independently of this button — setup messaging is always displayed when active.
- **Inactive (pressable, helper hidden):** At least one valid checkout exists, but the player has chosen to hide the helper. Button reads "Show Checkout" or carries an icon for the hidden state.
- **Active (pressable, helper visible):** Helper is showing. Button reads "Hide Checkout" or shows the active state.

The button state recomputes after every throw and every modifier-state change. The player's visibility preference persists across throws — toggling on once keeps the helper visible until the player toggles off (or the disabled state preempts it).

Button styles for each state — colors, icons, label strings — all exported with hover descriptions.

---

## 5. Modifier-Toggle Soft Hint

When the player has at least one toggleable (unlocked) scoring modifier active, the helper appends a one-line soft hint below the path list:

> Try toggling a modifier to recalculate

The hint:

- Does *not* suggest which specific modifier to toggle. The active recommendation ("disable Color Streak to enable T20-T20-Bull") is intentionally avoided — it makes the helper feel like it's playing for the player.
- Only appears when the player has at least one unlocked modifier in the active set. If all active modifiers are locked, the hint is suppressed.
- Appears in both checkout and setup states.

The helper recomputes on every modifier-toggle event, just as it does on throws. No special UI for the recompute — the panel updates in place.

Hint text exported as a string variable for easy phrasing tweaks.

---

## 6. Edge Cases

- **Player throws something not on any displayed path:** Full recompute from new remainder. No "off-script" UI; the helper just updates.
- **Multiple paths tie at every ranking criterion:** Stable sort by candidate target enum order. Predictable, never surfaces UI noise.
- **Off-board preservation state:** Setup solver naturally produces the off-board recommendation; display layer labels it appropriately (see 2c).
- **Helper visible but no checkouts exist:** Toggle button greys out; setup recommendation displays in the same panel region with a distinct visual treatment (e.g., italic, different color tag) to differentiate setup from checkout.
- **Player at remaining 1 or other non-checkout-eligible value:** Solver returns no paths (no double sums to 1). Helper treats this as a setup case.
- **Speculative simulation must not leak into hit history:** Solver wraps simulations to ensure `hit_history_turn` / `hit_history_leg` / `hit_history_run` remain untouched until a real throw lands.

---

## Deferred / Out of Scope

- **V2 streak-aware preferred remainder list.** Project carried-over streak state forward when computing the preferred set. Build only if V1's setup recommendations fail in playtest under `WITHIN_LEG` / `WITHIN_RUN` carry-over scenarios.
- **Active modifier-toggle suggestions.** Helper telling the player exactly which modifier to disable to unlock a checkout. Intentionally avoided per agency-over-hand-holding design call.
- **Dart-accuracy-aware EV ranking.** Ranking paths by the player's actual hit probability using dart component stats. Currently the fattest-reliable-segment heuristic handles this implicitly. Upgrade only if playtest reveals bad advice.
- **Multi-turn setup planning.** Helper suggesting full 3-dart setup sequences when no checkout exists. V1 handles one dart at a time.
- **Helper interaction with future rule-modifier category** (extra turns, rethrows). Out of scope until rule modifiers exist as a system.

---

## Implementation Notes

- All tunable values exposed as exported variables with hover descriptions per project conventions: `max_displayed_paths`, panel position/colors/font sizes/spacing, button styles for each state, annotation string templates, hint message text.
- Static typing throughout per project conventions.
- The solver lives in `scoring_modifier_manager.gd` alongside the existing `calculate_checkout_segments`. The existing single-dart function should be generalized into the recursive solver — the 1-dart case becomes its base case rather than a separate function.
- Preferred-remainder list cached as `Array[int]` on `ScoringModifierManager`, invalidated and immediately recomputed on any modifier-state change. Recompute is triggered explicitly off the throw path to keep per-throw work minimal.
- Side panel UI extends the existing right-side stats area. Reuse existing panel layout / typography rather than creating a separate widget.
- Toggle button state derives from `solve_checkout(...).is_empty()` — single source of truth, no separate "has checkout" flag to maintain.
- The helper UI listens to existing turn/throw/modifier signals and re-queries the solver. If clean signals don't yet exist for "throw resolved" and "modifier state changed", surface them — they will be needed regardless.

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
