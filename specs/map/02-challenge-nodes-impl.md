---
Spec date: 2026-06-05
Status: IMPL SPEC — ready to build (Claude Code). Converts the design-complete `02-challenge-nodes.md` into a
  buildable doc, the way slice 1 became `01-substrate-impl.md`. Design forks below were all resolved in a
  Cowork sparring session (Max + Claude, 2026-06-05); this records the resolutions and the build surface.
Part of: the Map Program (`specs/map/00-overview.md`), Phase 02.
Depends on: Phase 01 substrate — slice 1 (graph/view/seam, `01-substrate-impl.md`) + slice 2 (pressure-ratio
  generator, `01-substrate-slice2-impl.md`). **Reads the slice-2 pressure seam** (`baseline_target` /
  `expected_per_dart`, and `pressure_of` which §14 notes still needs implementing — the seam is currently a
  skeleton: `baseline_target` calls `_act_ceiling` / `_act_floor` / `_snap`, and `pressure_of` is referenced but
  not yet defined). Phase 02 must not land before those compile.
Supersedes (in design): the turns↔rarity "banter table" in `02-challenge-nodes.md`. That dial is replaced by the
  deposit-size dial below (§2, §6) — strictly better: one number, no pre-pick UI, rarity from demonstrated play.
---

# Phase 02 — Challenge Nodes (impl)

## 0. One-line thesis

An optional, post-boss-1, off-branch map node where the player **wagers banked darts as the race budget** to
re-clear a score they've already beaten, **in a tighter budget than a normal leg**. Win → reward (rarity = how
few darts they used) + bank the unused darts. Lose → forfeit the whole wager, run continues. The challenge verb
is **match concisely**, not **match big** — precision, not size — and it exists to break up the game's most
repetitive stretch (leg, shop, leg, shop) with a different rhythm.

---

## 1. The locked model (resolved this session)

Everything below is decided; the rest of the doc is the build surface.

1. **Gating:** challenges appear **post-boss-1 only**. Pre-boss-1 the player is still getting started and has no
   cleared *boss* to anchor to; locking it out removes the early-anchor special case entirely.
2. **Target anchor:** `target = within −300 of the highest score the player has actually cleared` (boss *or*
   leg). A score they've *eaten*, never one they haven't reached. Finer increment than legs allowed (251, not
   only the 101/201/301 lattice — see §3, §9 checkout caveat).
3. **Deposit = wager = race budget.** One pool of darts, not two. The darts you stake are the darts you throw.
4. **Loss forfeits the entire deposit** (including darts never thrown), no reward, **run continues** (never a
   run-ender). This is what makes deposit-size a real decision (§2).
5. **Rarity = how few darts you finish in.** Bands split the deposit range; finishing lean = rarer (§6).
6. **`darts_per_turn` is rolled per node ∈ [2,5]**, shown *before* deposit, and only regroups the budget into
   turns (the "ice-tray" fill, §5). It changes texture and bust-cost, never the total-dart budget.
7. **Budget is capped by total darts** (ice-tray), not by whole turns — the last turn may be partial (§5).
8. **Generation is algorithmic**, not bespoke `.tres`. The anchor makes per-node hand-authoring unnecessary; a
   `ChallengeNode` resource still exists for inspector-tunable knobs, house style (§7).
9. **Skip is allowed.** The player may walk past the challenge and take the parallel leg instead (§12).

---

## 2. The economic core — deposit size is the whole risk/reward dial

The original spec used a pre-chosen `turns → rarity` table. We replace it with a single dial: **how many darts
you deposit**, because rarity comes from how few you *actually use* and a loss forfeits everything you staked.
That makes one number do all the work, via a **safety-net** logic:

- **Deposit lean (near min).** Few darts available → you *must* finish efficiently or you bust out of budget and
  lose; there's no room to fail soft. Win and it's **rare**; lose and you only dropped a few darts. High skill
  bar, cheap downside.
- **Deposit fat (near max).** You buy a graduated net — miss the rare pace and you can still scrape an
  **uncommon/common** win instead of losing. Safe, but a loss now costs the whole fat stake.

