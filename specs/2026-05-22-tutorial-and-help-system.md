---
Spec date: 2026-05-22
Status: Shipped 2026-05-22
Implementation: Claude Code across three commits — `26c5bd8 tutorial A` (Phase A: Start Screen, mechanics tutorial scaffolding, throw mechanic hooks, ghost-dart layer, rules slideshow v1, welcome modal, settings store), `592322c full tutorial` (Phase B1–B5: stat-bar progressive reveal, three live-slider demos, real-stats requirement, rules slideshow mini-dartboard side-by-side layout, tutorial_slider widget), `7c288d9 accuracy zone update and cleaner tutorial` (refinement pass on throw mechanic + tutorial controller polish).
Notes: All five Phase B parts shipped. Section 5 (Assembly Tutorial) and Section 6 (Stats Reference) intentionally deferred — playtest during Phase B confirmed that in-context teaching during the mechanics tutorial covers the stat education the Stats Reference panel was originally intended to handle, so the Reference becomes a "look it up later" surface rather than a primary teaching tool. The Assembly Tutorial similarly becomes lighter-weight follow-on work focused on assembly-screen mechanics rather than re-teaching stats. `start_screen.stats_reference_pressed` signal exists but is not yet wired in `main.gd`. `scripts/stat_descriptions.gd` (the planned single-source-of-truth for stat copy) was not created. Mini-board geometry math is now duplicated three times (main dartboard, assembly zone preview, rules slideshow mini board) — flagged as an optional DartboardGeometry refactor in this spec, not blocking. All deferred items can be picked up in a future spec.
---

# Tutorial & Help System — Phase A Shipped, Phase B Additions

**Spec date:** 2026-05-22 (original) | revised 2026-05-22 (Phase B additions)
**Status:** Phase A shipped via Claude Code; Phase B additions designed, ready for implementation.
**Scope of this pass:** Fold stat education into the existing mechanics tutorial via progressive bar reveals and three interactive slider demos, a "real stats" requirement that ties the tutorial throws to the player's actual build, and a side-by-side mini-dartboard rework of the rules slideshow (because the current implementation's highlights are obscured by the modal scrim). Leaves Assembly Tutorial (Section 5) and Stats Reference (Section 6) as smaller follow-ons.

---

## Already Shipped (do NOT rebuild)

The first Claude Code pass shipped the bulk of the original spec. Before adding anything, read the relevant files to understand the current shape — Phase B plugs *into* this code, not alongside it.

| Spec section | Status | Lives in |
|---|---|---|
| 1. Start Screen | Shipped | `scripts/start_screen.gd`; wired in `main.gd` (signals: `start_game_pressed`, `play_tutorial_pressed`, `rules_pressed`, `stats_reference_pressed`). `stats_reference_pressed` is emitted but not yet handled — see Section 6 below. |
| 2. Mechanics Tutorial | Shipped | `scripts/tutorial_controller.gd` (448 lines, full 3-throw walkthrough). Captions live in the exported `tutorial_strings: Dictionary`. Throw 1 beats are split across named functions: `_throw1_place_aim`, `_throw1_explain_ideal`, `_throw1_lock_vertical`, `_throw1_start_h_freezes`, `_throw1_show_h_freeze`, `_throw1_next_h_freeze`, `_throw1_resume_h`. Throw 2 is `_start_throw_2_guided` → `_on_throw_2_completed`. Throw 3 is `_start_throw_3_free` → `_on_throw_3_completed` → `_build_end_buttons`. |
| 2c. Throw mechanic hooks | Shipped | `throw_mechanic.gd`: `set_paused`, `set_scripted_mode`, `set_bounce_t`, `set_horizontal_bounce_t`, `force_lock_aim`, `force_lock_vertical`, `force_lock_horizontal`, `meter_position_changed` signal, `get_zone_boundary_h_positions`. |
| 2e. Callout overlay | Shipped | `scripts/tutorial_callout.gd`. |
| 3. Ghost-Dart Scatter Preview | Shipped | `scripts/ghost_dart_layer.gd`; sampler is `throw_mechanic.sample_scatter_points(...)`; opt-in live preview exposed via `live_scatter_preview: bool` and `live_scatter_sample_count: int` on throw_mechanic. |
| 4. Meter Zone Bands | Shipped | `throw_mechanic.gd::show_h_meter_zone_bands: bool` toggles them; rendered alongside the H meter using existing `accuracy_*_color` exports. |
| 7. Rules of Darts | Shipped | `scripts/rules_slideshow.gd` (405 lines, slideshow + doubles drill). Dartboard highlight via `dartboard.set_tutorial_highlight(...)` / `clear_tutorial_highlight()`. Slide content lives in exported `rules_slides: Array[Dictionary]`. |
| 8. First-Run Trigger | Shipped | `scripts/settings_store.gd` (static singleton over `ConfigFile` at `user://settings.cfg`). `scripts/welcome_modal.gd` is the soft prompt. `main.gd::_ready` checks `SettingsStore.get_tutorial_seen()` and routes accordingly. `debug_reset_tutorial_seen` export on main.gd lets Max reset the flag from the inspector. |

