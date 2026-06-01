---
Spec date: 2026-06-01
Status: Shipped 2026-06-01 (commit `3c27cb1` — "improved turtorial and rules")
Implementation: Manual / Claude Code pass during the same session that wrote this spec; pushed.
Notes: Both additions shipped — the two multi-dart checkout drills (55, then 83) after the existing one-dart 32 drill, and the mechanics→rules explicit two-way hand-off. Deferred items remain deferred: cosmetic mini dart marker + thunk per click (scoring stays click→auto-score), and the unrelated ellipse-reference copy pass in `rules_slideshow.gd`.
---

# Spec: Rules Tutorial — Multi-Dart Checkout Drills + Mechanics Hand-off

Status: **Designed 2026-06-01, not yet implemented.** Two additive extensions to the existing onboarding, agreed in a design session. Neither touches the mechanics-tutorial throw loop or the existing one-dart drill.

## Problem

Two gaps in the current onboarding:

1. **The rules slideshow under-drills checkouts.** It teaches x01 scoring and the doubles rule, then validates with a *single* one-dart drill (32 → D16, in `rules_slideshow.gd::_build_slides`). The core mental loop of x01 — subtract, keep a double in reach, finish on a double — only really clicks across *multi-dart* finishes. One single-dart check doesn't exercise it.
2. **The mechanics tutorial and the rules slideshow are disconnected.** A new player finishes the throw tutorial (`tutorial_controller.gd::_t3_complete` → "Finish" → `tutorial_finished.emit`) and is dropped back to the menu with no nudge toward learning the rules, even though that's the natural next step.

## Design

Two additions, both additive; existing flows unchanged.

### 1. Mechanics → Rules hand-off (explicit choice)

At mechanics-tutorial completion (`_t3_complete`), offer an **explicit two-way choice**: "Learn the rules" vs "Play / back to menu". (Per Max — explicit choice, *not* an auto-flow that opens rules on its own.) Choosing rules launches the existing rules slideshow **as a continuation**; on close it routes back to the original destination (`start_screen` / `assembly`) instead of sitting on top of a menu that isn't there yet. Rules launched from the menu button is byte-identical to today.

The routing subtlety: today `slideshow_closed` → `_on_rules_closed` just clears highlights (the menu is underneath). As a continuation, the slideshow must know it was opened from the tutorial and, on close, drive `_on_tutorial_finished(destination)`. Add a `launched_from_tutorial` flag + destination on the slideshow.

### 2. Two more checkout drills — 55 (two darts) then 83 (three darts)

After the existing one-dart drill, add two interactive checkout drills with escalating remaining: **55**, then **83**. Difficulty escalates as 1 → 2 → 3 darts of mental math.

**Not throw-mechanic throws.** Clicking a board segment **auto-scores it** exactly like the existing 32 drill — no aim/meters/RNG. The only new thing vs. the existing drill is that these are *multi-dart*: a running remaining counts down across clicks until a legal finish. (Optional cosmetic polish, deferred: drop a mini dart marker + play the thunk on each click. Scoring stays click→auto-score regardless.)

**Rules enforced** (the same ones slides 7–8 teach):
- Each click subtracts the segment's value: face value × ring multiplier (Inner/Outer Single ×1, Triple ×3, Double ×2), outer bull = 25, double bull = 50.
- Intermediate darts can be anything; **only the dart that reaches 0 must be a double** (incl. double bull).
- **Bust** = drops below 0, leaves exactly 1, or reaches 0 on a non-double.

**Decisions locked in the design session (Max):**
- **Any legal checkout is accepted** — not a memorized path. The drill validates the *rules*, not a specific sequence. (55 and 83 each have many valid outs; this is truer to the game and makes Undo meaningful.)
- **No dart-count cap** — soft framing ("finish from 83"). A clever shorter out is accepted and rewarded — note 83 is checkout-able in *two* darts (T17, D16), and that's a valid win, not a violation. 55 and 83 kept as written.
- **Bust → show the bust, explain which rule broke, then reset remaining to the drill's start.** Independently, an **Undo** button steps back the last (non-busting) dart for players who just want to rethink. So: Undo = manual one-step back; bust = automatic reset with explanation.
- **Next gates on a legal finish** (reaching exactly 0 on a double), same gating pattern as the existing drill.

New drill-slide UI: a remaining-score readout ("Remaining: 55"), the thrown-dart list/markers, an Undo button. Reset is implicit on bust.

## Implementation plan

- `scripts/rules_slideshow.gd`:
  - New slide `type: "checkout_drill"` with fields: `start_score`, body copy, bust/win feedback strings. The existing `type: "drill"` path is untouched.
  - Segment → points value function (face × ring multiplier, plus 25 / 50 bull). Reuse `_get_mini_board_segment` for click→(wedge, ring).
  - Running state: `_checkout_remaining: int`, `_checkout_darts: Array[Dictionary]` (each `{wedge_index, ring_name, value}`). Click handler branches to checkout logic when the current slide is a `checkout_drill`.
  - Bust detection (below 0 / leaves 1 / zero-on-non-double) → feedback + reset to `start_score`. Win (zero-on-double) → enable Next. Undo pops the last dart and re-adds its value.
  - Render: remaining readout + thrown-dart markers on the mini board (reuse the feedback-highlight draw path). Undo button in the drill container.
  - Insert two `checkout_drill` slide entries (55, then 83) after the existing 32 drill, before the "That's the Basics" closer.
  - Static-type everything; exported colors/sizes for the new readout + markers per project conventions.
- `scripts/tutorial_callout.gd`:
  - Add an **optional secondary action button** (e.g. `set_secondary_action(text: String, show: bool)` + a `secondary_pressed` signal), hidden by default. Purely additive — every existing beat that doesn't call it is byte-identical. Chosen over a dedicated choice widget (more code, new style to match for a one-off) and over repurposing the Skip button (Skip already means "skip tutorial" with its own signal/styling — overloading it is confusing).
- `scripts/tutorial_controller.gd`:
  - `_t3_complete` presents the two-way choice via the callout's primary + secondary buttons. **Primary = "Learn the rules"** (gets the emphasis — it's the step we're nudging toward); **secondary = "Play / back to menu"**. "Learn the rules" emits a new signal (e.g. `request_rules`) that asks `main.gd` to open the slideshow as a continuation; "Play / back to menu" runs the existing finish path (`tutorial_finished.emit(destination)`).
- `scripts/main.gd`:
  - Open `rules_slideshow` flagged as tutorial-continuation (carry the destination). On `slideshow_closed`, if flagged, call `_on_tutorial_finished(destination)` instead of only clearing highlights. Menu-launched path unchanged.

## Acceptance
- Existing 32 one-dart drill unchanged; two new drills (55, 83) play after it, before the closer.
- Any legal checkout wins; intermediate darts unrestricted; the finishing dart must be a double (or double bull).
- A busting dart names the broken rule and resets the drill; Undo steps back exactly one dart.
- No dart-count cap — a legal shorter finish (e.g. 83 in two via T17, D16) is accepted.
- Mechanics-tutorial completion offers "Learn the rules" vs "Play / back to menu"; choosing rules opens the slideshow and returns to the correct destination on close. Menu-launched rules is unchanged.

## Deferred / polish
- Cosmetic mini dart marker + thunk per click (scoring stays click→auto-score).
- Ellipse-reference copy pass in `rules_slideshow.gd` (pre-existing deferred item, unrelated).