So one number sets *both* the precision bar attempted *and* the loss exposure. Confident players go lean for
cheap rares; unsure players buy the net at a higher price and settle for commons. No node is strictly dominated;
the gate is genuine precision, exactly the skill wall the program's build-steering spine wanted.

**Why the loss-forfeits-everything rule is load-bearing:** without it, depositing max would be free insurance
(rarity keys off darts *used*, not *deposited*), so everyone deposits max and the dial dies. Forfeiting unused
darts on a loss is what prices the safety net.

---

## 3. The target anchor

```
highest_cleared = max score the player has banked a win on so far (boss or leg)
target_raw      = roll in [highest_cleared - 300, highest_cleared]      # never above what they've eaten
target          = snap(target_raw, to a finer lattice than legs)        # 251 allowed, see §9
```

- **Post-boss-1 only**, so `highest_cleared ≥ 501` always (boss 1 = the first act ceiling). The −300 floor keeps
  it a *known* number; the upper bound (`highest_cleared`) keeps it from ever exceeding proven ability.
- The **difficulty is the budget, not the number** — `target` is lower than the local leg target, but it's
  compressed into fewer darts (§4). Re-clearing an old number with a now-stronger build, on a lean budget, is the
  precision check.
- Track `highest_cleared` on the run state (it generalizes the "last boss" idea and handles legs cleared between
  bosses). It updates on every banked leg/boss win.

> **Tuning note:** −300 is the session's working figure (originally −200; widened to −300 for more headroom on
> the lean end). Expose it as a config knob (§7) so it's dialable without a code change.

---

## 4. The deposit-range formula — from the slice-2 seam

The min/max deposit is **derived**, not authored, from the pressure seam slice 2 exposed for exactly this. Do
**not** invent a points-per-dart divisor (the session's hand-estimate `/6` implied ~100 pts/dart, too hot as a
*reliable* baseline). Use the tuned curve:

```
E  = expected_per_dart(challenge_depth)          # = baseline_target(depth) / 15, the tuned pts/dart at THIS depth
T  = target                                       # from §3, anchored to highest_cleared
reliable_darts = ceil(T / E)                      # darts an average run needs to clear T at current build power
min_deposit    = max(MIN_FLOOR, round(reliable_darts * LEAN_FACTOR))   # precision floor (rare end), LEAN_FACTOR ~0.65
max_deposit    = reliable_darts + CUSHION         # forgiving end (common), CUSHION ~2
```

The key coupling: **`T` comes from history (a low, already-cleared number) but `E` comes from the challenge's
*current* depth (higher build power).** So re-clearing an old number costs fewer darts now — "match concisely"
made literal — and because `E` rises with depth in lockstep with the anchor, the deposit band stays in a tight
**~6–13 dart** range across the whole game instead of ballooning.

**Worked numbers** (computed from the documented act floor→ceiling interpolation; act ceilings 501/1001/1501.
Claude Code should re-confirm against the live curve once the §14 seam helpers compile):

| Where | baseline_target(depth) ≈ | E = /15 | highest_cleared | T (roll) | reliable = ⌈T/E⌉ | min / max deposit | rarity thirds (rare / unc / common) |
|---|---|---|---|---|---|---|---|
| early act 1 | ~550 | ~37 | 501 | 351 | 10 | 6 / 12 | 6–7 / 8–9 / 10–12 |
| mid act 1 | ~750 | ~50 | 600 | 451 | 9 | 6 / 11 | 6–7 / 8–9 / 10–11 |
| mid act 2 | ~1250 | ~83 | 1100 | 901 | 11 | 7 / 13 | 7–9 / 10–11 / 12–13 |

All land on sane integers and split cleanly into thirds. The band never starves the bank (min ≥ ~6) nor demands
an absurd reserve (max ≤ ~13).

---

## 5. `darts_per_turn` and the ice-tray cap

