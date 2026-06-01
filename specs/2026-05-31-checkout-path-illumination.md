---
Spec date: 2026-05-31
Status: Drafted and unblocked — its dependency (Bug 3 ring-threading + bust guard, specs/2026-05-31-post-color-brush-bug-fixes.md) shipped and that spec is closed (2026-06-01). Not yet implemented; ready to start. Stepped down as the active CLAUDE.md spec by the Throw Anticipation Animation spec (2026-06-01); this is the next implementation target.
Implementation: Pending (not started; dependency cleared)
Notes: Follow-up to the post-color-brush bug fixes. Illumination reads the ring-accurate, re-validated path/segment data that Bug 3 produced. Two pieces: necessity-gated inner/outer ring labels (Part 1) and checkout path illumination (Part 2). The open sub-decision (illuminate current step only vs. all steps) is flagged for Max during implementation.
---

# Spec: Checkout Path Illumination + Necessity-Gated Ring Labels

Follow-up to the Post-Color-Brush Bug Fixes spec (archived at `specs/2026-05-31-post-color-brush-bug-fixes.md`, handed to Claude Code). That pass makes the checkout help **trustworthy** (ring-accurate gold highlight + a guard that drops any segment that would bust). This spec makes it **legible** once per-ring color/value brushing makes the board ambiguous — so the player can act on the help with confidence rather than reading paragraphs of qualifier text.

**Depends on:** the Bug 3 ring-threading + bust guard from the archived spec must land first. Illumination reads the same ring-accurate, re-validated path/segment data that fix produces. Do not start this until that fix is merged.

## Problem

Per-ring color brushing breaks the old assumption that a face value identifies a segment. Max's worked example: with a +1 value brush on 19 and color brushes making one 20's inner single green and another 20's outer single red, the board can show **four different single-20 segments** with different colors and different resulting scores. A text-only checkout line ("S20") can't address that, and pushing text to disambiguate spirals into nonsense ("Inner Green S20, upper-left"). The disambiguation has to live on the **board** (spatial), with text staying a label, not an address.

Two complementary pieces:
1. **Necessity-gated ring labels** — small text nicety for the common two-rings-one-wedge case.
2. **Path illumination** — the general mechanism for everything text can't address.

## Part 1 — Necessity-gated inner/outer ring labels

The archived spec's step 3 added an unconditional "(inner)/(outer)" qualifier to `get_target_display_name()`. Refine it:

- **Only show the qualifier when it matters.** A single-ring finish gets an "Inner"/"Outer" prefix **iff** that wedge's inner single and outer single produce a **different resulting `total_score`** under the current scoring pipeline (run both rings through `process_score` and compare). If they're identical, show plain "S18" — no qualifier.
- This is the same necessity philosophy as the Color Brush UI (which stays hidden until the player has color modifiers): the qualifier is invisible on a vanilla board and only appears when brushing has actually made the rings diverge. It is **self-maintaining** — keyed on score divergence, not on "does the player own a brush" — so it covers value mods, parity mods, color mods, and anything future without special-casing.
- **Format:** leading and capitalized — `"Inner S18"` / `"Outer S18"` (not the trailing `"S18 (inner)"` from the archived draft).
- This handles the two-singles-of-one-wedge case only. It deliberately does **not** try to address two-different-wedges-same-value — that is illumination's job. Keep the printed path text simple; the board carries the precision.

## Part 2 — Checkout path illumination

**Model (always-on helper, one selected path illuminated):**
- The checkout helper is visible by default whenever checkouts exist (current behavior).
- A **toggle** controls path illumination on/off (exported default for Max to set). When illumination is on, exactly **one** path is the *selected* path and it is highlighted on the board. When off, no path highlight is drawn (the trust-critical gold finish pulse from the archived fix still behaves as before).
- **Selection:** default to the solver's top-ranked path (fattest/safest, per `_compare_paths`). The player can **click** a path line in the helper panel to select it, or use **arrow keys** to cycle once a selection exists. The selected line is visually marked in the panel to match its board highlight.
- Rationale for "always-on selected path" over a bare toggle: the bug being addressed is "help shown but not spatially grounded." A toggle that leaves text visible with nothing lit reintroduces that ungrounded state. Fewer modes = more trust. (If Max prefers a default-off toggle, that's a one-line default flip — but the selected-path-always-lit-when-on behavior should hold.)

**Illumination semantics (the important part):**
- For a path step, illuminate **every board segment that genuinely satisfies that step under the path's accumulated scoring state** — not just one segment. Max's example: a first-throw step `S20 (80)` should light **all** single-20 segments that resolve to 80 given current color/value modifiers, so the player has equivalent options rather than one arbitrary pick.
- **Streak/state correctness is the gating constraint.** A step's resulting score can depend on state earlier steps build (e.g. a path that routes through a red streak: the `(80)` only holds if the red streak is active). Illumination must compute each step's highlight set against the **streak/parity state the path produces up to that step** (snapshot → replay prior steps → evaluate candidates → restore), the same speculative machinery the solver already uses. Only segments that *actually* yield the step under that state may light up. Never illuminate a face-equal segment that would diverge once the streak is considered — that would recreate the very "trust" bug this whole effort is fixing.
- Equivalence is by **resulting effect** (resulting score, and that it advances the path), evaluated through the real pipeline — not by raw face value.

**Open sub-decision (flag for Max during implementation):** whether to illuminate all steps of the selected path at once (step 1 + step 2 + step 3, color-coded or numbered 1/2/3) or only the *current/next* step's equivalent set with later steps shown as text. Multi-step illumination is richer but later steps fan out combinatorially (step 2's valid set depends on which step-1 segment was hit). Recommended default: illuminate the **current step's** full equivalent set; render later steps as text in the panel. Revisit if Max wants the whole route drawn.

**Visual — blue ring outline, all tunable:**
- Path illumination draws a **blue outline on the ring** of each qualifying segment (distinct from the gold checkout-finish pulse so the two layers read differently).
- Export vars on `dartboard.gd` (mirror the existing `checkout_pulse_*` group): outline color, pulse rate/speed, border thickness, and min/max alpha. Max tunes all of these.
- When a path is selected and illuminated, **de-emphasize the generic gold all-finishes pulse** (dim or suppress) so the chosen route is the focus and the two highlight systems don't fight for attention.

## Files in scope
- `scripts/scoring_modifier_manager.gd` — score-divergence test for label gating; per-step equivalent-segment + state-aware enumeration for illumination (reuses `snapshot_all_streak_state` / `restore_all_streak_state` / `speculative_score`).
- `scripts/main.gd` — selection state, click + arrow-key input, wiring selected path → dartboard.
- `scripts/dartboard.gd` — blue path-illumination draw pass + exported tuning vars; de-emphasis of gold pulse when a path is illuminated.
- `scripts/hud.gd` — illumination toggle, selected-line marking in the checkout panel, simplified (gated) path text.

## Acceptance
- Vanilla board: no inner/outer qualifiers, illumination behaves as a single clear path; nothing regresses.
- Four-color-S20 board: selecting a path that finishes on a specific single-20 lights exactly the segments that yield the path's required score, and no others; the printed line stays simple ("S20") because the board disambiguates.
- Streak path: a checkout that depends on a red streak only illuminates segments consistent with that streak's accumulated state; face-equal but state-divergent segments are not lit.
- Label gating: "Inner S18"/"Outer S18" appears only when that wedge's two singles resolve to different scores; otherwise plain "S18".
- No illuminated or suggested segment may ever bust when thrown (inherited invariant from the archived fix; must still hold).
