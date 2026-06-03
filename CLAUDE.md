# Spec: (none active)

No spec is currently being designed or implemented. Two features shipped in the last cycle and
were archived:

- **Accuracy Upgrades as Shape** (Phase 1) — `specs/2026-06-02-accuracy-upgrades-as-shape.md`.
  Stat upgrades became net-zero-by-rarity trades (redistribute, not climb). Commit `b95d4e2`.
- **Darts as Currency — Phase A** (persistent bank + bailout + rail UI) —
  `specs/2026-06-02-darts-currency-phase-a.md`. Commits `c15d980` / `3277639` / `754dbd7`.

**Next direction: the mid-game progression rebalance** (move difficulty off big-number scaling
onto efficiency + spatial play). Two parked brainstorms feed the next spec — to be fleshed out in
a fresh session:

- `specs/future/map-pool-filtration.md` — map + reward-pool steering; **variable fronted darts**
  as the difficulty axis (e.g. choose 351-for-9-darts vs 401-for-15). The acquisition-frequency
  and routing half.
- `specs/future/scoring-on-the-board.md` — **scoring lives on the board** (spatial hotspots +
  categorical streaks; drop global conditional multipliers); components govern streak-slot
  capacity; cut even/odd streak; board as contested territory with bosses. The scoring/items half.

Also still parked: **Darts as Currency Phase B** (typed shop rings) in
`specs/future/darts-as-currency-economy.md` — needs the accuracy-into-shop-pool fork resolved.

When the next feature is being designed, replace this section with its spec (see the Workflow
Notes below).

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
