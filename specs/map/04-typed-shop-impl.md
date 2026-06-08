# Typed shop + family icons (Phase 03 remainder, part 1)

---
Spec date: 2026-06-07
Status: Shipped 2026-06-07 (Claude Code; Max confirmed "tested it out and plays good"). Two
  deliberate deviations recorded under "Implementation outcome" at the bottom. 2026-06-08
  Cowork follow-ups (brush ungated+unbiased, shop graph-spacing §8, drought breaker, branch
  divergence, density pass) all tested green by Claude Code — map_graph 18.1M checks / 0 fails,
  typed_shop + events suites green, brush repro harness clean. CC fix: drought/density lane→
  special conversions overflowed the per-path event/challenge caps; added `MapNode.is_offbudget`
  (set on conversions, excluded from cap counts) to honor the "off-budget spice" framing.
Designed: Cowork sparring session (Max + Claude, 2026-06-07). Codex is the OTHER half of the
Phase 03 remainder — separate slice, but it reuses these icons (see §6).
Implementation: Claude Code. Spot generation extracted to a pure ShopSpotGenerator (headless
  testable); tests in tests/test_typed_shop.gd.
Conventions as always: static-type everything, comment frequently, exported tunables with
hover descriptions.
---

**What this does:** five family icons (just added to `sprites/Icons/`) go live on event map
nodes, and the shop's lit spots become FAMILY-TYPED — hit a spot, get a choice of two from
that spot's family. This is the "currency" leg of the build-steering spine (routing = events,
currency = shop, skill = challenges) finally landing.

## 0. Spine amendment (deliberate, record it)

Trades (accuracy / geometry / brush) become PURCHASABLE in the shop, not only free at events.
The law refines rather than breaks: **events = free but rolled for you; shop = costs banked
darts but you chose the family.** The dart-cost IS the friction, and it's chosen —
chosen-friction-is-spice holds. Also supersedes the events-spec note that STREAK is never
family-steered in the shop (it now has a slot type like everyone else; capacity friction
handled in §3).

## 1. The five families + icons (LOCKED)

| Icon (`sprites/Icons/`) | Family key | Pool | Rarity-scaling? |
|---|---|---|---|
| `scoringItems.png` | `&"scoring"` | Hotspot, Wedge Value | YES |
| `streak.png` | `&"streak"` | Wedge/Color streak mods | YES |
| `accuracyIcon.png` | `&"accuracy"` | stat-swing trades (event swing table) | YES (tier = swing size) |
| `geoItems.png` | `&"geometry"` | the 8 zero-sum geometry trades | NO (`generate()` forces COMMON) |
| `brush.png` | `&"brush"` | rolled BrushModifier | NO (forces COMMON) |

The rarity split is already true in code (checked every `generate()`), so the shop's visual
language (§4) teaches the item ontology for free — that's the codex's silent partner.

Wiring: textures go into `EventFamilyIcons.icons` (the scaffold built for exactly this —
"the SAME glyph the typed-shop ring will use", 03-events-impl §2). Add the missing
`&"streak"` entry to `icons`/`fallback_colors`/`fallback_labels`. Fallback paths STAY.

## 2. Event nodes (small, do first)

Map event nodes currently render `"Event\n<glyph label>"`. With real art: keep the "Event"
text, render the family icon UNDER it (TextureRect, house pattern: `EXPAND_IGNORE_SIZE` +
`STRETCH_SCALE`, per assembly_screen). `texture_for()` null → existing label fallback.
Family tint on the button can stay or drop once the icon reads — Max eyeballs at impl.

## 3. Typed spot generation (LOCKED)

Replaces the rarity-only roll in `_generate_shop_spots` with a two-axis roll:

1. **Family:** each of the `lit_count` spots rolls family independently, UNIFORM over the 5
   (pure roll, no guaranteed coverage — scarcity texture is fine; expose weights as an
   exported Dictionary anyway for later tuning).
2. **Rarity (rarity families only):** apply the existing ratio to the rarity-spot SUBSET —
   `rares = max(1, n/6)`, `uncommons = n/3`, rest common (n = count of scoring/streak/
   accuracy spots; if n == 0, skip — no forced rare without a spot to carry it).
3. **Placement — TIGHTENED from current code** (which mixes rare+uncommon across
   doubles+triples): **rare → Triple, uncommon → Double, common → singles.** Harder hit =
   rarer reward, the ring teaches the tier. **Trade spots (geometry/brush) → any ring,
   fully random.** A trade on a triple costs more aim for the same trade — accepted
   texture, rarity-less means the ring signals nothing.
