---
Spec date: 2026-06-05
Status: SHIPPED 2026-06-05 (Claude Code, from this spec; tuning follow-up applied same session). Slice 2 of
  Phase 01: replaces the ported difficulty ladder with the pressure-ratio generator. Built + headless-verified
  (37,783 checks, 0 fails) + confirmed in playtest (per-leg turns/target variance visible). Self-contained build
  doc; the conceptual frame lives in `01-substrate-impl.md` §3 step 4 and `01-substrate.md`.
Notes: ships at parity (turns=5 reproduces slice 1). One post-build tuning fix — the default `turns_center_bias`
  (0.6) over the narrow [4,6] range collapsed every roll to turns=5 via lerp-then-round, making the generator
  inert; replaced with a discrete weighting (bias = fraction pinned to reference_turns), default lowered to 0.35,
  and a distribution-spread test added so it can't silently go inert again. Deferred-as-designed: difficulty ramp
  (depth-dependent `pressure_baseline`), arrival-ceremony presentation polish, Phase 02 challenge nodes (consume
  the §6 pressure seam). Refining the zig-zag variance later is pure config (`turns_min/max`, `turns_center_bias`).
Part of: the Map Program (`specs/map/00-overview.md`), Phase 01 (Substrate), slice 2.
Depends on: slice 1 (SHIPPED 2026-06-05, commit `e71762f`) — the graph, view, seam, and ported ladder this
  edits.
Feeds: Phase 02 challenge nodes (`02-challenge-nodes.md`) — slice 2 exposes the pressure math (§6) those nodes'
  turns↔rarity banter dial reads from. That phase is deferred to a later slice; this spec only builds the seam.
---

# Phase 01 — Map Substrate, Slice 2: The Pressure-Ratio Generator

## 0. One-line thesis

Slice 1 shipped a playable frame where **every leg at a given depth is identical** (`ladder(depth)`, 15 darts).
Slice 2 keeps difficulty *flat* but gives each leg its own **texture** — a rolled `(target, turns)` pair that
trades a long-forgiving leg against a short-lean one — so the map's legs stop being interchangeable. This is the
"furniture's difficulty model," deferred from slice 1 precisely so it could be tuned on a playable frame. That
frame now exists.

**Decided this session (2026-06-05):** flat pressure (no ramp), seeded from the existing ladder, per-leg roll
(not paired lanes), bosses untouched, and a node-data-model fix so the +1-dart item composes correctly.

---

## 1. What slice 1 left here, and what changes

Slice 1's `MapGraph._assign_leg_params` (`scripts/map/map_graph.gd:154`) walks every node and assigns
`target_score` by interpolating the act floor→ceiling on the depth axis, with `darts_fronted = 15` flat. Both
parallel nodes at a depth get the **same** target. That is the entire difficulty surface today.

Slice 2 replaces the *body* of `_assign_leg_params` (and only that body — the generator topology, the seam, and
the view are untouched). The new body rolls a per-leg `turns` and derives `target` from it against a flat
pressure line that, at the reference turn count, **reproduces the slice-1 ladder exactly** (ships at parity).

Three things change in code; everything else is internal to that one function:

| Change | File / location | Why |
|---|---|---|
| Node stores `max_turns`, not `darts_fronted` | `scripts/map/map_node.gd:19`; seam `scripts/main.gd:1059` | The +1-dart item makes `darts_per_turn` vary; storing total darts and dividing by it loses darts and shrinks budgets. See §3. |
| `_assign_leg_params` rolls `(target, turns)` per leg | `scripts/map/map_graph.gd:154` | The slice-2 generator (§2). |
| Config gains turns-roll knobs | `scripts/map/map_gen_config.gd` | Replaces the now-derived `darts_fronted` export with the turns range + roll shape (§4). |

The test's ladder-monotonicity assertion also relaxes (§5).

---

## 2. The generator — flat pressure, seeded from the ladder

### 2a. The pressure definition (carried from `01-substrate-impl.md`, made concrete)

```
pressure(target, turns, depth) = target / (turns * BASE_DARTS_PER_TURN * expected_per_dart(depth))
```

`expected_per_dart(depth)` is the **designer's model of how much a player can reliably score per dart at that
run-depth** — and, per the design decision this session, it models the player's *growing build power* (more
multipliers / hotspots / streak room late), not raw aim, so it rises with depth. `pressure = 1.0` means the
target exactly equals the expected total output across the budget — a nominal coin-flip leg.

