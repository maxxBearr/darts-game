# Tutorial & Help System

**Spec date:** 2026-05-22
**Status:** Designed, ready for implementation
**Scope:** First-time-player onboarding + persistent help reference. Adds a Start Screen ahead of Assembly, a sandbox Mechanics Tutorial (3-throw guided walkthrough using freeze-and-explain at the three accuracy zones, with ghost-dart scatter previews), an Assembly Tutorial (guided walkthrough of the assembly UI), a persistent Stats Reference, a persistent Rules of Darts reference (slideshow + interactive doubles-checkout drill), and a first-run welcome prompt. Replays available via buttons in Assembly. Designed so Max can hand the game to friends — including friends who've never thrown a dart — without sitting next to them to explain.

## Summary

Three-pronged problem:

1. **Darts mechanics** (V meter, H meter, accuracy zone, scatter) — the game's *signature interaction* that no other dart game does. Requires demonstration.
2. **x01 rules** (wedge layout, scoring, doubles checkout, bust) — the rules of *darts itself*. Required for anyone who hasn't played the pub game. Some friends will already know these; many will not.
3. **Build/assembly literacy** (components, stats, balance, modifier lock state) — the *roguelike* layer. Required for anyone playing more than one leg.

These three concerns are deliberately kept as separate flows. Darts vets skip the rules. Returning players skip the mechanics tutorial. The Assembly Tutorial only matters once the player understands throwing and rules. Mixing them is cognitive overload — and tracking them separately means each can be rebuilt independently if playtesting reveals one is unclear.

Eight parts to the spec:

1. The Start Screen (new entry point ahead of Assembly).
2. The Mechanics Tutorial — sandbox mode with 3-throw walkthrough using freeze-and-explain at each accuracy zone.
3. The Ghost-Dart Scatter Preview — reusable visualization, used in the tutorial and optionally always-on.
4. Meter Zone Bands — colored regions on the H meter showing the green/neutral/red zones.
5. The Assembly Tutorial — guided walkthrough of the assembly screen.
6. The Stats Reference — persistent expandable panel.
7. The Rules of Darts — persistent slideshow + interactive doubles-checkout drill.
8. First-Run Trigger + Settings Persistence.

A phasing recommendation appears at the end — if all eight pieces are too much for one Claude Code pass, parts 1, 2, 7, and 8 are the MVP "ship to friends" cut.

---

## 1. The Start Screen

New entry point. Currently `main.gd::_ready()` jumps directly to `_show_assembly()`. The start screen sits ahead of that.

### 1a. Layout

Full-screen `Control` overlay, same canvas layer as the HUD. Three buttons stacked vertically:

- **Start Game** — proceeds to the Assembly screen (current default behavior).
- **Play Tutorial** — enters the Mechanics Tutorial sandbox (Section 2).
- **Rules of Darts** — opens the Rules slideshow (Section 7).

A small "?" or text button for **Stats Reference** is visible but secondary — it's most useful in-game, but accessible here for completeness.

### 1b. Implementation

- New scene/script: `scripts/start_screen.gd` extending `Control` with `class_name StartScreen`.
- Lives at `$HUD/StartScreen` in the main scene tree.
- Signals: `start_game_pressed`, `play_tutorial_pressed`, `rules_pressed`, `stats_reference_pressed`.
- `main.gd::_ready()` shows the StartScreen first; only after `start_game_pressed` does `_show_assembly()` fire.
- StartScreen visibility is exclusive with AssemblyScreen — when one is visible the other is hidden.
- All button positions, sizes, fonts, and colors exported with hover descriptions.

### 1c. Replay buttons (in Assembly)

The Assembly screen gains two new buttons (in addition to the existing Begin Run flow):

- **Play Tutorial** — re-enters the Mechanics Tutorial sandbox. Same destination as the Start Screen button.
- **Assembly Tutorial** — enters the Assembly Tutorial overlay (Section 5).

