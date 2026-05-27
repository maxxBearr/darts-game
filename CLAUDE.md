# Tutorial Revamp: Discover → Do → Understand

**Status:** Active spec, designed 2026-05-27. Implementation TBD (Claude Code pass).
**Predecessor:** `specs/2026-05-22-tutorial-and-help-system.md` — the original tutorial system. This spec replaces the **mechanics tutorial** portion only; the rules slideshow, doubles drill, welcome modal, and Start Screen entry points outside of "Play Tutorial" remain unchanged.

## Scope

**In scope:**
- Complete rewrite of the mechanics tutorial flow in `scripts/tutorial_controller.gd` to a new three-throw structure: **DISCOVER** (guided throw with freeze-and-explain) → **DO** (free uninterrupted throw) → **UNDERSTAND** (stats walkthrough with live slider demos).
- Copy pass throughout the mechanics tutorial to reference the crosshair (the aim primitive shipped 2026-05-26 on the current branch) instead of the old ellipse language.
- New Start Screen sub-menu: clicking "Play Tutorial" opens a chooser between **Full Tutorial** and **Stats Walkthrough Only**.
- New launch mode on `tutorial_controller.gd` to support entering the tutorial directly at throw 3 (the stats walkthrough) without replaying throws 1-2.
- New persistent **Skip Stats Walkthrough** button visible during throw 3 beats (whether reached via auto-continue from throw 2 or via the stats-only menu entry).

**Out of scope:**
- The rules slideshow (`scripts/rules_slideshow.gd`), doubles drill, and mini dartboard. Untouched.
- The welcome modal (`scripts/welcome_modal.gd`) and `user://settings.cfg` first-run persistence. Untouched.
- The Start Screen "Rules" entry. Untouched.
- The Assembly screen tutorial (still deferred per prior spec).
- The persistent Stats Reference panel (still deferred per prior spec).
- Auditing ellipse-vs-crosshair language *outside* the mechanics tutorial — e.g., if the rules slideshow still references the ellipse, that's a separate later pass.

## Design context

The current mechanics tutorial (shipped 2026-05-22) used a **DEMO → GUIDED → FREE** three-throw structure where throw 1 was an autopilot demo with progressive stat-bar reveals and three slider demos (H Range, H Speed, H Accuracy). Post-ship playtest surfaced two consistent problems:

1. **Too much reading, not enough doing in throw 1.** Players sat through the autopilot demo plus three slider demos plus accuracy zone freeze-frames before they ever made their first input. By the time they got to throws 2-3 the cognitive load from throw 1 was already spent. Playtest evidence showed players bouncing or zoning out before they got to the doing part.
2. **Stat content was bundled with the mechanic teach.** Players who just wanted to "try a throw" got walled by stat explanations they hadn't earned context for yet. New players' mental model of *what* the meters do came after their mental model of *why the bars matter* — which is backwards.

Additionally, the aim primitive was reworked from the ellipse to a crosshair on 2026-05-26, so the existing tutorial copy is stale on the language of the aim itself. The rewrite is a natural moment to fold both fixes into one pass.

The new structure separates **what the player does** (throws 1-2) from **why their stats matter** (throw 3), and gives the player concrete sensory experience with the throw mechanic *before* layering abstract stat semantics on top. The stats walkthrough is replayable as a standalone unit so returning or curious players can dig in without redoing the mechanics throws.

## Design positions

1. **Throw 1 is DISCOVER, not DEMO.** The player throws cold with freeze-and-explain at each stage transition. There is no autopilot. Input locks during explanation copy and frees for the next action — Max explicitly notes input-lock moments in the design so the player reads first, acts second. This trades the "watch then try" canonical pedagogy of the prior tutorial for a "guided discovery" model. The crosshair is easier to describe verbally than the ellipse was, which makes mid-flow callouts feasible where they were awkward before.

2. **Throws 1-2 carry no stat explanations; bars are visible the whole time but unexplained.** The HUD stat bars live on the right of the screen during throws 1-2 just as they do in a real run. Players form a fuzzy "those bars are doing something" mental model from exposure alone. Throw 3 cashes this in by explicitly teaching what they mean. This avoids the prior tutorial's mistake of front-loading stat semantics before the player has experience to anchor them to.

3. **Throw 3 auto-continues from throw 2, with a persistent Skip button.** Rather than offer the stats walkthrough as opt-in, we offer it as opt-out — the player flows straight from throw 2's resolution into throw 3's setup, with a clearly-visible **Skip Stats Walkthrough** button surfaced at the transition and persistent for the rest of the tutorial. The design lean is to bias toward exposure on the assumption that more players will benefit from stat context than will resent being walked through it. Players who are veterans or want to bail can do so in one click.

