---
name: project-flight-archetype
description: "Flight is the dart's singular archetype-defining slot — one equipped per run, no mid-run swap, fliers must justify themselves as 'this run is about X' picks rather than stat tweaks."
metadata: 
  node_type: memory
  type: project
  originSessionId: 4cd9e318-da6a-47f4-8585-2444f9fc216b
---

**Flight = the run's archetype slot.** Barrel and shaft are stat-tuning slots. Flight is build-defining: exactly one equipped via `DartBuild.equipped_flight`, no swap mid-run. Each flight should justify itself as a "this run is about X" pick, not a stat tweak. Compared to barrel/shaft which players combine and swap freely, flight is closer to a class pick than a piece of equipment.

**Why:** Without a build-defining slot, every run plays the same shape and "build variety" reduces to stat numbers. The flight slot exists to make players ask "what kind of run is this?" upfront. The no-swap rule sharpens that choice — pick wrong and you live with it. This is consistent with the broader "parts = ceiling, balance = delivery quality" philosophy ([[project-balance-philosophy]]).

**Design implications when proposing new flights:**

1. *Substantial-enough effects only.* A flat +2 stat would be wasted as a flight — that belongs on shafts/barrels. Flights should change *how* the player plays, not just how well.
2. *Tougher unlock conditions.* Per the build-defining-equals-harder-unlock principle, new flights should use harder `UnlockCondition`s than easy shafts/barrels. The shipped [[project-component-unlock-system]] supports this naturally.
3. *Effects can be in-play, shop-time, or both.* Ability hook siblings on `DartComponent` (currently `throw_modifier` and `shop_bias`) let a flight fire effects at different lifecycle moments. See [[project-ability-extension-points]].
4. *Defensive-only verbs need extra punch.* A pure safety-net flight (e.g., "save a broken streak") feels underwhelming as a whole-run commitment. Pair defensive verbs with proactive scaling, or rethink the verb.
5. *Shop-shaping fits uncapped types only.* Flights that bias the shop pool (like Color Connoisseur) should bias modifier types with no natural saturation cap. Streak modifiers cap at 1 per category; biasing toward them creates fatigue. Color modifiers don't cap; biasing toward them keeps producing useful drafts.

**Working flights as of 2026-05-24:** Blue Whisp, Wide Sail (stat fliers, default unlocked); Momentum Marksman (throw-time streak accuracy), Color Connoisseur (shop-time color bias) — both shipped via [archived spec](../../../../Documents/GitHub/darts-game/specs/2026-05-24-flight-modifier-additions.md).

**How to apply:** When the player proposes a new flight idea, interrogate whether it's archetype-defining or just a stat bonus. If the latter, suggest it as a shaft/barrel instead. When the player proposes a flight effect that fires at a new lifecycle moment (e.g., on-bust, leg-start), reach for [[project-ability-extension-points]] before extending `ThrowModifier`.

See also: [[project-component-philosophy]], [[project-ability-extension-points]], [[project-dropped-rethrow-design]]
