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
## slot). The fork's opportunity cost is purely spatial — see the design doc.
@export var fork_chance: float = 0.6

## Leg dart budget fronted on every node this slice. max_turns is derived as
## darts_fronted / x01_game.darts_per_turn. Slice 2 varies this per node.
@export var darts_fronted: int = 15
