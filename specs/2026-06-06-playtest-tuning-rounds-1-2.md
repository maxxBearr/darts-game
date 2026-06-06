---
Spec date: 2026-06-06
Status: Shipped 2026-06-06 (uncommitted on top of `529c1e4` at archive time)
Implementation: Round 1 built in a Cowork session (no Godot available); verification, both bug fixes, and round 2 ran in Claude Code. Live-playtested by Max same day.
Notes: Both diagnosed bugs confirmed applied (generate_next_act → _refresh_reachable; Prism gate → has_color_dependent_scoring). The §Round-2.3 "report silly bands" prediction was confirmed in play (a 12–17 deposit band early in act 0) — addressed by the follow-up round-3 spec (challenge feel + transition cleanup, CLAUDE.md 2026-06-06 → specs/2026-06-06-playtest-round-3.md once shipped), which also resequences the leg-intro rail fill and retires the "Next Leg" framing.
---

# Playtest tuning rounds 1+2 — verify, fix bugs, then build round 2 (2026-06-06)

**Pass order:** §Verification (round-1 code is written but has never run) → §Bug fixes (two diagnosed,
cross-confirmed bugs; skip any already applied in a previous Claude Code session) → §Round 2 (new build
work: mini-branches, typed crossovers, act-0 challenges) → re-run all suites + the live checklist.
Conventions as always: static-type everything, comment frequently, exported tunables with hover
descriptions.

## Round 1: what was implemented (uncommitted working-tree changes on top of `529c1e4`)

**These four features were ALREADY IMPLEMENTED in a Cowork session on 2026-06-06 but never run — Godot
wasn't available in that sandbox. Do NOT rebuild them; verify and fix (§Verification).**

1. **Sideways-H topology** (`scripts/map/map_graph.gd::_build_act`, knob docs in `map_gen_config.gd`):
   Max's note — branches felt like "merge into a `>` then re-fork". Mid-act reconvergence chokepoints are
   GONE. Lanes now run straight between segments; between consecutive segments a **crossover interchange**
   node (sole at its depth → MapView auto-centres it; no view changes needed) is fed by BOTH lane-ends and
   exits to BOTH next runs. Staying in lane = straight edge past it; crossing (or doubling back) = playing
   the interchange leg. Crossovers per act = segments − 1. Only the pre-boss chokepoint still merges.
   Placed-node count per act is unchanged (crossover replaces chokepoint 1:1), so the validation budget
   band holds. Specials still never sit on sole-depth nodes; within a segment a path is lane-locked, so the
   per-traversal special caps survive.
