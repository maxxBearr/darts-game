# Map Program — Phase 02 Challenge Nodes (ACTIVE: impl spec ready to build)

**Active spec:** `specs/map/02-challenge-nodes-impl.md` — the buildable doc for Phase 02. Design was finalized in a
Cowork session (2026-06-05); the impl spec is the build surface for Claude Code. Program index + per-phase status
live in `specs/map/00-overview.md`.

**What Phase 02 is:** an optional, **post-boss-1**, off-branch map node (slice 1's reserved `is_off_branch` fork).
The player **wagers banked darts as the race budget** to re-clear a score they've already beaten, in a tighter
budget than a normal leg — the challenge verb is *match concisely*, not *match big*. Win → typed reward (rarity =
how few darts you used) + bank the unused darts. **Lose → forfeit the whole wager, run continues.** Skip is always
allowed (take the parallel leg instead).

**Core resolved decisions (see impl spec for the full surface):**
- **Deposit = wager = race budget**, one pool; **loss forfeits all of it** — that's what makes deposit-size the
  single risk dial (lean = cheap rare attempt with no fail-soft; fat = pricey safety net down to a common win).
  This **supersedes** the old `02-challenge-nodes.md` turns↔rarity "banter table."
- **Target anchor:** within −300 of the highest score the player has *cleared* (boss or leg); never above it.
- **Deposit range derived from the slice-2 seam:** `reliable = ceil(target / expected_per_dart(depth))`, then
  `min ≈ reliable×0.65`, `max ≈ reliable+2`. Lands in a tight ~6–13 dart band all game (worked numbers in §4).
- **`darts_per_turn` rolled per node ∈ [2,5]**, shown before deposit; **ice-tray** fill (raw-dart deposit chunks
  into rows of dpt, partial last row) with the budget **capped by total darts**, not whole turns.
- **Handicaps** reuse the benched bosses (Rotation / Narrow Double / two-darts — code still present).

**Build dependency (do first):** Phase 02 reads the slice-2 pressure seam, which is currently **skeleton** —
`baseline_target` calls undefined `_act_ceiling` / `_act_floor` / `_snap`, and `pressure_of` is referenced but not
implemented. Finish/compile the seam before Phase 02 consumes it (impl spec §14). Engine additions Phase 02 needs:
an x01 total-dart-cap budget mode (partial final turn) + a per-race `darts_per_turn` override (§9).

**Build-steering spine (unchanged):** exposure (codex) + informed shop + earned challenge selection; **no free
typed picks** (power stays earned — protects the darts-as-currency "bank is the climb" thesis). Phase 02 is the
*earned-selection* third. Design laws: *frame before furniture*, *chosen friction is spice*.

**Shipped before this — Phase 01 Substrate:** slice 1 (graph/view/seam, `01-substrate-impl.md`, commit `e71762f`)
+ slice 2 (pressure-ratio generator, `01-substrate-slice2-impl.md`). Note the slice-2 *seam* is skeleton in the
working tree (above). Deferred substrate polish: arrival ceremony, cramped-1501 layout fix, HUD dart-budget
texture. Later phases: 03 typed shop + codex, 04 pool filtration, 05 boss cadence (see overview).

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
