# Active Spec — Modifier Icon Language, Streak Section, & Color Streak Split

*Spec date: 2026-05-23.* Item-presentation tightening pass. Replaces the flat rarity-tinted squares in the modifier panel with category-aware shape icons, adds a dedicated runtime streak status section to the HUD, splits the single generic Color Streak modifier into four per-color variants that share the COLOR slot, and simplifies Wedge Streak (drops the leniency axis, surfaces the streaked wedge value in the display).

## Goals

1. **A consistent visual language for modifier items** that conveys category at a glance (color / parity / wedge) without forcing the player to read text on every relic square. Shape encodes category, fill/outline color encode the specifics, rarity is always the outermost ring.
2. **Persistent, explicit streak feedback.** Streaks are mechanically central to the game's late-run scoring (grouping is a real darts virtue) but currently only surface during target-tooltip hovers. A dedicated streak strip above the dart pips makes the player aware of what they're maintaining, what they've lost, and what they could still build.
3. **Structural separation of Bonus vs Streak modifiers.** Bonuses live in the modifier relic panel (visual-only "I own this" representation). Streak modifiers also appear in the relic panel but additionally get a runtime status line in the new streak section. The streak section explicitly labels them as streaks — the relic panel does not — so location does the bonus/streak disambiguation work, not a glyph variant.
4. **Color Streak granularity.** The current single `ColorStreakModifier` rewards "consecutive same-color hits" regardless of which color the streak forms on, which dilutes both the player's read of the streak and the rarity tuning. Split into four per-color variants (Red / Green / Black / White Streak) following the existing `ColorBonusModifier` "one class, target_color rolled at generation" pattern. Existing one-per-category COLOR slot rule still caps the player at one active color streak at a time.
5. **Wedge Streak simplification.** Drop the leniency axis (was being used by rarity); rarity now drives scope only, like the other streaks. Always WHOLE_WEDGE matching: any ring on the same numbered wedge counts. Surface the currently-tracked wedge value in the streak display (`20 Wedge Streak (per leg): x2` → switches to `5 Wedge Streak (per leg): x1` when the player breaks 20 by hitting a 5).
6. **Relic vs Board Mutation classification.** Introduce an explicit `ModifierKind` distinction. RELIC modifiers (Color Bonus, Color Streak, Even/Odd Bonus, Even/Odd Streak, Wedge Streak) live in the modifier panel and have icons. BOARD_MUTATION modifiers (Wedge Value, Wedge Swap, Color Flip) are one-time effects that mutate the dartboard at acquisition and then *disappear from the inventory* — the board itself becomes the receipt. They never get icons because they never appear in panel UI. Reduces visual noise and matches player mental model: "what's actively scoring for me?" (panel) vs "what does the board look like?" (the board).

## Non-Goals

- Not changing scoring math (apart from making the per-hit multiplier scale an exported var per streak type).
- Not changing slot system or rarity weights.
- Not changing the upgrade pick card layout, only the small icon shown on it (if room).
- Not redesigning the shop hover or tooltip UI.

---

## Modifier Kind Classification

Add a new enum to `scoring_enums.gd`:

```gdscript
## Whether a modifier persists in the player's inventory (relic panel) or
## is a one-time effect that mutates the board and then disappears.
enum ModifierKind {
    RELIC,           ## Persistent — shown in modifier panel, has an icon, contributes to live scoring per dart.
    BOARD_MUTATION,  ## One-time — applied at acquisition (or after a wedge/color picker), no panel presence afterward.
                     ## The board itself reflects the change (effective wedge values / segment colors).
}
```

Add to `ScoringModifier` base class:

```gdscript
## Whether this modifier appears in the HUD modifier panel after acquisition.
## RELIC modifiers persist as inventory items. BOARD_MUTATION modifiers fire
## once and then leave only their effect on the board, not a relic square.
@export var kind: ScoringEnums.ModifierKind = ScoringEnums.ModifierKind.RELIC
```

Default is RELIC (matches existing behavior for most modifiers). Subclasses override:

| Modifier | Kind |
|----------|------|
| ColorBonusModifier | RELIC |
| ColorStreakModifier | RELIC |
| OddEvenBonusModifier | RELIC |
| EvenStreakModifier / OddStreakModifier | RELIC |
| StreakBonusModifier (Wedge Streak) | RELIC |
| WedgeValueModifier | BOARD_MUTATION |
| WedgeSwapModifier | BOARD_MUTATION |
| ColorFlipModifier | BOARD_MUTATION |

