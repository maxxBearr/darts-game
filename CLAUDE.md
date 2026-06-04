# Spec: (none active)

**Board-scoring rework SHIPPED 2026-06-03** — `specs/2026-06-03-scoring-on-the-board.md` (Status: Shipped;
built by Claude Code, debugged + visuals added in the design session). Two-axis scoring landed: an additive
face-value baseline (ring + hotspot + wedge value) × an earned *multiplicative* streak factor that combines
all active streaks into ONE factor (`1 + Σ`, not per-streak compounding). Per-category streak capacity from
components (`DartComponent.streak_slot_grant`, base 1 wedge + 1 color) replaced the global `max_streak_slots`;
`StreakSlotExtensionReward` removed. Pool migrated (global `ColorBonus`/`OddEvenBonus` + all parity/even-odd
streaks dropped; `FlipSign` sidelined; `ColorStreak` weight raised; `family` tag Scoring/Placement/Brush
added). `HotspotModifier` (no-stack, +1/+2/+3) live with solver + tooltip support. Visuals: hotspot smoke
shader (toggle `use_hotspot_shader`, multi-tone per-wedge-color) + smokified "+N" label + streak pulse on
board darts (grey→white + slow→fast by count).

**Next direction: typed shop — make shop offers type/family-dependent.** The `family` tag on board items is
the (already-shipped) groundwork; the next spec wires shop/pool steering so the player sees the item *type*
before committing (e.g. one of each family, or biased rings), so they branch builds instead of always
grabbing the locally-strongest item. Folds into the parked map work:

- `specs/future/map-pool-filtration.md` — map + reward-pool steering (the `family` tag was its prerequisite).
- Overlaps **Darts as Currency Phase B (typed shop rings)** in
  `specs/future/darts-as-currency-economy.md` — still needs the accuracy-into-shop-pool fork resolved.

Also deferred from the board-scoring pass (pick up when relevant): **Tier-2 geometry** items (wedge resize,
bigger bull) behind the checkout-solver lift; hotspot **"value-in-the-smoke"** (the shader's `use_glyph`
path); the **map / fronted-darts** difficulty axis. Max-manual: component stat layouts + `streak_slot_grant`
values (inspector).

When the next feature is being designed, replace this section with its spec (see the Workflow Notes below).

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