4. Spot dict gains `"family": StringName`. Dedup/fallback placement logic unchanged.

## 4. Spot visuals (three treatments)

- **Rarity spots** (scoring/streak/accuracy): existing rarity smoke shader, family icon
  MELTED IN (icon texture as a shader param — the "glyph baked into the smoke" the overview
  promised). Rarity color stays the dominant read; icon says what, color says how good.
- **Geometry spots:** new kaleidoscope shader — geometric noise, mirrored/segmented, drawing
  from the geo UI green (`EventFamilyIcons` ships `Color(0.55, 0.80, 0.55)`; sample whatever
  the geo option cards actually use) plus black/grey. Icon melted in.
- **Brush spots:** new painted shader — brushstroke-textured fill, greenish-teal. Icon
  melted in. (Two shaders, not one shared trade shader — Max ruled per-family identity.)

### 4a. Live geometry tracking (LOCKED — folded in, it's the same shader work)

Region-attached visuals must follow wedge resizes LIVE, not just at board load. Playtest
case: Prism boss recolor rippling while geo items resize wedges — the board reflowed
beautifully, but the hotspot smoke stayed at its old size, making the resize read confusing.
Same bug class hits the shop: buy a geo item mid-shop and the remaining lit-spot shaders
must keep matching their rings.

Root cause (verified in code): `set_geometry` animates the DRAW geometry copy
(`_geo_*_draw`) via the `_apply_reflow` tween, but `_rebuild_hotspot_shader_layer` builds
its polygons from geometry ONCE at setup/toggle and never re-derives during a reflow.

**The rule:** every region-attached visual — hotspot smoke, shop spot smoke, kaleidoscope,
painted — is a function of the *draw* geometry (`_geo_*_draw`), never a cached build-time
polygon. Re-derive on every reflow tick (`_apply_reflow` is the one seam; 20-odd polys per
tick is cheap) so spots expand/shrink in lockstep with their wedge/ring, mid-shop and
mid-boss alike.