Both also accessible later via a top-bar "?" menu or similar (out of scope for this spec — for now, Assembly is the central re-entry point because that's where the player sits between legs).

---

## 2. The Mechanics Tutorial (Sandbox)

The signature flow of this spec. Walks a brand-new player through the throw mechanic in three throws: demo → guided → free. No score pressure, no x01 game logic, no dart budget.

### 2a. Sandbox mode

A new game phase, distinct from a real x01 run. Owned by `main.gd` via a new `_in_tutorial: bool` flag plus a small `tutorial_controller.gd` (new file) that orchestrates the beats.

- The dartboard renders normally.
- The throw mechanic runs normally — except where the tutorial pauses or scripts it (Section 2c).
- `x01_game.gd` is NOT involved. No remaining-score countdown, no busts, no leg/turn counters. The HUD hides score-related labels during tutorial.
- `scoring_modifier_manager.gd` runs in a clean state (no active modifiers) so the scoring is vanilla — the tutorial is teaching base mechanics, not modifier interactions.
- Dart markers from previous throws stay on the board until the tutorial exits.
- An "Exit Tutorial" button is visible at all times (top-right). Clicking it returns to the Start Screen if entered from there, or to Assembly if entered from there.

### 2b. The three-throw structure

**Throw 1 — Demo (autopilot with freeze-and-explain).** The tutorial drives the throw with the player as observer. Beats:

1. Show the dartboard with a callout pointing at a chosen target wedge (default: outer single 20 — fat, easy to see). Caption: "We'll throw at the 20."
2. Auto-place the aim ellipse at the target. Show a labeled callout on the ellipse: "This is your **aim ellipse**. Where your dart can possibly end up after the meters resolve. Bigger ellipse = wider range of outcomes." Pause for a "Next" click.
3. Highlight the target wedge centroid with a small marker (the "ideal aim point"). Caption: "The center of your target is the ideal spot. Time the meters to land as close to it as possible."
4. Auto-progress to VERTICAL_RELEASE. Marker bounces. Auto-stop at a roughly-center vertical position (within the green zone band for the V axis). Caption: "First you lock your **vertical** position." Pause for "Next".
5. Auto-progress to HORIZONTAL_RELEASE. Marker bounces, but the tutorial scripts the H meter (Section 2c) so that it auto-pauses at three predetermined points:
   - **First pause (green zone).** Caption: "Locked here — close to the centroid — your scatter shrinks." Show the Ghost-Dart Scatter Preview (Section 3) at this candidate locked position: a tight cluster of ~10 ghost darts.
   - **Second pause (orange/neutral zone).** Caption: "Here — neutral. No bonus, no penalty. Default scatter." Ghost-dart preview shows a wider cluster.
   - **Third pause (red zone).** Caption: "Far from the centroid — your dart sprays wider." Ghost-dart preview shows a loose, scattered pattern.
6. Resume and let the H meter complete at its natural moment (tutorial picks one — recommend the orange zone for an honest neutral outcome). The throw resolves normally. Dart lands. Caption: "That's the full throw. The colored zones on the H meter (Section 4) show you where green / orange / red are."

**Throw 2 — Guided.** Normal-speed throw. The tutorial places a banner: "Try to lock the H meter in the **green** zone." No forced click, no scripted pause — the player times it themselves. After the throw, the tutorial shows a post-throw caption naming which zone they landed in ("Green zone — your dart clustered tight" / "Orange zone — neutral scatter" / "Red zone — your dart sprayed"). No reward, no penalty, no judgment — just observation.

**Throw 3 — Free.** No banner, no prompts. The player throws normally. After the throw, a final caption: "That's it. The same loop runs every throw of a real game. Ready to play?" with two buttons: "Play a real game" (→ Assembly) and "Back to start" (→ Start Screen).

### 2c. Throw mechanic pause/scripting hooks

The tutorial needs the throw mechanic to support being paused mid-state and having its meter advanced programmatically. Additions to `throw_mechanic.gd`:

- **`var _scripted_mode: bool = false`** — when true, `_process()` skips its own update of `_bounce_t` and `_horizontal_bounce_t`. The tutorial advances them itself by calling `set_bounce_t(value: float)` and `set_horizontal_bounce_t(value: float)`.
- **`func set_paused(paused: bool) -> void`** — orthogonal to scripted mode. When paused, `_process()` returns early entirely (markers frozen exactly where they are, no input accepted). Used for "freeze and show callout" beats.
- **`func force_lock_aim(global_pos: Vector2, target: Dictionary) -> void`** — programmatically locks the AIM stage with a given center and declared target, bypassing the player's mouse click. Tutorial uses this to auto-place the aim ellipse on Throw 1.
- **`func force_lock_vertical(t: float) -> void`** — locks VERTICAL_RELEASE at the given bounce-t value (0–1). Skips player input.
- **`func force_lock_horizontal(t: float) -> void`** — locks HORIZONTAL_RELEASE at the given bounce-t value. Triggers resolve normally.
- **Signal: `meter_position_changed(state: ThrowState, normalized_t: float)`** — emitted on each `_process` tick during VERTICAL_RELEASE / HORIZONTAL_RELEASE. Lets the tutorial controller know when the meter has reached predetermined freeze points.

All of these are no-ops outside scripted mode — they don't change normal-gameplay behavior.

### 2d. Computing zone-boundary positions on the H meter

For Throw 1's three freeze points, the tutorial needs to know what H meter positions correspond to the green / orange / red zone *boundaries*, given the current locked V position and target centroid. This is the same math the meter zone bands (Section 4) use:

- For each possible H position along the meter, compute `normalized_distance` (existing `_get_target_distance_normalized_at(Vector2(h_x, locked_y))`).
- Find the H values where normalized_distance crosses `green_zone_threshold` and `penalty_zone_threshold`.
- The freeze positions are picked roughly in the middle of each zone: green-midpoint, orange-midpoint, red-midpoint.

Surface this as a helper on `throw_mechanic.gd`: `func get_zone_boundary_h_positions(locked_y: float) -> Dictionary` returning `{"green_min": x, "green_max": x, "orange_max": x, "red_max": x}`. Reused by both the tutorial and the zone bands.

### 2e. Callout overlay

Tutorial captions and pointer arrows need a reusable overlay widget. New script: `scripts/tutorial_callout.gd` extending `Control`.

- A callout is `{text: String, anchor_pos: Vector2 (optional), arrow_target: Vector2 (optional)}`.
- Renders a semi-transparent rounded panel containing the text, with an optional arrow pointing from the panel to a screen position.
- "Next" button at the bottom advances to the next beat. "Skip Tutorial" button at the top-right.
- Position, sizing, colors, fonts, arrow style — all exported with hover descriptions per project conventions.
- The TutorialController owns a stack of beats and advances on "Next" clicks.

### 2f. Tutorial controller

New file: `scripts/tutorial_controller.gd` extending `Node`, instantiated as a child of `Main`.

- Owns the beat sequence as an `Array[Dictionary]` of `{type, ...args}` entries: `{type: "callout", text, anchor, arrow_target}`, `{type: "auto_lock_aim", target_wedge, target_ring}`, `{type: "auto_lock_v"}`, `{type: "h_meter_freeze_at", zone: "green"|"orange"|"red"}`, `{type: "show_scatter_preview"}`, `{type: "wait_for_throw_completed"}`, `{type: "end_tutorial"}`, etc.
- Beats are declared in a single function `_build_mechanics_tutorial_beats() -> Array[Dictionary]` so the entire walkthrough script lives in one readable place. Captions and parameters tweakable without restructuring code.
- The controller subscribes to `throw_mechanic.state_changed` and `throw_mechanic.meter_position_changed` to drive the beat progression.
- All beat text exported as a `@export var tutorial_strings: Dictionary` so wording can be tuned in the inspector without code changes (key per beat).

---

## 3. The Ghost-Dart Scatter Preview

A reusable visualization that samples N candidate dart landing positions from the current accuracy zone and renders them as ghost markers. Communicates "here's where your dart will probably land" in a way that maps directly to player intuition (much more so than a heatmap shader, per the design discussion that fed this spec).

### 3a. Sampler

New helper, ideally on `throw_mechanic.gd` (already owns the gaussian + accuracy zone math):

```
func sample_scatter_points(
    locked_release_pos: Vector2,
    sample_count: int = 10,
    rng_seed: int = -1
) -> Array[Vector2]
```

- Computes the effective accuracy zone size at the candidate `locked_release_pos` using the same `_get_accuracy_multiplier` and accuracy-half functions the live throw uses.
- Samples `sample_count` 2D gaussian draws scaled by the accuracy zone half-dimensions and offset by `accuracy_skew_v`.
- If `rng_seed >= 0`, uses a deterministic RNG seeded with that value — important for the tutorial so the same "green zone" demonstration always shows the same cluster pattern. (-1 = use global RNG, for production always-on previews.)

### 3b. Renderer

New scene/script: `scripts/ghost_dart_layer.gd` extending `Node2D`, instantiated as a sibling of `DartContainer` so it draws under landed darts but over the board.

- Takes an `Array[Vector2]` of positions and renders each as a small semi-transparent dart marker.
- Exported visual params: ghost marker color, alpha, size, outline. Match the real dart marker style at ~30–40% opacity.
- `show_scatter(points: Array[Vector2]) -> void` and `clear_scatter() -> void`.
- Auto-fades on a timer if `auto_fade_duration > 0.0` (exported), or stays visible until explicitly cleared.

### 3c. Tutorial usage

During the Throw 1 H-meter freeze beats (Section 2b), the tutorial calls:

```
var points = throw_mechanic.sample_scatter_points(
    Vector2(zone_boundary_x, locked_y),
    sample_count=10,
    rng_seed=42 + zone_index  # green=42, orange=43, red=44
)
ghost_dart_layer.show_scatter(points)
```

Cleared between freeze beats so each zone's scatter is shown alone (less visually busy than three overlapping clusters).

### 3d. Always-on preview (optional, exported)

A small additional behavior: `@export var live_scatter_preview: bool = false` on `throw_mechanic.gd`. When true, during the brief RESOLVING preview stage (the existing `resolve_preview_duration` window), the same ghost-dart sampler runs with the *actual* locked release position and renders the scatter alongside the existing variance-rectangle overlay. Off by default — opt-in player-facing visualization. Sample count tuned via `@export var live_scatter_sample_count: int = 10`.

This costs almost nothing to add given the sampler exists, and gives the player a permanent "show me the spread" toggle that some will love and others will turn off for vibes.

---

## 4. Meter Zone Bands

Colored bands drawn on the H meter showing where the green / orange / red zones are, before the player commits the click. This is the missing visual that connects "I see the meter moving" to "I know where I want to click."

### 4a. Where they appear

Only on the H meter. The V meter does have a vertical-accuracy zone too, but the tutorial's main teaching axis is the H meter freeze beats, and adding V bands risks visual clutter on a smaller axis. If playtest shows V bands are needed, add them in a follow-up.

### 4b. Computation

At the start of HORIZONTAL_RELEASE (when the V is locked), call the new `get_zone_boundary_h_positions(locked_y)` helper from Section 2d to get the screen-space H positions of each zone boundary. Draw three filled rectangles along the H meter axis at those positions:

- Green band: from `green_min` to `green_max`, filled with the existing `accuracy_green_color` at lower alpha.
- Orange band: from `green_max` to `orange_max`, filled with `accuracy_neutral_color` at lower alpha.
- Red band: from `orange_max` to `red_max` (and mirrored for symmetric H meter), filled with `accuracy_red_color` at lower alpha.

The bands hug the H meter visually — same thickness as the meter line, drawn just behind it.

### 4c. Toggle

`@export var show_h_meter_zone_bands: bool = true` on `throw_mechanic.gd`. Default on. Players who want a pure-skill feel can turn off; tutorial players see it on by default.

### 4d. Update on V re-lock

The bands depend on the locked V position. If V is re-locked (which doesn't happen in normal gameplay, but might during tutorial scripting), the bands recompute. In practice this means computing once at HORIZONTAL_RELEASE entry and caching for the duration of that state.

---

## 5. The Assembly Tutorial

A guided walkthrough of the assembly screen. Conceptually similar to the Mechanics Tutorial but for a static screen — no scripted throw beats, just callouts pointing at UI elements with explanations.

### 5a. Scope decision

**Single combined flow**, not split into Components + Modifiers. The assembly screen as it stands doesn't yet have heavy modifier UI — locking visualization happens in the modifier panel in the active game HUD, not on the assembly screen. Until that changes, one walkthrough covers the assembly screen end-to-end.

If a future spec adds significant modifier UX to the assembly screen (e.g., a modifier loadout panel), revisit this — split into "Components" and "Modifiers" tutorials at that point.

### 5b. Beat sequence

Reuses the same `tutorial_callout.gd` infrastructure as Section 2 (callouts, Next buttons, Skip button).

1. Callout pointing at the dart preview area: "This is your dart. Three components: barrel, shaft, flight. Click left/right arrows on each slot to cycle through your owned components."
2. Callout pointing at the stat bars: "Your dart parts give you stat bonuses across three categories: **Range** (smaller aim ellipse), **Speed** (slower meter, easier to time), **Accuracy** (tighter dart scatter)." Each stat name in the caption links to the persistent Stats Reference (Section 6) — clicking opens the reference panel inline.
3. Callout pointing at the balance bar: "This is your **balance**. Component weights sum to a balance value. Stay in the green zone for a stat bonus, drift into orange/red for penalties — but sometimes the trade is worth it."
4. Callout pointing at the zone preview (bottom-left): "This preview shows your dart's aim ellipse and accuracy zone at current stats. Watch it change as you swap parts."
5. Callout pointing at the Begin Run button: "When you're happy with your build, hit Begin Run."
6. End: a small message "That's the assembly screen. You'll come back here between legs to swap parts." with an "OK" button that closes the overlay.

### 5c. Implementation

- New beat-set in `tutorial_controller.gd`: `_build_assembly_tutorial_beats() -> Array[Dictionary]`.
- Entered when the Assembly Tutorial button (Section 1c) is pressed.
- The TutorialController handles assembly beats the same way it handles mechanics beats — callouts pointing at UI elements (using `arrow_target` positions read from the AssemblyScreen's exported layout vars so the callouts move when Max retunes UI positions in the inspector).
- All beat strings exported in `tutorial_strings` so wording is tunable.

### 5d. Stat description hover-link

When a stat name appears in a callout (e.g., "Range", "Speed", "Accuracy"), allow the player to click it to open the Stats Reference overlay (Section 6) inline. This is a small "click-through" interaction inside the callout text. If RichTextLabel doesn't support arbitrary click handlers cleanly, fall back to a small "?" button next to each stat name in the callout.

---

## 6. The Stats Reference

A persistent, anywhere-accessible expanded description of all six throw stats. Same content as the existing `STAT_DESCRIPTIONS` const in `hud.gd`, but expanded and presented in a dedicated panel.

### 6a. Single source of truth

Move stat descriptions out of `hud.gd` and into a new dedicated source: `scripts/stat_descriptions.gd` (singleton or static class).

```gdscript
class_name StatDescriptions
extends RefCounted

# Short descriptions (for hover tooltips) — same as current STAT_DESCRIPTIONS
const SHORT: Dictionary = { ... }

# Long descriptions (for the Stats Reference panel) — multi-paragraph
const LONG: Dictionary = { ... }

# Display names — same as current STAT_DISPLAY_NAMES
const DISPLAY_NAMES: Dictionary = { ... }

# Throw stage each stat affects (for grouping in the reference)
const STAGE: Dictionary = {
    "horizontal_range": "Aim (Stage 1)",
    "vertical_range": "Aim (Stage 1)",
    "vertical_speed": "Vertical Release (Stage 2)",
    "horizontal_speed": "Horizontal Release (Stage 3)",
    "vertical_accuracy": "Resolve (Stage 4)",
    "horizontal_accuracy": "Resolve (Stage 4)",
}
```

`hud.gd::STAT_DESCRIPTIONS` and `STAT_DISPLAY_NAMES` become references to `StatDescriptions.SHORT` and `StatDescriptions.DISPLAY_NAMES`. The Assembly Tutorial (Section 5) and Stats Reference panel both pull from this same source. Tune in one place, propagates everywhere.

### 6b. The reference panel

New script: `scripts/stats_reference_panel.gd` extending `Control`.

- Modal overlay (full-screen scrim with centered panel).
- Lists all six stats grouped by throw stage.
- Each stat shows: display name, short description (one-liner), long description (multi-paragraph).
- Close button (top-right) and click-outside-to-close on the scrim.
- Position, sizing, colors, fonts — all exported with hover descriptions.

### 6c. Where it's accessible

- A "?" or "Stats Reference" button on the Start Screen (Section 1a) — secondary affordance.
- A "?" or "Stats" button on the Assembly Screen — primary location for this reference (Max sits here between legs).
- Click-through from the Assembly Tutorial callouts (Section 5d).
- Optional: a "?" button on the in-game HUD next to the stat bars. Defer this to playtest — depends on whether the in-game stat tooltips are enough.

---

## 7. The Rules of Darts

A persistent slideshow walking through x01 rules + dartboard layout. Built as a hybrid: slideshow-primary for the bulk of the content, with one interactive moment for the doubles checkout rule (the most counterintuitive rule for newcomers).

### 7a. Slideshow structure

New script: `scripts/rules_slideshow.gd` extending `Control`.

- Modal overlay, similar shape to the Stats Reference.
- Slides advance with Next / Previous buttons or arrow keys.
- "Skip to end" link in the corner for vets.
- Each slide has: title, body text, optional illustration, optional **board highlight** (triggers the dartboard's tutorial highlight mode — Section 7c).

### 7b. Slide sequence (draft)

1. **The board.** Show the dartboard. Caption: "20 wedges, numbered 1-20, arranged in this specific order to punish missing your target. Standard around the world."
2. **Wedges and rings.** Highlight one wedge end-to-end (e.g., the 20 wedge from bullseye outward). Caption: "Each wedge has the same number value, but different rings on it score differently."
3. **Singles.** Highlight the inner and outer single regions of all wedges. Caption: "The big body of a wedge is a single — face value × 1. A single 20 = 20 points."
4. **Doubles.** Highlight the outer thin ring of all wedges. Caption: "The thin outer ring is the double — face value × 2. A double 20 = 40 points. **Important — you'll need this in a moment.**"
5. **Triples.** Highlight the inner thin ring of all wedges. Caption: "The thin inner ring is the triple — face value × 3. A triple 20 = 60 points. **The highest single-dart score is triple 20.**"
6. **The bullseye.** Highlight the bullseye. Caption: "Outer bull = 25 points. Inner bull (double bull) = 50 points. **Double bull counts as a double** for checkout purposes."
7. **x01 scoring.** Caption: "You start each leg at a target score (101, 201, 301, etc.). Every dart subtracts its score from your remaining. Get to exactly 0 to win the leg."
8. **The doubles rule.** Caption: "There's a catch — your **last dart** has to land on a **double** (or the double bull). Hitting 0 with anything else = **bust**. Going below 0 = **bust**. Leaving 1 remaining = **bust** (because no double sums to 1)." Bold the bust conditions.
9. **The doubles drill (interactive — Section 7d).** "Try it: you have 32 remaining. Which dart wins the leg?" — three buttons: "Double 16", "Single 16", "Triple 10 + Double 1". Click the correct one (Double 16 = 32) for a green confirmation. Click wrong for a brief "Not quite — remember the dart must be a double" with explanation.
10. **End.** "That's the basics. The game throws scoring modifiers and dart customization on top, but the throwing and counting always work this way." Close button.

All slide text exported via `@export var rules_slides: Array[Dictionary]` so Max can edit slide content in the inspector. Each slide entry: `{title, body, illustration_path (optional), board_highlight: Dictionary (optional)}`.

### 7c. Dartboard tutorial highlight mode

Reuses the existing `set_picker_mode` infrastructure conceptually but adds a new method specifically for tutorial highlighting that doesn't activate click handlers. New methods on `dartboard.gd`:

- `func set_tutorial_highlight(highlights: Array[Dictionary]) -> void` — takes a list of highlight specs:
  - `{type: "all_wedges_ring", ring_name: "Triple"}` — highlight that ring on every wedge.
  - `{type: "single_wedge_all", wedge_index: 0}` — highlight every ring of a single wedge.
  - `{type: "single_segment", wedge_index: 0, ring_name: "Triple"}` — highlight one specific segment.
  - `{type: "bullseye", which: "inner"|"outer"|"both"}` — highlight bullseye region(s).
- `func clear_tutorial_highlight() -> void` — removes all tutorial highlights.
- Drawing logic reuses the existing `_draw_segment` and `_draw_full_wedge_highlight` helpers with a new color: `@export var tutorial_highlight_color: Color = Color(1.0, 0.85, 0.2, 0.4)` and `@export var tutorial_highlight_border_color: Color = Color(1.0, 1.0, 1.0, 0.7)`. Bright and distinct from hover/picker highlights so it's unmistakable as "the slideshow is pointing at this."

### 7d. The doubles drill

Implemented as a special slide type — `{type: "drill", question, options, correct_index}`. Renders as a panel with the question text and three buttons. Click the correct → green checkmark + "Correct! 32 = double 16. Next slide →." Click wrong → red border on the wrong button + a small explanation appears, but the player must click the correct answer to advance. No high score, no consequence — this is a comprehension check, not a quiz.

V1 ships with one drill (the 32 = D16 question). Future expansions could add more drill slides (busting scenarios, harder checkouts).

### 7e. Where it's accessible

- A "Rules of Darts" button on the Start Screen (Section 1a).
- A "Rules" button on the Assembly Screen.
- Optional: in-game HUD "?" menu. Defer.

---

## 8. First-Run Trigger + Settings Persistence

A soft prompt on first launch: "Welcome — looks like this is your first time. Want a walkthrough?" with two buttons: "Yes, show me" (→ Mechanics Tutorial) and "No thanks, I'll figure it out" (→ Start Screen).

### 8a. Persistence

A small settings file persisted to `user://settings.cfg` via Godot's `ConfigFile` API.

- `[tutorial]` section with `has_seen_welcome: bool` (default false).
- Helper script: `scripts/settings_store.gd` (singleton via `class_name SettingsStore extends RefCounted` plus a static accessor, or registered as an autoload).
- `SettingsStore.get_tutorial_seen() -> bool` and `SettingsStore.set_tutorial_seen(value: bool) -> void`.

Future settings (audio levels, control prefs, the H meter zone bands toggle, the live scatter preview toggle) live in the same file.

### 8b. Welcome prompt

On launch, after `main.gd::_ready()` initializes everything but before showing the Start Screen, check `SettingsStore.get_tutorial_seen()`:

- If false → show the Welcome modal. Player picks. Either choice sets `has_seen_welcome = true`. "Yes" routes to Mechanics Tutorial; "No" routes to Start Screen.
- If true → show Start Screen directly.

Welcome modal is its own small `Control` overlay (`scripts/welcome_modal.gd`). All text and colors exported.

### 8c. Manual reset for testing

`@export var debug_reset_tutorial_seen: bool = false` on `main.gd`. When true, resets the flag at startup so Max can re-test the first-run experience. (Toggleable from the inspector — typical Max workflow.)

---

## Implementation Notes

- **Static typing throughout** per project conventions. Every `var`, every function parameter, every return.
- **Frequent commenting** per project conventions — especially on the tutorial beat sequence builders (the captions and beat order are themselves the design, and should be readable to non-coders).
- **All tunable values exported with `##` hover descriptions** per project conventions. This spec calls out exports per section, but the rule is universal — UI positions, colors, fonts, font sizes, animation durations, callout dimensions, all of it.
- **Beat strings as exported `Dictionary` of keyed entries** rather than inline string literals. Max edits captions in the inspector without code changes — same pattern as the existing checkout helper's `checkout_toggle_hint`.
- **No new scoring, no new game logic.** This spec is pure UX/onboarding. The throw mechanic gets new *hooks* (pause, force-lock, signal) but no behavior changes outside tutorial mode. The dartboard gets new *highlight modes* but no scoring changes. `x01_game.gd` and `scoring_modifier_manager.gd` are untouched.
- **Sandbox tutorial does not initialize `x01_game`.** A clean separation so the tutorial can't accidentally affect run state.
- **Scene tree additions:**
  - `Main/HUD/StartScreen` — new (`start_screen.gd`).
  - `Main/HUD/WelcomeModal` — new (`welcome_modal.gd`).
  - `Main/HUD/StatsReferencePanel` — new (`stats_reference_panel.gd`).
  - `Main/HUD/RulesSlideshow` — new (`rules_slideshow.gd`).
  - `Main/HUD/TutorialCalloutLayer` — new (`tutorial_callout.gd`), parent of active callouts during tutorial.
  - `Main/TutorialController` — new (`tutorial_controller.gd`), Node.
  - `Main/GhostDartLayer` — new (`ghost_dart_layer.gd`), Node2D, sibling of DartContainer.
- **No new dependencies on external libraries.** Pure Godot 4 GDScript.
- **The TutorialController owns the active tutorial state** (which beat is current, which sub-tutorial is running). `main.gd` queries it via `tutorial_controller.is_active()` to decide whether to show normal HUD elements or hide them.

---

## Phasing Recommendation

If one Claude Code pass is too large, the suggested MVP cut for "ship to friends" is:

**Phase A (MVP — required to ship to friends):**

- Section 1 (Start Screen)
- Section 2 (Mechanics Tutorial)
- Section 3 (Ghost-Dart Scatter Preview — at minimum the tutorial-triggered version; the always-on toggle can defer)
- Section 7 (Rules of Darts)
- Section 8 (First-Run Trigger)

**Phase B (polish — can ship slightly later):**

- Section 4 (Meter Zone Bands) — nice-to-have, but the Mechanics Tutorial teaches the zones implicitly via freeze beats. Bands are a permanent visual aid for repeat play, not strictly required for first-time comprehension.
- Section 5 (Assembly Tutorial) — friends doing a one-leg demo may not need the assembly walkthrough; defaulting to a sensible pre-built dart and skipping assembly initially is a viable workaround if needed.
- Section 6 (Stats Reference) — useful but the existing hover tooltips (`STAT_DESCRIPTIONS` in `hud.gd`) are a sufficient stopgap. Promote to the dedicated panel once playtest confirms they're not enough.

If shipping all eight at once, the build order should still start with the new infrastructure (StartScreen, SettingsStore, TutorialCallout, GhostDartLayer, throw_mechanic hooks) before the content layers (beat sequences, slideshow slides) — those are easier to iterate on once the scaffolding works.

---

## Deferred / Out of Scope

- **Form / throw-style tutorial.** Form system isn't implemented yet (Phase 8). When it ships, it'll need its own tutorial beat — likely a small addition to the Mechanics Tutorial, or a new sub-tutorial entered from the Form select screen.
- **Modifier mechanics tutorial.** No dedicated walkthrough for what scoring modifiers do, how locking works, how the checkout helper reads modifier state. The first time the player picks a modifier post-leg, the existing modifier tooltips and the checkout helper's behavior should suffice. Add a dedicated walkthrough if playtest shows new players are bouncing off modifier complexity.
- **Shop tutorial.** Same logic — the shop has its own UI affordances (lit spots, hover tooltips). If new players don't get it, add a small one-time popover on first shop entry. Out of scope for this pass.
- **Always-on V meter zone bands.** Section 4 ships H-only by default. Add V bands if playtest shows they help.
- **Multi-question rules drills.** Section 7 ships one drill (32 = D16). More drills (bust scenarios, awkward remainders) are easy to add later via the same `{type: "drill"}` slide format.
- **Tutorial localization.** All strings are English-only for now, but the export-everything pattern means a future localization pass can swap dictionaries cleanly.
- **Accessibility (text size, colorblind palette, controller input).** All separate concerns. The export-everything pattern keeps the door open; no in-spec work required now.
- **In-game "?" menu** — a contextual help button on the active-game HUD that surfaces Stats Reference / Rules of Darts mid-run. Could be added later; for now those references are accessible from Assembly between legs.

---

## Key Design Decisions (for the archive)

- **Three concerns kept separate**: mechanics tutorial, rules of darts, assembly tutorial. Mixing them was rejected — different players need different subsets, and cognitive load on a "full" tutorial would be too high.
- **3-throw demo → guided → free structure** for the Mechanics Tutorial. Shorter (1 throw) is "look at this" not "you did this." Longer (5+ throws) overstays welcome. Three is the sweet spot: demonstrate, attempt, internalize.
- **Sandbox mode, not first-leg-of-real-game.** No score pressure during learning. Tutorial can let the player flub a throw without consequences. Cleaner mental model — tutorial throws are tutorial throws, real throws are real throws.
- **Ghost-dart scatter over heatmap shader** for the accuracy zone visualization. Players don't think in probability density; they think "where will my darts probably land." A scatter of 10 ghost darts says that intuitively.
- **Freeze-and-explain at three accuracy zones rather than forced-click-now prompts.** Show-then-do is gentler and more respectful of the learner than railroading their inputs. Plus you can only commit H once per throw, so a "click now in each zone" approach would require three separate throws.
- **Hybrid slideshow + one drill** for rules of darts. Pure slideshow risks zoning out on the doubles rule (the most counterintuitive part of x01). Interactive moment specifically there cements the rule via doing.
- **Single source of truth for stat descriptions** (`stat_descriptions.gd`). Assembly Tutorial, Stats Reference, and the existing in-game hover tooltips all pull from one place. Avoids three-way drift when Max tunes wording.
- **First-run soft prompt, not forced tutorial.** Respect that some friends will be game-mechanics-literate even if they're new to *this* game. "Want a walkthrough?" with an honest "no thanks" path.
- **Tutorial state lives in a dedicated controller, not main.gd.** `main.gd` is already orchestrating x01, modifiers, shop, assembly, upgrade picks. Adding tutorial state would push it past readability. The TutorialController is a small, self-contained node that main.gd queries when relevant.

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
