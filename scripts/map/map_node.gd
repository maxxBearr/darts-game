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
var darts_fronted: int = 15       ## leg dart budget → max_turns = darts_fronted / darts_per_turn

# --- Graph wiring ---
var next_ids: Array[int] = []     ## forward edges (the legal next picks)
var prev_ids: Array[int] = []     ## back edges (layout + reachability checks)

# --- View/runtime state ---
var visited: bool = false
var reachable: bool = false       ## true when legally pickable from the current node

## Reserved off-branch fork slot — where a CHALLENGE/EVENT will prefer to sit in
## Phase 02/03. Filled with a LEG/SHOP this slice; only marks the geometry.
var is_off_branch: bool = false


func _to_string() -> String:
	return "MapNode#%d(%s d%d l%d a%d t%d)" % [id, Type.keys()[type], depth, lane, act, target_score]
