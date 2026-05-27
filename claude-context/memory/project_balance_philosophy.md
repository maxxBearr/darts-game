---
name: project-balance-philosophy
description: "Balance system design — \"parts = ceiling, balance = delivery quality.\" Three zones (green/orange/red) gate stat bonuses and introduce accuracy skew at extremes."
metadata: 
  node_type: memory
  type: project
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

**Core principle:** *Your dart parts determine your ceiling, your balance determines how cleanly you can actually deliver.* Components give raw stats (range/speed/accuracy); balance is a separate accuracy modifier layered on top.

**Three balance zones** (using `abs(balance_value)` where balance_value = sum of three component weights, range -3.0 to +3.0):
- **Green (0.0 – 0.3):** Flat bonus to all stats. Balanced dart flies true.
- **Orange (0.3 – 0.6):** Neutral. No effect.
- **Red (0.6+):** Penalties scale. Accuracy skew introduced (front-heavy → dart drops, back-heavy → dart floats).

**Transition sub-zones (HUD pass refinement, shipped 2026-05-21):** Between the three named zones, two soft transition bands apply mild gameplay effects — a slight stat boost just inside the green→orange edge, and a slight accuracy skew just inside the orange→red edge. The transitions are tunable and small (started at ~10–20% of the corresponding full-zone effect). The bar's *visual* is now a smooth color gradient, even though the three named zones still drive the dominant gameplay states.

**Why three zones, not a continuous curve:** Simple for players to read and tune. Inspector-exposed thresholds. The transition sub-zones soften the cliff-edges without losing the readable three-state model.

**Why balance affects accuracy specifically:** Thematically clean — a balanced dart flies straighter. Avoids balance becoming a "do everything worse" penalty.

**Imbalance can be correct.** A rare barrel with extreme stats that pushes the build into orange/red can be worth the penalty if the raw stats are strong enough. The system should reward thoughtful tradeoffs, not punish all imbalance equally.

**How to apply:** When proposing balance-related features, preserve the parts/balance dichotomy. Don't let balance become a "bonus stat" the player optimizes for directly — it should always be a *constraint* on builds, not a goal. When discussing new components, the weight value is as much a design lever as the stat bonuses.

See also: [[project-dart-game-concept]], [[project-component-philosophy]]