### 2b. Seeding the curve from the shipped ladder (the key move)

We do **not** invent `expected_per_dart` numbers. We *define the slice-1 ladder to be pressure 1.0* and read the
curve off it. Slice 1's ladder gives, at each depth, a known-good `(target = ladder(depth), turns = 5, darts =
15)` point that Max has already feel-tuned. Setting `pressure ≡ 1.0` there yields:

```
expected_per_dart(depth) = ladder(depth) / (REFERENCE_TURNS * BASE_DARTS_PER_TURN)   # = ladder(depth) / 15
```

So `expected_per_dart` is just the existing per-depth ladder target divided by 15. We never store it separately —
we keep slice 1's ladder computation as `baseline_target(depth)` (the value a `REFERENCE_TURNS`-turn leg would
get) and derive everything by scaling. This is the whole reason the slice ships at parity.

### 2c. The per-leg roll (replaces the slice-1 body of `_assign_leg_params`)

For each **non-boss** leg node, in this order:

1. **Roll turns.** `turns = roll_turns(rng, cfg)` — a whole number in `[cfg.turns_min, cfg.turns_max]`, weighted
   toward `cfg.reference_turns` (default 5) so most legs feel "normal" and the marathon/sniper extremes are
   rarer (§4). Whole by construction → no divisibility problem, ever.
2. **Derive the target at flat pressure.** Solve `pressure = cfg.pressure_baseline` for `target`:

   ```
   target = cfg.pressure_baseline * turns * BASE_DARTS_PER_TURN * expected_per_dart(depth)
          = cfg.pressure_baseline * (turns / REFERENCE_TURNS) * baseline_target(depth)
   ```

   With `pressure_baseline = 1.0` and `REFERENCE_TURNS = 5`:
   - `turns = 5` → `target = baseline_target(depth)` — **exactly slice 1** (parity ✓).
   - `turns = 4` → `target = 0.8 × baseline` — a leaner, slightly snippier leg.
   - `turns = 6` → `target = 1.2 × baseline` — a longer, more forgiving, bigger-number leg.
3. **Snap to X01 parity.** Reuse slice 1's `_snap` (`map_graph.gd:193`) so targets stay on the
   `starting_target + n·target_increment` lattice (101, 201, 301…) the HUD, checkout tables, and bosses share.
4. **Clamp to the act window.** Keep the snapped target within `[act_floor, act_ceiling]` (the same per-act
   floor/ceiling slice 1 already computes) so a 6-turn leg near an act's top can't overshoot the act-ceiling
   boss, and a 4-turn leg at an act's bottom can't dip below the floor.
5. **Store `max_turns = turns`.** `darts_fronted` is no longer stored (§3).

**Pressure is held flat (`pressure_baseline`, one constant) — there is no pressure band in slice 2.** The
zigzag the design called for is the *kind* of difficulty (turns→target texture), not the *amount*. Difficulty
ramp is deliberately deferred (§7): a flat pressure line is the **control variable** that lets us later measure
shop-throwing effectiveness and the felt-difficulty of marathon vs sniper legs without difficulty drift
confounding the read.

### 2d. Per-leg, not paired lanes (design decision)

Each leg rolls **independently**. We do **not** deliberately pair a depth's two parallel nodes as one
marathon + one sniper. A systematically dart-starved lane would choke the dart bank, and lane-choice *meaning* is
meant to come from map *structure* (shop proximity, legs-since-last-help) — a later concern — not from a
designed difficulty contrast. Slice 2 only lays the texture groundwork; two parallel legs will sometimes differ
and sometimes not, by the roll.

### 2e. The documented blind spot (keep, don't correct)

The pressure formula is first-order and **undercounts darts on purpose.** More darts is more forgiving of misses
*and* gives streaks more turns to compound a larger total — so two legs at equal nominal pressure are **not**
equally hard in felt play: the higher-turn leg is easier and banks more darts. We are **not** correcting for
this, because that asymmetry is exactly what flat-pressure-as-control is meant to let us observe. The spec records
it as a named caveat: **nominal pressure ≠ felt difficulty; the turns knob carries an intentional difficulty
gradient.** The mitigation is to keep the turns swing gentle (default `turns_min = 4`, so never below 12 darts)
and centre-weighted, so the easy↔hard spread between sibling legs stays modest. Widen the range later if spicier
snipers prove fun.

---

## 3. The node-data-model fix — define a leg by turns

**Decision (confirmed this session):** a leg is defined by `max_turns`; `darts_fronted` is *always* the derived
quantity `max_turns × darts_per_turn`, computed live, never stored.

**Why.** Slice 1 stores `darts_fronted = 15` and the seam computes turns as `darts_fronted / darts_per_turn`
(`main.gd:1059`). With the existing +1-dart-per-turn item (`rewards/extra_dart_reward.gd:8` —
`x01.darts_per_turn += 1`) making `darts_per_turn = 4`, that is `15 / 4 = 3` turns → only 12 darts thrown,
*fewer* than intended, plus a dart lost to integer truncation. A power item must never shrink the budget.
(`darts_per_turn` is mutated elsewhere too — `bosses/two_darts_boss.gd` sets it outright — so the divide-by-live
approach is broken in more than one path, not just the item.) Defining the leg by **turns** fixes it: total darts `= max_turns × darts_per_turn`
(live), so +1-per-turn correctly *adds* `max_turns` darts (same turns, more each). This also matches how the bank
already computes savings — `x01_game.get_saved_darts()` is `max_turns * darts_per_turn - darts_used_in_leg`, live
on both factors — so the model becomes consistent end to end.

**Edits:**

- `map_node.gd`: replace `var darts_fronted: int = 15` with `var max_turns: int = 5`. (Keep a `## darts_fronted`
  doc note that the fronted-darts *concept* = `max_turns × darts_per_turn`, derived for display/economy, not a
  field.)
