---
Spec date: 2026-06-01
Status: Shipped 2026-06-01
Implementation: Claude Code, single pass during the session that approved this spec. No Godot CLI was available, so verification is manual playtest.
Notes: All four reworks + the cut + the new boss shipped. Prism (recolor-on-hit + checkout-helper suppression), Weak Board (replaces Recession; new `weak_board_*` ids/`.tres`; `WeakBoardBoss`), Void (drift via new per-ring void infrastructure in `dartboard.gd`), and The Drunkard (new boss hooking `throw_mechanic.gd`) are all in. one_dart/two_darts removed from pools and archived in place (`two_darts_boss.gd` marked DEPRECATED). New shared hook `Boss.on_dart_landed()`. Drunkard tiers slotted into 501/1001/1501 so the new boss is reachable; orphaned hard variants created but unslotted. DEFERRED as designed: full pool re-curation + map system + objective bosses; polish (Weak Board wear shader, Prism recolor animation, literal Void migration *slide* — shipped as a fade); Rotation and Narrow Doubles untouched. Two tuning flags for playtest: the Drunkard's `(100 − range)` meter-length floor formula, and Void drift legibility at high counts.
---

# Spec: Boss Redesign — Reactive Counters + Mutating Variants

Status: **Designed 2026-06-01, not yet implemented.** A roster rework agreed in a design session after a round of self/peer playtesting flagged several bosses as too flat or too simple. Reworks four bosses, cuts two, and establishes a design principle for all future bosses. Pool re-curation and the map system are explicitly deferred (see end).

## Problem

Two findings from playtest:

1. **Most bosses are flat global taxes.** Every current boss subtracts something at leg start and lets the player absorb it — Void/Recession remove value, Narrow Doubles shrinks the target, Two/One Dart cut resources, Prism/Rotation scramble the board read. None of them respond to what the player does, and none of them touch the *run the player built* (colors, streaks, flight archetype, modifiers). The ones that feel fun in play (Rotation, Prism, Narrow Doubles) are the ones that change the player's moment-to-moment *decisions*; the flat ones (Void, Recession) just lower the number while you play identically.
2. **Difficulty reads as inconsistent.** Selection is uniform random over `LevelDefinition.boss_pool` (`boss_manager.gd::start_boss_leg`) — there is no dynamic scaling. The "501 bosses feel like the medium version at 1001" perception comes from the 1001 pool mixing easy *and* medium variants that share a `display_name` ("The Void", "Prism", "Recession"), so the same-named boss is a coin-flip between tiers and the player can't tell which they got. There is also no dedup on draw, so a 2-boss level can roll the same boss twice.

## Design principle (applies to all bosses, current and future)

Sort every boss into one of two kinds, and prefer the first:

- **Build-counter (reactive)** — responds to what the player just did / targets a dominant strategy. These create adaptation instead of flat loss. The reworks below give us one counter per major build axis: **Weak Board** counters value-stacking ("4 black mods + an even streak, I'll power through"), **Prism** counters color/affinity builds, **The Drunkard** counters maxed accuracy stats.
- **Environmental** — imposes a board condition the player plays around. **Void**, **Rotation**, **Narrow Doubles**. Fine to keep, but they shouldn't be the whole roster.

Future boss test: *does it counter a dominant strategy, or impose an environment?* "Just take away X" (the dart-count bosses) is neither — it's a flat resource tax that doesn't change decisions, and is cut for that reason.

## The reworks

### Prism — recolor-on-hit, persist for the leg (counters color builds)

Today Prism is a leg-start whole-board pair-inverter (`prism_boss.gd`, `on_leg_start`/`on_leg_end`, shipped in the color-brush spec). Rework: it does **nothing at leg start**; instead, **each dart that lands recolors the hit segment(s) to a random color, and that recolor persists for the rest of the leg.** Consequences accumulate from the player's own choices — they watch the board mutate as they touch it and start routing around the corners they've already poisoned. It's now a *randomizer*, not a pair-inverter; the old `reshuffle_interval` tuning is obsolete.

