---
Spec date: 2026-05-21
Status: Shipped 2026-05-21
Implementation: Claude Code, with subsequent tweaks during playtest. Merged to main.
Notes: All four sub-features shipped as specified. Deferred items (multi-dart checkout helper, static on-board modifier visuals, persistent-indicator changes) remain deferred. The follow-up Shop spec assumes the parity slot system and the shared checkout-detection function from this spec are in place.
---

# HUD / Assembly Polish Pass

**Spec date:** 2026-05-21
**Status:** Designed, ready for implementation
**Scope:** Quality-of-life and clarity improvements to the in-game HUD and the assembly screen. Four surgical changes across existing UI; no new systems. The follow-up Shop spec will live on its own branch and will assume this work has shipped.

## Summary

Four discrete UX improvements bundled into one pass:

1. Balance bar becomes a smooth gradient with two new transition sub-zones that apply mild gameplay effects.
2. Score readout turns gold whenever a single-dart checkout exists on the board.
3. Target tooltip relocates to directly above the crosshair, simplifies its readout, and a new perk-up hover state lifts modifier icons off the items line when they apply to the hovered target.
4. Parity streak items split into distinct Even Streak and Odd Streak variants sharing a single slot.

---

## 1. Balance Bar Gradient

The balance bar currently shows three named zones (green / orange / red) with hard cliffs between them. Convert the bar's *visual* to a smooth color gradient across the full range, and introduce two transition sub-zones with mild gameplay effects:

- **Green→Orange transition:** slight stat boost applied to throws.
- **Orange→Red transition:** slight skew applied to throws.

The three named zones still drive the dominant gameplay states. The transitions are softer in-between regions that reward landing close to ideal balance and punish drifting toward red before the player is fully in it. The "imbalance can be correct" design principle still applies — transitions are a small flavor on top of the existing zone-driven system.

**Tuning:** Start the transition magnitudes small (suggested 10–20% of the corresponding full-zone effect) and tune in playtest. Both magnitudes — and the width of each transition sub-zone along the bar — should be exposed as exported variables with hover descriptions.

**Why:** Smooths the cliff-edge feel between zones and enables more nuanced build decisions during assembly. Not a fix for an observed playtest problem — a deliberate refinement to deepen the precision available to the player when tuning a build.

---

## 2. Gold Score Indicator

When the player's current score has at least one single-dart finish available on the board, render the score number in gold. Otherwise render it in its default color.

**Definition of "single-dart finish":** there exists a board spot that, if hit, would bring the player to exactly 0 *and* satisfies the leg's finish rule (typically double-out).

**Behavior:**
- Updates per-dart (live during a turn), not per-turn.
- Must respect active scoring modifiers. If a ×3 Red modifier is active and the player is at 60, single 20 on a red wedge now finishes the leg, so the score should be gold.
- Tied to the same checkout logic that drives the board's existing gold checkout highlights — score-gold and board-gold should always agree.

**Why:** Reduces mental arithmetic load during play, especially when unusual checkouts become viable through active modifiers. The board already highlights the specific finishing spots; the score turning gold is the redundant glanceable signal so the player doesn't have to scan the board to know "yes, I can win right now."

**Deferred:** A multi-dart checkout helper (e.g., "from 110 with 3 darts left in the turn, here's a route") is explicitly out of scope. Gold means *single-dart kill exists*. Multi-dart route assistance is a future feature that will build on this one.

---

## 3. Target Tooltip + Perk-Up Hover

Two coordinated changes to where modifier feedback lives during aiming.

### 3a. Tooltip relocation

The target preview tooltip moves from its current position to **directly above the crosshair**. It draws over the board ellipse if necessary for readability — use a semi-transparent background or similar treatment so the board stays visible underneath.

**Simplified format:** `Target: D7 ×3 = 35`, with the multiplier rendered in green to make modifier presence pop. When no modifier applies to the hovered target, the readout collapses to the base form (`Target: D7 = 14`).

**Behavior:**
- Tooltip appears on hover, before the player commits to the target.
- Tooltip disappears once the player commits to the throw, so it doesn't occlude during the actual aim and release.
- Existing streak tooltip logic (which already only shows when relevant) is preserved unchanged. It continues to appear in its existing location near the crosshair.

**Why:** The current tooltip lives outside the player's field of focus during aiming, which means the modifier feedback the player needs is effectively invisible at the moment it matters. Crosshair-adjacent placement puts the readout where the eyes already are.

### 3b. Perk-up hover state for items line

When the player hovers over a board element that a specific modifier in the items line applies to, that modifier's icon **perks up** — lifts off the line and gets highlighted. When the hovered target does not match a modifier, that modifier's icon stays in its default state.

**Example:** Player has a ×3 Red modifier and a +5 Odd modifier active. They hover over D7 (red, odd). Both modifier icons perk up. They hover over D8 (black, even). Neither perks up.

The *persistent* on-board modifier indicator (whatever currently shows "this wedge has a modifier" before any hover) stays exactly as it is. Perk-up is purely an additive focused state on hover — not a replacement for the static board-side indication. Players already trained on the existing static indicators don't lose anything; hover adds clarity in the moment of decision.

**Why:** Gives modifier feedback a tight per-target read without burdening the persistent board state. Keeps board scouting fast (static indicators) and decision-making clear (perk-up on hover).

**Deferred:** Static board-wide visual changes when modifiers are active — e.g., all red spots getting an artistic treatment when a red modifier is equipped — are deferred until the broader stylized art direction is more settled.

---

## 4. Parity Streak Differentiation

The current "Parity Streak" upgrade is replaced by two distinct items: **Even Streak** and **Odd Streak**.

**Slot behavior:**
- The two items share a single slot, `parity_streak`.
- Picking either item while the other is equipped triggers the existing streak conflict / replace warning — same logic and same UI as color and wedge streaks.
- All three streak categories (color, wedge, parity) now follow the same one-slot-per-category rule.

**Data model:** Parity items declare `streak_slot: "parity"` and a sub-field (e.g., `parity_target: "even" | "odd"`) indicating which parity they track. The conflict resolution logic already present for color and wedge requires no changes — it sees two items competing for the same slot and triggers the replace flow.

**Why:** The current implementation surfaces "Parity Streak" as a single ambiguous item, but the underlying mechanic actually tracks either evens or odds (not both). Differentiating the items makes the choice explicit at the pick screen and forces the player to commit to a parity orientation, matching how color and wedge streaks already work. Aligns the three streak categories under a single coherent rule.

---

## Deferred / Out of Scope

Captured here so future passes don't have to dig through chat history:

- **Multi-dart checkout helper.** Future feature once single-dart gold lands.
- **Static on-board modifier visuals.** Art treatment on wedges or color regions when a relevant modifier is active. Deferred until stylized art direction is more settled — heavily art-driven.
- **Changes to the persistent on-board modifier indicator.** Out of scope for this pass. Only the new hover state is being added; the persistent indicator stays as-is.
- **Shop system.** Separate spec, separate branch, after this work merges.

---

## Implementation Notes

- All new tunable values — transition zone magnitudes and widths, gold-trigger response, tooltip vertical offset above crosshair, perk-up animation magnitude and timing — should be exposed as exported variables on their owning scripts, with hover descriptions per project conventions.
- Static typing throughout per project conventions.
- Reuse the existing streak conflict logic for the parity slot. Do not duplicate it.
- The gold-score check and the board's gold checkout highlight should call the same underlying "is this score checkoutable in one dart" function. Single source of truth — they must never disagree.
