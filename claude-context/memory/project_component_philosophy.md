---
name: project-component-philosophy
description: "Dart component design — single DartComponent class for all three slots (barrel/shaft/flight); weight-stat correlation rule (heavy = horizontal stats, light = vertical stats)."
metadata: 
  node_type: memory
  type: project
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

**Three slots, not four.** Barrel, shaft, flight. The point was dropped from customization — it's the least interesting both visually and in real dart customization. Bringing it back would need a strong design justification.

**Single `DartComponent` Resource class for all three slots, not subclasses.** Structurally identical — the slot determines the "type" implicitly. Optional `ComponentType` enum can be added for shop/slot enforcement if needed later.

**Weight-stat correlation rule:** Heavier parts tend to have better horizontal stats (more mass = more resistant to lateral drift). Lighter parts tend to have better vertical stats (dart floats truer, less affected by gravity). This gives every part natural personality without arbitrary stat blocks. New components should respect this — heavy barrels with strong vertical stats would feel wrong.

**Primary stat per slot (rough mapping):**
- **Barrels** — range (and primary balance driver via weight)
- **Shafts** — speed (secondary balance)
- **Flights** — accuracy (minor balance)

**Player starts with same base stats every run.** Components add/subtract from base. Future Form system (deck equivalent) would modify the *base* before components apply.

**Ability hook integration:** Components can optionally carry a `ThrowModifier` resource (throw-time conditional stat bonus, e.g., Nervous Sweater) and/or a `ShopBias` resource (shop-time pool weight bias, e.g., Color Connoisseur). Both default to null. New ability hook types (e.g., a future `ScoringHook` for on-score effects) follow the same sibling-resource pattern — see [[project-ability-extension-points]].

**Flight is the run's archetype slot** (formalized 2026-05-24). Barrel and shaft are stat-tuning slots — players combine many over a run. Flight is build-defining: one equipped, no swap mid-run, intended to feel like "what's this run about?". Flight components warrant tougher unlock conditions because they represent commitment. See [[project-flight-archetype]] for the full semantics.

**Stable identity via `id: StringName` (added 2026-05-23).** Every component carries a slot-prefixed snake_case ID (`&"barrel_torpedo"`, `&"shaft_long_carbon"`, `&"flight_blue_whisp"`). Used by save data (`PlayerProgress.unlocked_ids`) and progression tracking. **NEVER change an ID after a build ships** — orphans player save data. The registry validator catches authoring mistakes (empty/duplicate IDs) at startup. See [[project-component-unlock-system]] and `DartComponentGuide.md` for the full rules.

**How to apply:** When designing new components, lean into weight-stat coherence. Don't propose subclasses for component types — slot enforcement should be data-driven if needed. When discussing component pool expansion, think about whether each slot has enough variety to make builds feel different. New components need an `id` assigned per the convention before being registered.

See also: [[project-dart-game-concept]], [[project-balance-philosophy]]