`darts_per_turn` (dpt) is **rolled per node ∈ [2,5] at generation and shown before the deposit** (it is
difficulty-relevant — it sets bust-cost and streak room — so hiding it behind the wager would violate the
program's exposure principle). It does **not** change the total-dart budget; it only regroups it.

**Cap by total darts, ice-tray fill.** The deposit is a raw dart count (preserving the fine wager granularity
§4 produces). It fills into rows of `dpt`; the last row may be partial:

```
deposit 7, dpt 2  →  rows [2,2,2,1]      (4 turns, last is a 1-dart turn)
deposit 11, dpt 5 →  rows [5,5,1]        (3 turns, last is a 1-dart turn)
deposit 9, dpt 3  →  rows [3,3,3]        (3 full turns)
```

**Why ice-tray over "deposit must be a multiple of dpt":** the bank stores **raw darts** (`_banked_darts` is an
int count); the *only* place darts quantize to whole turns is the bailout, and that quantization exists because a
partial turn is meaningless *mid-leg under pressure*. A challenge is a fresh race, so a partial final turn is just
"you ran out of darts at the end" — meaningful, not inconsistent. Ice-tray therefore matches the bank's native
unit; multiples-of-dpt would re-introduce the coarse-granularity problem (dpt 5 → only 5/10/15 deposit choices)
for a consistency benefit that doesn't actually apply.

**Why dpt is rolled, not player-chosen:** if the player picked dpt, a free-form deposit would let them
back-derive it (deposit 9 → forced dpt 3), handing them too much control. Rolled + shown-upfront + free deposit
keeps the two decoupled. The "throw them all in one line, bust and you're done" precision-mode Max floated is not
a separate system — it's the extreme config a node can roll into when `dpt = deposit` collapses to one row; keep
both as variables and that mode falls out for free.

**Bust semantics:** standard x01 — a bust ends the current turn, forfeiting the rest of that turn's darts (so a
bust at dpt 5 burns up to 4 darts of budget at once; at dpt 2, at most 1). This is the intended texture, and the
ice-tray UI surfaces it: **each row is one bust unit**, so four rows of 2 vs two rows of 4 tells the player at a
glance what a bust will cost.

---

## 6. Rarity from efficiency

On a **win**, rarity is a function of **darts actually used** to close out, against the node's deposit range:

```
used      = darts thrown up to and including the checkout
rare       if used ≤ min_deposit + band                 # lean / efficient
uncommon   if used in the middle third
common     if used in the top third (still a win)
```

Split `[min_deposit, max_deposit]` into thirds for the bands (the §4 table shows the splits). Because dpt is
fixed per node, darts-used stays fine-grained (you can check out mid-row), so the bands stay meaningful at any
rolled dpt. The reward itself is a **guaranteed typed pick** at the earned rarity — reuse the reward pool + the
`family` tag, filtered to the node's offered type (type rolled by the node; rarity from play). This is the same
grant path the typed shop (Phase 03) will share.

---

## 7. The `ChallengeNode` resource (data model — house style)

A new `Resource`, fully `@export`ed with `##` hover docs (per Max's GDScript conventions: static-type
everything, describe every export, expose anything tunable). The generator fills most fields by rolling against
the seam; the exports exist for inspector override and global tuning.

