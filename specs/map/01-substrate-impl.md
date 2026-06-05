---
Spec date: 2026-06-04
Status: SHIPPED 2026-06-04 (Claude Code, from this spec; commit `e71762f` "Phase 1 of the map"). Slice 1 of
  Phase 01 — full rough-rect topology + ported difficulty ladder. Verified in-editor + headless (200 seeds × 3
  levels). The ported ladder is superseded by the pressure-ratio generator in
  `01-substrate-slice2-impl.md` (specced 2026-06-05). Deferred from this slice: pressure generator (→ slice 2),
  challenge content (→ Phase 02), arrival ceremony + art reskin (polish). Original build-doc body preserved below
  for design context.
Part of: the Map Program (`specs/map/00-overview.md`), Phase 01. Design rationale lives in `01-substrate.md`;
  this file is the build doc. When this phase moves to build it takes CLAUDE.md's active-spec slot.
---

# Phase 01 — Map Substrate: Implementation Spec

This is the buildable companion to `01-substrate.md`. The design doc settled *what* and *why*; this settles
*where in the code* and *in what order*. Read `01-substrate.md` first for the topology / difficulty / info-model
rationale — it is not repeated here except where a code decision depends on it.

The one-line thesis carried over from design: **frame before furniture.** The substrate's first job is to host
the *current* run flow (legs / shops / bosses) as a navigable graph — a reorganization of what already exists,
not new game content. That makes every later phase (challenges, typed shop, path-biasing) felt-testable in
context.

---

## 1. Codebase grounding — what drives the run today

There is **no graph today.** Run structure is *implicit*, computed inline from a single integer leg counter.
The map replaces that implicit scheduling with an explicit, generated graph. Here is exactly what exists and
what gets lifted.

### The linear leg engine — `scripts/x01_game.gd` (Node `$X01Game` under `Main`)

Pure logic, no rendering. The whole of run *structure* lives in a handful of fields and three functions:

- Fields: `current_leg`, `target_score`, `remaining_score`, `max_turns` (`@export`, default 5),
  `darts_per_turn` (default 3), `starting_target` (101), `target_increment` (100).
- `start_run()` → `current_leg = 1`, `target_score = starting_target`, `start_leg()`.
- `advance_leg()` → `current_leg += 1; target_score += target_increment; start_leg()`. **This is the
  self-incrementing ladder the map will take over.**
- `get_saved_darts()` → `max_turns * darts_per_turn - darts_used_in_leg`. The leg's *total dart budget* is
  `max_turns * darts_per_turn` (15 today). The design's **`darts_fronted` is this budget** — varied per leg by
  setting `max_turns` (keep `darts_per_turn = 3`).

> **Handoff insight:** today the *leg supplies its own difficulty* (`advance_leg` bumps the target). Under the
> map, the *selected node* supplies `(target_score, max_turns)` and `x01_game` stops self-incrementing. This is
> the single load-bearing change to existing logic. Everything else is additive.

### The orchestrator — `scripts/main.gd` (`Main`, Node2D, ~3300 lines)

A monolith state machine keyed on `_leg_phase: String` plus `_awaiting_*` flags. The run-flow seam we touch is
small and well-isolated:

- **Run start:** `_on_run_confirmed()` (assembly → run) calls `boss_manager.configure_for_level(_current_level)`
  then `x01_game.start_run()`. **This is where the map gets generated.**
- **Leg won:** `_resolve_throw_impact()` → `_show_leg_won_banner()` → **`_show_leg_upgrades(response)`** — the
  post-leg fork. Today it branches, in order: end boss leg → check run victory (`target_score >=
  _current_level.max_score_target`) → bank saved darts (`_banked_darts += x01_game.get_saved_darts()`) → boss
  reward pick *or* shop (`response["current_leg"] % shop_cadence == 0`) *or* `_show_accuracy_pick()`.
- **Advance:** **`_on_next_leg()`** runs the board slide-out/in tween and, at the midpoint, calls
  `x01_game.advance_leg()`, then `if boss_manager.is_boss_leg(current_leg): boss_manager.start_boss_leg(...)`,
  then `_start_new_throw()`.

**What the map intercepts:** between "leg won, rewards/shop resolved" and "next leg starts," insert the
`MapView`. The player picks a node; the chosen node's type + params drive what `_on_next_leg` does next (start a
leg with the node's `(target, max_turns)`, or enter the shop, or start the boss). `advance_leg()`'s
self-increment is replaced by "apply the selected node's params."