- `map_graph.gd` `_assign_leg_params`: set `n.max_turns = turns` instead of `n.darts_fronted = cfg.darts_fronted`.
- `main.gd:1059`: `x01_game.start_leg_with(node.target_score, node.darts_fronted / x01_game.darts_per_turn)`
  → `x01_game.start_leg_with(node.target_score, node.max_turns)`. The generator did the pressure math at
  run-start with `BASE_DARTS_PER_TURN`; items then ease legs live, as intended.

**Forward note (no work this slice):** this is the same hook the Phase 02 challenge nodes' darts-per-turn
manipulation will compose with — a challenge race just runs a leg with its own `max_turns` (and possibly its own
`darts_per_turn`). Storing turns now future-proofs that; it is the same logic, not a parallel one.

---

## 4. Config knobs (`MapGenConfig`)

Replace the slice-1 `@export var darts_fronted: int = 15` (now derived) with the turns-roll surface. All
`@export`, all hover-doc'd per house style:

- `reference_turns: int = 5` — the turn count at which a leg reproduces the seeded ladder (`pressure_baseline`,
  base darts). The roll centres here.
- `turns_min: int = 4` — fewest turns a leg may roll (the sniper floor; 4 → ≥12 base darts so the bank isn't
  starved). Lower it for spicier snipers.
- `turns_max: int = 6` — most turns a leg may roll (the marathon ceiling).
- `turns_center_bias: float = 0.6` — 0 = uniform across `[min,max]`; 1 = almost always `reference_turns`.
  Controls how rare the extremes are. (Implement as a simple triangular/weighted pick centred on
  `reference_turns`.)
- `pressure_baseline: float = 1.0` — the flat pressure every leg targets. A single global difficulty dial
  (raise it to make *all* legs harder) — the seam where a future ramp (§7) plugs in by making this a function of
  depth instead of a constant.

`BASE_DARTS_PER_TURN` is **not** a new config value — it reads `x01_game.darts_per_turn`'s default (3). The
generator runs at run-start before any item changes it, so the base is correct for the gen-time math; document
the assumption in a comment.

---

## 5. Validation / test changes (`tests/test_map_graph.gd`)

Slice 1's test asserts the ladder is **monotonic non-decreasing by depth** (`map_graph.gd` had every depth share
a tier). Slice 2 breaks that on purpose: a 4-turn leg deeper than a 6-turn leg can carry a *lower* raw target.
Relax and re-aim the invariants:

- **Remove** the strict `max_target_by_depth` non-decreasing check.
- **Add** per non-boss leg: `pressure(target, max_turns, depth) ≈ pressure_baseline` within a snap tolerance
  (the ±half-increment that `_snap` + the act-window clamp can introduce). This is the real contract now —
  *flat pressure*, not *monotonic target*.
