class_name MapGenConfig
extends Resource
## Tunable knobs for MapGraph generation. Attach one to a LevelDefinition to
## override per level; a null config on the level means "use these defaults".
## See specs/map/01-substrate-slice3-impl.md §4 — each spacing/mix/budget number is
## meant to be an inspector-tunable export, not a hard-coded constant.
##
## Topology (tuning pass 2026-06-06, "sideways H"): an act is entry chokepoint →
## two continuous parallel lanes in branch segments, with a CROSSOVER interchange
## node between consecutive segments (lanes run straight through; stepping onto the
## crossover lets you switch lanes — or double back) → pre-boss chokepoint → boss.
## Only the pre-boss merge remains; mid-act reconvergence chokepoints are retired.
## The slice-1 mid-column/fork knobs are retired; the per-*act* shop framing becomes
## a per-*traversal* budget shared by shops / events / challenges.

## Roughly-parallel routes per branch segment. Lean 2 (a segment is two runs); a
## 3-way branch is a deferred experiment (slice 3 §7).
@export var lane_count: int = 2

# ── Round 2: lane length + crossovers (decoupled, 2026-06-06) ─────────────────
# The act is two parallel lanes of a rolled TOTAL length, cut into stretches by a
# rolled number of CROSSOVER interchanges (count decoupled from stretch length, so
# the traversed length stays ~constant regardless of how many lane-switch points an
# act rolls). Retires the slice-3 branch_segments_* / branch_len_* pair.

## How many CROSSOVER interchanges an act rolls (one between each pair of stretches, so
## stretches = crossovers + 1). Decoupled from lane length (below) — more crossovers means
## more, shorter stretches, not a longer act. Clamped so each stretch keeps ≥2 nodes
## (crossovers ≤ lane_len/2 − 1). Each crossover may itself be typed (crossover_weight_*).
@export var crossovers_min: int = 1

## Maximum crossovers per act.
@export var crossovers_max: int = 3

## Fewest nodes in ONE lane across the whole act (both lanes share this total; it is cut
## into crossovers+1 stretches of ≥2 each). Traversed path length per act ≈ lane_len + 3
## (entry + pre-boss + boss) + crossovers actually taken. Kept at 9: dropping the MIN starves a
## short act of room for its guaranteed lane-run challenge (challenges_per_path_min). The
## leg-lattice pass trims only the MAX (worst-case length) — see lane_len_max.
@export var lane_len_min: int = 9

## Most nodes in one lane across the whole act. Trimmed by 1 (was 12) in the leg-lattice pass to
## shave the longest acts; the cull rule already culls easy leftovers, so fewer leg nodes is fine.
@export var lane_len_max: int = 11

## Relative weights for a crossover's rolled TYPE (normalized internally). A crossover is
## off-budget, so these add spice on top of the lane-run special budget. Challenge respects
## the act-0 depth gate and the ≤1 detour-challenge-per-act cap; shop respects the act-wide
## shop_min_graph_gap spacing. Leg weight trimmed 0.5→0.35 in the 2026-06-08 density pass
## (Max: acts read too leg-heavy) — typed crossovers absorb 1–2 of the dry legs per act.
@export var crossover_weight_leg: float = 0.35
@export var crossover_weight_shop: float = 0.2
@export var crossover_weight_event: float = 0.2
@export var crossover_weight_challenge: float = 0.1

# ── Round 2: mini-branches (2026-06-06) ──────────────────────────────────────
# Short detours that fork off a lane, run on an outer render row, and rejoin THE SAME
# lane with an equal node count — a stay-vs-detour choice. Off-budget (chosen friction).

## How many mini-branches an act rolls. Capped at one per lane (2 lanes ⇒ effective max 2);
## with 2, one detours off each lane (top lane's branch above, bottom's below).
@export var branches_min: int = 1

## Maximum mini-branches per act.
@export var branches_max: int = 2

## Fewest nodes in a mini-branch detour. A branch of B nodes needs a stretch of ≥ B+2 nodes
## to fit (fork + B detour + rejoin); B is clamped to the host stretch, branch skipped if
## nothing fits.
@export var branch_node_min: int = 2

## Most nodes in a mini-branch detour.
@export var branch_node_max: int = 4

## Chance a placed mini-branch hosts exactly ONE special (rolled from the crossover type
## weights, leg excluded). 0 = branches are always plain legs; 1 = always one special.
@export_range(0.0, 1.0) var branch_special_chance: float = 0.6

# ── Slice 3: per-traversal special budgets ───────────────────────────────────
# A budget for ONE full path through the act (the player only walks one branch per
# split), NOT a per-act slot count. The generator caps every path at the max and
# aims each path near the band; the min is soft (contrast can leave a branch lean).

## Hard minimum graph distance (in edges) between any two SHOP nodes, enforced across ALL
## placement sources — lane budget, crossovers, mini-branches — and across stretch boundaries
## (Max's ruling 2026-06-08: the per-run special_min_gap was blind to both, rolling Shop→Shop
## runs and the recurring lane-Shop/crossover-Shop/lane-Shop diamond). 2 = no shop within two
## hops of another. 0 disables the rule.
@export var shop_min_graph_gap: int = 2

