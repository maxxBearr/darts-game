---
Spec date: 2026-06-05
Status: BUILT (Claude Code, 2026-06-06) — slice 3 of Phase 01: a topology revision of the shipped generator.
  Design resolved in a Cowork sparring session (Max + Claude, 2026-06-05). Segment-based incremental generation,
  state-aware special slotting, the raised/rewritten _validate, the per-act MapView render, and the main.gd
  generate_next_act seam all shipped; headless tests green (tests/test_map_graph.gd: 107847 checks; the challenge
  suite re-homed onto the branch model: 173848 checks). Built BEFORE the events spec (`03-events-impl.md`).
Part of: the Map Program (`specs/map/00-overview.md`), Phase 01 (substrate). Revises slices 1 + 2.
Depends on: slice 1 (`01-substrate-impl.md`, graph/view/seam) + slice 2 (`01-substrate-slice2-impl.md`, the
  pressure-ratio generator). Both shipped. This changes *topology* only; the slice-2 pressure seam
  (`baseline_target` / `expected_per_dart` / `pressure_of` / `_assign_leg_params`) is untouched and keeps working
  per-node regardless of how many nodes a path has.
Supersedes: §17 of `02-challenge-nodes-impl.md` (the queued "per-act challenge count + later-column placement"
  stopgap, and the `fork_chance` 0.6→0.85 bump). Challenge frequency/placement is solved structurally here by the
  branch model, not by piggybacking on the single generic fork. The single-fork `_add_fork` path is replaced.
---

# Phase 01 — Substrate Slice 3: Longer Paths + Multi-Node Branches (impl)

## 0. One-line thesis

The slice-1/2 map is a short lattice of single-node lane columns with one optional single-node fork per act. That
gives **too little to choose between** when picking a route, and it leaves challenges (and the incoming events)
nowhere good to live. Slice 3 makes each act a **longer path (~12 nodes traversed)** built from **multi-node
parallel branches** — at a split the player commits to one of *two 3–5 node runs* that reconverge, not one of two
single nodes. Density *is* the routing decision: the more a branch packs (a shop + two events vs. a challenge + two
legs), the more a player weighs when they pick it. This unblocks inline events (`03-events-impl.md`) and re-homes
challenges onto the branch model.

---

## 1. The locked model (resolved this session)

1. **~12 nodes per act, traversed.** Up from the slice-1 7–12 *total per act*. Confirmed per-act (so a 3-act/1501
   run is ~36 encounters), accepted as shorter than a Slay-the-Spire act but right *because not all nodes are full
   legs* — density is what differentiates paths, and short paths can't differentiate.
2. **Per-traversal type budget:** **1–3 shops, 1–3 events, 1–3 challenges, remainder legs** (+ the act's terminal
   boss). This is a budget for *one full path through the act*, not a per-act slot count — the player only walks one
   branch at each split, so the guarantee is about what a *single traversal collects*.
3. **Branches are multi-node.** A divergence splits the path into **two parallel runs of L ∈ [3,5] nodes** (one `L`
   rolled per segment, both runs equal-length so they reconverge cleanly at the next chokepoint). Picking a branch
   forgoes the *whole* parallel run, not a single node — that's the agency upgrade.
4. **Agency is at the path level, not the node level.** Events and challenges sit **inline** inside branch runs;
   you don't choose "event or leg?" at a fork, you choose *which branch* (and its whole composition). This is what
   licenses inline placement (see `03-events-impl.md` §1).
5. **Challenges re-home onto branches.** A challenge is now an inline node inside a branch run (acts ≥ 1 only,
   unchanged §1.1 gate). **Skip = take the other parallel run.** Hard invariant: a challenge **never** lands on a
   chokepoint or a no-parallel segment, so the skip path is always structurally present (preserves
   `02-challenge-nodes-impl.md` §12).
6. **Chokepoints stay.** Act entry (a single shared funnel) and the pre-boss node remain single shared nodes; the
   boss is the single terminal. Specials never sit on a chokepoint (no parallel ⇒ no opt-out).
7. **Incremental per-act generation (state-aware placement).** The map is generated **one act at a time** — act 0
   at run start, each later act when its predecessor boss is cleared — passing the **live run-state** into
   generation. This is *forced* by the icon-routing rule: a family glyph the player routes toward must be known
   when the section is shown, so any **runtime-gated** family (brush — `available_brush_colors` is affinity-gated
   and grows over the run; later content too) can only be placed correctly against current state. Full-run-at-start
   generation freezes those rolls before the prereqs exist. See §3.6.

