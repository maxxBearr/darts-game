---
name: project-ability-extension-points
description: "Pattern for adding new dart-component abilities — sibling Resource per lifecycle moment on DartComponent, with the second-eval pass pattern for target-aware throw-time bonuses."
metadata: 
  node_type: memory
  type: project
  originSessionId: 4cd9e318-da6a-47f4-8585-2444f9fc216b
---

**Each ability lifecycle moment gets its own sibling Resource on `DartComponent`.** Don't bolt new hooks onto `ThrowModifier`; add a new peer. This keeps each hook's shape clean and lets components opt into only the lifecycle moments they care about.

**Current siblings (as of 2026-05-24):**
- `throw_modifier: ThrowModifier` — throw-time conditional stat bonus. `should_activate(context)` + `get_active_bonuses(context)`. Used by Ice Veins, Nervous Sweater, Momentum Marksman.
- `shop_bias: ShopBias` — shop-generation pool weight bias. `get_weight_overrides() -> Dictionary` returning `{ScriptType: float_multiplier}`. Used by Color Connoisseur.

**Deferred (intentional design space):**
- `ScoringHook` (or similar) — fires inside `ScoringModifierManager.process_score`, would unlock retrigger-style fliers and other on-score reactive effects. Worth designing alongside any other on-score idea so the hook shape covers multiple use cases.
- Shop spot-spawning bias — currently `ShopBias` only affects the item pool. A future override method on the same base could bias *where* lit spots spawn.

**Second-evaluation pass pattern (throw-time):** Throw modifiers evaluate twice per throw — once at throw start (game-state-only context) and once at aim placement (with `declared_target` and `active_streak_modifiers` in context). The second pass overlays target-dependent bonuses on top of the first. `ThrowModifier.get_active_bonuses()` accepts an optional `context: Dictionary = {}` so dynamic subclasses (like Momentum Marksman) can compute bonuses from the placed target while static subclasses (Ice Veins, Nervous Sweater) ignore it. The aim-placed visual preview reflects the second-pass bonuses automatically because the ghost ellipse is recomputed each frame from the current `horizontal_accuracy` / `vertical_accuracy`.

**Streak continuation introspection:** `ScoringModifier.would_continue_streak(target: Dictionary) -> bool` is the standard way for throw-side code to ask streak modifiers "would hitting this target keep your streak alive?" Non-streak modifiers return false; each streak subclass implements its own check. Use this pattern for any future ability that needs to ask "is this target aligned with the current streak deck?"

**Why this pattern:** Bundling all hooks into one mega-class (`FlightAbility` with optional methods) couples unrelated lifecycle moments and turns every new hook into a shared-file edit. Sibling resources let each hook evolve independently and keep the diff surface tight when adding a new ability type.

**How to apply:** When the user proposes a new flight ability:
1. Identify which lifecycle moment it fires at. If it's a new moment (not throw, not shop, not score), propose a new sibling Resource type with a clean override-able interface.
2. If it needs context the existing hook doesn't have (e.g., a throw-time effect that needs the aim target), check whether the second-eval pass already provides it before adding a new hook point.
3. Don't reach for `ThrowModifier` for things that aren't throws (the Color Connoisseur conversation almost did this; we caught it and added `ShopBias` instead).

See also: [[project-architecture-rules]], [[project-flight-archetype]], [[project-component-philosophy]]
