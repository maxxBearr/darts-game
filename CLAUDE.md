# ACTIVE: Leg lattice — monotone (score, turns) frontier for act legs (2026-06-07)

Designed in a Cowork sparring session (Max + Claude, 2026-06-07, same day geometry shipped). Replaces
slice-2's per-leg turn roll for ordinary legs with a per-act difficulty lattice + monotone cull.
Challenge pricing / pressure seam untouched. Conventions as always: static-type everything, comment
frequently, exported tunables with hover descriptions.

**Problem (playtest):** the slice-2 flat-pressure roll can serve a 5-turn version of a score before its
6-turn version — "it's not getting harder, it's just easier" — and acts run long (a 13-leg top lane
observed; `lane_len_min/max` 9–12 constrains *nodes*, not leg count specifically).

## 1. The lattice (LOCKED)

Per act, legs are cells in a grid: rows = scores ascending in +100 steps over the act window,
columns = turn counts 6 → 5 → 4. Act 1: opener row 101 × {5, 4} (run always opens on the fixed
101/5 leg — calibration, not part of the draw), then {201, 301, 401} × {6, 5, 4}. 10 drawable
cells; the cap on legs per act is **lattice exhaustion, not a tuned number**.

**Unlock rule (frontier):** within a row, cells unlock left-to-right (6 before 5 before 4 —
never the tight version before the loose one). Row N+1's 6-turn cell unlocks when row N's
6-turn cell is *resolved* (cleared OR culled, see §2 — a culled cell counts as resolved for
unlocking, so a dead row doesn't strand the climb).

Pressure reference (points needed per dart, 3 dpt), for tuning intuition:

|     | 6t   | 5t   | 4t   |
|-----|------|------|------|
| 101 | —    | 6.7  | 8.4  |
| 201 | 11.2 | 13.4 | 16.8 |
| 301 | 16.7 | 20.1 | 25.1 |
| 401 | 22.3 | 26.7 | 33.4 |

Note the diagonals cross (201/4 ≈ 301/6; 301/4 > 401/6) — the cull rule below does real work
mid-grid, not just on the 101 row.

## 2. The cull rule (LOCKED) — monotone difficulty

**Any undrawn cell whose pressure is at or below the highest pressure the player has CLEARED
is culled (expired) for the rest of the act.** Consequences, all intended:

- Difficulty is strictly monotone — the "easier leftover" leak (clear 401/6, then face a
  still-eligible 201/5) is closed by construction.
- 101/4 needs no special-case lock: at pressure 8.4 it expires the moment 201/6 (11.2)
  clears, so it can only ever appear as the act's second leg. It STAYS in the grid (the one
  place the player feels pure turn-squeeze before score scaling kicks in).
- Culling naturally shortens acts — the "one or two fewer legs" trim falls out of the same
  rule (a fast climber exhausts the lattice in ~6–7 legs; the full 10-cell monotone walk
  still exists for a player who tightens before climbing).

## 3. Resolution at arrival (reuses the existing seam)

Leg identity is rolled **on node arrival**, from the live frontier — replacing
`claim_unplayed_leg_params`'s roll-then-dodge-collisions with draw-from-frontier. This is the
same arrival-time pattern the no-repeat rule already uses (`_played_leg_configs`), and it
sidesteps the branch-consistency problem entirely: pre-assigning cells along every possible
path is a constraint-satisfaction mess; lazy assignment makes any walk valid by construction.
Leg nodes are unlabeled on the map ("Leg"), so no routing information is lost.

- Frontier draw: uniform among eligible cells to start (frontier is typically 2 cells —
  "tighten or climb" — texture comes free). Weighting toward climb = a later tuning knob.
- **Exhaustion fallback:** if a path still has leg nodes after the lattice empties (possible:
  fast climb + long path), repeat the hardest cleared pair (the existing accept-the-repeat
  fallback's spirit; flag it, Max tunes).
- Retires for ordinary legs: `_roll_turns` / `turns_center_bias` / the flat-pressure target
  derivation. The pressure seam itself (`expected_per_dart` / `pressure_of` /
  `baseline_target`) STAYS — challenge pricing reads it and is untouched.

## 4. Leg cap = per-path budget (LOCKED)

The cap constrains **legs per traversed path**: every entry→boss route has ≤
`path_leg_budget` leg nodes (export, start ~8–9, hover doc). Displayed totals float —
parallel branch legs are alternatives, so two 3-leg branches cost 3 cells per path even
though 6 show on screen. Visual density is fixed separately: trim `lane_len_min/max`
(currently 9–12) by 1–2. Side effect worth keeping: a shorter branch route reaches the boss
lower on the lattice — easier ramp, fewer rewards. Routing becomes a pacing choice.

## 5. Boss overlap + per-act reset (FLAGGED, Max rules at impl)

- Boss currently reserves (act ceiling, reference_turns) — which IS a lattice cell (401/5 in
  act 1). Either keep the reservation (that cell expires to the boss, drawable cells = 9) or
  move the boss off-grid (e.g. boss = next act's opener score). Decide at impl.
- Lattice resets per act over that act's score window; the act's opener cell anchors to the
  act entry. Acts 2/3 windows per the existing `_act_ceiling` / `starting_target` /
  `target_increment` machinery.

## 6. Tests

- Monotone: over a seed grid, every run's sequence of cleared pressures is nondecreasing.
- Frontier legality: no cell drawn before its row/column predecessors resolved.
- 101/4 only ever appears as cumulative leg 2.
- No-repeat holds; cap: no entry→boss path exceeds `path_leg_budget` legs.
- Exhaustion fallback fires and repeats the hardest cleared pair, not an easier one.
- Distribution spread (the `[[feedback-rolled-generator-spread]]` lesson): across seeds, walks
  visit DIFFERENT cell sequences — not one canonical walk; both "tighten" and "climb" picks
  occur at observable rates.
- Existing map + challenge suites green; `--check-only` parse pass on every changed script.

**After this ships:** archive per Workflow Notes (`specs/2026-06-07-leg-lattice.md`), then the queue
resumes: **typed shop + codex** (Phase 03 remainder). Program index: `specs/map/00-overview.md`.
Geometry items (the previous active spec) archived at `specs/2026-06-07-geometry-items.md`.

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