---

## 2. Topology — the act as a segment sequence

An act is a **sequence of segments** between the entry chokepoint and the boss:

```
entry(chokepoint, 1 node)
  → BRANCH SEGMENT A : two parallel runs of L_A ∈ [3,5] nodes
  → (chokepoint, 1 node — the segments' reconvergence/handoff)
  → BRANCH SEGMENT B : two parallel runs of L_B ∈ [3,5] nodes
  → pre-boss chokepoint (1 node)
  → BOSS (1 node, terminal)
```

- **Segment count per act** is rolled (`branch_segments_min/max`, default **2**). Two ~4-node segments + 3
  chokepoints + boss ≈ `1 + 4 + 1 + 4 + 1 + 1 = 12` nodes traversed → the §1.1 target. (Total *placed* nodes are
  more, since each segment has two parallel runs; "traversed" counts one run per segment.)
- **Both runs in a segment share length `L`** (rolled once per segment). Unequal-length parallel runs are deferred
  tuning (§7) — equal length keeps reconvergence on a single depth and the layout grid honest.
- **Lanes are retired as the primary structure.** Slice 1's fixed `lane_count` parallel columns become the **two
  runs of the current branch segment**. Keep `lane_count = 2` semantics (a segment is two runs); 3-way branches are
  a deferred experiment (§7), same as slice 1's lane-count-3 note.
