---
Spec date: 2026-06-08
Status: Shipped 2026-06-08 (Claude Code pass, on-disk + uncommitted at archive time; git HEAD
  `911ee84` predates it). Pending Max's live-play confirmation.
Implementation: Claude Code. Verified against current code during the archive pass — all six
  sections landed as specced (renames/refinements noted below).
Notes: Designed in a Cowork sparring session (Max + Claude, 2026-06-08) off post-typed-shop
  playtesting. Six coupled reward/geometry tuning changes. Implementation deltas vs this spec:
  - §4 relic renamed "All In" → **Tunnel Vision** (`tunnel_vision_reward.gd`).
  - §5 lever named `main.option_bonus` (run-scoped int), NOT a `shop_pick_count` bump; the
    per-leg upgrade surface no longer exists (retired earlier), so it wires to events /
    accuracy events / challenge rewards / shop picks.
  - §1 decay lives in `GeometrySolver.decayed_cumulative` (pure/headless) with the manager
    aggregating same-fingerprint stacks; offer-gate via `_owned_geometry_stack_counts()` +
    `pow(decay, owned) < epsilon`.
  - §3 partial bail switches the leg onto `x01_game.dart_budget = max_turns*darts_per_turn + cost`.
  - New tests: `tests/test_rewards.gd`; geometry stacking cases in `tests/test_geometry.gd`.
  Program index: `specs/map/00-overview.md`. Next queued: codex (Phase 03 remainder, part 2).
---

# Reward cleanup + geometry stacking (2026-06-08)

A batch of reward/geometry tuning locked in a Cowork sparring session (Max + Claude, 2026-06-08)
off post-typed-shop playtesting. Six coupled changes, one theme: **make the item economy reward
commitment instead of quietly neutralizing it, and retire the rewards that mutated knobs the map
now owns.** Static-type everything, comment frequently, exported tunables carry `##` hover docs.

## 0. Why these six travel together

