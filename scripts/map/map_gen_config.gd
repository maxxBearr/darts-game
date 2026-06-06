class_name MapGenConfig
extends Resource
## Tunable knobs for MapGraph generation. Attach one to a LevelDefinition to
## override per level; a null config on the level means "use these defaults".
## See specs/map/01-substrate-slice3-impl.md §4 — each spacing/mix/budget number is
## meant to be an inspector-tunable export, not a hard-coded constant.
##
## Slice 3 topology: an act is entry chokepoint → branch segments (two parallel
## L-node runs that reconverge at a chokepoint) → pre-boss chokepoint → boss. The
## slice-1 mid-column/fork knobs are retired; the per-*act* shop framing becomes a
## per-*traversal* budget shared by shops / events / challenges.

## Roughly-parallel routes per branch segment. Lean 2 (a segment is two runs); a
## 3-way branch is a deferred experiment (slice 3 §7).
@export var lane_count: int = 2

# ── Slice 3: segment topology ────────────────────────────────────────────────

## How many branch segments per act (each segment = two parallel L-node runs). Two
## ~4-node segments + chokepoints + boss ≈ the ~12-node traversed-path target (§2).
@export var branch_segments_min: int = 2

## Maximum branch segments per act. Held at the min by default (a fixed 2-segment act);
## raise the max to let an act roll a longer spine.
@export var branch_segments_max: int = 2

## Fewest nodes in each parallel run of a branch segment (both runs share the rolled L).
@export var branch_len_min: int = 3

## Most nodes in each parallel run of a branch segment.
@export var branch_len_max: int = 5

# ── Slice 3: per-traversal special budgets ───────────────────────────────────
# A budget for ONE full path through the act (the player only walks one branch per
# split), NOT a per-act slot count. The generator caps every path at the max and
# aims each path near the band; the min is soft (contrast can leave a branch lean).

## Soft minimum shops a single traversal collects.
@export var shops_per_path_min: int = 1

## Hard maximum shops a single traversal collects.
@export var shops_per_path_max: int = 3

## Soft minimum events a single traversal collects.
@export var events_per_path_min: int = 1

## Hard maximum events a single traversal collects.
@export var events_per_path_max: int = 3

## Soft minimum challenges a single traversal collects. Acts >= 1 only (post-boss-1
## gate, slice 3 §1.5 / 02 §1.1) — act 0 places no challenges regardless.
@export var challenges_per_path_min: int = 1

## Hard maximum challenges a single traversal collects.
@export var challenges_per_path_max: int = 3

## Min node gap between two of the SAME special type within one run (no two adjacent
## when 1: a gap of <= this many indices is rejected). The spacing curve's hard floor.
@export var special_min_gap: int = 1

## How divergent the two runs of a segment are made (0 = identical mixes placed in
## both runs, 1 = a special goes into only ONE run so the branch pick is a real
## composition choice). The routing decision's strength. See slice 3 §3.
@export_range(0.0, 1.0) var branch_contrast: float = 0.6

# ── Slice 3: validation band ─────────────────────────────────────────────────

## Smallest legal PLACED-node count for a single act (entry + two runs per segment +
## chokepoints + boss). With 2 segments of L∈[3,5]: 1+2L_A+1+2L_B+1+1 ∈ [16,24]; the
## floor sits a little under to tolerate a future shorter roll. Asserted in _validate.
@export var act_node_budget_min: int = 14

## Largest legal placed-node count for a single act (the ceiling of the band above,
## with headroom for a longer segment/lane roll).
@export var act_node_budget_max: int = 26

# ── Retained from slice 1/2 ──────────────────────────────────────────────────

## Chance a placed challenge node carries a recycled benched-boss aim handicap (§8);
## otherwise it is a clean precision race. 0 = never handicapped, 1 = always. The
## handicap raises darts-used, so it nudges the earned rarity down a band on its own.
@export_range(0.0, 1.0) var challenge_handicap_chance: float = 0.5

# ── Slice 2: per-leg turns roll (the difficulty texture) ─────────────────────
# Each non-boss leg rolls a whole turn count, then derives its target from a flat
# pressure line that reproduces the slice-1 ladder at reference_turns (ships at
# parity). See specs/map/01-substrate-slice2-impl.md §2 / §4.

## The turn count at which a leg reproduces the seeded slice-1 ladder (pressure
## pressure_baseline, base darts). The roll centres here. turns = reference_turns
## ⇒ target = the depth's baseline ladder value (slice-1 parity).
@export var reference_turns: int = 5

## Fewest turns a leg may roll — the sniper floor. 4 → ≥12 base darts so the dart
## bank is never starved. Lower it for spicier (leaner, snippier) snipers.
@export var turns_min: int = 4

## Most turns a leg may roll — the marathon ceiling (longer, more forgiving, a
## bigger target number).
@export var turns_max: int = 6

## The fraction of legs pinned to reference_turns; the rest roll uniform across
## [turns_min, turns_max]. 0 = fully uniform; 1 = always reference_turns. At 0.35
## with a 4–6 range, ~57% of legs sit at reference_turns (0.35 pinned + a third of
## the remaining 0.65) and ~43% get marathon/sniper texture.
@export_range(0.0, 1.0) var turns_center_bias: float = 0.35

## The flat pressure every non-boss leg targets — a single global difficulty dial
## (raise it to make *all* legs harder). Held flat as a control variable this
## slice; a future depth-ramp plugs in by making this a function of depth.
@export var pressure_baseline: float = 1.0
