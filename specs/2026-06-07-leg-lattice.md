---
Spec date: 2026-06-07
Status: Shipped 2026-06-07
Implementation: Claude Code
Notes: Shipped the full lattice (§1–3), boss-off-grid + per-act reset (§5), and the §6 test suite.
  Two deviations from the locked text, both flagged with Max and recorded under "Implementation
  outcome" below: §4's `path_leg_budget` landed at 14 (the topology's real per-act ceiling), not the
  aspirational ~8-9 — the crossover interchanges dominate the leg count and the sanctioned "trim
  lane_len by 1-2" can't reach 8-9; and `lane_len_min` was reverted to 9 (only `lane_len_max` was
  trimmed 12→11) because dropping the min starved short acts of their guaranteed lane-run challenge.
  The cap is checked by the map test suite, not asserted in `_validate` (a live run must not crash on
  an unlucky roll). Follow-up queue unchanged: typed shop + codex (Phase 03 remainder).
---

# Leg lattice — monotone (score, turns) frontier for act legs (2026-06-07)

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

---

## Implementation outcome (2026-06-07, Claude Code)

What landed, and where the implementation diverged from the locked text (both deviations confirmed
with Max during the pass):

**Resolved design questions (asked at impl):**
- **§5 boss overlap → boss OFF-grid.** The boss must stay at the act ceiling (= `max_score_target`,
  a tested win condition) so it can't be 401; the LOCKED "10 drawable cells" only works if the
  drawable rows stop one increment *below* the ceiling. So rows = `act_floor … act_ceiling − 100`
  (act 1: 101/201/301/401), boss at the ceiling, never a drawable cell. The §5 "401/5 boss cell"
  line was a slip. Drawable = 10 (act 0: 101/4 + {201,301,401}×{6,5,4}).
- **Acts 2 & 3 → same shape, all cells drawable.** Only act 0 has the fixed non-drawn opener
  (101/5, auto-played at run start). Acts 2/3 arrive from a boss and pick, so every cell is
  drawable; the lowest row of each act is {5,4} (drops the trivial 6t column).

**Code:**
- `map_graph.gd`: `_build_act_lattice` (per-act cells; pressure = `score/(turns·3)`), the
  frontier/unlock walk (`_cell_predecessor` / `_cell_unlocked` / `_available_cells`), `_apply_cull`,
  `draw_leg_from_frontier` (arrival, uniform over the frontier via a dedicated `_lattice_rng`;
  exhaustion fallback repeats the hardest cleared), `record_leg_cleared` (cull/unlock on a WIN),
  `get_frontier` (read-only inspector). Retired `_roll_turns` / `_derive_leg_target` /
  `claim_unplayed_leg_params` / `record_played_config` / `_played_leg_configs` / `_config_key`.
  `_assign_leg_params` now only rebuilds the depth→act maps (pressure seam) + assigns boss tier
  pairs. `expected_per_dart` / `pressure_of` / `baseline_target` kept — challenge pricing untouched.
- `main.gd`: run-start `record_leg_cleared(101,5)` (marks the opener); arrival
  `draw_leg_from_frontier(node)` + `_active_leg_pair` cache (so the win hook resolves the drawn
  cell even after a bailout shifts `x01.max_turns`); the win hook fires only on ordinary legs;
  reset on new run.

**Deviations from LOCKED text:**
- **§4 `path_leg_budget` = 14, not ~8-9.** The branching topology (lane spine + up to 3 crossover
  interchanges, each adding a leg node when taken) yields up to 14 leg nodes per act over the test
  seed grid. The sanctioned "trim `lane_len` by 1-2" can't approach 8-9 — reaching it needs a deeper
  cut (fewer crossovers + a shorter lane floor, which cascades into `act_node_budget_min` and the
  topology invariants). Left for a follow-up. The **cull rule already delivers the felt pacing** —
  extra leg nodes just repeat/cull, so the player doesn't play 14 escalating legs. 14 is a tight
  regression guard tied to the current topology.
- **Only `lane_len_max` trimmed (12→11); `lane_len_min` kept at 9.** Dropping the min to 8 broke a
  pre-existing invariant (a too-short act couldn't host its guaranteed lane-run challenge,
  `challenges_per_path_min`). Trimming only the max shaves worst-case length without starving short
  acts.
- **The cap is checked by the map test suite, not asserted in `_validate`.** An unlucky low-special
  roll must not crash a live run, and the cap can't be hard-guaranteed without mandatory specials.

**Tests (`tests/test_map_graph.gd`):** retired the slice-2 roll/spread/parity/no-repeat-claim tests;
`_assert_structure` now checks the boss pair + that ordinary legs are unassigned at generation; added
monotone, frontier-legality, 101/4-as-leg-2, first-pick spread (verified 50/50 tighten/climb, 137
distinct act-0 sequences over 200 seeds), exhaustion-fallback, and the per-act `path_leg_budget` cap.
All suites green (map / challenge / geometry / events, 0 failures); headless boot clean.