2. **No-repeat leg rule** ("never play the exact same leg twice"; identity = `(target_score, max_turns)` —
   dpt is global): enforced at ARRIVAL, not generation (the player only plays ~half the placed nodes;
   act-0's combo space of 5 targets × 3 turns is smaller than an act's placed count, so generation-wide
   dedup would exhaust). New on `MapGraph`: `_played_leg_configs`, `record_played_config()` (leg 1, called
   from `_on_run_confirmed`), `claim_unplayed_leg_params(node)` (called at the top of
   `_slide_to_leg_node`). Collision policy (Max's pick): reroll turns first — each turn count re-derives
   its own flat-pressure target via the new `_derive_leg_target()` — then nudge the target along the
   lattice, deterministic nearest-first, no RNG draw (arrival order can't perturb the seeded generator).
   Each act's boss pair (act ceiling @ reference_turns) is RESERVED at generation so an ordinary leg can
   never pre-play the boss's numbers. Challenge races are excluded (own surface, own dpt).
3. **Event hover-preview fix** (`scripts/hud.gd::show_upgrade_choices`): accuracy events gave no stat-bar
   hover feedback — this path (unlike `show_shop_pick_items`) never connected
   `mouse_entered/exited` → `_on_upgrade_hover/_on_upgrade_unhover`. Now wired identically to the shop path.
4. **Leg-intro presentation** (every normal + boss leg, both entry points: `_slide_to_leg_node` and the
   run's first leg in `_on_run_confirmed`; NOT challenge races): info readouts print big at screen centre
   and fly+shrink onto their info-column slots in order (Leg X — target / Turns granted / Darts per turn),
   while the fronted rail trickle-fills row-by-row (rows = turns, row width = dpt) with the
   move-darts-to-saved tick per row, reversing the leg-win trickle. Permanent "FRONTED DARTS" header drawn
   above the rail. Per-step click-to-skip (full-rect `_intro_blocker` in hud.gd; `custom_step` fast-forward;
   no on-screen hint), `_leg_phase = "leg_intro"` gates input, `leg_intro_finished` awaited before
   `_start_new_throw` / boss announcement. Default total ≈ 2.5 s (exports: `leg_intro_*` in hud.gd,
   `intro_fill_row_interval` in dart_indicator.gd). New API: `hud.conceal_for_leg_intro()` /
   `hud.play_leg_intro()`; `dart_indicator.conceal_for_intro()` / `play_intro_fill()` / `skip_intro_fill()`.

## Verification (the actual task)

- **Integrity first:** mid-session, `scripts/hud.gd` and `scripts/dart_indicator.gd` suffered an
  interrupted write that was repaired by splicing the pre-edit tail back on. Before anything else, parse
  every changed script (`godot --headless --check-only` per file, or just open the project and watch for
  script errors) and eyeball `git diff` on those two files for duplicated/missing blocks.
- **Run the suites:** `godot --headless --script res://tests/test_map_graph.gd` (UPDATED: new traversal
  bounds, `_assert_crossover_invariants` — wiring + a not-inert stay/cross path check — and
  `_assert_no_repeat_claims`), plus `res://tests/test_events.gd` and `res://tests/test_challenge_nodes.gd`
  (should be untouched-green; they share map_graph).
- **Live checklist:** map renders the H (centred crossover, straight lane edges passing it); crossover is
  pickable from either lane and exits to either; a full run never repeats a `(target, turns)` leg and no
  ordinary leg replays the act boss's pair; accuracy-event options live-preview the stat bars on hover
  (brush events already did via the shop path); intro plays on leg 1, map legs, boss legs — not on
  challenge races — finishes ≤ ~3 s, click skips ONLY the current step, no aiming possible mid-intro, boss
  announcement still lands after the intro; leg-win bank trickle + shop rail mode still behave.
- **Known seams to watch:** `_leg_phase` interactions (bailout, challenge dpt restore, checkout-path
  cycling); `_update_all_hud()` calls landing during an intro (conceal runs after the writes by design);
  `await`-ing inside the slide-in tween callback.

## Bug fixes (diagnosed 2026-06-06; two independent passes agreed — skip any already applied)

1. **Act-boundary first leg unclickable (run-blocking).** Two reachability sources disagree: MapView
   enables buttons from a live `reachable_from()` query, but `MapView._on_node_pressed`
   (map_view.gd:~174) gates on the cached per-node `n.reachable` flag, which is only recomputed inside
   `MapGraph.advance_to()`. Picking the act boss runs `advance_to` while the boss still has NO successors
   (next act ungenerated); winning then runs `generate_next_act()` (main.gd:~978) which wires boss→entry
   but never refreshes flags → entry button looks live, click silently no-ops. FIX: call
   `_refresh_reachable()` at the end of `generate_next_act()`, AND make `_on_node_pressed` consult the
   live `reachable_from(graph.current_id)` so the two sources can't diverge again. Regression test: in
   test_map_graph's incremental-gen test, assert the new act's entry has `reachable == true` after
   `generate_next_act` while current is the cleared boss.
2. **Checkout helper dark during Prism — overbroad suppression.** `_update_checkout_helper`
   (main.gd:~2900) and `_update_checkout_highlights` (main.gd:~2870) unconditionally suppress on
   `is PrismBoss`. But Prism mutates COLOR only, never value; the solver's path math is value-based, so
   the helper is only untrustworthy when a color-dependent scoring modifier is active (and then genuinely
   so: each landed dart of a multi-dart path triggers its own recolor, invalidating later steps — don't
   try to "fix" that case with re-solves; dark is honest there). FIX: replace both gates with a predicate
   like `scoring_modifier_manager.has_color_dependent_scoring()` — derive exact membership from where
   `process_score` reads segment color (COLOR-category streaks at minimum). Update the rationale comments
   to explain the now-conditional gate.

## Round 2: topology tweaks (BUILD — Max's playtest notes, 2026-06-06)

The two lanes read as routes, not branches. Three structural changes to `map_graph.gd::_build_act` +
knobs in `map_gen_config.gd`:

1. **Mini-branches (3rd/4th rows):** short detours forking off a lane and rejoining THE SAME lane,
   rendered just outside their parent lane (top lane's branch above, bottom's below). Roll
   `branches_per_act` ∈ [`branches_min`, `branches_max`] (default 1–2, exported); with 2, one per lane.
   Branch of length B ∈ [2,4] forks from `run[i]` → `branch[0..B-1]` at depths i+1…i+B on the outer row →
   rejoins `run[i+B+1]`; lane keeps straight edges (stay-vs-detour choice, equal node counts both ways).
   Must fit within ONE stretch (never spans a crossover boundary); clamp B to fit, skip if nothing fits.
   New `MapNode.is_branch: bool`. Branch nodes default LEG; per branch, `branch_special_chance` (default
   0.6, exported) of hosting exactly ONE special (normal type/state/act gates). Off-budget (§4 below).
   Leg params + no-repeat rule need nothing (depth/arrival-driven). **MapView `_layout()` must
   generalize:** collect distinct lane values, sort → row indices; branch rows sit `lane_spacing` outside
   their parent lane; sole-at-depth centring unchanged. Eyeball all three acts after.
2. **Crossovers: roll 1–3, any type.** Decouple count from stretch length: roll `crossovers` ∈
   [`crossovers_min`, `crossovers_max`] (default 1–3, exported) and a TOTAL per-lane `lane_len` ∈
   [`lane_len_min`, `lane_len_max`] (default 9–12, exported), cut into crossovers+1 stretches of ≥2 each
   — traversed length stays ~12–16 regardless of crossover roll. Retire/repurpose `branch_segments_*` /
   `branch_len_*`; recalc `act_node_budget_*` and document the formula in the export comments. New
   `MapNode.is_crossover: bool`. Each crossover rolls its type from exported weights (suggested leg 0.5 /
   shop 0.2 / event 0.2 / challenge 0.1); event family state-gated as usual; challenge respects §3 gates.
   Cap at most ONE challenge across an act's crossovers+branches COMBINED (no wager-race stacking on
   detours). Off-budget (§4). **Validation relaxation:** "specials never on sole-depth nodes" becomes
   "special must have a same-depth sibling OR `is_crossover`" (the straight lane edges are a crossover's
   built-in skip) — in `_validate()` and the tests' twin asserts, including the challenge-skip assert.
3. **Challenges in the first act:** remove the hard `act >= 1` gate (`_slot_specials` + `_validate` +
   tests). New gates: in act 0, never within the first `challenge_act0_min_depth` (default 3, exported)
   depths after the act entry — the `highest_cleared` anchor needs a few cleared legs to mean anything.
   Act-0 per-path budget 1–2 (`challenges_act0_per_path_min/max`, exported); later acts keep 1–3. Verify
   early-act deposit bands (`compute_challenge_params` at `highest_cleared` ~101–301) look sane vs a
   realistic early bank; they're skippable so not run-blocking, but report silly bands.
4. **Budget semantics:** per-path special caps count LANE-RUN nodes only; crossover/branch content is
   excluded from cap math (detours are chosen friction — strictly additive spice). Only guard: the ≤1
   detour-challenge cap from §2.
5. **Tests:** update traversal bounds; crossover count ∈[1,3] AND its distribution spreads across seeds
   (not-inert check — don't let a clamp pin it at 1); typed-crossover wiring invariants unchanged (fed by
   both lane-ends, exits to both runs, stay edges present); branch invariants (same-lane rejoin, single
   stretch, outer row, some enumerated path takes it and some doesn't); act-0 challenge depth gate;
   budget enumeration excludes `is_crossover`/`is_branch`; ≤1 detour challenge per act. All three suites
   + a `--check-only` parse pass.

**After this ships:** archive this section per Workflow Notes (`specs/2026-06-06-playtest-tuning-rounds-1-2.md`),
then the queue resumes: more tuning dials if playtest demands, **geometry items**, **typed shop + codex**.
Program index: `specs/map/00-overview.md`. Slice-3/events context: `specs/map/01-substrate-slice3-impl.md`,
`specs/map/03-events-impl.md`.
