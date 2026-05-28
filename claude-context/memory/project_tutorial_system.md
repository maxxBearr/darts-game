---
name: project-tutorial-system
description: "Tutorial & help system shipped 2026-05-22, mechanics tutorial revamped 2026-05-27 to DISCOVER → DO → UNDERSTAND. Three-throw structure with stats walkthrough as opt-out checkpoint. Rules slideshow + welcome modal unchanged. Assembly tutorial + persistent Stats Reference still deferred."
metadata: 
  node_type: memory
  type: project
  originSessionId: 9eb44a98-027f-4e30-9e81-eb15770988d6
---

**Originally shipped 2026-05-22** (`specs/2026-05-22-tutorial-and-help-system.md`). **Mechanics tutorial revamped 2026-05-27** (`specs/2026-05-27-tutorial-revamp.md`) — three throws restructured from DEMO → GUIDED → FREE to **DISCOVER → DO → UNDERSTAND**, stats walkthrough is now an auto-continued checkpoint with a Skip button, sub-menu lets players replay stats-only without redoing mechanics. Rules slideshow, doubles drill, welcome modal, and first-run persistence unchanged.

The tutorial system makes the game shippable to friends who've never thrown a dart. Three separate flows, deliberately not merged into one walkthrough:

1. **Mechanics Tutorial** — 3-throw sandbox teaching the throw loop (revamped 2026-05-27).
2. **Rules of Darts** — slideshow + interactive doubles drill teaching x01 scoring (unchanged).
3. **First-Run Welcome** — soft prompt on first launch routing new players into the mechanics tutorial (unchanged).

**Where each piece lives:**

| Concern | File |
|---|---|
| Pre-game menu (Start Game / Play Tutorial / Rules / Stats Reference) | `scripts/start_screen.gd` (~221 lines) |
| Play Tutorial sub-menu chooser (Full / Stats Walkthrough Only / Back) | `scripts/start_screen.gd::_build_chooser()` |
| First-launch prompt + persistence | `scripts/welcome_modal.gd` + `scripts/settings_store.gd` (`user://settings.cfg`) |
| Mechanics tutorial beat sequencer | `scripts/tutorial_controller.gd` (~830 lines, post-revamp) |
| Callout overlay (text + Next + Skip) | `scripts/tutorial_callout.gd` |
| Interactive slider widget (with "Set" button) | `scripts/tutorial_slider.gd` (~117 lines) |
| Ghost-dart scatter visualization | `scripts/ghost_dart_layer.gd` + `throw_mechanic.sample_scatter_points(...)` |
| Rules slideshow + doubles drill + mini dartboard | `scripts/rules_slideshow.gd` (unchanged) |
| Throw mechanic tutorial hooks | `throw_mechanic.gd::set_paused`, `set_scripted_mode`, `force_lock_horizontal`, `state_changed` signal, `set_input_blocked`, `sample_scatter_points`, `set_tutorial_visual_boost`, `set_tutorial_pulse_target`, `recompute_aim_dimensions` |
| Dartboard tutorial highlights | `dartboard.gd::set_tutorial_highlight(...)` / `set_declared_target(...)` / `clear_declared_target()` |
| Stat bar visibility | `hud.gd::show_all_stat_bars()` / `update_stats(current, base)` |

**Mechanics Tutorial structure (revamped 2026-05-27):**

The new shape is DISCOVER → DO → UNDERSTAND, with throw 3 (UNDERSTAND) auto-continued from throw 2 and replayable as a checkpoint via the Start Screen sub-menu. Stat bars are visible from throw 1 onward (no progressive reveal — exposure-first, explanation-last).

- **Throw 1 (DISCOVER):** Player throws cold with freeze-and-explain at each stage. Input locks during explanation copy (`set_input_blocked(true)`), meters keep bouncing visibly so the player sees the moving thing while reading. Beats: welcome → aim phase → aim placed (V meter intro) → V stopped (H meter intro) → H stopped (accuracy zone intro) → 10-dart scatter reveal → resolve. The H meter click is intercepted by the controller (`_listening_for_h_click`) so the player's click *captures* the meter position but defers resolve until the scatter explanation runs.
- **Throw 2 (DO):** "Try an uninterrupted throw" callout, then player throws end-to-end with no interruptions. On resolve, auto-continues to throw 3.
- **Throw 2 → 3 transition:** "Nice throw! Now let's look at how your stats shape what just happened." Persistent **Skip Stats Walkthrough** button surfaces here (currently top-left at position 16,16 — placement may want a second pass).
- **Throw 3 (UNDERSTAND):** Three paired slider demos, each with two sliders (a Range and a Speed/Accuracy stat) shown simultaneously. Beats: target select → V Range + V Speed sliders → V meter timing → H Range + H Speed sliders → H meter timing (with accuracy zone breathing as the crosshair sweeps) → H stopped → V Accuracy + H Accuracy sliders with live ghost-dart scatter → resolve → "Tutorial complete."