### Implicit scheduling being replaced

| Today (implicit) | Source | Becomes (explicit, on the node) |
|---|---|---|
| Target ladder 101,201,… | `x01_game.advance_leg()` | `MapNode.target_score` (slice 1: ladder by depth) |
| Dart budget = 15 | `max_turns(5) × darts_per_turn(3)` | `MapNode.darts_fronted` → sets `max_turns` |
| Shop every 3 legs | `current_leg % shop_cadence` in `_show_leg_upgrades` | `MapNode.type == SHOP` |
| Boss every 5 legs, capped | `boss_manager.is_boss_leg()` / `LevelDefinition.boss_count` | `MapNode.type == BOSS`, terminal per act |
| Run victory | `target_score >= max_score_target` | reaching the terminal BOSS node of the last act |

### Full-screen overlay pattern to reuse (for `MapView`)

`LevelSelectScreen` (`scripts/levels/level_select.gd`) is the model: a `Control` built **in code**, instantiated
in `main.gd`'s setup (`level_select = LevelSelectScreen.new()` → set props → connect signals →
`hud.add_child(level_select)`), shown/hidden via `.visible`. `MapView` follows this exactly — a code-built
`Control` added under `$HUD` (the `CanvasLayer`), toggled visible between legs. **No `.tscn` for the view in
slice 1** (grey rects are drawn/instantiated in code); the art reskin later swaps the node scene only.

### Other touch points (read-only awareness)

- `BossManager` (`scripts/bosses/boss_manager.gd`): keep it as the boss *roster/lifecycle* owner. The map
  decides *when* a boss happens (a `BOSS` node); `BossManager` still rolls *which* boss from
  `LevelDefinition.boss_pool` and runs its hooks. `is_boss_leg(leg_number)` (the `% cadence` test) is retired in
  favor of node type, but `start_boss_leg` / `end_boss_leg` / `boss_count` cap stay.
- `LevelDefinition` (`scripts/levels/level_definition.gd`): gains map-generation params (act windows, lane
  count, type-mix ranges) as `@export`s — see §3. `max_score_target` / `boss_count` / `boss_pool` /
  `rarity_weight_shift` stay.
- `_reset_run_state()` (main.gd): must also clear the generated graph + hide `MapView`.

---

## 2. Class / data breakdown

Three new units, mirroring the design's **graph (data) / view (scene)** split. All GDScript-typed per project
conventions; exported vars get hover-doc comments.

### 2a. `MapNode` — `scripts/map/map_node.gd` (`extends Resource` or `RefCounted`)

One graph entry. Pure data; no visuals. Use `RefCounted` (graph is generated per-run, not authored as `.tres`).

```gdscript
class_name MapNode
extends RefCounted

enum Type { LEG, CHALLENGE, SHOP, EVENT, BOSS }   ## extend the enum, never the topology

var id: int                       ## unique within the graph
var type: Type
var depth: int                    ## run-position: column index start→boss. Drives target tier.
var lane: int                     ## which lane (0/1[/2]); bridges belong to two — see edges.
var act: int                      ## 0..2; which of the 3 acts this node sits in

# --- Leg params (the x01 handoff payload; meaningful for LEG/CHALLENGE/BOSS) ---
var target_score: int = 0         ## what x01_game.target_score becomes on arrival
var darts_fronted: int = 15       ## leg dart budget → max_turns = darts_fronted / darts_per_turn

# --- Graph wiring ---
var next_ids: Array[int] = []     ## forward edges (PackedInt? keep Array[int] for typing simplicity)
var prev_ids: Array[int] = []     ## back edges (for layout + reachability checks)

# --- View/runtime state ---
var visited: bool = false
var reachable: bool = false       ## true when the player could legally move here this step

# --- Type-specific payload (slice 1: minimal) ---
# CHALLENGE → ChallengeNode resource ref (Phase 02; null in slice 1)
# EVENT     → family glyph id (Phase 03; null in slice 1)
# BOSS      → BossManager still rolls the concrete boss from the level pool
```

`darts_fronted` (not `max_turns`) is the stored field because it's the design's vocabulary and it keeps
`darts_per_turn` changes (relics) honest: `max_turns = darts_fronted / darts_per_turn`.

### 2b. `MapGraph` — `scripts/map/map_graph.gd` (`extends RefCounted`)

The generated data model + the generator. Owns the nodes and the rules that produced them. **No `Node`/scene
dependency** — unit-testable headless.

