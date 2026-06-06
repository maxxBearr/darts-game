---
Spec date: 2026-06-05
Status: BUILT (Claude Code, 2026-06-06). The **event-node slice of Phase 03**. Design resolved in a Cowork
  sparring session (Max + Claude, 2026-06-05). Shipped: the EVENT route + _enter_event (accuracy swing via
  EventRewards + the section ramp; brush via the BRUSH-filtered modifier draw with the availability fallback),
  removal of the per-leg free pick, the EventFamilyIcons scaffold, the challenge family edit (BRUSH dropped →
  [SCORING, PLACEMENT]), and tests/test_events.gd (52024 checks; realized rarity distribution matches the ramp).
  The rest of Phase 03 (typed-shop-ring rework + the codex) is deferred to later Phase-03 slices.
Part of: the Map Program (`specs/map/00-overview.md`), Phase 03 (typed shop + codex; this is its events portion).
Depends on: **`01-substrate-slice3-impl.md` (build that first)** — events are placed *inline* inside the new
  multi-node branch runs, so they need the longer, branch-rich paths to exist. Also reuses the slice-1 EVENT enum
  slot (`MapNode.Type.EVENT`, currently routed to the leg stub in `_on_map_node_chosen`) and the existing
  accuracy-trade machinery (`UPGRADE_TYPES` / `_apply_upgrade`, `scripts/main.gd`).
---

# Phase 03 (events slice) — Event Nodes (impl)

> **Reward paths at launch:** **accuracy** uses the diagonal swing table in §3; **brush** uses the modifier-pool
> draw in §2 (not the swing table — that table is accuracy-stat-specific). Both roll rarity off the §3 section ramp.

## 0. One-line thesis