4. **Throw 3 is densely packed by design.** It contains four slider demos (V Speed, H Speed, V Accuracy, H Accuracy) plus the accuracy-zone-breathing teach during H meter sweep plus the live ghost-dart scatter teach. This is intentional — start dense, trim from playtest. Adding beats back later is worse than removing them.

5. **The accuracy-zone-breathing during H meter sweep replaces the three-position scatter freeze.** The prior tutorial showed three discrete scatter clusters (green/orange/red) at frozen positions. The new tutorial uses the live `accuracy_zone_reference_radius`-normalized zone resizing — as the H meter sweeps the crosshair across the board, the accuracy zone visibly tightens near the target centroid and bloats away from it. This is a continuous spatial gradient teach, more memorable than three discrete freeze-frames and closer to what the player actually sees during real play.

6. **Default stats / equipped build invariant preserved.** Per `feedback-onboarding-ux-patterns` Pattern 4, the tutorial uses real stats throughout: default `throw_mechanic` exports on first run, the player's equipped build on Assembly replay. No tutorial-only override and no "0 index components" hard-code — exposure to the unexplained bars is sufficient and any override would risk the "tutorial felt different from the real game" trust-break Pattern 4 exists to prevent.

7. **Stats Walkthrough Only is a true checkpoint.** When entered via the Start Screen sub-menu, the player drops directly into throw 3 setup with the Skip button immediately visible. State setup matches what throw 3 would see after throw 2 — the throw_mechanic, hud, and dartboard are in the same state they'd be in mid-flow. This requires `tutorial_controller.gd` to parameterize its launch path.

8. **Sub-menu over a fourth Start Screen button.** The Stats Walkthrough Only entry lives behind a sub-chooser surfaced when "Play Tutorial" is clicked, not as a sibling button to Play Tutorial / Rules. Keeps the Start Screen lean at three top-level buttons; trades one extra click for screen cleanliness. Discoverability is acceptable because anyone who completed throw 2 and skipped throw 3 already knows the stats walkthrough exists.

## System description: beat-by-beat

The beat sequencer in `tutorial_controller.gd` orchestrates a series of beats. Each beat declares an **input-lock state** (input blocked vs. allowed), a **callout** (text + position + optional arrow + Next button or wait condition), and an **advance trigger** (Next button click, meter stop, throw resolve, etc.). The pattern is preserved from the prior tutorial — only the beat content changes.

### Throw 1: DISCOVER

The player makes their first throw with freeze-and-explain at each stage transition. Input is locked during explanation copy and freed when the next action is expected.

1. **Intro callout.** "Welcome to the throw mechanic. You'll do three darts — first one we'll walk through together." Next button. Input locked.
2. **Aim phase.** "Move the crosshair with your mouse. Left-click to lock on a target." Crosshair input freed; everything else stays locked.
3. **Target selected.** Game pauses. "Nice — you picked [target]. See that marker moving up and down the vertical arm of the crosshair? Click or press space to set the height of your throw." Next button. Game un-pauses after Next; V meter input freed.
4. **V meter stopped.** Game pauses. "Good. Now do the same along the horizontal arm — stop the meter to lock in your aim." Next button. H meter input freed after Next.
5. **H meter stopped.** Game pauses. "This bubble around your locked aim is your **accuracy zone** — your dart could land anywhere inside it." Next button. Game stays paused.
6. **10-dart scatter reveal.** Ghost-dart layer fires `throw_mechanic.sample_scatter_points(10, ...)`. "Here's where ten darts would land in this zone." Next button. Game stays paused.
7. **Resolve.** Game resumes; the dart resolves at its actual sampled position. No callout — the resolution speaks for itself.

### Throw 2: DO

The player throws without interruption. This beat validates that throw 1's discovery stuck.

1. **Intro callout.** "Now try an uninterrupted throw — you've got it." Next button. Input locked until dismissed.
2. **Free throw.** Input fully free; player executes the throw end-to-end with no callouts.
3. **Dart resolves.** Auto-continue to the throw 2 → throw 3 transition (see below).

### Transition: Throw 2 → Throw 3

A short bridge beat. Skip button surfaces here and remains visible until the tutorial ends.

