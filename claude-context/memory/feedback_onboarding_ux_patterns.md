---
name: feedback-onboarding-ux-patterns
description: "Design patterns Max validated during the tutorial system pass — teach in context not in a separate reference, visuals belong next to the text explaining them, hybrid slideshow + one interactive moment beats pure slideshow, real stats throughout tutorials."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9eb44a98-027f-4e30-9e81-eb15770988d6
---

A set of design patterns that Max landed on (and validated through playtest iteration) during the tutorial & help system build. Apply these to future onboarding, help, walkthrough, or tooltip-adjacent features in the Dart Game.

**Pattern 1: Teach in context, not in a separate reference panel.**

Showing what a stat does *next to the thing it controls*, at the moment it matters, beats listing it on a separate reference panel. The first cut of the spec had a persistent Stats Reference as a primary teaching tool; after Phase A shipped, Max immediately saw that folding stat reveals into the mechanics tutorial (range bars appear when the ellipse appears, accuracy bars appear when the scatter shows) was much more effective. The standalone reference was demoted to "look it up later" tool.

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

The tutorial sandbox uses the player's actual base stats (default exports on first run, equipped build on Assembly replay). Tutorial throw 3 must feel identical to throw 1 of the first real leg. Demos that temporarily mutate stats (the H Range / H Speed / H Accuracy sliders) snapshot before and restore after.

**Why:** A tutorial with diverged "tutorial-friendly" stats teaches the player a feel that doesn't match the real game. They notice — not consciously, but as a "the dart doesn't behave like it did in the tutorial" itch. Trust is fragile; lying about feel breaks it. Side benefit: replaying the tutorial after upgrades becomes a "feel my current build" tool for free.

**How to apply:** Any future tutorial, demo mode, or sandbox should use real player stats. If a demo needs to mutate a value to teach a concept, wrap the mutation in snapshot/restore. The patterns to copy are `main.gd::_snapshot_base_stats` / `_restore_raw_stats` and the per-stat snapshot/restore in `tutorial_controller.gd`.

---

**Pattern 5: Three is the sweet spot for "demonstrate → guide → free" walkthroughs.**

The mechanics tutorial uses three throws: one autopilot demo, one guided ("try to land in green"), one free. One throw is "look at this" not "you did this." Five+ overstays welcome. Three is enough to demonstrate, attempt, and confirm without bloating.

**Why:** The middle "guided" step is where the player actually applies what they saw. Without it, the demo isn't internalized. The final "free" step proves they have it. Skipping either weakens the arc.

**How to apply:** When designing other walkthrough-style tutorials (e.g., the deferred Assembly Tutorial), default to three-step structure unless there's a specific reason for more or fewer.

See also: [[project-tutorial-system]], [[user-role]]
