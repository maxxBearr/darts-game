---
name: project-architecture-rules
description: "Three load-bearing architecture/UX rules — board shows effective values, hover is off during active throw, scoring modifiers and stat upgrades share UI but have independent backends."
metadata: 
  node_type: memory
  type: project
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

**Rule 1: The board always renders effective values.**
If a modifier changes a wedge's value (e.g., +3 makes "10" display as "13"), the board shows "13." The player should never have to remember invisible modifications.

**Why:** Hidden math kills strategic play. The point of board-perception modifiers is to *change how the board looks*, not to add a mental load.

**How to apply:** Any new modifier that changes wedge values, colors, or scoring rules must surface that change visually on the board. If it can't be made visible, reconsider the design.

---

**Rule 2: Hover/inspect is OFF during active throw stages.**
Hover tooltips are available between darts. They are *not* available during VERTICAL_RELEASE, HORIZONTAL_RELEASE, or RESOLVING. The current throw enum is `IDLE, AIMING, VERTICAL_RELEASE, HORIZONTAL_RELEASE, RESOLVING, DONE` — there is no longer a separate POSITIONING state (the vertical-window placement was folded into AIMING when the ellipse-placement rework shipped). The aim primitive itself was reworked from ellipse to **crosshair on 2026-05-26**; the state machine and the hover-off rule were preserved verbatim. Accuracy-zone distance is now absolute pixels (`accuracy_zone_reference_radius`-normalized) rather than ellipse-relative.

**Why:** Player needs to focus during active throw phases. Inspect-mode information is for planning, not for execution.

**How to apply:** Any new hover/inspect UI follows the same rule. If new throw states are added, default them to hover-off unless there's a specific design reason.

---

**Rule 3: Scoring modifiers and stat upgrades share UI but have independent backends.**
Both are "upgrades the player picks" and reuse the 3-card pick UI. But:
- **Stat upgrades** mutate `throw_mechanic` properties directly.
- **Scoring modifiers** run a per-dart pipeline through `ScoringModifierManager` and never touch `throw_mechanic`.
- `x01_game.gd` receives already-modified scores and doesn't know modifiers exist.

**Why:** Keeps the scoring pipeline composable and the throw mechanic agnostic to roguelike items. Future systems (Form, items that affect both) should layer on without breaking this split.

**How to apply:** When proposing new systems, check which side they belong on. If something affects throw *stats*, it's a throw-side mutation. If it affects *scores*, it's a pipeline modifier. Avoid systems that need both — those create coupling that's hard to untangle.

---

**Rule 4: Dart-component ability hooks are sibling resources on `DartComponent`, one per lifecycle moment.**
Each new "passive ability" a component might have lives as its own optional `Resource` field on `DartComponent`, keyed to a specific lifecycle moment. Two exist as of 2026-05-24: `throw_modifier: ThrowModifier` (throw-time stat bonus) and `shop_bias: ShopBias` (shop-generation pool weight bias). A deferred third is `ScoringHook` for on-score effects (would fire inside `ScoringModifierManager.process_score`).

**Why:** Bundling all abilities into one mega-class (`FlightAbility` with optional `on_throw`/`on_shop`/`on_score` methods) couples lifecycle moments that have no shared shape and makes each new hook type an edit to a shared file. Sibling resources let each hook evolve independently and let designers attach only the abilities they need.

**How to apply:** When proposing a new component ability that fires at a new lifecycle moment, add a new sibling Resource type with its own base class and `@export` field on `DartComponent`. Don't extend `ThrowModifier` to do non-throw things; create a peer. The second-evaluation pass pattern (re-evaluating throw modifiers at aim placement so target-aware bonuses can compute) is the canonical way to inject *aim-time* context into the throw-time hook.

See also: [[project-component-philosophy]], [[project-flight-archetype]], [[project-dropped-rethrow-design]]

---

See also: [[project-dart-game-concept]], [[project-open-questions]]