- Reuses the existing per-ring color mutation on `effective_wedge_colors` — just driven on the hit segment per throw instead of all 20 wedges at leg start.
- **The checkout helper goes dark (or shows "?") under Prism.** Color/value can't be trusted once it mutates reactively — the uncertainty is the boss, not a bug.

Difficulty tiers (new lever = splash radius):
- **easy** — recolor only the exact ring hit.
- **medium** — recolor the hit ring + the adjacent rings on the same wedge.
- **hard** — recolor the **whole hit wedge** + the hit ring on **both neighboring wedges**. Worked example (Max): hitting single-20 recolors single-1 and single-5 (the hit ring on the two neighbor wedges) *plus* double-20 and triple-20 (the rest of the 20 wedge).

### Weak Board — replaces Recession (counters value-stacking)

New fantasy: the board *wears out* where you keep hitting it (lore nod — old competitions banned barbed tips for chewing up boards). **Each hit on a wedge permanently reduces that wedge's value by X% for the rest of the leg; repeats stack the damage deeper.** The board does not heal. This punishes the power-through player hardest — their money wedge degrades fastest — while a spread player slowly wears down the whole board.

- **Value only, never color.** Keeps Weak Board (value) and Prism (color) cleanly orthogonal.
- **Floor so a wedge never reaches 0.** Degraded-but-scorable stays distinct from Void (0 / denial). Difficulty tiers scale X% per hit (easy small → hard large), and/or the floor.
- **Permanent-for-the-leg, not a rolling window.** This is the version Max picked — it reads as "damage" and avoids redundancy with Prism's per-hit-but-spatial effect.
- This **reuses Recession's plumbing** (`recession_boss.gd`'s `_original_wedge_values`, the reduction math, `BossManager.get_recession_data`), driven per-hit instead of once at leg start. Recession is the foundation here, not an archive.
- **Polish (deferred):** a shader noise/damage texture on degraded wedges that intensifies with stack depth, to visualize the wear.

### Void — drift mutation that spreads as it scales (environmental)

Today Void voids N whole wedges per turn, re-rolled each turn (`void_boss.gd`, `void_count` tuning). Rework keeps the whole-wedge voiding but makes higher tiers **mutate**: voided rings *drift* outward to adjacent wedges, so the void grows in volume *and* spreads sideways, becoming less uniform as it hardens.

- **easy** — 6 whole wedges voided, aligned, no drift.
- **medium** — 10 whole wedges voided; **1–2** voided rings drift to an adjacent wedge's same ring (the source ring becomes hittable).
- **hard** — 14 whole wedges voided; **2–3** rings drift.

Counts are deliberately capped at 14 (not the earlier 18): **drift needs non-void neighbors to migrate into**, so at near-total void the signature mutation can't fire — exactly when it should peak. Holding counts moderate keeps the drift legible. Hard's difficulty comes from *more drift / more spread*, not raw void volume.

- **Overlap constraint:** a drifted ring must land on a non-void spot; total voided ring-count is conserved (prevents two voids stacking into the same ring and accidentally making the board easier).
- **Tween:** void the set normally first (continuity with the easy version), *then* play the live ring migration as the reveal — same boss, evolved.

### The Drunkard — distorted aim + enforced meter length (counters maxed accuracy)

New boss attacking the *throw mechanic* rather than the board (a new axis; first of a potential family). One unified "drunk = loose, wandering aim" fantasy:

1. **Distorted crosshair** — the V/H crosshair arms become squiggly / zigzag, and the release meters follow the new path. Keep it a **learnable** zigzag, not jitter — hard, not nauseating.
2. **Enforced minimum meter length** — floors the meter length to ~100–200px **plus extra scaled by `(100 − current range stat)` per axis** (`throw_mechanic.gd` maps `horizontal_range`/`vertical_range` 1–100 to half-width/height). This claws back *more* from a maxed-accuracy player and barely touches a low-stat one — self-balancing, and it ensures the distortion actually matters (a maxed player's meters would otherwise be too small for the wobble to bite).

Difficulty tiers scale wobble amplitude + the enforced floor.

## Cuts

- **one_dart and two_darts are both cut.** "Just take away X darts per turn" is a flat resource tax that changes nothing about how you play — it fails the design-principle test. Remove both from all level pools and the registry.
- **Archive, don't delete.** They're correctly wired into the gameplay systems, so keep the scripts/`.tres` **in place** (moving them risks the `.tres`/uid references) with a `## DEPRECATED — archived for reuse` header, and log the archival in DesignNotes. The "−1 dart" idea survives only as a possible future **reward-tradeoff** (the Glass Cannon pattern — a downside on a high-power item), never again as a boss.

## Implementation plan

- `scripts/bosses/prism_boss.gd` — move the recolor from `on_leg_start` (all 20) to `on_turn_start`/a per-hit hook on the landed segment; recolor to a random color and persist; add a splash-radius tuning key for the easy/medium/hard tiers. Wire the checkout helper to suppress/`?` while a Prism boss is active.
- `scripts/bosses/recession_boss.gd` → **Weak Board**: drive the existing value reduction per-hit with stacking and a floor instead of once at leg start on one color. Rename the boss id/display/`.tres` set accordingly; reuse `_original_wedge_values` + `BossManager.get_recession_data`.
- `scripts/bosses/void_boss.gd` — keep whole-wedge selection; add the ring-drift pass (with the non-overlap constraint) for medium/hard; add the migration tween. New tuning: `void_count` (6/10/14) + `drift_count` (0 / 1–2 / 2–3).
- New `scripts/bosses/drunkard_boss.gd` (+ `.tres` tiers) — crosshair distortion hook into `throw_mechanic.gd` (squiggly arm path + meter-follows-path) and an effective-meter-length floor override scaled by range stats.
- Resources: new/renamed `.tres` under `resources/bosses/` for Weak Board and Drunkard tiers; delete one_dart/two_darts from pools; `boss_definition.gd` already carries `tuning` + `difficulty_tier`.
- Static-type everything; exported colors/sizes/tuning per project conventions.

## Acceptance
- Prism recolors hit segments to random colors that persist for the leg (splash by tier: ring / +adjacent rings / whole wedge + neighbor wedges); checkout helper is suppressed under Prism.
- Weak Board permanently reduces hit wedges' value, stacking, value-only, with a floor that never reaches 0; replaces Recession and reuses its reduction plumbing.
- Void voids 6/10/14 whole wedges by tier; medium/hard drift 1–2 / 2–3 rings to non-void neighbors with conserved total; migration plays as a tween after the initial void.
- The Drunkard distorts the crosshair (legible zigzag, meters follow) and floors meter length scaled by `(100 − range)`, hitting maxed-accuracy builds hardest.
- one_dart and two_darts no longer appear in any pool; their code remains in place, marked deprecated.

## Deferred
- **Pool re-curation.** Tangled with the map decision below. Minimal cleanup required now: remove one_dart/two_darts and point pools at the renamed Weak Board. Full re-curation — tier-consistent pools (so a level has a coherent difficulty identity), distinct names or surfaced tiers to fix the "same name, two difficulties" perception, dedup on draw, and slotting the orphaned hard variants (`void_hard`→reworked, `rotation_hard`, `narrow_double_hard`) — waits for the map.
- **Map system (parked, high-leverage).** A Slay-the-Spire-style map would both raise boss frequency *and* demote the weaker/environmental effects to map-node mini-encounters rather than full bosses, instead of forcing every effect up to boss strength. It's also the natural vehicle for the game's missing personality — a pub/bar darts circuit ("beat each venue's house board"). Increase frequency only *after* bosses are reactive; more-frequent flat taxes would just be tedium.
- **Objective bosses (parked).** Race/objective framings ("check out within N turns", "hit all four colors before you can finish") instead of debuffs — changes rhythm rather than math. Revisit after the reactive reworks land.
- **Rotation and Narrow Doubles** untouched this pass.
- **Prism/Weak Board polish:** shader wear texture on Weak Board; Prism recolor animation.
