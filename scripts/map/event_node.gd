class_name EventNode
extends Resource
## One event encounter. The family is rolled at GENERATION (uniform over the trade families,
## NO state gates — Max's ruling 2026-06-07, typed-shop slice) and shown as the node's map
## icon; the 3 concrete options are rolled at ARRIVAL from the node's section (act),
## mirroring how ChallengeNode defers its target/deposit.
## See specs/map/03-events-impl.md §2–§4 + specs/map/04-typed-shop-impl.md (gate removal).
## Slice 3 places the node + rolls the family; the event payload (the 1-of-3 pick) is
## filled by the events slice.

## The trade-family this event offers (rolled uniformly from the trade families). Drives
## the icon and the grant path. Active families: &"accuracy", &"brush" (pre-affinity rolls
## draw from the full color pool), and &"geometry" (zero-sum trades are a legal build-around
## even when currently inert). Later: &"scoring".
@export var reward_family: StringName = &"accuracy"

## How many options the player chooses among on arrival. 3 per the locked model;
## exported for tuning.
@export var option_count: int = 3
