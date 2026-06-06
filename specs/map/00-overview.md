---
Spec date: 2026-06-04
Status: PROGRAM BLUEPRINT — in design (Cowork sparring session, Max + Claude). Not scheduled to build.
  This is the index/overview for the whole map program; the individual phases live as numbered specs in
  this folder. Captures decisions + open forks so future refinement sessions have structure to reference.
Supersedes/absorbs: `specs/future/map-pool-filtration.md` (becomes Phase 04 here) and the **Phase B (typed
  shop rings)** half of `specs/future/darts-as-currency-economy.md` (becomes Phase 03 here). Those files
  stay as-is for now; fold them in when each phase is scheduled.
Workflow note: a multi-phase epic doesn't fit CLAUDE.md's single-active-spec slot. This folder is the
  durable home; CLAUDE.md's active slot holds whichever *phase* is currently being designed/built. Keep the
  whole program together here with per-phase status headers rather than scattering shipped phases out to
  dated top-level files — the map's story is one story.
---

# Map Program — Overview / Blueprint

## Why now (and why it's a program, not a spec)

"Tools before the house." The scoring/items toolkit shipped (`specs/2026-06-03-scoring-on-the-board.md`):
two-axis scoring, hotspots, the `family` tag, component-gated streaks. Those are the *furniture*. The map
is the **house** — the run-spanning structure that arranges the tools into a journey and supplies the
non-vertical tension the scoring pass deliberately left out ("difficulty zigzags via the map, not just the
score climbing").

It's too big for one spec. It folds together three previously-scattered threads:

1. **Pool steering / filtration** — item acquisition currently plays as "what's the strongest item on
   offer?" instead of "what fits my build?". Steering the pool toward a category lets the player branch
   builds. (Was `specs/future/map-pool-filtration.md`.)
2. **Boss cadence** — the map as the Slay-the-Spire boss-frequency vehicle; a home to demote benched boss
   effects to optional encounters. (Long-parked in DesignNotes.md.)
3. **Run-spanning resource flow** — the darts-as-currency economy wants typed shop rings and a place for
   the bank to *matter* between legs. (Phase B of `specs/future/darts-as-currency-economy.md`.)

## The spine decision: where build-steering lives (resolved this session)

We split the "how does the player steer their build" problem into three surfaces operating at different
grains, so no single surface has to do everything:

- **Exposure (information, zero power)** — a codex/dictionary that explains the item *families* up front, so
  the player makes informed shop decisions instead of "fuck-around-and-find-out" wasting a dart on a type
  they didn't understand. FAFO is fine for *gambling*; it's unfair as a punishment for *not knowing the
  rules*. Teach the rules; keep the gamble.
- **Informed shop (typed, in-place)** — each shop ring shows a **family glyph baked into the smoke**
  (reusing the hotspot shader's already-shipped "glyph-as-a-parameter" groundwork); hovering reads
  "Target: Brush / Scoring / Accuracy…". Now a ring communicates **type** (glyph) *and* **rarity**
  (position) at once — the full zone×type×hittability read the economy spec wanted, but *informed* instead
  of blind. This is Phase B, basically resolved.
- **Earned selection (skill + currency gated)** — optional **challenge nodes** where the player *earns* a
  guaranteed typed pick by clearing a costed, handicapped x01 race. This is the clean "give me a Brush" tap
  the filtration spec warned would flatten variance — made safe by gating it behind a real skill wall + a
  dart wager, exactly the scarce-gate that spec demanded. (Phase 02.)

Net: **the player chose NOT to get free typed picks.** Power stays earned; the free layer is pure
*information*. This protects the darts-as-currency "the bank is the climb" thesis.

> **Refined 2026-06-05 (events session):** the rule's final form is **trades are free, flats are earned.**
> Event nodes (`03-events-impl.md`) give free typed picks of *trade-shaped* items only (a `+` bought with a
> `−` — accuracy swings now, geometry later). A trade deepens a commitment instead of climbing power, so it
> can't beeline variance flat — the original concern only applies to *flat* items, which stay gated behind
> darts (shop) or skill (challenge). The three surfaces tier as **routing < currency < skill**.

## Two reusable design laws this program leans on

- **Frame before furniture.** Same doctrine as "tools before house," one level in. Within the map, the
  *substrate* (the navigable graph that hosts the current run flow) goes up before any new node type,
  because positional features (challenge nodes especially) can't be *felt-tested* without a run-position to
  sit in. Build the rough grey-rect map first precisely so everything after it is testable in context.
- **Chosen friction is spice; mandatory friction is punishment.** Benched boss effects (Rotation, Narrow
  Double, −1-dart-per-turn, dart-count) were cut as *mandatory* gates because forced handicaps read as the
  game cheating you. Opt-in, with a reward attached, consent flips the valence — the same mechanic becomes
  a flex you bragged your way into. The cut list is therefore a **content mine**, not a graveyard. Anything
  that breaks up the repetition of the vanilla darts experience earns a second life as an optional node.

## Phases (sequencing reflects frame-before-furniture)

| # | Phase | One-liner | Status |
|---|---|---|---|
| 01 | **Substrate** | Data-graph + view; first hosts the *current* run flow (legs/shops/bosses) as a navigable graph. Code-first rough visuals, art swap later. The dependency everything else needs. | **SHIPPED** — slice 1 (rough-rect topology + ported ladder, `01-substrate-impl.md`, 2026-06-04, commit `e71762f`) + slice 2 (pressure-ratio generator, `01-substrate-slice2-impl.md`, 2026-06-05). **Slice 3 IMPL SPEC READY** (`01-substrate-slice3-impl.md`, 2026-06-05) — topology v2: ~12-node per-act paths, multi-node 3–5 parallel branches, re-homes challenges onto branches (supersedes 02 §17). **Build-first** for the events work. Deferred: arrival ceremony + art reskin (polish). |
| 02 | **Challenge nodes** | Optional post-boss-1 x01 races; **deposit darts = the race budget** (loss forfeits all), rarity earned by finish-efficiency, recycled benched bosses as handicaps. | **BUILT + PLAYTESTED** (`02-challenge-nodes-impl.md`, 2026-06-05; Claude Code). Playtest takeaway: the nodes feel incomplete without a fuller map to test the flow → motivates slice 3 + events. §17 placement follow-up superseded by slice 3's branch model. |
| 03 | **Typed shop + codex (+ events)** | Family glyph in the smoke + hover type; the codex that teaches families; **inline event nodes** (free typed *trade* picks). The informed-shop + exposure layer. | **Events slice IMPL SPEC READY** (`03-events-impl.md`, 2026-06-05): inline events, trade-only rewards (accuracy swing now, geometry later), depth rarity ramp, replaces the per-leg free pick. Typed-shop-ring rework + codex = later slices, design pending. Folds in Phase B of darts-currency. |
| 04 | **Pool filtration / path-biasing** | Map paths bias the reward pool toward a family (soft bias, gated — not a clean tap). | Absorbs `map-pool-filtration.md`; design pending |
| 05 | **Boss cadence** | Map raises boss frequency; benched effects become node mini-encounters. | Design pending |

Build order is roughly the table order. 01 unblocks all. 02's *mechanic* can be built/unit-tested before
01, but its *design* can't be validated without it. 03's typed shop can partly ship into the current shop
ahead of the map, but its *steering meaning* needs the map.

## Open blueprint forks

Most of these were **resolved in the 2026-06-04 substrate session** — see `01-substrate.md` for the full
reasoning. Kept here as a resolution log:

- **Procedural vs hand-authored layout.** ✅ Resolved → *both*, layered: fixed skeleton + rolled legs +
  authored challenge Resources + slotted shops/events. Data-graph approach confirmed non-negotiable.
- **What are the node types?** ✅ Resolved → leg, challenge, shop, event, boss (no non-eventful nodes;
  rest/treasure deferred behind an enum extension).
- **How the map expresses existing structure.** ✅ Resolved → 3 acts = the 3 boss tiers (501/1001/1501 as act
  ceilings) via *sliding* windows so the climb reads continuous; legs are the rolled traversal; the
  every-5-legs cadence becomes a ~7–12-node act once the new types fold in.
- **Steering grain overlap** — codex (coarse education) vs typed shop (tactical, in-shop) vs challenge node
  (earned, guaranteed). Still good; 01 adds that *events + challenges also seed item-literacy before the first
  shop* (exposure double-duty), reinforcing rather than duplicating the codex.
- **Implementation/art split.** ✅ Resolved → code-first rough (grey rects) → Max draws art → reskin the node
  scene without touching `MapGraph`. Graph/view decoupling is the architecture call in 01.

New this session (the one genuinely load-bearing addition): **hiding leg parameters on the map promotes Phase
04 path-biasing from optional to required** — if node *type* is the only routing signal, the branches must
differ in type composition or the map flattens. See 01's information model.

## Related

- `specs/2026-06-03-scoring-on-the-board.md` — the shipped toolkit this arranges; the `family` tag is the
  steering prerequisite, already landed.
- `specs/future/darts-as-currency-economy.md` — the economy; Phase B (typed rings) becomes Phase 03 here;
  the challenge-node deposit is a new sink for the bank.
- `specs/future/map-pool-filtration.md` — becomes Phase 04; structural realities (#2 accuracy lives in a
  different building, #3 gate the steering) carry forward.
- `specs/future/async-checkout-solver.md` — Tier-2 geometry solver dependency, relevant if geometry nodes
  appear.