`hud.gd::add_modifier_to_panel()` gates on `kind == RELIC` — BOARD_MUTATION modifiers early-return without creating a relic square. They still go through the manager's `add_modifier(...)` for state tracking and effect application, but they never show up in the relic bar.

This means **BOARD_MUTATION modifiers don't need icons** — they never appear in any icon-rendering surface (panel or streak section). The icon system only handles RELIC modifiers.

---

## Visual Language

### Category Shapes (RELIC modifiers only)

| Category | Base Shape | Why |
|----------|------------|-----|
| Color | Circle | Round = "ball of color." Fill = target color. |
| Parity (Even) | Square | Even = "level / regular." Reinforced by red outline. |
| Parity (Odd) | Triangle | Odd = "pointed / off." Reinforced by green outline. |
| Wedge | Pie slice / sector | Direct semantic link to a dartboard wedge. |

The shape carries the *category*. Within a category, the fill and inner outline carry the *specifics* (which color, which parity), and rarity is always the *outermost* ring.

### Outline Rules

- **Color modifiers (Color Bonus, per-color Streaks):** ONE outline = rarity. The fill color *is* the category-specific information; an inner category outline would be redundant.
- **Parity modifiers (Even/Odd Bonus, Even/Odd Streak):** TWO outlines. Inner outline = category color (red for even, green for odd). Outer outline = rarity color. Both should be visible at panel size.
- **Wedge Streak:** ONE outline = rarity. Filled with a neutral dark color, since the player reads the streaked-wedge value from the streak section text, not the icon fill.

### Per-Modifier Specifics

| Modifier | Shape | Fill | Inner Outline | Outer Outline |
|----------|-------|------|---------------|---------------|
| Color Bonus (Red/Green/Black/White) | Circle | target color | — | rarity |
| Red/Green/Black/White Streak | Circle | target color | — | rarity |
| Even Bonus | Square | dark neutral | red | rarity |
| Odd Bonus | Triangle | dark neutral | green | rarity |
| Even Streak | Square | dark neutral | red | rarity |
| Odd Streak | Triangle | dark neutral | green | rarity |
| Wedge Streak | Sector | dark neutral | — | rarity |

Bonus vs Streak is **not** distinguished visually within a category — the player tells them apart by where they appear (relic bar for "owned" status, streak strip for live streak state) and by the modifier name on hover. BOARD_MUTATION modifiers (Wedge Value, Wedge Swap, Color Flip) don't appear in this table — they have no icons and no panel presence.

### Sizes

Three render sizes, all driven by exported vars:

- **Relic-bar size** (`modifier_square_size`, currently `40px`) — full-size on the HUD modifier panel.
- **Streak-line icon size** (`streak_icon_size`, new, default `20px`) — smaller inline icon at the start of each streak section line.
- **Pick-card icon size** (`pick_card_icon_size`, new, default `28px`) — medium icon shown on upgrade/shop modifier pick cards. Optional this pass — see Deferred.

---

## Streak Section in HUD

### Position & Layout

A new `StreakSection` VBoxContainer added to the HUD scene tree, positioned **above** `DartIndicator` and **below** `TurnScoreLabel`. Visible only when at least one streak modifier is owned. Vertically grows with the number of owned streaks (max 3, gated by the one-per-category slot rule: WEDGE + COLOR + PARITY).

```
HUD (CanvasLayer)
├── ... existing labels ...
├── TurnScoreLabel
├── StreakSection (VBoxContainer)   ← NEW
│   ├── StreakLine (HBoxContainer)  ← one per owned streak modifier
│   │   ├── StreakIcon (ModifierIcon)   ← small shape icon
│   │   ├── StreakNameLabel (Label)     ← e.g. "Red Streak" or "20 Wedge Streak"
│   │   ├── StreakScopeLabel (Label)    ← "(per leg)", rarity-colored
│   │   └── StreakCountLabel (Label)    ← ": x2"
│   ├── ... up to 3 ...
├── DartIndicator
└── ... rest of HUD ...
```

### Display Format

`[Icon] [Name] [(per scope)] [: xN]`