```gdscript
class_name ChallengeNode
extends Resource
## One challenge encounter's tunable surface. The map generator rolls target/dpt/deposit-range from the
## slice-2 pressure seam (see specs/map/02-challenge-nodes-impl.md §3–§5); these exports let the designer
## clamp the rolls or hand-tune a specific node. Lives on an off-branch (is_off_branch) map node.

## Score the player must reach. Rolled in [highest_cleared - target_undercut, highest_cleared] at generation,
## snapped to the challenge lattice (finer than legs — 251 allowed). A number they have ALREADY cleared.
@export var target_score: int = 301

## How far below the player's highest cleared score the target may roll. Larger = leaner-feeling challenges
## (more headroom to compress). Session default 300.
@export var target_undercut: int = 300

## Darts thrown per turn for THIS node, rolled in [dpt_min, dpt_max] at generation and shown before deposit.
## Low (2) = little within-turn rescue, weak streaks; high (5) = malleable but a bust torches a whole row.
@export var darts_per_turn: int = 3
@export var dpt_min: int = 2          ## floor of the per-node darts-per-turn roll
@export var dpt_max: int = 5          ## ceiling of the per-node darts-per-turn roll

## Wager bounds, in raw darts. Derived from ceil(target/expected_per_dart(depth)) via LEAN_FACTOR / CUSHION
## (§4); exposed so a node can be clamped. The player chooses any integer in [min_deposit, max_deposit].
@export var min_deposit: int = 6
@export var max_deposit: int = 12

## Tuning knobs for the deposit derivation (used by the generator, not per-throw).
@export var lean_factor: float = 0.65   ## min_deposit ≈ reliable_darts × this (the rare-end precision floor)
@export var deposit_cushion: int = 2    ## max_deposit ≈ reliable_darts + this (the common-end safety net)

## The upgrade family this node offers (rolled). Rarity is earned by efficiency (§6), not stored here.
@export var reward_family: StringName = &""

## Which benched-boss effect handicaps the race (§8). Empty = a clean precision race, no handicap.
@export var handicap_id: StringName = &""
```

> **Open: should `min/max_deposit` be stored or always recomputed?** Lean toward the generator computing them
> from the seam at placement and writing them onto the node instance, with these exports as override clamps — so
> a designer *can* pin a node but doesn't *have* to. Same pattern as slice 2's "algorithmic baseline + exported
> knobs."

---

## 8. Recycled handicaps — the benched-boss content mine

The handicap (optional per node — empty = clean race) comes from the **benched** effects, not the 4 reactive
puzzle bosses. The code is still present (`scripts/bosses/rotation_boss.gd`, `narrow_double_ring_boss.gd`,
`two_darts_boss.gd`), so this is a re-skin, not a rebuild. Keep them as **aim handicaps** (they test precision) —
cleanly distinct from the main bosses, which are **reactive puzzles** that fight your build. Different verb, no
overlap. Difficulty↔reward stays matched implicitly: a handicap raises `used` (more darts spent fighting it), so
it naturally pushes the earned rarity down a band unless the player is sharp enough to absorb it — the §6
efficiency-rarity link does the balancing for free.

---

## 9. x01 handoff + engine changes

A challenge runs the **existing x01 flow** with a constrained front. Two real additions:

1. **Total-dart cap with a partial final turn.** Today the budget is `max_turns × darts_per_turn` (slice 2). A
   challenge needs a hard cap on *total darts* that need not divide evenly by dpt (the ice-tray remainder). Add a
   budget mode to x01: a `dart_budget` ceiling that ends the race when reached, independent of turn count, with
   the last turn allowed to be short. This composes with slice 2's turns model — a normal leg is the special case
   where `dart_budget = max_turns × darts_per_turn` exactly.