The thinned boss-reward pool (§2 cuts two, §4 retools one) is exactly what motivates the shop
relic channel (§6): bosses get leaner, so relics gain a second home. And the geometry-stacking
fix (§1) and the suppress-accuracy relic (§4) are the same insight from two angles — the current
pools punish or stall a committed build (collect-everything walks the board back to neutral; a
finished accuracy shape keeps drawing aim-trades it doesn't want). Each section is independently
shippable, but they were designed as one pass; keep the rationale.

## 1. Geometry items stack again — with diminishing per-stack decay

**Bug we're fixing (verified in code):** geometry can't stack, but not because the math forbids it —
`recompute_geometry()` already sums Ring Trade dials and multiplies Color/Parity rules per copy.
The block is at the OFFER layer: `_generate_geometry_event_picks` (main.gd ~1123) skips any entry
whose `get_config_fingerprint()` is already owned, so you own exactly one of each of the eight.
Worse, the eight are pairwise zero-sum against EACH OTHER (Wide Triple cancels Wide Double; the
four Grow-colors renormalize within each wedge; Grow Even cancels Grow Odd), so a player who
greedily takes every geometry node offered is actively walking the board back to neutral. The
design punishes collecting. **The fix lets you commit to a direction harder than one item allows.**

- **Remove the owned-skip for geometry** in `_generate_geometry_event_picks` (the shared
  event+shop geometry path — `_generate_shop_picks` routes `&"geometry"` here too, main.gd ~2098).
  Keep WITHIN-draw distinctness (don't show the same entry twice in one pick); only the
  across-runs "already owned → never offered again" skip goes.
- **Geometric per-stack decay (the brake on runaway stacking).** Marginal effect of stack *k* =
  `base × decay^(k-1)`, summed — so the cumulative effect asymptotes. With Color Territory's
  `growth_factor = 0.30` and `decay ≈ 0.65` the sum tops out at `0.30 / (1 − 0.65) ≈ 0.86` no
  matter how many you stack, with the existing `ring_band_floor` / `wedge_angle_floor` as the hard
  backstop underneath. Same curve for Ring Trade's `triple_shift` and Parity Shift's
  `weight_factor` (a factor decays toward 1.0, not 0.0 — decay the *excess over 1*).
  - Implement in the MATH layer, not at acquire time, so it stays dynamic: `recompute_geometry()`
    (scoring_modifier_manager.gd ~221) already groups rules by reading `active_modifiers`; have it
    AGGREGATE same-fingerprint stacks and pass a decayed cumulative magnitude to `GeometrySolver`
    (geometry_solver.gd), rather than appending each copy at flat magnitude. New exported tunable
    `geometry_stack_decay: float = 0.65` (`##` hover) on the manager, alongside the existing floors.
  - GeometrySolver stays pure/headless-testable; the decay sum can live there or in the manager's
    aggregation step — keep it where it's unit-testable without autoloads (the EventRewards pattern).
- **Don't ship a dead offer (the `[[feedback-rolled-generator-spread]]` lesson).** Once a stack is
  near its asymptote/floor, its next copy does ~nothing — re-offering it is an inert card. Gate the
  offer off when the marginal effect of one more stack drops below an epsilon (compute the next
  stack's delta; skip the entry if < `geometry_stack_offer_epsilon`, exported). This is the soft
  cap — no hard stack count needed; the curve + epsilon self-limit.
- **Studs (geometry spec §5):** a stacked item shows ONE stud with a stack count + the live
  cumulative effect in its tooltip (e.g. "Grow Red ×3 — red bands +71%"), not three studs.

## 2. Cut the +dart-per-turn and +turn rewards

`ExtraDartReward` (`darts_per_turn += 1`) and `ExtraTurnReward` (`max_turns += 1`) mutate knobs the
map now OWNS, not player-facing power. `max_turns` is set per-leg by the leg lattice (a leg is
*defined* by its turn budget; the generator seeds pressure off turns=5), so a run-wide +1 desyncs
the generator's pressure math. `darts_per_turn` is baked into bailout cost, the
`winning_turn_all_darts_scored` unlock test, streak cadence, and the whole 3-dart-turn assumption.
And +turn is doubly redundant — the bank already buys turns via bailout (the sanctioned
"replacement climb"). Cut both.

- Remove `extra_dart.tres` and `extra_turn.tres` from `RewardRegistry.ALL_REWARDS`
  (scripts/rewards/reward_registry.gd). Delete the two `.tres` + reward classes, or sideline them
  FlipSign-style (class kept, unlisted) if you'd rather not churn — Max's call at impl; prefer
  delete since nothing references them.
- Sweep for readers: anything assuming these rewards exist (reward-pool tests, any tutorial/codex
  copy that names them).

## 3. Bailout floor → 2 darts, as a conserving partial turn

Today `_try_bailout` (main.gd ~1646) requires `_banked_darts >= darts_per_turn` (3) and grants a
full extra turn for 3. Max wants the floor at 2 — but explicitly **no free dart spawned**: pay 2,
get a turn that reads **2/3 darts**. That's conserving (you buy exactly what you pay for) and it's
already expressible via the flat-budget seam, no new turn machinery:

- x01_game has `dart_budget` (line 26): `0` = legacy `max_turns × darts_per_turn`; non-zero = an
  explicit flat dart budget, and `darts_remaining = min(darts_per_turn − darts_this_turn,
  budget_left)` (line ~197) already caps a turn's visible darts by the remaining budget. So a
  bailout that adds EXACTLY the darts paid to the budget yields a short final turn automatically.
- **New bailout rule:** floor is 2. When the bank can afford a full turn (≥ `darts_per_turn`), bail
  at full strength as today (pay 3, full turn). When it can only afford 2, switch the leg onto the
  flat `dart_budget` path and add exactly 2 darts → the rescue turn reads 2/3 and ends after two
  darts. `cost == darts added`, so the bank conserves exactly (no free dart — this preserves the
  invariant the current `cost = darts_per_turn` comment leans on).
- Floor reading confirmed (Max): 2 is the *minimum*, full turn preferred when affordable — not an
  always-available "cheaper short turn" choice. Export `bailout_min_darts: int = 2` (`##` hover).
- Glass-Cannon / challenge-race exclusions unchanged (a fixed wager still can't bail).

## 4. All In → "suppress accuracy" relic (retool + rename)

`AllInReward` ("shops only offer modifiers — no more accuracy upgrades") is outdated: in the typed
shop you already choose the family by which spot you hit, so "no accuracy in the shop" means almost
nothing. Retool it into a relic that **strikes accuracy from the family roll for the rest of the
run** — and architect the suppression generically.

- **Don't literal-reroll** (a reroll-until-not-accuracy loop has a degenerate all-accuracy case).
  Remove accuracy from the roll TABLES so nothing accuracy-typed can spawn in the first place:
  drop `&"accuracy"` from `shop_family_weights` (main.gd ~358) and from the `_roll_event_node`
  families list (map_graph.gd ~665, `[&"accuracy", &"brush", &"geometry"]`). Challenge rewards are
  already `[SCORING, STREAK]` — no accuracy there — so scope is events + shop only.
- **Generic `suppressed_families: Array[StringName]`** (run-scoped, on the run-state / main) that
  both roll sites filter against, so a future relic can suppress another family. The relic's
  `apply()` just appends `&"accuracy"`.
- **Why it's a thing to WANT, not just "less":** accuracy is the one family with a natural
  *finished* state — it's redistribution, not a climb (`[[project-accuracy-as-shape]]`), so once a
  shape is set you don't want more swaps. Suppressing it concentrates every future roll into
  families that still advance the build, and collapses events to brush+geometry — which feed each
  other (paints make boards asymmetric, asymmetry makes geometry interesting). Identity: "stop
  offering me aim trades, double down on board-shaping." Rename off "All In" (e.g. Tunnel Vision /
  Specialist — Max picks). Update `reward_id`, display name, description; keep the `excludes[]`
  entry if any pairing still applies.

## 5. Pool Widener → global "+1 option" on every choice surface

`PoolWidenerReward` does `shop_pick_count += 1`, which is muddy in the typed shop (some pick paths
read it, the event/accuracy card UI is hardwired to 3 buttons). Make it a clean global: **+1 option
on every surface the player picks from** — shop spots, events, challenge rewards, leg upgrades.

- The shop family pick paths already read `shop_pick_count` (main.gd ~2092); confirm all four
  family branches honor it AND the HUD renders the extra card.
- Extend to the other surfaces: event `option_count`, challenge-reward pick count, leg-upgrade
  count. The event/accuracy upgrade-card UI is "hardwired to 3 buttons" (main.gd ~1138) — it needs
  to render a VARIABLE count for this to land there; do that small UI lift or scope-flag any surface
  you can't reach this pass (don't half-apply silently).
- Keep it a single run-scoped `+1` (stackable per §6 if Max wants a +2 ceiling). Rename optional.

## 6. Gold relic channel in the shop (the bull) + reward typing

Boss rewards become shop-purchasable so the thinned pool gains surface area and relics turn
seekable. The spine law refines, doesn't break (same as the typed-shop trade retrofit): **bosses =
earned run-defining prizes; shop = incremental relics you chose to fish for.**

- **Eligibility = run-definer vs utility, NOT stackable-vs-unique.** Unique relics are perfectly
  shop-able — you buy one once and it drops out of the pool (the owned-dedup we already run). The
  cut that matters:
  - **Boss-only (stay earned):** Glass Cannon, the §4 suppress-accuracy relic, Mirror Zone — these
    reshape the whole run.
  - **Shop-eligible (incremental):** Lucky Eye, Triple Outs, Bigger Bull, Pool Widener (§5). Tag
    each `RuleModifierReward` with a `shop_eligible: bool` and a `stackable: bool`
    (re-buyable vs pulled-once-owned) — `stackable` decides repeat offers, NOT eligibility. Keep
    the existing declarative `excludes[]` (rule_modifier_reward.gd:26) for mutual exclusion.
- **Placement — the full bullseye.** The bull is dead space in the shop today and a fitting premium
  home (bonus theming: Bigger Bull literally grows that spot). The relic spot is a SEPARATE slot,
  not one of the `lit_count` family spots (`ShopSpotGenerator.generate`, main.gd ~1980) — so a shop
  shows its usual family spots PLUS, at `relic_spot_chance = 0.40` (export), one gold relic on the
  bull, `cap 1`. When it doesn't roll, or every shop-eligible relic is already owned, the bull stays
  dark (built-in exhaustion fallback). Claim target = the WHOLE bull (single + double) — start easy,
  dial back later if needed (Max's rule).
- **Hit detection seam:** lit spots are `wedge:ring` keyed; the bull isn't per-wedge. "Hit the bull
  → open the relic pick" is a small dedicated path in the shop-throw resolver
  (`_resolve_shop_impact`, main.gd ~1989) reading `bull_radii` like `calculate_score` does — not a
  reuse of the wedge-spot lookup.
- **No premium price — every shop spot costs exactly one THROW** (you enter with throws = banked
  darts; `_shop_darts_remaining -= 1` per hit; there is no per-item dart price). So a relic is one
  throw like everything else; its specialness is the 40%/cap-1 scarcity + run-definers staying
  boss-only. (We considered "hit it twice" for premium feel and rejected it — fiddly, RNG-punishing
  for what should read as a treat.)
- **Visuals:** reuse the flat-fill spot treatment (geometry/brush style — relics aren't
  rarity-laddered) tinted GOLD (`shop_color_relic` export), with a 6th relic glyph drawn on the
  spot (Max is dropping the glyph in `sprites/Icons/`). Re-derive on reflow like every other
  region-attached visual (typed-shop §4a). Add a `&"relic"` icon entry to `EventFamilyIcons`.
- **Follow-up (2026-06-10): the channel is now GATED, not always-on.** The relic spot no longer
  lights in any shop by default — it's opt-in behind the new boss-only `Relic Subscription` reward
  (`relic_subscription_reward.gd`), which flips `main._relic_shop_unlocked`. Until that's owned the
  bull stays dark, so a relic can't appear before a boss is beaten (relics stay earned/premium).
  After unlock the `relic_spot_chance = 0.40` roll + exhaustion fallback apply unchanged. The gate
  lives in the pure `RewardRegistry.roll_gated_shop_relic` (headless-tested). Boss-only +
  unique, with a 501 dead-pick guard (`is_applicable` false when `boss_count <= 1`).

## 7. Tests

- **Geometry stacking:** the owned-skip is gone — the same entry can be offered/acquired twice;
  stacking ×N produces the DECAYED cumulative (assert the geometric sum, not N× flat); the offer is
  gated off once the next stack's delta < epsilon (assert a near-maxed item stops being offered);
  floors still hold under a spam stack; opposite stacks still net to base. NOT-inert check survives
  (default magnitudes still move the board on the first stack).
- **Rewards:** `ALL_REWARDS` no longer contains extra_dart/extra_turn; pool-generation tests updated.
- **Bailout:** with 2 banked and a would-be-ending leg, bail fires, grants a 2-dart turn, bank
  conserves (paid == darts added, no free dart); with ≥3 banked, full turn as before; floor at 2.
- **Suppress-accuracy:** after the relic, no event or shop spot ever rolls `&"accuracy"` across a
  seed grid (distribution, not just membership); challenge rewards unaffected; the generic
  `suppressed_families` filter is read at both roll sites.
- **Pool Widener:** +1 option observed on each wired surface; the variable-count card UI renders
  3+1 without overflow.
- **Relic channel:** across seeds, ≤1 relic spot per shop, appears ~40% when the eligible pool is
  non-empty, never when exhausted; only shop-eligible (utility) relics appear, never the
  run-definers; unique relics pulled once owned, stackable re-offered; a bull hit opens the relic
  pick (hit-detection path); the gold spot re-derives on reflow.
- Existing shop / map / challenge / geometry suites green; `--check-only` parse pass on every
  changed script.

## 8. Tunables introduced (all exported, `##` hover docs)

`geometry_stack_decay` (0.65), `geometry_stack_offer_epsilon`, `bailout_min_darts` (2),
`relic_spot_chance` (0.40), `shop_color_relic` (gold). Magnitudes are starting points — keep dead
easy to retune in the inspector.