- **Icon:** small (`streak_icon_size`) version of the modifier's shape icon (same drawing helper, scaled down). Color/outline rules identical to the relic-bar version.
- **Name:** the modifier's `modifier_name`. For Wedge Streak, prepend the current streaked wedge value: `"%d %s" % [face_value, modifier_name]` → `"20 Wedge Streak"`. When `_streak_wedge_index < 0` (no streak), display `"— Wedge Streak"` (em-dash placeholder).
- **(per scope):** the scope string (`"(per turn)"`, `"(per leg)"`, `"(per run)"`) — modulate color set to the modifier's `rarity_color`.
- **: xN:** the current streak count.

### Idle vs Active State

A streak with `_streak_count == 0` (owned but no live streak yet, or just reset) renders with reduced opacity (~0.5) — the line is still visible so the player remembers they own it, but it's clearly inactive. When the streak goes live (count ≥ 1), the line jumps to full opacity. Drive this via an exported `streak_idle_opacity` var.

### Update Cadence

The HUD's streak section is repopulated when:

- A streak modifier is acquired (`add_modifier_to_panel`-equivalent path also adds a streak line).
- A streak modifier is replaced (one-per-category swap): old line removed, new line added.
- A streak modifier is toggled off (unlocked modifier): line is shown but at a deeper-dimmed opacity (e.g. `streak_disabled_opacity`, default `0.3`) and prefixed with a `[OFF]` tag.
- Per-throw: after every throw, walk the owned streak modifiers and rewrite each line's count, opacity, and (for wedge streak) name. This is cheap — max 3 modifiers.
- New run: clear the section entirely.

### Where the Update Hook Lives

Add a `hud.update_streak_section(active_streak_modifiers: Array)` method called from `main.gd`'s post-throw pipeline, right after `scoring_modifier_manager.process_score(...)` and before the existing `set_modifier_perkup(...)` call. `main.gd` already has access to the modifier manager and can pull the active modifiers list.

---

## Color Streak Split

### Behavior Change

The current `ColorStreakModifier` rewards consecutive *same-color* hits without caring what that color is. Hit red → red → red = streak. Hit green → green = streak. Hit red → green = streak resets.

New behavior: each Color Streak instance has a **fixed target color** rolled at generation. A Red Streak only counts red hits, etc. Same architecture as `ColorBonusModifier`.

### Code Changes to `color_streak_modifier.gd`