**Hover tooltip** (added 2026-06-07, post-build): lit spots read family AND tier — rarity spots
= "<Rarity> <Family> Upgrade" ("Uncommon Accuracy Upgrade"), trade spots = "<Family> Trade" (no
tier shown — geometry/brush force COMMON, so naming one would imply a ladder that doesn't exist).

## 5. Hit → choice of two (per family)

Hit a spot → 2 picks from ITS family (replaces `_generate_shop_picks`' mixed draw):

- **scoring / streak:** 2 distinct modifiers, registry filtered by family, generated at the
  spot's rarity. Streak with no free capacity: spot still appears and is buyable — the
  existing replace-streak warning flow handles it (LOCKED: always offer, never gate at gen).
- **accuracy:** 2 swing-table trades at the spot's rarity tier (reuse the event swing
  machinery + `show_upgrade_choices` card UI, just 2 cards not 3).
- **geometry:** 2 DISTINCT trades from the geo pool (existing ownership/pool rules apply).
- **brush:** 2 independently rolled brushes (different color rolls = the choice). **Affinity
  gate REMOVED from shop spot gen** (Max's ruling 2026-06-07, post-build): when brushes were
  mixed into the untyped pool, gating on owned color streaks made sense (a stray brush
  offered nothing); now that the typed shop makes brushes *seekable*, they roll for everyone.
  ~~Pre-affinity picks draw from the full pool; post-affinity they steer to streak colors~~
  **SUPERSEDED (Max's ruling 2026-06-08, playtest):** brush rolls are fully UNBIASED — always
  the full 4-color pool, owned streaks never steer. Affinity steering collapsed every option
  to the one owned color (three identical "Brush: Black" cards = no choice), and the old
  reroll-dedup appended duplicates anyway. Picks now sweep a shuffled `ALL_COLORS`
  (`BrushModifier.make(color)`) — DISTINCT colors guaranteed, owned fingerprints skipped.
  `get_pool_weight()` flattened to 15 (no affinity term). **Event gates removed too** (Max's second ruling, same session): brush
  rolls in `_roll_event_node` unconditionally — brushes and geometry trades feed each other
  (paints make boards asymmetric; asymmetric boards make geometry interesting), and ungated
  rolls make branch compositions more distinct. The arrival downgrade-to-accuracy fallback is
  gone with it, and `_enter_brush_event` switched off the registry draw (whose
  `get_pool_weight()==0` pre-affinity would have silently emptied it) onto the same direct
  roll the shop uses.

Pick cards stay clean — no family tag on the card; the spot you hit already said it.

## 6. Other icon surfaces

- **Challenge entry view:** add the reward-family icon next to the existing
  `_family_name()` text line. Cheap, do in this slice.
- **Challenge map nodes** show their reward-family icon (LOCKED — Max ruled 2026-06-07):
  the player risks a deposit to enter, so they're entitled to an informed decision. Same
  render pattern as event nodes (§2).
- **Codex** (Phase 03 remainder, part 2): reuses these same icons as its family headers.
  Out of scope here; noted so nobody builds a second icon set.

## 7. Tests

- Typed-pick legality: picks from a spot ALWAYS match its family; rarity-spot picks match
  spot rarity; trade-family picks are always COMMON-tier.
- Ring mapping: every rare on a Triple, every uncommon on a Double, every common on a
  single; trade spots observed on all four rings across seeds.
- Distribution spread (the `[[feedback-rolled-generator-spread]]` lesson): across seeds, all
  5 families appear at ~equal observed rates; shops are not one canonical composition; the
  rarity-subset ratio holds for varying subset sizes (incl. n == 0 edge).
- Streak spot with full capacity → replace-warning path fires, purchase completes.
- Geometry picks distinct; brush picks differ in roll; accuracy shop cards = 2.
- Event AND challenge nodes render their family texture when present, fall back when not.
- Live tracking (§4a): trigger a geometry change with an active hotspot and active shop
  spots; at reflow midpoint and completion, overlay polygons match the draw-geometry
  wedge/ring bounds (not the pre-change bounds). Cover both directions: geo item acquired
  mid-shop, and a boss-turn resize with a hotspot live.
- Shop spacing (§8): across seeds and all acts, no two SHOP nodes within
  `shop_min_graph_gap` edges of each other — covering lane-budget, crossover, and
  mini-branch placements, and crossing stretch boundaries.
- Existing shop + map + challenge suites green; `--check-only` parse pass on every changed
  script.

## 8. Map-gen addendum: act-wide shop spacing (LOCKED — playtest ruling 2026-06-08)

Two playtested maps in a row rolled shop clusters: a Shop→Shop lane run, and (repeatedly)
the lane-Shop / crossover-Shop / lane-Shop diamond. Root cause: `special_min_gap` only
checks within ONE stretch's run array — blind across stretch boundaries — and crossover/
branch typing never checks neighbours at all. Back-to-back shops are also near-dead nodes
(the second opens on an empty bank).

**The rule:** no SHOP within `shop_min_graph_gap` (export, default 2) edges of another shop,
enforced by an undirected BFS (`_shop_within`) at every placement source: lane budget
(`_place_special_in_run`), crossover typing, and branch specials (both via
`_roll_detour_type`, where SHOP simply drops out of the roll when too close). Mid-stretch
both-lane mirror shops stay legal (lanes don't connect there — the budget's no-contrast
guarantee survives); mirrors adjacent to a crossover are blocked, which is exactly the
diamond. Crossover shops away from other shops remain legal spice — zero
`crossover_weight_shop` in the inspector to ban them outright.

Flagged, NOT implemented (didn't make the ruling): an act-wide shop COUNT cap across
sources, and a HARD per-lane event floor. Revisit if the density pass (below) doesn't hold.

**Drought breaker (2026-06-08, second density follow-up):** even post-density-pass, lanes
shipped 4-leg dry runs (and an all-leg 4-node mini-branch). Max proposed a per-leg
convert-chance after 2 in a row; built as a HARD cap instead — a chance can whiff and ship
the same dry stretch, an invariant is testable. `_break_leg_droughts` (step 6.5, runs last):
no stay-on-lane sequence (runs concatenated across stretch seams) or mini-branch may exceed
`max_consecutive_legs` (export, 3) plain legs; longer runs get ONE rolled-position node
converted — EVENT by default, CHALLENGE at `drought_break_challenge_chance` (export, 0.25)
where the act-0 depth gate allows. Off-budget spice. Suite-assertable invariant: walk every
lane sequence + branch run, assert no leg-run > cap.

**Branch divergence guard (2026-06-08, third density follow-up):** rare maps shipped a
mini-branch whose contents exactly matched the lane segment it bypasses (identical up to one
extra pre-boss leg) — a fake choice, since staying vs detouring gives the same rewards.
`_ensure_branches_diverge` (step 6.6, after the drought breaker so both sides are final):
compares the branch's type MULTISET against the parallel bypassed lane nodes (composition, not
sequence — [Event,Leg] vs [Leg,Event] is the same decision); on a match, flips one non-event
branch node to EVENT (always changes the multiset), or for the all-event degenerate case nudges
one to CHALLENGE/SHOP where legal. Off-budget. Stores `{branch, parallel}` id lists per branch
(was just `branch`); drought breaker updated to read `.branch`. Suite-assertable: every branch's
type multiset differs from its parallel segment's.

**Density pass (2026-06-08, follow-up playtest):** Max approved the post-spacing map size/
pace but acts read leg-heavy (one lane rolled 9 legs + 2 shops, zero events/trials — a low
event roll contrast-lumped onto the other lane). Default nudges, both inspector exports:
`events_per_path_min` 1→2 (events are the free-trade spice, the right leg-filler; challenge
bands untouched — deposit friction shouldn't inflate) and `crossover_weight_leg` 0.5→0.35
(typed crossovers absorb 1–2 dry legs). Net: ~1–3 legs per act become events/typed
crossovers. Per-lane coverage is now LIKELY but still soft — the hard floor stays flagged.

**After this ships:** archive here per Workflow Notes, then part 2: the codex.
Program index: `specs/map/00-overview.md`.

---

## Implementation outcome (2026-06-07/08, Claude Code) — shipped, with flags

Core slice shipped and playtested ("tested it out and plays good"):
- **Icons (§1):** five textures wired into `EventFamilyIcons.icons` + the `&"streak"` key; added
  `EventFamilyIcons.key_for_family(Family) -> StringName` for challenge nodes (enum, not StringName).
- **Map nodes (§2/§6):** event AND challenge nodes render their reward-family icon (TextureRect
  child, lower-centre, click-through; text-glyph fallback). Challenge entry view shows the icon
  inline (RichTextLabel `[img]`).
- **Typed spots (§3):** extracted to a pure, headless-testable `ShopSpotGenerator` (injected RNG);
  `main._generate_shop_spots` is a thin wrapper. Uniform 5-way family roll (exported
  `shop_family_weights`); rarity ratio over the rarity-family subset only (n==0 edge handled);
  ring tightened (rare→Triple / uncommon→Double / common→single; trades→random ring). Spot dict
  gains `"family"`. Brush family auto-zeroed when no colors owned.
- **Picks (§5):** per-family — scoring/streak via the family-pure registry draw at spot rarity,
  accuracy via the swing table, geometry from the geo pool, brush via independent color rolls.
  Streak at full capacity flows through the existing replace-warning path.
- **§4a live tracking:** `_apply_reflow` re-derives hotspot smoke + shop-spot overlays each tick.
- **Tests:** `tests/test_typed_shop.gd` (ring mapping, rarity-subset ratio incl. n==0, family
  spread, icon wiring) + a §8 shop-spacing assertion added to `tests/test_map_graph.gd`.

### Deviations / flags to revisit
1. **Bespoke trade shaders NOT built (§4).** Geometry-kaleidoscope and brush-painted shaders +
   the literal "icon-melted-as-shader-param" need a per-spot-material refactor and are
   eyeball-tuned, so they're deferred. Shipped instead: per-family spot fill colour
   (`shop_color_geometry`/`shop_color_brush` exports) + the family icon drawn on the spot
   (`shop_icon_size`), which re-derives on reflow. **Follow-up: the two shaders, with Max's eye.**
2. **Flight `shop_bias` no longer biases shop picks.** The old mixed pool-weight draw is gone
   (picks are family-pure per the hit spot), so a flight's `get_weight_overrides()` has no pick
   to bias. If a flight relies on it, re-express as a bias on `shop_family_weights`.
3. **Brush ungate test fallout (resolved).** Max's documented brush ungate — events roll
   `[accuracy, brush, geometry]` unconditionally and `_enter_event`'s arrival downgrade was
   removed (colorless brush picks now fall back to the full color pool in
   `BrushModifier.generate`) — left three stale test assertions; all updated to the new contract
   (`test_map_graph` event-family + state-aware-roll; `test_events` brush-fallback source scrape).
4. **OPEN — §8 challenge-starvation (2 seeds).** The §8 shop-spacing skip shifts the seeded
   placement stream, and on `level_1501` seeds 24 & 27 act 2 ends up with **no lane-run
   challenge**, tripping `test_map_graph`'s `_assert_per_path_budget` "act offers ≥1 lane-run
   challenge" check. `challenges_per_path_min` is documented as a SOFT minimum, so the hard
   per-seed assertion is arguably too strict — but whether every act≥1 must guarantee a lane-run
   challenge is a design call. **Max to decide: relax the test to a cross-seed/statistical check,
   or tighten challenge placement so §8's stream shift can't starve an act.** Until then the
   map suite is red on those two seeds only.
