class_name MapNode
extends RefCounted
## One entry in the run-map graph. Pure data — no visuals. Generated per run by
## MapGraph and rendered as a grey rect by MapView (slice 1). See
## specs/map/01-substrate-impl.md §2a.

## Extend the enum, never the topology. Slice 1 only emits LEG / SHOP / BOSS;
## CHALLENGE/EVENT slots are reserved (off-branch) and filled as legs for now.
enum Type { LEG, CHALLENGE, SHOP, EVENT, BOSS }

var id: int = -1                  ## unique within the graph
var type: Type = Type.LEG
var depth: int = 0                ## global column index, start→final boss; drives the target tier
var lane: int = 0                 ## render row (0/1[/2]); funnels centre, forks use an extra row
var act: int = 0                  ## which act this node sits in (0-based)

# --- Leg params (the x01 handoff payload; meaningful for LEG/CHALLENGE/BOSS) ---
var target_score: int = 0         ## what x01_game.target_score becomes on arrival
## A leg is defined by its turn budget, NOT a stored dart total. The fronted-darts
## *concept* — the leg's dart budget — is the derived quantity max_turns ×
## x01_game.darts_per_turn, computed live so power items that raise darts_per_turn
## (e.g. extra_dart_reward) correctly *add* darts instead of shrinking the budget.
## See specs/map/01-substrate-slice2-impl.md §3.
var max_turns: int = 5            ## what x01_game.max_turns becomes on arrival

# --- Graph wiring ---
var next_ids: Array[int] = []     ## forward edges (the legal next picks)
var prev_ids: Array[int] = []     ## back edges (layout + reachability checks)

# --- View/runtime state ---
var visited: bool = false
var reachable: bool = false       ## true when legally pickable from the current node

## Reserved off-branch fork slot — where a CHALLENGE/EVENT prefers to sit (Phase 02/03).
## Marks the geometry; a post-boss-1 fork is upgraded to Type.CHALLENGE at generation.
var is_off_branch: bool = false

## Set on Type.CHALLENGE nodes only (Phase 02): the wager/race tuning for this node.
## Its target_score + deposit band are computed at arrival from the live highest_cleared
## (they depend on runtime progress), not at generation. Null on every other node type.
## See specs/map/02-challenge-nodes-impl.md §7.
var challenge: ChallengeNode = null

## Set on Type.EVENT nodes only (Phase 03): the rolled trade-family (its map icon) for
## this node. The family is chosen at generation against the live run-state (slice 3
## §3.6); the 3 concrete options are rolled at arrival. Null on every other node type.
## See specs/map/03-events-impl.md §4.
var event: EventNode = null


func _to_string() -> String:
	return "MapNode#%d(%s d%d l%d a%d t%d)" % [id, Type.keys()[type], depth, lane, act, target_score]
