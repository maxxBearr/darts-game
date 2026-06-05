class_name MapGenConfig
extends Resource
## Tunable knobs for MapGraph generation. Attach one to a LevelDefinition to
## override per level; a null config on the level means "use these defaults".
## See specs/map/01-substrate-impl.md §3 (each spacing/mix number is meant to be
## an inspector-tunable export, not a hard-coded constant).

## Roughly-parallel routes per act. Lean 2; 3 is an open tuning call.
@export var lane_count: int = 2

## Minimum number of middle (lane) columns per act. With 2 lanes the per-act node
## count ≈ 2 + lane_count*mid_cols (+1 optional fork), so a floor of 3 keeps acts
## inside the design's 7–12 band.
@export var mid_cols_min: int = 3

## Maximum number of middle columns per act.
@export var mid_cols_max: int = 4

## Soft minimum shops slotted per act.
@export var shops_per_act_min: int = 1

## Soft maximum shops slotted per act.
@export var shops_per_act_max: int = 2

## Minimum column gap enforced between two shops within an act (the spacing
## curve's hard floor — "never two shops within N").
@export var shop_min_col_gap: int = 1

## Chance per act to inject one in-lane reconverging fork (a reserved off-branch
## slot). The fork's opportunity cost is purely spatial — see the design doc. A
## post-boss-1 fork (act ≥ 1) is upgraded to a Phase 02 challenge node, so this
## also sets how often challenges appear: at 0.85 a post-boss-1 act reliably
## offers one. NOTE: only ONE fork per act, so this can't push a 1001 run past a
## single challenge or a 1501 past two — raise challenges_per_act for that.
@export var fork_chance: float = 0.85

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