**Reminder for the next pass:** if a section in this spec contradicts what's in the code, treat the *code* as the current truth and adapt the spec changes to it (Phase A may have made small variations during implementation). Don't restructure shipped code unless the spec explicitly calls for it.

---

## Phase B — New Work

Five changes. B1–B4 are all folded into the existing mechanics tutorial — the goal there is to **teach stats in context**, where each stat is revealed and explained next to the throw stage it controls, rather than as a separate Stats Reference flow. B5 is independent — a layout/visual fix to the already-shipped rules slideshow.

### B1. Real stats throughout the tutorial

The tutorial sandbox should use the player's *actual* build stats — not arbitrary tutorial-friendly defaults — so the throws in tutorial throw 3 feel exactly like the throws in their first real leg.

**Behavior:**

- When tutorial is entered from the **Start Screen on first run**, the player has no equipped build yet, so the throw_mechanic is on its default exported values. That's fine — use them as-is. Don't seed special tutorial values.
- When tutorial is entered from **Assembly** (replay), the player has an equipped build. The throw_mechanic stats reflect that build (per `dart_build.apply_to_throw_mechanic(...)` in main.gd's `_on_run_confirmed`). Use those values. This becomes an emergent "feel my current build" tool for returning players.
- When the **live slider demos** (B3) temporarily mutate a stat, the original value must be snapshotted before the demo and restored after. Pattern to follow: `main.gd::_snapshot_base_stats` / `_restore_raw_stats`. Wrap each demo in a save/restore.

**Implementation:**

- Add a small helper on `tutorial_controller.gd`: `_snapshot_stat(stat_name: String) -> float` and `_restore_stat(stat_name: String, value: float) -> void`. The snapshot stores the throw_mechanic property by name; restore writes it back. Called before/after each B3 demo.
- No new public API on `throw_mechanic.gd` — the controller reads/writes the existing exported vars directly.
- Document in the controller's class comment that the tutorial assumes throw_mechanic stats are pre-configured by main.gd before the tutorial starts. No re-initialization inside the controller.

### B2. Progressive stat-bar reveal

The six stat bars (currently rendered by `hud.gd::_build_stat_bars` into the `StatsContainer`) start **hidden** when the tutorial begins. As each relevant stage is explained, the corresponding bars fade in and a callout names them. By the end of throw 1, all six are visible. They remain visible for throws 2 and 3.

**Reveal mapping (which stat appears at which beat):**

| Tutorial beat (existing function) | Stats revealed | Caption (new `tutorial_strings` key) |
|---|---|---|
| `_throw1_place_aim` — aim ellipse shown | H Range, V Range | `"reveal_range"`: "These two stats — **H Range** and **V Range** — control the size of your aim ellipse. Higher Range = smaller ellipse = more precise aim." |
| `_throw1_lock_vertical` — V meter active | V Speed | `"reveal_v_speed"`: "**V Speed** controls how fast the vertical marker bounces. Higher = slower = easier to time." |
| `_throw1_start_h_freezes` — H meter active | H Speed | `"reveal_h_speed"`: "**H Speed** is the same idea for the horizontal marker." |
| `_throw1_show_h_freeze` at the green-zone beat | H Accuracy, V Accuracy | `"reveal_accuracy"`: "**H Accuracy** and **V Accuracy** set your base scatter size. Where you lock on the meters then modifies it — closer to the centroid shrinks the scatter, farther bloats it." |

**Implementation:**

- The HUD already builds the stat rows. Add a method `hud.set_stat_bar_visibility(stat_keys: Array[String], visible: bool)` that toggles `visible` on the matching rows in `stats_container`. Stat keys use the existing `STAT_KEYS` constant.
- Tutorial controller starts by calling `hud.set_stat_bar_visibility(STAT_KEYS, false)` and the stats title (the "— Stats —" label) also hidden. Then at each reveal beat it un-hides the named subset.
- Fade in via a short `create_tween()` on each row's `modulate.a` from 0 → 1. Duration exported on `tutorial_controller.gd` as `@export var stat_reveal_fade_duration: float = 0.4`.
- After the tutorial finishes (`_finish_to_assembly` or `_finish_to_start`), re-show all stat bars regardless of state, so normal gameplay isn't affected.
- The reveal beats are inserted *into the existing throw 1 flow* — they're not their own throws. Each reveal piggybacks on a callout already happening at that stage (e.g., the aim-ellipse callout grows to include the range-stat reveal). Or, if cleaner, add a new sequential callout immediately following the existing one. Either is fine; pick whichever flows better in playtest.

### B3. Three live-slider demos (Range, Speed, Accuracy)

After the stat reveal at each stage, a small interactive demo lets the player drag a slider on the *horizontal* stat (H Range, H Speed, H Accuracy) and watch the visual update live. Three demos total; the player gets the cause-effect once per category and generalizes to the vertical counterpart.

**Demo 1 — H Range (after aim-ellipse + reveal_range callout):**

- Pauses the throw mechanic in AIMING with the aim ellipse placed (the tutorial already auto-places it via `force_lock_aim`).
- Shows a slider widget at a tutorial-controlled screen position, labeled "H Range" with the current value displayed.
- Slider min/max derived from the H Range gameplay range — recommend `(20, 90)` to bracket the visible-difference window. Pull from new exports `@export var demo_h_range_min: float = 20.0` and `@export var demo_h_range_max: float = 90.0`.
- On slider drag, write the value to `throw_mechanic.horizontal_range` and call `throw_mechanic.queue_redraw()`. The aim ellipse half-width recomputes (the throw mechanic already redraws the ellipse from the current `horizontal_range` value).
- Caption: `"demo_range"`: "Try it — drag the slider and watch the ellipse change. **V Range** works the same way for the vertical axis."
- A "Got it" button next to the slider continues the tutorial. On click: restore the original `horizontal_range` value, remove the slider widget, advance to the next beat.

**Demo 2 — H Speed (after H meter starts + reveal_h_speed callout):**

- Pauses the H meter only briefly to set up, then resumes with the marker free-running. The marker keeps bouncing left/right at whatever speed the slider currently dictates. Player clicks are *blocked* during the demo (no commit).
- Slider on `throw_mechanic.horizontal_speed`. Min/max `(1.0, 5.0)` covering the documented gameplay range.
- On slider drag, write to `throw_mechanic.horizontal_speed`. The bounce loop already reads this value each frame — no extra redraw call needed.
- Caption: `"demo_speed"`: "Drag to feel the difference. Slower meter = more time to react. **V Speed** is the same for the vertical meter."
- "Got it" → restore, remove slider, *unblock H meter input*, continue.
- **Implementation note:** the controller already has `set_scripted_mode(true)` for throw 1. Add an explicit `set_input_blocked(blocked: bool)` flag on throw_mechanic (or reuse `set_paused` carefully) so the marker keeps moving but clicks don't commit during the demo. Cleanest is a new internal flag, since `_paused` halts `_process` entirely.

**Demo 3 — H Accuracy (after the H freeze beats, just before resume to throw resolution):**

- Pauses in HORIZONTAL_RELEASE with a representative locked position (the orange-zone freeze position from the existing `_throw1_show_h_freeze` sequence is a good baseline — neutral, no zone bonus or penalty).
- Shows ghost-dart cluster via `ghost_dart_layer.show_scatter(sample_scatter_points(..., rng_seed=<fixed>))`. **Fixed seed is essential** so the cluster pattern stays consistent and the player perceives shrink/grow rather than "shuffle."
- Slider on `throw_mechanic.horizontal_accuracy`. Min/max `(20, 80)`.
- On slider drag: write the new value, then re-sample with the same seed, then call `ghost_dart_layer.show_scatter(new_points)`. Cluster shrinks/grows visibly.
- Caption: `"demo_accuracy"`: "Watch the scatter shrink and grow. Tighter accuracy = your darts land closer together. **V Accuracy** does the same for vertical spread."
- "Got it" → restore, clear scatter, remove slider, continue to `_throw1_resume_h`.

**Slider widget:**

- New file: `scripts/tutorial_slider.gd` extending `Control`. Small VBox: label (stat name + current value), HSlider, "Got it" button.
- Signals: `value_changed(value: float)`, `dismissed`.
- Position, size, fonts, colors all exported with hover descriptions per project conventions.
- Lives transiently — instantiated by tutorial_controller for the demo, freed when dismissed.

**New beat ordering inside throw 1:**

The existing throw 1 sequence has beats roughly: intro → place aim → explain ideal → lock vertical → start H freezes → show H freeze ×3 → resume H → throw completed. The new beats slot in as:

1. intro
2. place aim
3. **reveal H/V Range bars + caption** (B2)
4. **H Range slider demo** (B3 demo 1)
5. explain ideal
6. lock vertical
7. **reveal V Speed bar + caption** (B2)
8. start H freezes
9. **reveal H Speed bar + caption + H Speed slider demo** (B2 + B3 demo 2 — the demo runs *before* the freeze sequence so the player isn't pulled out mid-freeze)
10. show H freeze (green)
11. **reveal H/V Accuracy bars + caption** (B2) — anchored to the green-zone freeze since that's where scatter is most visibly tight
12. show H freeze (orange)
13. show H freeze (red)
14. **H Accuracy slider demo** (B3 demo 3) — after all three freezes have established what zone-driven scatter changes look like
15. resume H
16. throw completed

Beats 10-13 are unchanged from current code. The new beats (3, 4, 7, 9, 11, 14) plug in around them.

### B4. Skip-tutorial behavior under the new beats

The existing tutorial already has a Skip Tutorial path. The new demos add interactive widgets that need cleanup on skip. The cleanest pattern: any active demo registers a teardown callback with the tutorial controller; the skip handler walks the teardown stack before exiting. This avoids leaked sliders or mutated stats when a player skips mid-demo.

### B5. Rules Slideshow — mini dartboard + side-by-side layout

The shipped rules slideshow (`scripts/rules_slideshow.gd`) routes highlight calls to the **main dartboard**, but the dartboard sits behind a 0.75-opacity modal scrim while the slideshow is open — so the highlights technically fire but are nearly invisible. Fix: add a dedicated mini dartboard *inside* the slide panel, and restructure the panel layout side-by-side (text left, board right).

**Behavior:**

- Modal panel widens (current `panel_width: 520.0` → ~720). The panel splits into two columns: left column holds title, body, slide counter, prev/next/close buttons (current single-column layout, just narrower); right column holds a small label ("The Board") above a mini dartboard.
- The mini dartboard is **always visible** while the slideshow is open, even on slides whose `highlight` array is empty. Acts as a spatial reference the player can glance at throughout.
- Slides whose `highlight` array is non-empty render those highlights on the **mini board only** — never on the main board. The main dartboard stays clean and unhighlighted for the slideshow's entire lifetime.

**Implementation — model after the assembly screen's zone preview:**

The pattern to copy is `scripts/assembly_screen.gd::_build_zone_preview()` and `_draw_preview_dartboard(center)` (around lines 841–966). That's a custom-drawn `Control` with its own simplified `_draw_board_segment(...)` and `_draw_board_ring(...)` helpers that draw arc-based wedges and concentric rings at a given center — **not** a Dartboard node instance. Lightweight, self-contained, and already proven in production. The same ring threshold constants (0.032, 0.08, 0.48, 0.53, 0.76, 0.83) used by both the assembly preview and the main dartboard mean the mini board's geometry matches the real board.

Add to `rules_slideshow.gd`:

1. **Mini-board widget construction.** A `Control` child of the slide panel, positioned in the right column. Connect its `draw` signal to a new `_draw_mini_board()` method that mirrors `assembly_screen.gd::_draw_preview_dartboard(center)`. Copy the segment/ring helpers verbatim (or extract them to a shared utility if Max prefers — see note below). All visual constants (background color, segment colors, wire color) exported with hover descriptions.
2. **Highlight overlay.** After drawing the base board, draw any active highlights on top. Port the four highlight-type handlers from `dartboard.gd::set_tutorial_highlight` (`all_wedges_ring`, `single_wedge_all`, `single_segment`, `bullseye`) into the mini board's draw method. Highlights are stored in a small `_active_highlights: Array[Dictionary]` field on the slideshow, set per-slide in `_display_current_slide()` and `queue_redraw()` triggered on the mini board.
3. **Stop passing highlights to the main dartboard.** Remove the `dartboard.set_tutorial_highlight(slide["highlight"])` call (currently in `_display_current_slide`). The existing `dartboard: Node2D` field can be kept solely for the open/close cleanup below, or removed entirely if the slideshow no longer needs any reference to the main board.
4. **Cleanup pass for stale main-board highlights.** `show_slideshow()` should call `dartboard.clear_tutorial_highlight()` on open (currently only called on close, which means a slideshow opened immediately after a previous one closed could briefly inherit stale highlights from elsewhere — defensive cleanup is cheap). After this pass, the main board's tutorial-highlight system is touched ONLY by the rules slideshow on open/close, and never set during slideshow play.

**New exports (with hover descriptions per project conventions):**

- `mini_board_radius: float` (default ~100.0) — pixel radius of the mini board. Pulled from the same scaling logic the assembly preview uses (`preview_ratio = mini_board_radius / 300.0`).
- `mini_board_column_width: float` (default ~200.0) — width of the right column inside the panel.
- `text_column_width: float` (default ~480.0) — width of the left column. Old `body_label` width binds to this.
- `mini_board_label_text: String` (default "The Board") — title above the mini board.
- `mini_board_label_font_size: int` (default 14).
- Per-color exports for the mini board's background, segment colors, wire color, and highlight overlay (highlight color can default to the same `Color(1.0, 0.85, 0.2, 0.4)` value as the main dartboard's `tutorial_highlight_color`).
- `panel_width` already exists — update default from 520 to ~720 (or whatever fits two columns cleanly).

**Note on factoring the segment/ring drawing helpers:**

The mini-board draw code in `assembly_screen.gd` is ~60 lines of arc/polygon math. It's already duplicated (the main `dartboard.gd::_draw_segment` does the same thing at a different scale). After this change there'd be three copies. If Max wants to clean that up:

- Extract a `class_name DartboardGeometry extends RefCounted` (or similar) with static helpers `draw_segment(canvas, center, start_deg, end_deg, outer_r, inner_r, color)` and `draw_ring(canvas, center, radius, color)`.
- Both `dartboard.gd` and `assembly_screen.gd` and the new rules-slideshow mini board call into it.

This is a small refactor and not strictly required for B5 to ship. Flag it as a follow-up cleanup if Max wants it.

**Skip-tutorial / close behavior:**

- Close button or scrim-click: hide slideshow, mini-board widget stays as a child of the panel (no need to destroy/recreate), main dartboard's highlights stay clear.
- Re-opening the slideshow: re-runs `show_slideshow()` from slide 0, which calls `dartboard.clear_tutorial_highlight()` defensively, and the mini board re-draws based on the new active slide.

---

## Pending from Original Spec (still applicable, lower priority)

### Section 5 — Assembly Tutorial (trimmed)

Now that Phase B teaches stats in context during the mechanics tutorial, the Assembly Tutorial becomes a lighter walkthrough focused on the *assembly screen itself*, not stat fundamentals. New scope:

1. Callout pointing at the dart preview: "Your dart — barrel + shaft + flight."
2. Callout pointing at slot arrows: "Cycle through your owned components on each slot."
3. Callout pointing at stat bars: "Watch the bars change as you swap parts." (No re-teaching of what each stat means — that lived in the mechanics tutorial.)
4. Callout pointing at the balance bar: "Component weights sum to a balance value. Green = bonus, drifting into orange/red = penalties. Sometimes worth it for the raw stats."
5. Callout pointing at the zone preview (bottom-left): "Live preview of your aim ellipse and accuracy zone at current stats."
6. Callout pointing at Begin Run: "Hit this when you're happy with the build."
7. End message.

**Implementation:**

- Add `_build_assembly_tutorial_beats() -> Array[Dictionary]` to `tutorial_controller.gd`. Reuses the existing `tutorial_callout.gd` infrastructure.
- Wire to a new "Assembly Tutorial" button in `assembly_screen.gd` (separate from the existing "Play Tutorial" button, which re-enters the mechanics tutorial). New signal: `assembly_tutorial_pressed`.
- `main.gd` connects the new signal to a handler that calls `tutorial_controller.start_assembly_tutorial()`.
- Arrow targets read from the AssemblyScreen's existing exported layout vars (e.g., `dart_preview_position`, `barrel_slot_position`, `zone_preview_position`) so callouts move when Max retunes UI positions in the inspector.

### Section 6 — Stats Reference (deferred / nice-to-have)

With stats taught in-context, the persistent Stats Reference shifts from *teaching tool* to *reference tool* — "I forgot what V Accuracy does, let me look it up." Still useful, but no longer mission-critical for first-time comprehension.

If shipped:

- Create `scripts/stat_descriptions.gd` (RefCounted, static dictionaries for `SHORT`, `LONG`, `DISPLAY_NAMES`, `STAGE`). Migrate `hud.gd::STAT_DESCRIPTIONS` and `STAT_DISPLAY_NAMES` to reference these so there's a single source of truth.
- Create `scripts/stats_reference_panel.gd` (modal Control overlay listing all six stats grouped by stage).
- Wire `start_screen.stats_reference_pressed` (already emits, just not handled) to show the panel.
- Add a "Stats" button to the Assembly Screen that also opens it.

Defer unless playtest shows the in-context teaching alone is insufficient.

---

## Implementation Notes

- **Static typing throughout** per project conventions. Every `var`, every parameter, every return.
- **Frequent commenting** — especially on the new beat ordering inside throw 1. Note in the controller's class comment which beats are "shipped Phase A" vs "added Phase B" so future readers can trace the design history.
- **All tunable values exported with `##` hover descriptions** per project conventions: slider widget position/size/colors, slider min/max for each demo, stat reveal fade duration, the demo captions (new `tutorial_strings` keys).
- **Snapshot/restore around every demo.** Critical — a tutorial that leaves the player's stats mutated would be a bug players never notice but always feel as "the dart doesn't behave like it did in the tutorial."
- **No changes to scoring, game logic, or modifier systems.** Phase B is pure tutorial enhancement.
- **Scene tree additions (Phase B only):**
  - `scripts/tutorial_slider.gd` — new transient widget, instantiated by tutorial_controller as needed.
  - Possibly a `set_input_blocked(blocked: bool)` on `throw_mechanic.gd` if the existing `_paused` flag isn't right for the H Speed demo (marker keeps bouncing, clicks ignored).
- **HUD changes:** add `set_stat_bar_visibility(stat_keys: Array[String], visible: bool)` to `hud.gd`. Pair it with a "show all" convenience caller that the tutorial uses on exit.

---

## Key Design Decisions (for the archive)

- **Stats taught in-context during mechanics tutorial, not as a separate Stats Reference flow.** Realized post-Phase-A playtest: a separated reference is less effective than showing the stat next to the thing it controls. The Stats Reference becomes a "look it up later" tool rather than a primary teaching surface.
- **Three live demos, one per category (Range, Speed, Accuracy), horizontal axis only.** Six demos would balloon the tutorial; one per category teaches the cause-effect once and the player generalizes to the V counterpart. Horizontal axis is the visually larger one for each category, so the slider delta is more striking.
- **Real stats throughout the tutorial.** No "easy mode" tutorial values that diverge from real gameplay. Tutorial throw 3 must feel exactly like the first throw of the first real leg, or the player feels lied to. Side benefit: replaying the tutorial from Assembly with an upgraded build becomes a "feel my current dart" tool for free.
- **Progressive bar reveal vs all-visible-from-start.** Progressive avoids the "wall of unfamiliar numbers" reaction on first sight and makes each reveal feel like depth being uncovered. Costs a small amount of choreography; worth it.
- **Demos use fixed RNG seeds for the scatter sampler.** Without this, the cluster reshuffles on every re-sample and the player perceives chaos instead of shrink/grow. Same approach as the existing green/orange/red freeze beats.
- **Slider demos block commits without freezing the meter.** For the H Speed demo specifically: the marker must keep bouncing so the player can feel the speed change, but clicks must not commit. New `set_input_blocked` flag is cleaner than overloading `_paused`.
- **Rules slideshow uses a self-contained mini dartboard, not the main board.** Phase A shipped highlights routed to the main board, but the 0.75-opacity modal scrim renders them nearly invisible. A mini board inside the slide panel (modeled on the assembly screen's existing zone preview pattern) puts the visual next to the text it's explaining, eliminates scrim-occlusion, and isolates the slideshow from any state changes on the main board.