An **inline map node that grants a free upgrade** — the player picks **1 of 3 options within a single item family**
(the family the node's icon advertises, chosen by *routing* to it). Events **replace the old free post-leg accuracy
pick**: that drip moves off "every leg" and onto these scarcer, weightier nodes, where the reward is a bigger
**diagonal swing** (real `+` for a real `−`) instead of a near-net-zero reshape. Free is safe because **every event
reward is a trade**, and a trade deepens a build commitment rather than climbing power (the accuracy-as-shape thesis
generalized).

---

## 1. The locked model (resolved this session)

1. **The organizing rule: trades are free (events); flats are earned (shop / challenge).** A trade is self-limiting
   (its `−` governs its `+`), so giving it away can't power-creep. A flat is a pure climb, so it must cost darts
   (shop) or skill (challenge). This is *why* events can be free — a property of the item, not an arbitrary call.
   **Event reward pool = trade-shaped families only.** *Any* family is eligible **once it is trade-shaped**.
   Trade-shaped *now*: **accuracy** (stat redistribution) and **brush** (a color-for-color swap — zero-sum board
   real estate: painting a ring one color costs the old color's representation, and color drives color-streak
   builds, so it's build-defining on some paths and skippable on others — ideal event variance). Trade-shaped
   *later*: **geometry** (inherently a reshape — `[[project-geometry-items]]`). **Not yet a trade:** the pure-flat
   board families (**Scoring / Hotspot**) — eligible only after a "make-it-a-trade" retrofit (e.g. a hotspot that
   draws energy from its neighbours); until then a free flat would out-class the shop and challenge (§1.2). Icons
   are scaffolded for *all* families now (§2); content unlocks per family as it becomes a trade.
2. **Three earned/free surfaces, re-differentiated** so none goes limp:
   - **Event** — *free* typed trade; family chosen by **routing** (steer toward the icon). Control = navigation.
   - **Shop** — typed item bought with **darts**; you see the offer and pick. Control = currency (at a survivability
     cost — darts spent are darts not banked for bailout).
   - **Challenge** — typed **flat / board** item whose **rarity is earned by skill** (the precision race). The
     premium tier; also a bet on *self-knowledge* (read whether you can clear it; skip cleanly if not).
   Ascending control/quality: **routing < currency < skill.** **Events and challenges never share a family** —
   challenges reward only the high-impact *flat* board families (**Scoring + Placement**), events reward only
   *trades* (accuracy, brush, geometry-later). So there's no same-family rarity ceiling to enforce: the challenge is
   the skill-tier source of high-impact flats, the event is the free source of self-limiting trades, the shop bridges
   both (buys either, for darts). **Required Phase-02 edit:** drop `BRUSH` from `_roll_challenge_node`'s family list
   (it's now a *trade*, so it lives at events, not on the earned surface) → challenge families become
   `[SCORING, PLACEMENT]`. `_generate_challenge_reward_picks`'s empty-brush fallback can then also go.
3. **Inline placement.** Events sit *in* a branch run, not on a one-node fork. Agency is the **branch choice** (one
   run packs the event, the parallel run packs something else), per `01-substrate-slice3-impl.md` §1.4. No dart cost
   and no fork — the opportunity cost is purely spatial (the forgone parallel run's banked darts / other specials).
4. **No bank interaction.** Events never deposit, charge, or refund darts. Shop + challenge already tax the bank;
   a third sink would over-strain it. The friction is the *trade itself* + the spatial opportunity cost.
5. **Per-leg free pick is removed.** `_show_accuracy_pick` no longer fires after a normal leg (§5). Scarcer picks
   make each one matter — which is exactly why the event reward is a bigger swing (§3) and not the old reshape.
6. **Three options, one family.** Routing picked the family; the player picks the *shape* — 3 distinct stat-axis
   trades within that family, each with its own rolled rarity (§3). Sculpting-lite.

---

## 2. Family axis + the icon scaffold

Events are **typed by family**, shown as an **icon on the map node** (a bullseye = accuracy), the *same* glyph the
typed shop ring will use — built once, shared. The map shows the family (type-level info); the 3 concrete options
are revealed on arrival (the substrate "type on map, params on arrival" rule).

The event family axis spans two underlying taxonomies, so it gets its **own id** rather than overloading
`ScoringEnums.Family`. **Icons are scaffolded for every family now** (placeholder basic shapes, exactly like the
relics' first-pass icons); the `active` column gates which families the generator may actually *roll* as a reward —
a family flips to active only once it is trade-shaped (§1.1):

| Event family | Active? | Grant path | Maps to |
|---|---|---|---|
| `&"accuracy"` | **yes** | stat-upgrade (`UPGRADE_TYPES` + `_apply_upgrade`) with the swing table (§3) | throw-stat trades |
| `&"brush"` | **yes** | `ScoringModifier` draw (reuse `_generate_challenge_reward_picks`, BRUSH-filtered) at a rarity rolled off the §3 section ramp | `ScoringEnums.Family.BRUSH` — a color-for-color trade |
| `&"geometry"` | later | `ScoringModifier` draw | `Family.PLACEMENT` trades, once geometry items exist |
| `&"scoring"` | later | `ScoringModifier` draw | `Family.SCORING` — **only after** a make-it-a-trade retrofit (else it's a free flat) |

Two grant paths are live at launch: **accuracy** (the swing table, §3) and **brush** (the modifier-pool draw — same
family-filtered pick the challenge reward uses, but rarity comes from the §3 event ramp, not finish-efficiency). So
events render *two* distinct glyphs from day one (bullseye + brush), which softens the single-family samey-ness.

**Brush availability:** primarily handled by slice 3's **incremental per-act generation**
(`01-substrate-slice3-impl.md` §3.6) — an act is generated against live run-state, so an event only rolls the brush
family where `available_brush_colors` is non-empty *at that point*. The routed icon is therefore honest (no dead
brush nodes). Keep a lightweight **arrival fallback to accuracy** as residual safety (availability could drop within
an act between gen and arrival), mirroring the challenge's empty-brush→SCORING guard. Reuse the challenge pick's
distinctness logic — if the pool can't supply `option_count` distinct brushes, relax rarity or offer fewer.

The generator rolls a family from the **active** trade-families. The architecture is family-agnostic: flipping a
family active = register its grant path + mark it, no restructure. Scaffold the placeholder icon for *all four* now
so the map renders distinct glyphs the moment a family activates.

**Icon export (the clear place Max drops art later).** A small tunable resource:

```gdscript
class_name EventFamilyIcons
extends Resource
## Maps an event family id -> its map glyph (shared with the typed-shop ring, Phase 03).
## Drop the art here when ready; until then the view falls back to a labelled coloured shape.
@export var icons: Dictionary = {}          ## StringName family -> Texture2D
@export var fallback_colors: Dictionary = {} ## StringName family -> Color (placeholder swatch)
```

---

## 3. The reward — diagonal swing trade (accuracy, at launch)

Reuses the existing accuracy-trade structure: every `UPGRADE_TYPES` entry is already a tradeoff (a `property` `+`
and a `penalty_property` `−`); `_apply_upgrade` already applies both. Events change **only the rarity table and the
rarity-roll weights** — the gain grows with rarity (a *diagonal*, not the per-leg table's flat-gain reshape).

**Event swing table** (Max's numbers; gain and penalty are ranges, both rolled):

| Rarity | gain (`+property`) | penalty (`−penalty_property`) | net ≈ |
|---|---|---|---|
| Common | **6–8** | **2–4** | +2 … +6 |
| Uncommon | **9–11** | **3–5** | +4 … +8 |
| Rare | **12–14** | **4–5** | +7 … +10 |

Rare's downside barely grows over uncommon — rarer = a *better-priced* swing. (No cross-surface ceiling to enforce:
events and challenges reward different families per §1.2.)

**Rarity weights ramp by section (events only).** Section = bosses cleared = `node.act`. Per section, +10 to
uncommon and +10 to rare, common absorbs −20:

| Section | where | Common / Uncommon / Rare |
|---|---|---|
| 0 | pre-boss-1 (act 0) | **85 / 10 / 5** |
| 1 | post-boss-1 (act 1) | **65 / 20 / 15** |
| 2 | post-boss-2 (act 2) | **45 / 30 / 25** |

Scope: **events only.** Shop and challenge keep their own rarity control (shop = zone-based; challenge = earned by
finish-efficiency). Clamp section to the table's range.

**Generating the 3 options** (`_generate_event_picks(family, section)`):
- Pick 3 **distinct** `UPGRADE_TYPES` (distinct stat axes) — for `accuracy`, draw from the 6 throw-stat trades.
- For each: roll rarity off the section ramp, then roll `gain ∈ [gain_min, gain_max]` and
  `penalty ∈ [penalty_min, penalty_max]` from the swing table.
- Build the same upgrade dict shape `_generate_upgrades` already returns (`name / property / scale / description /
  rarity / color / value / tradeoff / penalty_property / penalty_name / penalty_amount`) so `_apply_upgrade` and the
  existing pick UI consume it unchanged.

> Speed-axis note: speed stats are in display units (per the `SPEED_RARITY_TABLE` comment), so the swing numbers
> apply as-is. If speed swings feel off in playtest, give speed its own swing row — exported, a tuning knob, not a
> structural change.

---

## 4. The `EventNode` resource (data model — house style)

Lightweight; most of the reward is rolled at arrival from the live section, mirroring how `ChallengeNode` defers
its target/deposit to arrival.

```gdscript
class_name EventNode
extends Resource
## One event encounter. The family is rolled at generation (shown as the node's map icon); the 3 options are
## rolled at arrival from the node's section (act). See specs/map/03-events-impl.md §2–§3.

## The trade-family this event offers (rolled from the available trade-families). Drives the icon and the grant
## path. Launch: &"accuracy". Later: &"geometry".
@export var reward_family: StringName = &"accuracy"

## How many options the player chooses among. 3 per the locked model; exported for tuning.
@export var option_count: int = 3
```

`MapNode` already has the `EVENT` enum value and a generic payload slot; hang the `EventNode` off it the same way
`ChallengeNode` hangs off `MapNode.challenge` (add `var event: EventNode` or reuse a typed payload ref).

---

## 5. Code seam — `scripts/main.gd`

**a) Route the EVENT node.** `_on_map_node_chosen` currently sends EVENT to the leg `else` branch. Add a case:

```gdscript
elif node.type == MapNode.Type.EVENT:
    _enter_event(node)
```

`_enter_event` rolls the 3 picks from the node's family + section and shows the pick UI (no board slide / no x01 —
an event is a menu moment, not a leg). On pick → `_apply_upgrade(choice)` (existing) → return to the map.

**b) Remove the per-leg free pick.** In `_show_leg_upgrades`, the normal-leg tail currently calls
`_show_accuracy_pick()`. Remove that call; a normal leg now ends at its leg-complete banner and returns to the map
(reuse the leg-complete → Next → `_show_map` transition, just without the upgrade panel). Keep `_show_accuracy_pick`
/ `_generate_upgrades` / the rarity tables in the file — `_generate_event_picks` is a sibling that reuses
`UPGRADE_TYPES` + `_apply_upgrade`; don't fork the apply path. Boss-reward picks and challenge-win rewards are
untouched.

**c) Reuse the pick UI.** The event's 1-of-3 surface is the existing upgrade-pick panel
(`show_leg_complete_with_upgrades`'s card row, or the challenge reward surface) re-shown at the event node with the
event-rolled options. No new screen.

---

## 6. Tests (`tests/test_events.gd`, headless)

- **Swing table bands:** rolled gains/penalties fall in the per-rarity ranges; rare's net ≥ uncommon's net ≥
  common's net (the diagonal holds).
- **Section ramp:** weights resolve to 85/10/5 (act 0), 65/20/15 (act 1), 45/30/25 (act 2); each row sums to 100;
  over many rolls the realized rarity distribution matches the section weights within tolerance (the
  `[[feedback-rolled-generator-spread]]` lesson — assert the distribution *spreads*, don't just bounds-check).
- **Three distinct options, one family:** every offer has `option_count` distinct stat axes, all in the node's
  family.
- **No bank mutation:** entering/resolving an event leaves `_banked_darts` unchanged.
- **Per-leg pick gone:** a normal leg win does not open the accuracy pick (regression guard for §5b).
- **Placement (cross-check with slice 3):** EVENT nodes only sit in branch runs (covered by the slice-3 suite;
  assert here too if cheap).

## 7. Slice boundary — ships vs defers

**Ships:** `EventNode`; **two launch families** — `accuracy` (swing table + section ramp, via `UPGRADE_TYPES` /
`_apply_upgrade`) and `brush` (modifier-pool draw via `_generate_challenge_reward_picks` BRUSH-filtered, rarity off
the ramp, with the availability fallback); the 3-option pick reusing the existing pick UI; the EVENT route in
`_on_map_node_chosen`; removal of the per-leg accuracy pick; **dropping `BRUSH` from `_roll_challenge_node`**
(challenge families → `[SCORING, PLACEMENT]`); the `EventFamilyIcons` scaffold (placeholder shapes for all four
families); tests.

**Defers:**
- **Geometry event family** — needs the unbuilt geometry items (`[[project-geometry-items]]`; pulls the
  async-checkout-solver). Architecture leaves a registered slot for it.
- **Activating the pure-flat families (scoring / hotspot) as event options** — gated on a "make-it-a-trade"
  retrofit (a flat can't be a free event reward). Icons are scaffolded now; flip them active if/when trade-shaped.
  Bundle the retrofit with the geometry spec or its own pass.
- **Real family icons** — art drops into `EventFamilyIcons` later; ship on placeholder basic shapes.
- **The rest of Phase 03** — typed-shop-ring rework + the codex. Events share the glyph scaffold but are their own
  slice.
- **Per-speed-axis swing row** — only if playtest shows speed swings feel wrong.

## Related
- `specs/map/01-substrate-slice3-impl.md` — the branch topology that hosts inline events (build first).
- `specs/map/02-challenge-nodes-impl.md` — the *earned* typed pick; the event is its *free/trade* sibling (§1.2).
- `specs/map/00-overview.md` — the build-steering spine (exposure + informed shop + earned selection); events are
  the free/exposure layer, kept spine-safe by trade-only rewards.
- `specs/2026-06-02-accuracy-upgrades-as-shape.md` — the trade model the swing table amplifies.
- `specs/2026-06-03-scoring-on-the-board.md` — the `family` tag the geometry grant path will filter on later.