- **Bridges** (slice 1's crossover) are dropped for now: with multi-node branches the lane-switch mid-run muddies
  the "commit to a branch" decision. If cross-branch movement is wanted later it returns as an explicit
  mid-segment crossover node (deferred, §7).

This stays inside the **graph (data) / view (scene)** split — only `MapGraph` generation changes. `MapView` reads
`(depth, lane)` and draws edges exactly as today; a branch run is just consecutive depths at the same lane offset,
so the existing `_layout` handles it (verify spacing; §6).

---

## 3. Generation algorithm — what changes in `map_graph.gd`

`_build(cfg, rng)` is rewritten around segments; `_assign_leg_params` / the pressure seam / traversal API / `_new_node`
/ `_connect` are **unchanged**. The replaced pieces:

**Replace `_build`'s middle-column loop with a segment loop.** Per act:

1. **Entry chokepoint** — one shared `LEG` node (act 0's is `start_id`), as today.
2. **For each branch segment** (`branch_segments_min..max`):
   - Roll `L ∈ [branch_len_min, branch_len_max]` (default 3..5).
   - Build **two parallel runs** of `L` `LEG` nodes each (lane 0 and lane 1), wired in-run depth→depth+1.
   - Wire the segment's **entry**: the preceding chokepoint fans into the first node of *both* runs.
   - Advance depth by `L`.
   - Place a **reconvergence chokepoint** (a single shared `LEG` node) that both runs' last nodes connect into —
     unless this is the last segment, in which case the pre-boss chokepoint serves that role.
3. **Pre-boss chokepoint** — single shared `LEG`, both final-segment runs reconverge here.
4. **Terminal boss** — single `BOSS` at the act's last depth, as today; `terminal_id` on the final act.
5. Chain acts: previous boss → next act entry, as today.

**Replace `_add_fork` + `_slot_shops` with `_slot_specials`** — one pass that distributes shops, events, and
challenges across the act's **branch-run nodes only** (never chokepoints), meeting the §1.2 per-traversal budget:

```
For each type in [SHOP, EVENT, CHALLENGE]:   # CHALLENGE only when act >= 1
  roll a per-traversal target count in [type_min, type_max]
  distribute that many across the segments so that EITHER run a player could walk
    collects ~target of this type (place into both runs across different segments,
    or differentiate runs so each run-choice still meets the budget)
  honour a per-type min spacing (no two of a spacing-sensitive type adjacent within a run)
  CHALLENGE: only into branch-run nodes (guaranteed parallel) — never a chokepoint (§1.5)
```

Differentiation is the point: bias the *two runs of a segment* toward **different** type mixes (run 0 gets the
shop, run 1 gets the challenge) so the branch pick is a real composition choice, while keeping each run's *total*
across the act inside the budget. Expose the differentiation strength as a knob (`branch_contrast`, §4) — 0 =
identical runs (boring), 1 = maximally divergent.

**Leg params (`_assign_leg_params`) unchanged.** Each non-chokepoint, non-boss node still rolls its
`(target, max_turns)` off the slice-2 pressure curve by depth; parallel-run nodes at the same depth share the tier
(the info-model rule — routing differs by *type composition*, not hardness). Chokepoint `LEG` nodes roll like any
leg. Bosses stay act-ceiling at reference turns.

### 3.6 Incremental per-act generation (the §1.7 change)

Today `MapGraph.generate(level, rng)` builds **all acts at run start** in one `_build` pass, chaining boss→entry.
Slice 3 makes generation **per-act and state-aware**:

- **Split `_build` into per-act.** `MapGraph` becomes an *accumulating* container. `generate(level, rng)` seeds
  **only act 0** (entry → segments → pre-boss → boss). A new `generate_next_act(run_state)` appends the next act's
  subgraph and chains the previous boss → the new entry. `terminal_id` is set only when the **final** act
  (`act == level.boss_count - 1`) is generated.
- **Pass live run-state in.** `generate_next_act` takes a `run_state` snapshot (at minimum
  `available_brush_colors`, `highest_cleared`, and whatever a state-gated family needs). `_slot_specials` consults
  it: a family is eligible for a node only if its prereq holds *now* (brush ⇒ `available_brush_colors` non-empty).
  This is what makes the routed icon honest (§1.7) — accuracy is always eligible; brush places only where it can
  actually pay off.
- **Seam (`main.gd`).** On a boss clear that isn't the run victory (the `_show_leg_upgrades` boss branch, after the
  victory check), call `_map_graph.generate_next_act(_build_run_state())` **before** showing the map for the next
  pick. Run victory stays "cleared the terminal boss" — now known once the last act has been generated (keep the
  `score_victory` belt-and-suspenders).
- **View.** `MapView` renders the **current act** (plus visited history if cheap), not the whole run — which also
  resolves the long-deferred *cramped-1501 layout* item, since only one act's ~12 columns are on screen at once.
- **RNG.** Keep the single seeded generator threaded across act generations so a seed still reproduces the whole
  run; just consume it incrementally.

This generalizes the challenge pattern (stable knobs at gen, state-dependent values at arrival) up to the section
level: the *section* is deferred until its state exists. Challenge `compute_challenge_params` can stay at arrival
(idempotent) or move to act-gen now that `highest_cleared` is known then — either is fine; leave at arrival to
minimize churn.

---

## 4. Config — new `MapGenConfig` exports

All `@export` with `##` hover docs, per Max's conventions. The slice-1 mix knobs that no longer apply
(`mid_cols_min/max`, `fork_chance`, `shop_min_col_gap` stays) are removed/renamed; keep `lane_count`,
`reference_turns`, `turns_*`, `pressure_baseline`, `shops_per_act_*`, `challenge_handicap_chance`.

```gdscript
## How many branch segments per act (each segment = two parallel L-node runs). Two ~4-node
## segments + chokepoints + boss ≈ the ~12-node traversed-path target.
@export var branch_segments_min: int = 2
@export var branch_segments_max: int = 2

## Node length of each parallel run in a branch segment (both runs share the rolled L).
@export var branch_len_min: int = 3
@export var branch_len_max: int = 5

## Per-traversal soft target counts (a single path through the act collects ~this many).
@export var shops_per_path_min: int = 1
@export var shops_per_path_max: int = 3
@export var events_per_path_min: int = 1
@export var events_per_path_max: int = 3
@export var challenges_per_path_min: int = 1   ## acts >= 1 only (post-boss-1 gate)
@export var challenges_per_path_max: int = 3

## Min node gap between two of the same spacing-sensitive type within a run.
@export var special_min_gap: int = 1

## How divergent the two runs of a segment are made (0 = identical mixes, 1 = maximally
## different). The routing decision's strength.
@export var branch_contrast: float = 0.6
```

> Note: `shops_per_act_min/max` becomes `shops_per_path_*`; the per-*act* framing was the slice-1 model and is
> superseded by the per-*traversal* budget (§1.2).

---

## 5. Validation (`_validate`) — new invariants

Keep slice 1's reachability checks (every node reachable from start; every node can reach the terminal boss; start
has no predecessors; boss no successors). Change/add:

- **Raise the act node budget.** The 7–12 assert becomes a wider band — the *placed* node count per act is larger
  now (two runs per segment). Assert per-act placed nodes ∈ `[act_budget_min, act_budget_max]` (start ~14..26;
  expose as a knob) and assert the **traversed** path length (one run per segment) ≈ 12 ± slack.