1. **Transition callout.** "Nice throw. Let's look at how your stats shape what just happened." A persistent **Skip Stats Walkthrough** button appears in a fixed corner (recommend top-right, but Max to confirm placement) and remains visible for the rest of the tutorial. A Continue button advances; clicking Skip ends the tutorial cleanly.

### Throw 3: UNDERSTAND

The stats walkthrough. Dense by design. All slider demos use the existing snapshot/restore pattern — values are mutated for the demo only, then restored before the actual throw input resumes.

1. **Intro callout.** "One more throw. Pick a target like before." Crosshair input freed.
2. **Target selected.** Game pauses. V Speed slider demo: "Try dragging this slider — watch how the vertical meter changes speed." V Speed bar live-updates. V meter is visible but not yet running so the player can see speed change as a preview. Next button when ready. Slider snapshot-restores on Next.
3. **V meter active.** "Okay, time the meter to set your vertical aim." V meter input freed at true V Speed.
4. **V meter stopped.** Game pauses. H Speed slider demo, same shape as step 2 but for H Speed (shorter copy — same idea). Next button when ready. Snapshot-restore on Next.
5. **H meter active.** "Now watch your accuracy zone — as the crosshair sweeps closer to your target, the zone tightens. Farther away, it bloats. Stop the meter when you're aimed where you want." H meter input freed; accuracy zone breathes in real time as the meter sweeps the crosshair across the board.
6. **H meter stopped.** Game pauses. "This is your final accuracy zone — your H and V accuracy stats decide how tight or loose your dart's landing scatter is." V Accuracy and H Accuracy sliders both shown; ghost-dart scatter updates live as either slider moves (use `throw_mechanic.sample_scatter_points` per-frame as in the prior tutorial). Next button when ready. Snapshot-restore on Next.
7. **Resolve.** Game resumes; dart resolves at its actual sampled position with true stats.
8. **Completion callout.** "Tutorial complete — you're ready for a real run." Single button: Finish. Skip button hides. Tutorial state tears down.

## Phases

Recommended Claude Code chunking, each phase independently testable.

### Phase 1: Rewrite mechanics tutorial flow

The bulk of the work. Replace the existing beat sequence in `scripts/tutorial_controller.gd` with the new three-throw structure described above. All beats with their input-lock states, callouts, and advance triggers. All copy updated to crosshair language. Stat bars visible from throw 1 onward (no hidden-bars phase). Slider demos in throw 3 use the existing `tutorial_slider.gd` widget and the snapshot/restore pattern. The ghost-dart scatter renderer (`scripts/ghost_dart_layer.gd`) is reused for both throw 1's 10-dart reveal and throw 3's live accuracy scatter. The dartboard's tutorial highlights (`dartboard.gd::set_tutorial_highlight`) and the throw mechanic's tutorial hooks (`set_paused`, `set_scripted_mode`, `force_lock_*`, `meter_position_changed`, `get_zone_boundary_h_positions`, `sample_scatter_points`, `set_input_blocked`) are unchanged. The auto-continue from throw 2 to throw 3 is implemented here, but the Skip button is deferred to Phase 3.

**Acceptance:** A fresh run from Start Screen → Play Tutorial routes into throw 1, walks through all beats, and lands cleanly on the completion screen. All copy reads as crosshair language. Stat bars are visible from throw 1 onward. Snapshot/restore preserves player stats on slider demos.

### Phase 2: Sub-menu and stats-only entry mode