## Soft minimum shops a single traversal collects.
@export var shops_per_path_min: int = 1

## Hard maximum shops a single traversal collects.
@export var shops_per_path_max: int = 3

## Soft minimum events a single traversal collects. Raised 1→2 in the 2026-06-08 density pass
## (Max: too many plain legs; a lane could roll its whole act event-less when contrast lumped
## a low event roll onto the other lane). Events are the free-trade spice, so they're the
## right filler — challenges stay at their band (deposit friction shouldn't inflate).
@export var events_per_path_min: int = 2

## Hard maximum events a single traversal collects.
@export var events_per_path_max: int = 3

## Drought breaker (2026-06-08): the longest run of plain LEG nodes a traversal may see.
## Any longer run gets ONE rolled node converted to an event/challenge. Deliberately a hard
## cap, not a per-leg chance — a chance can whiff and ship the same 4-leg dry stretch, and an
## invariant is suite-assertable while a tendency isn't. Walks lanes ACROSS stretch seams and
## every mini-branch detour. 3 = "4+ legs in a row never ships". 0 disables.
@export var max_consecutive_legs: int = 3

## When the drought breaker converts a leg, the chance it becomes a CHALLENGE rather than an
## EVENT (challenge only where the act-0 depth gate allows). Events are the default filler —
## free-trade spice, no deposit friction.
@export_range(0.0, 1.0) var drought_break_challenge_chance: float = 0.25

## Soft minimum challenges a single traversal collects, for acts ≥ 1. Act 0 uses its own
## (leaner) band below — the post-boss-1 hard gate was removed in round 2 (challenges may
## now appear in act 0, just not too early; see challenge_act0_min_depth).
@export var challenges_per_path_min: int = 1

## Hard maximum challenges a single traversal collects (acts ≥ 1).
@export var challenges_per_path_max: int = 3

## Soft minimum challenges an act-0 traversal collects (leaner than later acts: the
## highest_cleared anchor is still small early, so wagers stay modest).
@export var challenges_act0_per_path_min: int = 1

## Hard maximum challenges an act-0 traversal collects.
@export var challenges_act0_per_path_max: int = 2

## Earliest depth (relative to the act entry) an act-0 challenge may sit: a challenge's
## target anchors on highest_cleared, which is meaningless until a few legs are cleared, so
## the first `challenge_act0_min_depth` columns after the act-0 entry are challenge-free.
@export var challenge_act0_min_depth: int = 3

## Min node gap between two of the SAME special type within one run (no two adjacent
## when 1: a gap of <= this many indices is rejected). The spacing curve's hard floor.
@export var special_min_gap: int = 1

## How divergent the two runs of a segment are made (0 = identical mixes placed in
## both runs, 1 = a special goes into only ONE run so the branch pick is a real
## composition choice). The routing decision's strength. See slice 3 §3.
@export_range(0.0, 1.0) var branch_contrast: float = 0.6

# ── Slice 3: validation band ─────────────────────────────────────────────────

## Smallest legal PLACED-node count for a single act. Round-2 formula:
##   2 (entry + pre-boss; boss counted separately below makes +1 → 3 sole spine nodes)
##   + 2·lane_len   (two parallel lanes of the rolled total)
##   + crossovers   (one interchange between each stretch pair)
##   + branch nodes (0 … 2·branch_node_max)
## i.e. 3 + 2·lane_len + crossovers + branches. Floor = 3 + 2·lane_len_min + crossovers_min
## + 0 = 3 + 18 + 1 = 22, set a little under for a shorter future roll. Asserted in _validate.
@export var act_node_budget_min: int = 20

## Largest legal placed-node count for a single act. Ceiling = 3 + 2·lane_len_max +
## crossovers_max + 2·branch_node_max = 3 + 24 + 3 + 8 = 38, with a little headroom.
@export var act_node_budget_max: int = 40

# ── Retained from slice 1/2 ──────────────────────────────────────────────────

## Leg-lattice pass (2026-06-07): the most LEG-type nodes any single entry→boss route may hold —
## the per-traversal pacing cap. Parallel branch legs are alternatives (a stay-vs-detour pair costs
## one path's worth, not both), so the on-screen leg count floats above this. The cull rule already
## bounds the MEANINGFUL legs (extra legs beyond the act's ~10-cell lattice just repeat the hardest
## cleared pair), so this is a SOFT pacing target on node count, checked by the map test suite over
## the seed grid (not a hard _validate assert — an unlucky low-special roll mustn't crash a run).
## Trim lane_len to lower it. Set to 14 = the trimmed generation's observed per-act ceiling over
## the test seed grid (a tight regression guard). NOTE: the spec's aspirational ~8-9 is NOT
## reachable by the sanctioned "trim lane_len by 1-2" alone — the crossover interchanges (up to 3,
## each adding a leg when taken) plus the lane spine dominate the count. Reaching 8-9 would need a
## deeper topology cut (fewer crossovers and a shorter lane floor, which cascades into
## act_node_budget_min and the topology invariants) — left for a follow-up tuning pass. The cull
## rule already delivers the FELT pacing: extra leg nodes just repeat/cull, so you don't play 14
## escalating legs.
@export var path_leg_budget: int = 14

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
