---
name: feedback-onboarding-ux-patterns
description: "Design patterns Max validated through tutorial-system playtest iterations — teach in context, visuals adjacent to text, hybrid slideshow + one interactive moment, real stats throughout, three-step pedagogy (with two valid shapes), experience before semantics for action-driven mechanics."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9eb44a98-027f-4e30-9e81-eb15770988d6
---

A set of design patterns that Max landed on (and validated through playtest iteration) during the tutorial & help system build. Apply these to future onboarding, help, walkthrough, or tooltip-adjacent features in the Dart Game.

**Pattern 1: Teach in context, not in a separate reference panel.**

Showing what a stat does *next to the thing it controls*, at the moment it matters, beats listing it on a separate reference panel. The first cut of the spec had a persistent Stats Reference as a primary teaching tool; after Phase A shipped, Max immediately saw that folding stat reveals into the mechanics tutorial (range bars appear when the crosshair appears, accuracy bars appear when the scatter shows) was much more effective. The standalone reference was demoted to "look it up later" tool.

**Why:** Players don't read reference panels with the same attention they pay to a thing in front of them. Context binds the explanation to the visual; a separated panel forces the player to maintain two mental models.

**How to apply:** Any future helper, callout, or explanation feature should prefer "show X, explain X right here" over "here's a panel listing what all the X things do." The reference still has value as a "I forgot" surface but should never be the primary teaching path.

---

**Pattern 2: Visuals belong next to the text that explains them, not behind it.**

Phase A shipped the rules slideshow with highlights routed to the **main dartboard** — which sat behind a 0.75-opacity modal scrim. The highlights fired correctly but were nearly invisible. Fix (Phase B5): a self-contained mini dartboard inside the slide panel itself, side-by-side with the text.

**Why:** A scrim that exists to focus attention on a modal is fighting the modal if the modal wants to point at something *outside* itself. Either remove the scrim (busy) or bring the visual *inside* the modal (cleaner).

**How to apply:** Whenever a modal/overlay needs to reference a game-world visual, embed a self-contained miniature inside the overlay rather than relying on the player to look "past" the scrim. The pattern to copy is `assembly_screen.gd::_build_zone_preview()` — custom-drawn `Control` with simplified arc/polygon helpers.

---

**Pattern 3: Hybrid slideshow + one interactive moment > pure slideshow.**

For multi-concept content (rules of darts: wedge layout + ring scoring + bullseye + x01 + doubles checkout + bust), a pure slideshow risks players zoning out on the highest-stakes concept. The rules slideshow ships as slideshow-primary with **one** interactive drill specifically at the doubles checkout rule (the most counterintuitive piece for newcomers): "32 remaining, which dart wins?" with three buttons. The interactive moment cements the rule via doing in a way passive reading doesn't.

**Why:** Slideshows scale well across many concepts but are weak at retention for any single concept. Interactive moments retain hard but don't scale. Combining them: cheap slideshow for the bulk, expensive interactive moment only where retention matters most.

**How to apply:** Don't pure-quiz a tutorial (annoying) and don't pure-slideshow a tutorial that has a high-stakes rule buried in it (forgettable). Identify the single most-likely-to-be-misunderstood concept and put one interactive check there.

---

**Pattern 4: Real stats throughout tutorials — no "easy mode" tutorial values.**

The tutorial sandbox uses the player's actual base stats (default exports on first run, equipped build on Assembly replay). Tutorial throw 3 must feel identical to throw 1 of the first real leg. Demos that temporarily mutate stats (the slider demos in the 2026-05-27 revamp's throw 3) snapshot before and restore at tutorial end — adjustments stay live during the tutorial but never bleed into real runs.

**Why:** A tutorial with diverged "tutorial-friendly" stats teaches the player a feel that doesn't match the real game. They notice — not consciously, but as a "the dart doesn't behave like it did in the tutorial" itch. Trust is fragile; lying about feel breaks it. Side benefit: replaying the tutorial after upgrades becomes a "feel my current build" tool for free.

**How to apply:** Any future tutorial, demo mode, or sandbox should use real player stats. If a demo needs to mutate a value to teach a concept, wrap the mutation in start-of-tutorial snapshot + end-of-tutorial restore (the 2026-05-27 model — `_base_stats` captured in `start_mechanics_tutorial`, restored in `stop_tutorial`). The teardown stack pattern in `tutorial_controller.gd` handles mid-flow skip cleanup correctly.

---

**Pattern 5: Three-step walkthroughs work — pick the right three-step shape for the mechanic.**

Two valid three-step shapes have shipped for tutorial walkthroughs:

- **DEMO → GUIDED → FREE** (original 2026-05-22 mechanics tutorial). Player watches autopilot demo, then attempts a guided throw, then a free throw. Canonical "watch then try" pedagogy. Good for mechanics that are visually complex or where mistakes feel high-stakes.
- **DISCOVER → DO → UNDERSTAND** (2026-05-27 revamp). Player throws cold with freeze-and-explain at each stage (DISCOVER), then a free throw (DO), then an optional stats deep-dive (UNDERSTAND). Stronger for action-driven mechanics where the player learns by *doing* rather than watching. Trades the demo's cold-start absorption for a feeling of empowerment from throw 1.

The 2026-05-22 version had too much reading and not enough doing in throw 1 — the demo + slider explanations + scatter freezes preceded any input. The 2026-05-27 revamp moved the player into doing from throw 1 and pushed stat semantics into an opt-out checkpoint. Playtest will tell us if the new shape sticks.

**Why three:** One throw is "look at this" not "you did this." Five+ overstays welcome. Three is enough to demonstrate (or discover), attempt, and confirm without bloating. The middle step is where the player applies what they saw; without it, the demo isn't internalized.

**How to apply:** Default to three. For an action mechanic where the player can be productive on the first attempt with mid-flow callouts (the crosshair, post-revamp), prefer DISCOVER → DO → UNDERSTAND. For a high-stakes mechanic where mistakes are scary or the loop is hard to read without seeing it run (the original ellipse aim, pre-crosshair), prefer DEMO → GUIDED → FREE. If the mechanic's stats are semantically rich, push the stat-teach into an opt-out third step rather than bundling it with the mechanic-teach.

---

**Pattern 6: Experience before semantics for action-driven mechanics.**

The 2026-05-22 mechanics tutorial bundled the throw mechanic teach with the stat teach — sliders for H Range, H Speed, H Accuracy fired during throw 1 alongside the mechanic explanation. Players walled. Playtest evidence: cognitive load was spent before the player even got to the "doing" part. The 2026-05-27 revamp split these: throws 1-2 teach the throw loop with stat bars *visible but unexplained*, throw 3 layers stat semantics on top of the now-felt mechanic.

**Why:** Abstract stat semantics ("V Speed controls how fast the vertical meter bounces") don't bind to anything if the player hasn't yet felt the vertical meter bounce. Concrete sensory experience first, abstract semantic layer second. The bars being silently visible during throws 1-2 plants seed-curiosity ("those bars are doing *something*"); throw 3 cashes it in.

**How to apply:** Any future tutorial that teaches both a mechanic and the stats that shape that mechanic should let the player experience the mechanic first with stats visible-but-unexplained, then teach the stat semantics afterward as a separate beat. Avoid front-loading stat semantics before mechanic experience.

---

See also: [[project-tutorial-system]], [[user-role]]