- Add `@export var target_color: ScoringEnums.SegmentColor = ScoringEnums.SegmentColor.RED` with a `##` doc comment.
- Drop `_streak_color: int` — the target color is now fixed at generation, no need to track which color the streak is "on" (it's always `target_color`). Only track `_streak_count`.
- Rewrite `apply()`:
  - If `segment_color == target_color`, increment streak.
  - If `segment_color != target_color` OR no segment (off-board), reset streak.
- Update `generate(rarity_tier)` to roll a random target color and bake it into `modifier_name` (e.g. `"Red Streak"`, `"Green Streak"`, `"Black Streak"`, `"White Streak"`) and description.
- Update `save_streak_state()` / `restore_streak_state_from(snapshot)` to only persist `_streak_count` (target_color is part of the modifier, not the live state).
- Update `get_streak_display()` to return `"%s ×%d" % [color_name, _streak_count]` (no longer a generic "Color" label).

### Pool Weighting

`get_pool_weight()` currently returns `15` for color streak. With four flavors competing for the same slot, the *effective* color-streak appearance rate would quadruple if we kept `15` per flavor. To keep total color-streak prevalence steady, set `get_pool_weight()` to `4` (so the four together sum to ~16, near the original 15). Color is chosen uniformly within the color-streak pool: each of red / green / black / white has equal odds when a color streak is rolled.

**Why uniform, not weighted by streak difficulty.** Black/white are easier to streak (almost any wedge counts) and red/green are harder (require doubles/triples/bullseye), but those streak-difficulty differences are not the same as "modifier power" differences. The trade-offs cut multiple ways:

- Doubles and triples score far more per dart than singles, so a red/green streak is *fewer hits but more raw score per hit*. Black/white streaks are *more hits but lower individual scores*.
- Synergy with the player's other modifiers, build, and target-selection plans matter more than the bare streak rate.
- Lock/unlock status and rarity scope (per turn / leg / run) already provide several independent variation axes that affect each flavor's effective power.

For these reasons the spec deliberately does **not** introduce per-color weighting on the color-streak roll. Revisit only if playtest shows one or two color flavors are dominantly best or worst across every build configuration.

### Backward Compatibility

If any saved `ColorStreakModifier` resources or `debug_modifiers` array entries reference the old "generic any-color" behavior, those resources need a `target_color` default. The `@export var target_color = RED` default handles this — old resources load as Red Streaks by default. No save-format breakage (this is a runtime-generated modifier system, not a persisted-across-runs system at this point).

---

## Wedge Streak Simplification

### Behavior Change

- Drop the `leniency` axis. Always WHOLE_WEDGE — any ring on the same numbered wedge counts (D20 → S20 → T20 → S20 all streak).
- Rarity now drives scope only (turn/leg/run), like the other streaks.
- The streaked wedge value (face value of `_streak_wedge_index`) is surfaced in the streak section display.

### Code Changes to `streak_bonus_modifier.gd`

- Remove `@export var leniency`.
- Remove `_streak_ring: String` from state (no longer needed without leniency).
- Remove `_ring_name_to_zone()` helper.
- Simplify `_is_qualifying_hit(wedge_index)` to `return wedge_index == _streak_wedge_index`.
- Drop the leniency branch in `generate()`. Each rarity tier just sets `streak_scope`.
- Add `@export var bonus_per_hit: int = 2` with a `##` doc comment explaining: "Multiplier added per consecutive same-wedge hit. Default 2 because grouping (consecutive same-wedge throws) is significantly harder than streaking color or parity — most consecutive-wedge attempts are skill plays."
- Apply: `result["multiplier"] += bonus_per_hit` per accumulated bonus (loop replaced with `multiplier += effective_count * bonus_per_hit`-equivalent — make sure `_track_modification` still records the change).
- Update `modifier_name` to just `"Wedge Streak"` (no leniency suffix).
- Update `get_streak_display()` to return `"Wedge ×%d" % _streak_count` (leniency label removed). The "20 Wedge Streak" wedge-value prefix is composed in the new streak section, not inside the modifier.
- `save_streak_state()` / `restore_streak_state_from()`: drop the `"ring"` key. Keep `"wedge_index"` and `"count"`.

### Parity / Color bonus_per_hit

Add the same `@export var bonus_per_hit: int` to:
- `parity_streak_modifier.gd` — default `1`.
- `color_streak_modifier.gd` — default `1`.

Update each one's `apply()` to multiply the bonus by `bonus_per_hit` instead of always `+1`. Gives Max one-stop tuning for streak power balance from the inspector.

### Wedge Value Display in Streak Section

The streak section needs the face value, not the wedge index. The modifier knows its `_streak_wedge_index`. The dartboard knows the wedge order. Two options:

1. The streak modifier holds a reference to `scoring_modifier_manager.effective_wedge_values` and looks up `effective_wedge_values[_streak_wedge_index]` on demand. **Preferred** — it picks up any active Wedge Swap or Wedge Value modifications, so the display reads `20 Wedge Streak` even if the player has swapped 20 with another wedge. Source of truth = effective values, consistent with "the board renders effective values" principle.
2. The HUD looks up the value when rendering. Same lookup, just lives in the HUD instead of the modifier.

Go with option 2 — keeps modifiers ignorant of the manager. `hud.update_streak_section(active_streak_modifiers, effective_wedge_values)` receives the lookup table.

### Open Question — bonus math change

Bumping wedge streak from `+1x` to `+2x` per consecutive hit is a balance change. The exported var makes this trivial to revert. **Default to 2 in the spec; flag it for playtest verification before considering shipped.**

---

## ModifierIcon — New Drawing Helper

Create `scripts/modifier_icon.gd`:

```gdscript
class_name ModifierIcon
extends Control
## Custom-drawn icon for a scoring modifier. Renders the modifier's category
## shape (circle / square / triangle / sector), fill, category outline, and
## rarity outline based on a single ScoringModifier resource reference.
##
## Used by the HUD modifier panel (relic squares), the new streak section
## (small inline icons), and optionally upgrade pick cards. Same renderer,
## different sizes — see the size-related export vars below.

## The modifier resource this icon represents. Setting this triggers a redraw.
@export var modifier: Resource = null:
    set(value):
        modifier = value
        queue_redraw()

## Outline width of the rarity ring in pixels.
@export var rarity_outline_width: float = 2.0

## Outline width of the inner category ring (parity modifiers only).
@export var category_outline_width: float = 2.0

## Gap in pixels between the inner category outline and the outer rarity outline.
@export var outline_gap: float = 1.0

## Inset from the Control's bounds before drawing — leaves room for outlines.
@export var draw_inset: float = 2.0

## Color used as the neutral fill on parity and wedge shapes (no category color).
@export var neutral_fill_color: Color = Color(0.18, 0.18, 0.22)


func _draw() -> void:
    if modifier == null:
        return
    # Dispatch to category-specific shape draw, then layer outlines.
    ...
```

Implementation notes:

- `_draw()` reads the modifier's IconShape via `get_icon_shape()` to figure out which shape to draw.
- Shape draw helpers as private methods: `_draw_circle()`, `_draw_square()`, `_draw_triangle()`, `_draw_sector()`. All operate inside the Control's `size` minus `draw_inset`.
- Color-specific lookup table: map `ScoringEnums.SegmentColor` → drawn `Color`. Use the same colors as the dartboard's segment fills for consistency. Export the four colors so they can be tuned alongside the dartboard's colors.
- Rarity outline color: read from `modifier.rarity_color` (already exposed by the base ScoringModifier resource).
- Category outline (parity only): exported red / green colors. Default red for even = the dartboard's red segment color, green for odd = the dartboard's green segment color. Reinforces the visual link between "the red ring on the board is even-numbered wedges' double/triple."
- No inner glyphs in this pass. If future iterations call for stronger per-modifier visual identity, the path forward is hand-drawn art on a more focused art-direction pass — not exported font glyphs.

### Categorization Helper

To decide which shape to draw, the `ModifierIcon` needs to classify the modifier. Add an enum to `scoring_enums.gd`:

```gdscript
## Visual icon category — drives ModifierIcon's shape dispatch.
## Independent of streak_category (which controls slot rules).
## Only RELIC modifiers have an IconShape; BOARD_MUTATION modifiers
## never get rendered and don't need to override.
enum IconShape {
    NONE,           ## Default / fallback — should not appear in practice for RELIC modifiers.
    COLOR_CIRCLE,   ## Color Bonus, per-color Streak.
    EVEN_SQUARE,    ## Even Bonus, Even Streak.
    ODD_TRIANGLE,   ## Odd Bonus, Odd Streak.
    WEDGE_SECTOR,   ## Wedge Streak.
}
```

Add a virtual `get_icon_shape() -> ScoringEnums.IconShape` method to `ScoringModifier`, default returning `IconShape.NONE`. Each RELIC subclass overrides:
- `ColorBonusModifier`, `ColorStreakModifier` → `COLOR_CIRCLE`
- `OddEvenBonusModifier` → branches on `target_odd` (`ODD_TRIANGLE` or `EVEN_SQUARE`)
- `ParityStreakModifier` (and subclasses) → branches on `target_is_odd`
- `StreakBonusModifier` → `WEDGE_SECTOR`

BOARD_MUTATION subclasses (`WedgeValueModifier`, `WedgeSwapModifier`, `ColorFlipModifier`) do **not** override `get_icon_shape()` — they keep the `NONE` default and are never asked to render. The `ModifierIcon._draw()` should early-return when the modifier's kind is BOARD_MUTATION or its IconShape is NONE, as a defensive double-check.

This keeps the icon system *out* of the modifier scoring code (modifiers don't draw themselves; they just declare their shape).

---

## HUD Integration

### Modifier Panel (Relic Bar) Update

In `hud.gd::add_modifier_to_panel(modifier)`:
- **First line: early-return if `modifier.kind != ScoringEnums.ModifierKind.RELIC`** — BOARD_MUTATION modifiers (Wedge Value, Wedge Swap, Color Flip) never get a relic square. Their effect is visible on the dartboard itself.
- Replace the `Panel` + `StyleBoxFlat` background approach with a `ModifierIcon` Control as the child.
- Keep the existing `set_meta("modifier", modifier)`, `set_meta("rest_y", ...)`, click/hover handlers, and the lock indicator label overlay — all of that wraps the ModifierIcon.
- Container hierarchy per relic: `Control (slot wrapper) → ModifierIcon (the shape) + Label (lock O/X overlay)`.
- The perk-up animation tweens the wrapper Control's position, same as today.
- The disabled-state visual (currently `square.modulate = Color(0.3, 0.3, 0.3, 0.6)`) still applies to the wrapper, which dims the icon and the lock label together.

Side effects of removing BOARD_MUTATION modifiers from the panel:
- `set_modifier_perkup(triggered_names)` — currently iterates `modifier_panel.get_children()`. Since BOARD_MUTATION modifiers never made it into the panel, no functional change; they just stay out.
- Hover tooltips — only RELIC modifiers will have hover tooltips. Acceptable, since BOARD_MUTATION effects are visible on the board (effective wedge values, segment colors) — the board is its own tooltip.
- `clear_modifier_panel()` — unchanged. It just nukes the children regardless of kind.

### New `_build_streak_section()`

In `hud.gd::_ready()`, after `_build_stat_bars()` and `_build_checkout_panel()`, call `_build_streak_section()` which:
- Locates the `StreakSection` VBoxContainer added in the scene tree (between `TurnScoreLabel` and `DartIndicator`).
- Sets up an empty container and stores it.
- Adds a small title label `"— Streaks —"` matching the style of `_modifier_status_title` / `_stats_title_label`. Hidden when no streaks are owned.

### New `hud.update_streak_section(streak_modifiers, effective_wedge_values)`

- Clears existing streak lines.
- If `streak_modifiers.is_empty()`, hides the section title and returns.
- Shows the title.
- For each streak modifier:
  - Create an `HBoxContainer` line.
  - Add a `ModifierIcon` Control with `custom_minimum_size = Vector2(streak_icon_size, streak_icon_size)` and `modifier = mod`.
  - Add a Label with the name. If `mod is StreakBonusModifier` (wedge streak), compose `"%d Wedge Streak" % effective_wedge_values[mod._streak_wedge_index]` (or `"— Wedge Streak"` if `_streak_wedge_index < 0`). Other streak types: just `mod.modifier_name`.
  - Add a Label with `"(per %s)" % scope_name`, modulate set to `mod.rarity_color`.
  - Add a Label with `": x%d" % mod.get_streak_count()`.
  - Set the HBoxContainer's modulate alpha:
    - `streak_disabled_opacity` (default 0.3) if `mod.toggleable` and not `mod.enabled`.
    - `streak_idle_opacity` (default 0.5) if `mod.get_streak_count() == 0`.
    - `1.0` otherwise.
- New `@export var streak_icon_size: int = 20` on hud.gd.
- New `@export var streak_idle_opacity: float = 0.5` on hud.gd, with a `##` doc comment.
- New `@export var streak_disabled_opacity: float = 0.3` on hud.gd, with a `##` doc comment.

### Where `main.gd` Calls It

`main.gd::_on_throw_completed()` already calls into the modifier manager. After the score pipeline finishes (and before / alongside `set_modifier_perkup`), call:

```gdscript
hud.update_streak_section(
    scoring_modifier_manager.get_active_streak_modifiers(),
    scoring_modifier_manager.effective_wedge_values
)
```

Add a public `get_active_streak_modifiers() -> Array` method on `ScoringModifierManager` that filters `active_modifiers` to those whose `streak_category != NONE`. Also call `hud.update_streak_section(...)` after:
- A modifier is acquired (`add_modifier(...)` returns).
- A modifier is toggled (the existing `modifier_toggled` signal handler in `main.gd`).
- A turn / leg / run reset (where streak scopes reset).
- A new run (clears everything).

---

## Pick Card Icon (Optional / Light)

Upgrade pick cards currently display the modifier as text + rarity-tinted button. **Light touch**: add a small `ModifierIcon` (`pick_card_icon_size`, default `28px`) next to the modifier name on each card.

If layout adjustment becomes thorny, defer this — the relic bar and streak section are the primary surfaces. See Deferred.

---

## File-by-File Change List

### New Files

- `scripts/modifier_icon.gd` — `ModifierIcon extends Control`. Per the spec above.

### Modified Files

- `scripts/scoring_enums.gd`:
  - Add `ModifierKind` enum (RELIC / BOARD_MUTATION).
  - Add `IconShape` enum (NONE / COLOR_CIRCLE / EVEN_SQUARE / ODD_TRIANGLE / WEDGE_SECTOR).
  - No other changes.

- `scripts/scoring_modifier.gd`:
  - Add `@export var kind: ScoringEnums.ModifierKind = ScoringEnums.ModifierKind.RELIC` with a `##` doc comment.
  - Add virtual `get_icon_shape() -> ScoringEnums.IconShape` returning `NONE` by default.

- `scripts/modifiers/color_bonus_modifier.gd`:
  - Override `get_icon_shape() -> ScoringEnums.IconShape: return ScoringEnums.IconShape.COLOR_CIRCLE`.

- `scripts/modifiers/color_streak_modifier.gd`:
  - Add `@export var target_color: ScoringEnums.SegmentColor` (with doc comment).
  - Add `@export var bonus_per_hit: int = 1` (with doc comment).
  - Drop `_streak_color: int` (now fixed at `target_color`).
  - Rewrite `apply()` to compare against `target_color` instead of the previous-color cache.
  - Rewrite `generate()` to roll target color and bake name (`"Red Streak"` etc).
  - Override `get_icon_shape()` → `COLOR_CIRCLE`.
  - Update pool weight handling (see Pool Weighting in Color Streak Split section).

- `scripts/modifiers/even_streak_modifier.gd`, `scripts/modifiers/odd_streak_modifier.gd`, `scripts/modifiers/parity_streak_modifier.gd`:
  - Add `@export var bonus_per_hit: int = 1` on the base (`parity_streak_modifier.gd`).
  - Apply uses `bonus_per_hit` in the multiplier accumulation.
  - Override `get_icon_shape()` on `EvenStreakModifier` → `EVEN_SQUARE`; on `OddStreakModifier` → `ODD_TRIANGLE`. Base `ParityStreakModifier` returns based on `target_is_odd`.

- `scripts/modifiers/odd_even_bonus_modifier.gd`:
  - Override `get_icon_shape()` → branches on `target_odd`.

- `scripts/modifiers/streak_bonus_modifier.gd` (Wedge Streak):
  - Remove `@export var leniency`.
  - Remove `_streak_ring` from state, `_ring_name_to_zone()` from code.
  - Simplify `_is_qualifying_hit()`.
  - Add `@export var bonus_per_hit: int = 2` (with doc comment about the per-hit power being elevated vs color/parity streaks).
  - Use `bonus_per_hit` in `apply()`.
  - Update `generate()` to drop leniency rolling; rarity drives scope only.
  - Update `modifier_name` to plain `"Wedge Streak"`.
  - Override `get_icon_shape()` → `WEDGE_SECTOR`.
  - Update `save_streak_state` / `restore_streak_state_from` to drop the `"ring"` key.

- `scripts/modifiers/wedge_value_modifier.gd`, `wedge_swap_modifier.gd`, `color_flip_modifier.gd`:
  - In each `_init()` (or as the export default), set `kind = ScoringEnums.ModifierKind.BOARD_MUTATION`.
  - Do **not** override `get_icon_shape()` — they keep the `NONE` default and never render an icon.

- `scripts/scoring_modifier_manager.gd`:
  - Add `get_active_streak_modifiers() -> Array` returning modifiers whose `streak_category != NONE`.

- `scripts/hud.gd`:
  - New exports: `streak_icon_size: int`, `streak_idle_opacity: float`, `streak_disabled_opacity: float`, plus `streak_section_title_text: String = "— Streaks —"`.
  - Replace `Panel` creation in `add_modifier_to_panel()` with a wrapper `Control` containing a `ModifierIcon` + the existing lock label.
  - Update `_update_modifier_square_visual()` to set the `ModifierIcon.modifier` property and the lock label, instead of building a `StyleBoxFlat`.
  - Add `_build_streak_section()`, `update_streak_section(...)`, `_clear_streak_section()`.

- `scripts/main.gd`:
  - Call `hud.update_streak_section(...)` from:
    - `_on_throw_completed()` post-score-pipeline.
    - The `modifier_toggled` handler.
    - The `add_modifier` callback path (post-acquisition).
    - `start_new_run()` (clear / refresh).

- `scenes/main.tscn`:
  - Add `StreakSection` VBoxContainer to the HUD CanvasLayer, positioned between `TurnScoreLabel` and `DartIndicator`. Set `visible = false` initially.

---

## Exported Var Summary

Newly exposed for inspector tuning (all with `##` doc comments per project conventions):

| Var | File | Default | Purpose |
|-----|------|---------|---------|
| `target_color` | `color_streak_modifier.gd` | `SegmentColor.RED` | Which color this streak instance tracks. |
| `bonus_per_hit` | `color_streak_modifier.gd` | `1` | Multiplier added per consecutive same-color hit. |
| `bonus_per_hit` | `parity_streak_modifier.gd` | `1` | Multiplier added per consecutive same-parity hit. |
| `bonus_per_hit` | `streak_bonus_modifier.gd` | `2` | Multiplier added per consecutive same-wedge hit. Higher than parity/color because grouping is harder. |
| `streak_icon_size` | `hud.gd` | `20` | Pixel size of the small icon in each streak section line. |
| `streak_idle_opacity` | `hud.gd` | `0.5` | Alpha applied to a streak line when count is 0 (owned but no live streak). |
| `streak_disabled_opacity` | `hud.gd` | `0.3` | Alpha applied to a streak line when the modifier is unlocked and toggled off. |
| `streak_section_title_text` | `hud.gd` | `"— Streaks —"` | Title shown above the streak section when at least one streak is owned. |
| `rarity_outline_width` | `modifier_icon.gd` | `2.0` | Pixel width of the outer rarity ring. |
| `category_outline_width` | `modifier_icon.gd` | `2.0` | Pixel width of the inner category ring (parity only). |
| `outline_gap` | `modifier_icon.gd` | `1.0` | Pixel gap between inner category outline and outer rarity outline. |
| `draw_inset` | `modifier_icon.gd` | `2.0` | Pixel inset from the Control bounds; leaves room for outlines. |
| `neutral_fill_color` | `modifier_icon.gd` | `Color(0.18, 0.18, 0.22)` | Fill for parity/wedge shapes (where the fill color isn't category-defined). |

Plus optional exports for the four `SegmentColor → Color` lookup values (red / green / black / white) on `modifier_icon.gd`, defaulting to the dartboard's actual segment colors. Lets Max tweak the icon palette in lockstep with the board.

---

## Open Questions Resolved in This Pass

- **Streak modifier identity.** Color Streak is now four discrete items, each clearly labeled by which color it tracks. Player decision-space goes from "do I take color streak" to "do I take *this color's* streak given my current build and rarity scope."
- **Wedge streak balance lever.** Bumping per-hit multiplier from `+1x` to `+2x` reflects the much harder skill curve of streaking a specific wedge vs streaking by color/parity. Behind an exported var so playtest can dial it.
- **Visual category encoding.** Shape + color + outline now communicate "this modifier is a {color, parity, wedge} thing" without text. Reduces text-reading cost in the relic bar.
- **Streak feedback explicit.** Players can now see streak state at all times, not just on tooltip hover.
- **Relic vs Board Mutation distinction.** Explicit `ModifierKind` enum cleans up the "do I get an icon?" question. One-time board-changing modifiers (Wedge Value, Wedge Swap, Color Flip) do not appear in the modifier panel and do not need icons — the board itself is their receipt.
- **Color streak pool weighting.** Uniform 1/4 each for red / green / black / white. Black/white score less per hit, red/green score more but are harder to streak — trade-offs are bidirectional and synergy + lock/rarity provide enough variation axes. Revisit only if playtest shows dominance.

## Open Questions Still Floating (Not For This Pass)

- **Wedge value display source of truth.** Currently the new streak section pulls `effective_wedge_values` from the manager. If/when the Wedge Value modifier system grows (e.g., per-throw temporary value changes), this lookup may need to be a snapshot-at-streak-start rather than always-current.
- **Stacking implications.** Splitting color streak doesn't change the slot rule (still one per COLOR slot). But: if rule modifiers ever let the player exceed slot caps, the per-color split is now more impactful (four red streaks would never make sense — they'd just be one). Worth keeping in mind for the rule-modifier category design.
- **Where does the player see what board mutations are active?** With BOARD_MUTATION modifiers out of the panel, the board itself is the only visible record. For Wedge Value the board's modified-number rendering already covers it. For Color Flip the segment colors carry it. For Wedge Swap the swapped numbers carry it. If a future modifier (or stacked board mutations) makes "why is the board like this?" hard to answer, consider an "Active Board Effects" inspect-only list — outside this pass's scope.

## Deferred From This Pass

- **Pick-card icons.** If layout fights us during implementation, defer the icon on the upgrade/shop pick buttons. The relic bar and streak section are the primary read surfaces.
- **Streak-line entry animation.** When a streak ticks from x0 to x1, the line could fade-in / pulse to draw attention. Spec calls for a static opacity flip; animation is polish, do later.
- **Streak-line "broken!" feedback.** When the player breaks a streak (e.g. has Red Streak x3, hits a black wedge → reset), no special call-out. Could later add a brief flash / shake on the affected line.
- **Refactor of shared shape-drawing helpers.** `dartboard.gd`, `assembly_screen.gd`, and `rules_slideshow.gd` all draw board geometry separately. The new `modifier_icon.gd` adds a fourth shape-drawing site. Could consolidate into a `DartboardGeometry` helper (already noted as a deferred refactor in the tutorial spec).

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