- **Add**: `max_turns ∈ [turns_min, turns_max]` for every leg; every target within its act window
  `[floor, ceiling]`.
- **Keep** (unchanged): exactly one BOSS per act, terminal target == `max_score_target`, one sink, full
  reachability both directions, per-act 7–12 budget.
- The `turns = reference_turns ⇒ target = baseline_target(depth)` parity identity is worth a direct spot-check
  assertion (regenerate with the roll forced to `reference_turns` and compare against the slice-1 ladder values)
  so "ships at parity" stays a guarantee, not a hope.

Run headless: `godot --headless --script res://tests/test_map_graph.gd` (200 seeds × 3 levels, as slice 1).

---

## 6. The challenge-node-facing seam (build now, consume later)

Phase 02's turns↔rarity banter dial is the same pressure math turned into a player knob. To stop the two from
drifting, slice 2 exposes the math as **public, reusable functions on `MapGraph`** (or a small static
`MapPressure` helper if `MapGraph` gets crowded), rather than burying it inside `_assign_leg_params`:

- `expected_per_dart(depth) -> float` — the seeded curve (`baseline_target(depth) / 15`).
- `pressure_of(target: int, turns: int, depth: int) -> float` — the formula in §2a.
- `baseline_target(depth) -> int` — the `reference_turns` target (slice 1's ladder), kept callable.

`_assign_leg_params` calls these instead of inlining. Phase 02 then computes a challenge's rarity by reading
`pressure_of` for each turn choice the player could banter to, off the *same* curve — so the leg difficulty and
the challenge difficulty are guaranteed coherent.

**Coherence sanity-check to run when tuning** (note, not code): the 02 banter table's reference points are ~50 /
33 / 25 per dart on a 301 race (2 / 3 / 4 turns). Those should fall out of `pressure_of` at the curve's early
depths as *above*-1.0 pressures (a real wall) — confirming the slice-2 curve and the challenge ladder agree
before Phase 02 is built. No action this slice beyond exposing the functions; just don't inline the math.

---

## 7. Slice boundary — what slice 2 ships vs defers

**Slice 2 (this build):**
- `_assign_leg_params` rewritten to the §2 flat-pressure per-leg roll, seeded at parity from the slice-1 ladder.
- `MapNode` stores `max_turns`; seam + bank read it; `darts_fronted` becomes derived (§3).
- `MapGenConfig` turns-roll knobs (§4).
- Pressure math exposed as reusable functions for Phase 02 (§6).
- Test invariants re-aimed to flat-pressure + parity spot-check (§5).
- Bosses **unchanged** — fixed at act ceilings (501/1001/1501), `reference_turns`, the existing difficulty
  treatment. They are tier checkpoints, not rolled.

**Deferred (explicit follow-ups):**
- **Difficulty ramp / scaling system.** Held flat on purpose as a control variable. When wanted, make
  `pressure_baseline` a function of depth/act instead of a constant — the §4 dial is already the plug point.
- **Felt-difficulty correction.** The §2e blind spot stays uncorrected by design; revisit only if the
  marathon/sniper spread proves to need it after observation.
- **Structural lane-choice meaning** (shop proximity / legs-since-help weighting) — a generation concern beyond
  difficulty; not slice 2.
- **Phase 02 challenge nodes** — consume §6's seam; their own slice, deferred per this session's decision.

---

## 8. Open tuning (numbers, not structure)

All `@export`, all dialled in-engine on the now-playable map — none are architectural unknowns:
`reference_turns`, `turns_min/max`, `turns_center_bias`, `pressure_baseline`, and (if it ever proves too coarse)
the shape of `baseline_target(depth)` itself. The slice ships at parity, so the starting point is the
already-tuned slice-1 feel; every knob moves *away* from a known-good baseline.

## Related
- `specs/map/01-substrate-impl.md` — slice 1 (the frame this edits); §3 step 4 is the conceptual seed of this slice.
- `specs/map/01-substrate.md` — the substrate design rationale (info model, difficulty philosophy).
- `specs/map/02-challenge-nodes.md` — consumes §6's exposed pressure math; deferred to a later slice.
- `specs/map/00-overview.md` — program index; frame-before-furniture sequencing.
- `specs/future/darts-as-currency-economy.md` — the bank the §3 turns-model keeps consistent with.