```gdscript
class_name MapGraph
extends RefCounted

var nodes: Dictionary = {}         ## id -> MapNode
var start_ids: Array[int] = []     ## act-0 entry node(s) (the shared funnel)
var current_id: int = -1           ## where the player is now (-1 before first step)
var acts: int = 3
var lane_count: int = 2

# --- generation (see §3) ---
static func generate(level: LevelDefinition, rng: RandomNumberGenerator) -> MapGraph
func _place_skeleton(...) -> void
func _slot_special_nodes(...) -> void   ## shops/events/bosses by type-mix + spacing
func _assign_leg_params(...) -> void     ## slice 1: ladder by depth; slice 2: pressure roll
func _wire_edges(...) -> void            ## lanes, in-lane forks, bridges

# --- traversal API (consumed by main.gd + MapView) ---
func get_node(id: int) -> MapNode
func reachable_from(id: int) -> Array[int]   ## legal next picks
func advance_to(id: int) -> void              ## set current_id, mark visited, recompute reachable
func is_terminal(id: int) -> bool             ## the act-3 boss
```

Pass an explicit `RandomNumberGenerator` (seeded) into `generate` so runs are reproducible for debugging and so
a future "seeded run" feature is free. Don't call the global `randi`.

### 2c. `MapView` — `scripts/map/map_view.gd` (`extends Control`, code-built)

The scene layer. Instantiates one grey-rect node widget per `MapNode`, positions it by `(depth, lane)`, draws
edges, routes clicks. Built in code (no `.tscn`) following the `LevelSelectScreen` pattern.

```gdscript
class_name MapView
extends Control

signal node_chosen(node: MapNode)   ## emitted when the player clicks a reachable node

var graph: MapGraph
func display(graph: MapGraph) -> void   ## build/refresh widgets from data
func _layout() -> void                   ## x = depth * col_spacing, y = lane * lane_spacing (+ fork offset)
func _refresh_reachability() -> void     ## enable only reachable_from(current_id); grey out the rest
```

**Slice-1 node widget = a `Button` (or `ColorRect`+click) per node**, colored by `type` (a flat palette: leg /
shop / boss / fork-alt / bridge tint), labeled with the type name. No target/darts shown on the map — that's
the design's "type on map, params on arrival" rule (params are revealed by the existing leg-start HUD, §4).
Edges drawn with `_draw()` lines between widget centers. Reachable nodes are bright + clickable; everything
else is dimmed.

