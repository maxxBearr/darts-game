---
name: project-tutorial-system
description: "Tutorial & help system shipped 2026-05-22 — Start Screen, 3-throw sandbox mechanics tutorial with in-context stat reveals + interactive slider demos, rules-of-darts slideshow with mini dartboard + doubles drill, first-run welcome modal. Assembly Tutorial and persistent Stats Reference deferred."
metadata: 
  node_type: memory
  type: project
  originSessionId: 9eb44a98-027f-4e30-9e81-eb15770988d6
---

**Shipped 2026-05-22 (spec: `specs/2026-05-22-tutorial-and-help-system.md` once archived; until then in `CLAUDE.md`).**

The tutorial system makes the game shippable to friends who've never thrown a dart. Three separate flows, deliberately not merged into one walkthrough:

1. **Mechanics Tutorial** — 3-throw sandbox teaching the throw loop.
2. **Rules of Darts** — slideshow + interactive doubles drill teaching x01 scoring.
3. **First-Run Welcome** — soft prompt on first launch routing new players into the mechanics tutorial.

**Where each piece lives:**

| Concern | File |
|---|---|
| Pre-game menu (Start Game / Play Tutorial / Rules) | `scripts/start_screen.gd` |
| First-launch prompt + persistence | `scripts/welcome_modal.gd` + `scripts/settings_store.gd` (`user://settings.cfg`) |
| Mechanics tutorial beat sequencer | `scripts/tutorial_controller.gd` (~776 lines, full Phase A + Phase B) |
| Callout overlay (arrows + text + Next button) | `scripts/tutorial_callout.gd` |
| Interactive slider widget (Range/Speed/Accuracy demos) | `scripts/tutorial_slider.gd` |
| Ghost-dart scatter visualization | `scripts/ghost_dart_layer.gd` + `throw_mechanic.sample_scatter_points(...)` |
| Rules slideshow + doubles drill + mini dartboard | `scripts/rules_slideshow.gd` (~792 lines) |
| Throw mechanic tutorial hooks | `throw_mechanic.gd::set_paused`, `set_scripted_mode`, `force_lock_*`, `meter_position_changed` signal, `get_zone_boundary_h_positions`, `sample_scatter_points`, `set_input_blocked` |
| Dartboard tutorial highlights (used by mini board in slideshow) | `dartboard.gd::set_tutorial_highlight(...)` / `clear_tutorial_highlight()` |
| Stat bar visibility toggle (used for progressive reveal) | `hud.gd::set_stat_bar_visibility(stat_keys, is_visible)` |

**Mechanics Tutorial structure (the bulk of the shipped work):**

Throw 1 is autopilot demo with freeze-and-explain at three accuracy zones (green/orange/red), each showing a ghost-dart scatter cluster. Progressive stat-bar reveal: bars start hidden, fade in stage-by-stage (Range bars at aim ellipse, V Speed at vertical meter, H Speed at horizontal meter, Accuracy bars at green-zone freeze). Three interactive slider demos let the player drag and watch live: H Range (ellipse resizes), H Speed (meter bounces faster/slower), H Accuracy (ghost scatter shrinks/grows). Throw 2 is guided ("try to land in green"). Throw 3 is free. The tutorial uses the player's *real* stats (default exports on first run, equipped build on Assembly replay) — demos snapshot/restore around mutations.

**Rules Slideshow structure:**

Side-by-side layout (text left, mini dartboard right) inside a modal panel. Walks through wedge layout, singles/doubles/triples, bullseye, x01 scoring, the doubles checkout rule. Mini dartboard is a custom-drawn `Control` modeled on `assembly_screen.gd::_build_zone_preview()` — not a Dartboard node instance. Highlights via local draw logic (no longer routed to the main board). One interactive drill: "32 remaining, which dart wins?" → D16.

**What did NOT ship (still pending):**

- **Assembly Tutorial.** A separate guided walkthrough of the assembly screen itself (cycling components, balance bar, zone preview, Begin Run). Scope is trimmed because the mechanics tutorial now teaches stats in-context, so the assembly tutorial doesn't need to re-teach stat fundamentals.
- **Stats Reference panel.** A persistent expandable panel listing all six stats with longer descriptions. Demoted to "nice-to-have" because the mechanics tutorial's in-context teaching covers the same ground for first-time players. `start_screen.stats_reference_pressed` signal exists but isn't yet handled in `main.gd`. `scripts/stat_descriptions.gd` (the single-source-of-truth file) doesn't exist yet.

**Why these were deferred:** post-Phase-A playtest convinced Max that contextual teaching (next to the thing it explains) was much more effective than a separate reference panel. The reference becomes a "look it up later" tool rather than a primary teaching surface — useful eventually but not load-bearing.

**Design decisions captured during the design pass** (also reflected in [[feedback-onboarding-ux-patterns]]):

- Three separate flows, not one merged tutorial — darts vets can skip rules, returning players can replay just mechanics.
- 3-throw demo→guided→free for mechanics — shorter is "look at this," longer overstays welcome.
- Sandbox mode (no x01, no score pressure) so the player can flub a throw without consequences.
- Ghost-dart scatter beats a heatmap shader — players think "where will my darts land," not "probability density."
- Freeze-and-explain at zone transitions, not forced "click now!" prompts — show-then-do > railroad clicks.
- Hybrid rules: slideshow primary + one interactive drill specifically at the doubles checkout rule (the most counterintuitive piece).
- Real stats throughout — tutorial throw 3 must feel identical to first throw of first real leg.

See also: [[project-dart-game-concept]], [[project-architecture-rules]], [[feedback-onboarding-ux-patterns]], [[reference-design-notes]]