Add a chooser dialog surfaced when the Start Screen's Play Tutorial button is clicked. Two buttons in the chooser: **Full Tutorial** (current behavior — routes into Phase 1's throw 1) and **Stats Walkthrough Only** (routes directly into throw 3's setup). Parameterize `tutorial_controller.gd` with a launch mode (recommend an enum `TutorialMode { FULL, STATS_ONLY }`) on its entry function, defaulting to FULL. The STATS_ONLY mode skips throws 1-2 entirely and initializes the controller in the same state throw 3 would normally see at its start. Welcome modal's first-run route continues to use FULL.

**Acceptance:** Clicking Play Tutorial opens a small chooser. Full Tutorial works identically to Phase 1. Stats Walkthrough Only drops the player into throw 3's intro callout with no replay of throws 1-2. State is clean — the player can complete or skip the stats walkthrough and return to menu without artifacts.

### Phase 3: Skip Stats Walkthrough button

Persistent UI element visible from the throw 2 → throw 3 transition onward (or from the start of throw 3 when entered via Stats Walkthrough Only). Recommend a corner-anchored button (top-right) with clear "Skip Stats Walkthrough" labeling. On click: tear down throw 3 state, restore any in-flight slider snapshots, route the player back to the Start Screen (no completion celebration — they bailed, not finished). Button is hidden during throws 1-2 entirely.

**Acceptance:** Skip button is visible from throw 2 → 3 transition onward, hidden before. Clicking it immediately returns to Start Screen with no state leakage. Re-entering the tutorial after a skip works cleanly.

## Architectural notes

- **All "live update" code is reused.** `tutorial_slider.gd`, `ghost_dart_layer.gd`, `throw_mechanic`'s tutorial-mode hooks, the dartboard highlight API, and `hud.gd::set_stat_bar_visibility` (used in the prior tutorial for progressive bar reveal — likely unused or differently-used in the new flow since bars stay visible) all stay. Only the beat sequencer in `tutorial_controller.gd` is rewritten.
- **The new launch mode pattern.** Adding `TutorialMode` to the controller's entry function is the cleanest place to fork. The controller's existing init flow becomes the FULL path; a new branch handles STATS_ONLY by jumping to throw 3's entry beat. Avoid duplicating beat content — both paths share the same throw 3 beat sequence.
- **Skip button is a new persistent overlay.** It's not a tutorial beat — it's a sibling UI element controlled by the tutorial controller's lifecycle. Add a `CanvasLayer` or `Control` child to the tutorial controller, visible from a `_show_skip_button()` call at the appropriate beat. Hide it on tutorial teardown.
- **State cleanup must handle truncated flows.** Phase 2 (skipping throws 1-2 entirely) and Phase 3 (mid-throw-3 skip) both produce non-canonical exit paths. The teardown logic must restore any snapshotted stats, unpause the game, hide tutorial overlays, and return to a clean menu state. The existing snapshot/restore patterns are the model — extend them where needed.
- **Skip button placement is a small UX call.** Recommend top-right corner with a subtle but legible button style. Worth a quick visual confirmation before merging — Max may want to specify exact placement / styling.
- **Stat bar visibility for throws 1-2.** With bars visible throughout, `hud.gd::set_stat_bar_visibility(stat_keys, is_visible)` may become unused for the new flow. Don't remove the API — the rules slideshow or future tutorials may want it. Just stop calling it from the new controller.

## Open future hooks

- **"Just Mechanics" tutorial mode.** Currently the only opt-out from the stats walkthrough is the Skip button mid-flow. If playtest shows players consistently skipping, consider adding a third sub-menu option ("Just Mechanics — No Stats") that routes into throws 1-2 and then ends cleanly. Easy to add: just another `TutorialMode` enum value.
- **Stats Reference panel (deferred from prior spec).** Still deferred. The new stats walkthrough is the primary teaching surface; a persistent reference panel could land later as a "look it up" complement. `start_screen.stats_reference_pressed` signal still exists and is still unhandled.
- **Assembly tutorial (deferred from prior spec).** Still deferred. The new structure doesn't change anything about whether or when the Assembly tutorial happens.
- **Per-throw replay.** Currently the only replay granularity is "Full Tutorial" or "Stats Only." A finer-grained replay (e.g., "redo just the V meter explanation") is possible by parameterizing the entry beat index, but is overkill for now.
- **Ellipse references in rules slideshow.** Out of scope for this spec but a known follow-up. The rules slideshow may still reference the old ellipse aim — a focused copy-only pass on `rules_slideshow.gd` (and any other lingering references) lands later.

---

## Workflow Notes

`CLAUDE.md` holds the **single active spec** — the feature currently being designed or implemented. It auto-loads into every Claude conversation in this repo, so it should stay lean and focused on one thing at a time.

When a feature ships (or work moves on to a new spec), the previous one gets archived:

1. Move everything above this "Workflow Notes" section into `specs/YYYY-MM-DD-feature-slug.md`.
2. Add a status header at the top of the archived file:
   ```
   ---
   Spec date: YYYY-MM-DD
   Status: Shipped YYYY-MM-DD | Partially shipped | Superseded by specs/X
   Implementation: Where the implementation pass ran (Claude Code, manual, etc.)
   Notes: What shipped vs deferred, links to follow-up specs that revisit anything here.
   ---
   ```
3. Reset the spec section in `CLAUDE.md` to this placeholder (or replace it with the next spec).

The archive is for design context, not implementation reference. Code lives in code; the archived spec exists to remind future-Max (and future-Claude) *why* a system was built a certain way, what alternatives were considered, and what the design assumptions were. When making changes that touch an existing system, scan `specs/` for any prior decision that constrains the new work.