Layout exports (inspector-tunable, hover-doc'd): `col_spacing`, `lane_spacing`, `fork_offset`, `node_size`,
plus the type palette colors. This is the "rough rect" surface that gets reskinned later **without touching
`MapGraph`.**

### 2d. The `(target, darts)` → x01 handoff (the seam)

In `main.gd`, replace the implicit advance with node-driven application. Concretely:

1. `_on_run_confirmed()` — after `x01_game.start_run()` is replaced/augmented: build the graph and place the
   player at start.
   ```gdscript
   _map_graph = MapGraph.generate(_current_level, _make_run_rng())
   # first node is an act-0 leg the player steps onto; or show the map immediately for the first pick
   ```
2. After a leg/shop/boss resolves (end of `_show_leg_upgrades` flow, where it currently chose shop vs accuracy),
   **show `MapView`** instead of auto-advancing: `map_view.display(_map_graph); map_view.visible = true`.
3. On `map_view.node_chosen(node)`: hide the map, run the existing slide tween (reuse `_on_next_leg`'s tween),
   and at the midpoint **apply the node** instead of `advance_leg()`:
   ```gdscript
   _map_graph.advance_to(node.id)
   match node.type:
       MapNode.Type.LEG, MapNode.Type.CHALLENGE, MapNode.Type.BOSS:
           x01_game.target_score = node.target_score
           x01_game.max_turns = node.darts_fronted / x01_game.darts_per_turn
           x01_game.remaining_score = node.target_score
           x01_game.current_leg += 1          # keep for unlock/HUD continuity
           x01_game.start_leg()               # NOT advance_leg() — params come from the node
           if node.type == MapNode.Type.BOSS:
               boss_manager.start_boss_leg(_build_game_state())   # rolls concrete boss from pool
       MapNode.Type.SHOP:
           _start_shop(...)                   # existing shop entry, unchanged
       MapNode.Type.EVENT:
           # slice 1: stub — treat as a no-op pass-through or a free modifier pick; content is Phase 03
   ```
4. Run victory = `_map_graph.is_terminal(node.id)` cleared (replaces the `target_score >= max_score_target`
   test). Keep the old test as a belt-and-suspenders assert during slice 1.

`advance_leg()` stays in `x01_game` but is no longer the driver on the map path. Add a new
`x01_game.start_leg_with(target, max_turns)` helper rather than poking fields from `main.gd` — keeps the
engine's invariants in one place.

> **Two interception points, not one.** `advance_leg()` is called from *two* places today: the normal next-leg
> tween (`_on_next_leg`, main.gd:1027) **and** the post-shop tween in `_end_shop` (main.gd:1647). The second one
> exists because today **a shop is a phase appended to the leg you just won, then it auto-advances to the next
> leg.** Under the map, **a shop is its own node**: the player enters it *by choosing the shop node*, and on
> leaving (`_end_shop`) returns to the `MapView` for the next pick — it does **not** auto-`advance_leg()`. So the
> map seam replaces *both* call sites: the normal advance becomes "apply chosen node," and the post-shop advance
> becomes "show the map again." This also unwinds the `% shop_cadence` coupling in `_show_leg_upgrades` (shops
> are no longer scheduled off the leg counter at all).

---

## 3. Generation algorithm — as ordered steps

`MapGraph.generate(level, rng)` runs these in order. **Slice 1 implements all of it except the pressure roll in
step 4** (ported ladder instead). Each spacing/mix number is an `@export` on `LevelDefinition` (or a dedicated
`MapGenConfig` resource if `LevelDefinition` gets crowded — recommended).

**Step 0 — Read the skeleton (fixed).** `acts = 3`; `lane_count` (default **2**); per-act node budget (7–12);
boss terminal per act; act windows (sliding: A1≈101–501, A2≈301–1001, A3≈601–1501). These are the spine; the
rest rolls inside.

**Step 1 — Place the depth grid.** For each act, choose a depth length within the node budget. Lay `lane_count`
parallel nodes at each interior depth. Acts share **funnel chokepoints**: act start (single shared node) and the
pre-boss depth (lanes reconverge before the terminal boss). The boss is a single node at the act's last depth.
This produces the bare lattice of node *slots*, all defaulting to `LEG`.

**Step 2 — Wire edges** (`_wire_edges`):
- **Lane edges:** each node connects forward to the same-lane node at the next depth.
- **In-lane forks:** at chosen depths, split a lane into two reconverging slots `A1 → (alt | leg) → A3` (both at
  depth+1, rejoining at depth+2). Mark one slot as the off-branch (where a `CHALLENGE`/`EVENT` will prefer to
  sit — Phase 02/03; in slice 1 it's just a second `LEG` or a `SHOP`). The fork is a *local content choice*, not
  a lane change. **Opportunity cost is spatial** (taking the alt forgoes the parallel leg) — no coded penalty.
- **Bridges:** at chosen depths, add a crossover node with edges to *both* lanes in and out. A bridge is **not a
  type** — it's an ordinary node that happens to sit at a crossover (see design). Lane-switching costs a real
  encounter.

**Step 3 — Slot special nodes** (`_slot_special_nodes`) by **type-mix + one distance-decay weight**:
- Per-lane soft targets (all exported): **1–3 shops, 0–2 events, 1–3 challenges, remainder legs**, inside the
  7–12 budget. Challenge/event exposure intentionally ≥ shop (the design's "exposure double-duty").
- **Spacing = one weight function per spacing-sensitive type:** `weight = base × f(distance_since_last_of_type)`,
  where `f = 0` below the type's min spacing and ramps up after. One curve gives both "never two shops within N"
  and "still rare-ish just past N." Tune per type: shops/challenges spaced hard, **legs near-flat** (repeat
  freely). All exported.
- **Guarantees stay soft** — no hard "shop on the pre-boss chokepoint" mandate (design call). If playtest shows
  zero-shop runs feel bad, the ready fix is to force the must-have onto the shared funnel node; noted, not built.
- **Slice 1 active types:** `LEG`, `SHOP`, `BOSS`. `CHALLENGE` slots are reserved (off-branch marked) but filled
  with `LEG` until Phase 02. `EVENT` slots optional stub (§4). So slice 1's branches differ by **shop placement
  + fork/bridge geometry**, which is enough to feel-test routing.

**Step 4 — Assign leg params** (`_assign_leg_params`) — **the slice boundary:**
- **Slice 1 (ported ladder):** `target_score = ladder(depth)` — a monotonic climb across the whole run mapped
  onto absolute depth (e.g. linear from `starting_target` to the act-3 boss's `max_score_target`, matching
  today's 101→1501 feel). **Both parallel nodes at a depth share the tier** → parallel legs are interchangeable
  in difficulty; routing differences come from *type composition*, not hardness (consistent with the design's
  claim that type-only routing makes Phase 04 load-bearing). `darts_fronted = 15` for all (today's budget).
  Bosses get the act ceiling (501/1001/1501).
- **Slice 2 (pressure-ratio generator — deferred task):** replace `ladder(depth)` with a roll: pick
  `(target, darts_fronted)` from the act window to hit a target **pressure band**
  `pressure = (target / darts_fronted) / expected_per_dart(depth)`; the knob used (big-target/generous-darts =
  marathon vs modest-target/starved-darts = sniper) is itself rolled for flavor. `expected_per_dart(depth)` is a
  static designer curve, **not adaptive** (the bank is the catch-up mechanic). Deferred because the curve's
  numbers can't be tuned until the map is playable — build the frame first, tune the furniture on it.

**Step 5 — Validate.** Assert: every node reachable from start; every path terminates at the act-3 boss; no
dangling slots; lane budgets within 7–12. Fail loud in debug (`assert`) so a bad roll never ships a soft-locked
map.

---

## 4. Information model in code — type on map, params on arrival

- `MapView` renders **type only** (color + label). It never reads `target_score` / `darts_fronted`. Enforce by
  *not passing* those to the widget.
- **Params revealed on arrival** reuse the existing leg-start HUD. Today a leg simply starts; slice 1 can ship
  the *plain* version (the leg HUD already shows target via `_update_all_hud`). The design's full ceremony
  (center-screen `Score to match: 401` that docks to its slot, darts printing one-by-one in sets of 3 reusing
  the bank-save animation in `hud.bank_leg_savings`) is a **polish task, not a slice-1 blocker** — list it under
  deferred. The data path (`node → x01_game`) is what slice 1 must land; the ceremony dresses it later.

---

## 5. Slice boundary — what slice 1 ships vs defers

**Slice 1 (this build):**
- `MapNode` / `MapGraph` / `MapView` units + `scripts/map/` folder.
- Generator steps 0–3 + step 4 *ported ladder* + step 5 validation. Full topology: 2 lanes, in-lane reconverging
  forks, bridges, funnel chokepoints — all as grey-rect/`Button` widgets.
- Active node types: `LEG`, `SHOP`, `BOSS` (challenge/event slots reserved, filled as legs/stubs).
- The `main.gd` seam: generate at run start, show `MapView` between legs, apply chosen node's `(target,
  max_turns)` to `x01_game`, terminal-boss = run victory. `_reset_run_state` clears the graph.
- `BossManager` retains roster/lifecycle; `is_boss_leg(%cadence)` retired in favor of `BOSS` node type.
- Seeded RNG. Headless unit test for `MapGraph.generate` validation (step 5).

**Deferred (explicit follow-up tasks):**
- **Slice 2 — pressure-ratio generator** (step 4 roll + `expected_per_dart` curve). Tuned on the playable frame.
- **Phase 02 — challenge nodes** (`02-challenge-nodes.md`): fills the reserved off-branch fork slots.
- **Phase 03 — typed shop + codex / event content + family glyphs.** Slice 1's `EVENT` is a stub.
- **Arrival ceremony** (center-screen readout dock + dart print-out reusing bank-save animation).
- **Art reskin** of the node widget (the whole point of the graph/view split — `MapGraph` untouched).
- **Phase 04 path-biasing** — rides this graph; made load-bearing by the type-only info model.
- Lane-count = 3 experiments; bridges-per-act tuning. (Exported, so they're knobs, not rebuilds.)

---

## 6. Open tuning (not structure)

Carried from `01-substrate.md` §"Remaining opens": lane count (2 vs 3), the `expected_per_dart(depth)` curve
(slice 2), per-type spacing curve shapes, and the art handoff. All are `@export` numbers or deferred-phase work,
not architectural unknowns.

## Related
- `specs/map/01-substrate.md` — conceptual design + rationale (read first).
- `specs/map/00-overview.md` — program index; frame-before-furniture sequencing.
- `specs/map/02-challenge-nodes.md` — fills the reserved fork off-branch; blocked on this substrate.
- `specs/2026-06-03-scoring-on-the-board.md` — the `family` tag the event/shop glyphs key off (Phase 03).