2. **Per-race `darts_per_turn` override.** The challenge sets its own dpt (§5) for the duration of the race, then
   restores. (`darts_per_turn` is already mutated elsewhere — `two_darts_boss.gd` — so the override path exists;
   reuse it, don't fork it.)

The handoff payload extends the slice-2 seam (`start_leg_with(target, max_turns)`): add the dart cap + dpt
override + handicap id. Reuse `get_saved_darts()` for the unused-darts-bank-on-win path (§11).

> **Checkout caveat (§1.2, finer lattice):** if challenges go off the 101/201/301 lattice (e.g. 251), confirm the
> HUD checkout display / any checkout table doesn't assume hundreds. Likely minor, but verify before allowing
> non-lattice targets; if it's a problem, restrict the challenge lattice to 51-increments or fall back to the leg
> lattice and drop the "251" nicety.

---

## 10. UI — almost entirely reuse

No genuinely new screen. Three surfaces, all reskins:

- **Pre-entry readout** (on the map / on arrival): show `target_score`, `darts_per_turn` (the bust-grain),
  `[min, max]` deposit, and the offered `reward_family`. This is the informed-decision surface — everything
  difficulty-relevant is visible *before* the wager.
- **Deposit picker (ice-tray):** the player picks an integer in `[min, max]`; render it filling as rows of `dpt`
  with a partial last row (§5). The rows *are* the turn structure and the bust-grain — the visual teaches the
  rule.
- **Reward grant:** reuse the existing upgrade-pick surface; the earned rarity (from §6) filters the typed pool.

---

## 11. Bank integration (a new sink alongside shop + bailout)

Reads/writes the persistent `_banked_darts`:

- **On entry:** require `_banked_darts ≥ min_deposit` to qualify (low bank = node is closed — itself part of the
  steering gate). Withhold the chosen deposit from the bank for the race.
- **On win:** the deposit is *spent as budget*, so unused darts return via the normal leg-savings path
  (`get_saved_darts()` = `dart_budget − darts_used`) → bank them; grant the typed reward at the earned rarity.
- **On loss:** forfeit the entire deposit (used and unused). No reward. Run continues.

Net: a won challenge that finishes lean both banks leftover darts *and* yields a rare — generous on purpose,
because the lean win is the hard one. A fat, sloppy win banks little and yields a common. A loss is a real cost.

---

## 12. Skip

The player can decline the challenge and take the **parallel leg** on the reconverging fork instead (the
challenge sits on `is_off_branch`, slice 1's reserved slot; the fork rejoins immediately). Skipping is not
"walking away with nothing" — you play the leg, which banks darts as usual. This is the tempo cost paid *by
position*, not by a coded penalty (per `01-substrate.md`): taking the challenge forfeits the parallel leg's
farming. Keep challenges **only** on the off-branch, never inline in the mandatory sequence.

---

## 13. Validation / tests (`tests/test_challenge_nodes.gd`, headless)

- **Coherence with the seam:** for a sampled spread of post-boss-1 depths, assert
  `reliable_darts = ceil(target / expected_per_dart(depth))` and that `min_deposit ≤ reliable_darts ≤ max_deposit`
  with both ends sane (`min ≥ MIN_FLOOR`, `max ≤ a ceiling`). This is the §4 contract.
- **Anchor invariant:** every rolled `target_score ≤ highest_cleared` and `≥ highest_cleared − target_undercut`,
  and challenges never generate pre-boss-1.
- **dpt + ice-tray:** `dpt ∈ [dpt_min, dpt_max]`; the row decomposition of any deposit sums back to the deposit
  (full rows of dpt + one partial). Total-dart cap honored (race ends at `dart_budget`).
- **Rarity bands:** the three bands partition `[min, max]` with no gap/overlap; lean `used` ⇒ rare.
- **Bank conservation:** win → `bank += unused`; loss → `bank −= deposit`; run not ended either way; entry blocked
  when `bank < min_deposit`.
- **Placement:** challenges only on `is_off_branch` nodes with a reconverging parallel leg (skip is always
  available).

---

## 14. Dependencies / the seam to finish first

Phase 02 reads the slice-2 pressure seam. Right now that seam is **partly skeleton** — `baseline_target` is
written but calls `_act_ceiling` / `_act_floor` / `_snap` (not yet defined), and `pressure_of` (the §6 function
of `01-substrate-slice2-impl.md`) is referenced but not implemented. **Finish/compile the seam before Phase 02
consumes it.** Concretely, Phase 02 needs callable: `baseline_target(depth)`, `expected_per_dart(depth)`, and
(nice-to-have for handicap/coherence checks) `pressure_of(target, turns, depth)`. Other touch points:

- **x01 game** — total-dart-cap budget mode + per-race dpt override (§9).
- **Benched boss effects** — Rotation / Narrow Double / two-darts as handicaps (§8); code present.
- **Reward grant** — guaranteed typed pick filtered by `family` + earned rarity (§6); reuses the pool.
- **Darts-as-currency bank** — deposit/forfeit/refund-as-savings on `_banked_darts` (§11).
- **Run state** — track `highest_cleared`, updated on every banked win (§3).

---

## 15. Slice boundary — ship vs defer

**This phase ships:**
- `ChallengeNode` resource (§7); algorithmic placement on the off-branch fork; the §3 anchor; the §4 deposit
  derivation; the §5 dpt roll + ice-tray total-dart cap; §6 efficiency-rarity; §8 handicaps; §10 UI reuse; §11
  bank integration; §12 skip; §13 tests.
- The x01 total-dart-cap + dpt-override additions (§9).

**Deferred (explicit):**
- **Finer-than-51 challenge lattice / non-lattice targets** — only if §9's checkout caveat clears; otherwise ship
  on the leg lattice.
- **Handicap↔reward explicit balancing knobs** — rely on the §6/§8 implicit link first; add tuning only if
  observation shows a dominant node.
- **Node scarcity tuning** (how many challenges per run/section) — start with the fork's natural rarity; tune
  after feel-testing.
- **First-node identity-seed** (a gentle tutorial challenge) — the `02-challenge-nodes.md` open question; revisit
  after the post-boss-1 gate is felt.
- **Phase 03 typed shop / codex** — shares the typed-grant path (§6) but is its own phase.

---

## 16. Open tuning (numbers, dialed in-engine)

All `@export`, all moved away from a known baseline: `target_undercut` (−300), `lean_factor` (0.65),
`deposit_cushion` (+2), `dpt_min/max` (2/5), `MIN_FLOOR` for `min_deposit`, and the rarity-band split. The
deposit derivation rides the already-tuned slice-2 curve, so every knob moves away from a sane starting point.

## 17. Follow-up build pass — challenge frequency + placement (queued 2026-06-05)

After first playtest the single-fork-per-act cap made challenges too rare (a 1001 run had a ~40% chance of
*none*). `fork_chance` was bumped 0.6 → 0.85 as a stopgap, but the real fix is to stop piggybacking challenge
frequency on the generic fork. Two changes, one generator pass:

1. **Per-act challenge count (cap 3).** Replace the single `_add_fork` challenge upgrade (act ≥ 1) with **up to 3
   challenge forks per post-boss-1 act**, rolled from new config `challenges_per_act_min` / `challenges_per_act_max`
   (start `1` / `3`). Place them on **different columns** (reuse the shop spacing rule — a `challenge_min_col_gap`
   so two don't stack on one column), each on its own off-branch reconverging fork with the **parallel leg always
   intact** (skip stays structurally guaranteed, §12). Because each fork is a binary opt-in at its column and the
   player traverses one path, a single run-through should meet ~1 challenge (sometimes 2), with the other path
   carrying the rest — the routing choice Max wants. Act 0 keeps its existing single off-branch *leg* fork at
   `fork_chance` (no challenge pre-boss-1); only act ≥ 1 uses the new count.
2. **Bias placement to later columns.** A challenge fork on an act's *early* columns sits before the player has
   banked anything, so the bank gate (§11) auto-closes it and it reads as dead rather than earned. Weight
   challenge placement toward the **back half of the act's columns** so the player banks a couple of legs first
   and arrives with a real wager decision. (The bank gate stays — this just stops it firing on turn one.)

Tests: extend `tests/test_challenge_nodes.gd` — assert per act the challenge count ∈ [min, max], no two on the
same column, every challenge still has an intact parallel leg, and placement skews later. Keep all §13 invariants.

## Related
- `specs/map/02-challenge-nodes.md` — the design doc this implements; its turns↔rarity table is superseded by §2.
- `specs/map/01-substrate-slice2-impl.md` — the pressure seam (§4 reads it; §14 notes it must compile first).
- `specs/map/01-substrate-impl.md` — slice 1: the off-branch fork (§12) and the x01 seam (§9) this extends.
- `specs/map/00-overview.md` — program index; the build-steering spine this is the "earned selection" third of.
- `specs/future/darts-as-currency-economy.md` — the bank this wagers against; the deposit is a new sink (§11).
- `specs/2026-06-03-scoring-on-the-board.md` — the `family` tag the typed reward filters on (§6).