**The "Set" button slider behavior** (subtle but important): each slider has a "Set" button. Player drags slider, clicks Set, the value is *kept* for the rest of the tutorial. There is no snapshot/restore on Next — the throw proceeds with whatever the player dragged to. Base stats are snapshotted at tutorial start and restored on finish or skip, so adjustments never bleed into the real game.

**TutorialMode enum (added 2026-05-27):**

```gdscript
enum TutorialMode { FULL, STATS_ONLY }
```

- `FULL` — Start Screen → Play Tutorial → Full Tutorial routes here. Runs throws 1, 2, 3 in sequence.
- `STATS_ONLY` — Start Screen → Play Tutorial → Stats Walkthrough Only routes here. Jumps directly to `_t3_intro()`, with the Skip button immediately visible.

Welcome modal's first-run route uses `FULL`. The signature is `start_mechanics_tutorial(source: String, mode: TutorialMode = TutorialMode.FULL)`. The `source` field tracks where the tutorial was launched from (`"start_screen"` vs `"assembly"`) so the `tutorial_finished` signal routes correctly back on finish or skip.

**Teardown stack (added 2026-05-27).** `_teardown_stack: Array[Callable]` accumulates cleanup callbacks during throw 3's slider demos. On Skip mid-flow, `_run_all_teardowns()` fires each callback in order — frees sliders, unblocks input, clears scatter, etc. Base stats restore via `_restore_base_stats()` from the `_base_stats` snapshot. This is what makes mid-tutorial Skip clean.

**New `throw_mechanic` tutorial hooks (added 2026-05-27):**

- `set_tutorial_visual_boost(bool)` — when enabled, draws a thicker aim crosshair and more opaque accuracy zone preview. Improves legibility during tutorial freeze frames.
- `set_tutorial_pulse_target(target: String)` — pulses a named element's border to draw attention. Valid: `"aim_crosshair"`, `"accuracy_zone"`, `"vertical_band"`, `"marker"`. Pass `""` to stop.
- `recompute_aim_dimensions()` — recomputes cached aim dimensions from current range stats. Called by the live V Range / H Range sliders so the crosshair and meter range update in real time as the player drags.

**Rules Slideshow structure** (unchanged from 2026-05-22): Side-by-side layout (text left, mini dartboard right) inside a modal panel. Walks through wedge layout, singles/doubles/triples, bullseye, x01 scoring, the doubles checkout rule. Mini dartboard is a custom-drawn `Control` modeled on `assembly_screen.gd::_build_zone_preview()`. One interactive drill: "32 remaining, which dart wins?" → D16.

**What did NOT ship in the 2026-05-27 revamp (still pending):**

- **Assembly Tutorial.** A separate guided walkthrough of the assembly screen itself. Still deferred — the mechanics tutorial teaches stats in-context, so the assembly tutorial doesn't need to re-teach stat fundamentals.
- **Stats Reference panel.** A persistent expandable panel listing all six stats with longer descriptions. Still deferred — the throw 3 stats walkthrough is the primary teaching surface. `start_screen.stats_reference_pressed` signal exists, is not yet handled in `main.gd`. `scripts/stat_descriptions.gd` (the single-source-of-truth file) doesn't exist yet.
- **Ellipse references in `rules_slideshow.gd`.** Out of scope for the mechanics revamp. Known follow-up — a focused copy-only pass on `rules_slideshow.gd` will land later.
- **"Just Mechanics" sub-menu option.** Currently the player can skip the stats walkthrough mid-flow via the Skip button. If playtest shows consistent skipping, add a third sub-menu option that routes through throws 1-2 only. Easy add — just another `TutorialMode` enum value.

**Design decisions captured during the 2026-05-27 revamp** (also reflected in [[feedback-onboarding-ux-patterns]]):

- DISCOVER → DO → UNDERSTAND replaces the canonical DEMO → GUIDED → FREE pedagogy for action-driven mechanics where the player learns by doing rather than watching first.
- Stats are exposure-first (bars visible silently from throw 1) and explanation-last (throw 3 cashes in the exposure).
- Throw 3 is opt-out (auto-continue + persistent Skip), not opt-in. Bias toward stat-teaching exposure for players who won't seek it out otherwise.
- Stats Walkthrough Only is a true checkpoint — replayable via Start Screen sub-menu without redoing throws 1-2.
- All copy lives in `tutorial_strings: Dictionary` exported var — tunable from inspector.
- Real stats throughout (Pattern 4 still holds) — defaults on first run, equipped build on Assembly replay. Slider demos let the player keep their adjustments for the throw, but all stats restore on tutorial end or skip.

See also: [[project-dart-game-concept]], [[project-architecture-rules]], [[feedback-onboarding-ux-patterns]], [[reference-design-notes]]
