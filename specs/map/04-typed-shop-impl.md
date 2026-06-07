# Typed shop + family icons (Phase 03 remainder, part 1)

---
Spec date: 2026-06-07
Status: QUEUED — behind the leg lattice (current CLAUDE.md active spec). Promote to CLAUDE.md
when the lattice ships/archives.
Designed: Cowork sparring session (Max + Claude, 2026-06-07). Codex is the OTHER half of the
Phase 03 remainder — separate slice, but it reuses these icons (see §6).
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

## 5. Hit → choice of two (per family)

Hit a spot → 2 picks from ITS family (replaces `_generate_shop_picks`' mixed draw):

- **scoring / streak:** 2 distinct modifiers, registry filtered by family, generated at the
  spot's rarity. Streak with no free capacity: spot still appears and is buyable — the
  existing replace-streak warning flow handles it (LOCKED: always offer, never gate at gen).
- **accuracy:** 2 swing-table trades at the spot's rarity tier (reuse the event swing
  machinery + `show_upgrade_choices` card UI, just 2 cards not 3).
- **geometry:** 2 DISTINCT trades from the geo pool (existing ownership/pool rules apply).
- **brush:** 2 independently rolled brushes (different ring/color rolls = the choice).

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
- Existing shop + map + challenge suites green; `--check-only` parse pass on every changed
  script.

**After this ships:** archive here per Workflow Notes, then part 2: the codex.
Program index: `specs/map/00-overview.md`.