- **Challenge placement invariant (load-bearing).** Every `CHALLENGE` node sits in a branch run that has a live
  parallel run — i.e. it has a sibling-lane node reachable between the same two chokepoints. Fail loud otherwise
  (this is the structural guarantee that `Skip` always exists).
- **Per-traversal budget.** For a sampled set of full start→boss paths, assert each collects ≤ `type_max` of each
  special type (and, softly, ≥ `type_min` where the act allows).
- **No specials on chokepoints.** Entry / reconvergence / pre-boss nodes are always `LEG`/`BOSS`, never SHOP /
  EVENT / CHALLENGE.

Fail loud in debug (`assert`) so a bad roll never ships a soft-locked or skip-less map.

---

## 6. View (`map_view.gd`) — mostly free

`MapView` lays out by `(depth, lane)` and draws edges between connected widgets; a branch run is consecutive depths
at one lane, so the existing `_layout` + `_draw` handle it without structural change. Two checks:

- **Column spacing** must comfortably fit ~12 columns across the act (was ~5). Verify `col_spacing` × max depth fits
  the viewport or the view scrolls/zooms; if cramped, this is the same "cramped-1501 layout" polish already on the
  deferred list — fold it in here since paths got longer.
- **Reconvergence rendering**: two run-final nodes both edge into the chokepoint — the existing multi-edge `_draw`
  already does this (it drew lane→boss reconvergence in slice 1).

Node-type color/label is unchanged; the **family icon** for EVENT/SHOP nodes is added in `03-events-impl.md`, not
here.

---

## 7. Slice boundary — ships vs defers

**This slice ships:** the segment-based `_build`; **incremental per-act generation** (§3.6: `generate` seeds act 0,
`generate_next_act(run_state)` appends on boss clear, state-aware `_slot_specials`, per-act view render);
`_slot_specials` (shops + events*-slots* + challenges across branch runs with per-traversal budgets and run
differentiation); the re-homed challenge placement + skip invariant; the new `MapGenConfig` exports; the
raised/rewritten `_validate`; headless tests (§8). *EVENT nodes are placed (type + branch-run position + a rolled
family eligible against run-state) but their reward content/icons land in `03-events-impl.md`* — slice 3 owns the
*topology slot + the state-aware family roll*, events owns the *payload*.

**Deferred (explicit):**
- **3-way branch segments** (three parallel runs) — `lane_count = 3` experiment, exported.
- **Unequal-length parallel runs** within a segment.
- **Mid-segment crossover nodes** (the bridge's successor, if cross-branch movement is wanted).
- **The event payload + family icons** → `03-events-impl.md`.
- **Long-path view polish** (scroll/zoom/cramped layout) beyond "it fits and reads."

---

## 8. Tests (`tests/test_map_graph.gd`, extend; headless)

- **Budget:** over N seeds × 3 levels, per-act placed-node count in band; traversed-path length ≈ 12 ± slack.
- **Per-traversal type budget:** enumerate (or sample) full start→boss paths; each collects ≤ `type_max` of each
  type; act-0 paths collect **zero** challenges (gate); acts ≥ 1 collect ≥ 1 challenge on at least one branch.
- **Challenge skip invariant:** every CHALLENGE node has a parallel sibling run between its bounding chokepoints.
- **No specials on chokepoints.**
- **Reachability** (unchanged): all nodes reachable from start and able to reach the terminal boss; seeded RNG
  reproducibility.
- **Incremental gen:** `generate` yields only act 0 (no act-1+ nodes present); `terminal_id` is unset until the
  final act is generated; `generate_next_act` appends a chained act (prev boss → new entry) and the per-act
  invariants above hold on each appended act; a fixed seed reproduces the full multi-act run.
- **State-aware family roll:** generate an act with a `run_state` that has brush colors vs one that has none —
  assert EVENT nodes only roll a brush family in the former (and only accuracy in the latter). (Cross-checks the
  events spec's availability rule from the generation side.)

## Related
- `specs/map/01-substrate-impl.md` / `01-substrate-slice2-impl.md` — the slices this revises.
- `specs/map/02-challenge-nodes-impl.md` — its §12 skip + §17 placement follow-up; §17 is superseded here.
- `specs/map/03-events-impl.md` — the event payload that fills the EVENT slots this places (build after this).
- `specs/map/00-overview.md` — program index; the type-composition routing this makes load-bearing (and the
  Phase-04 path-biasing it sets up).
