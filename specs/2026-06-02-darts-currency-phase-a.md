---
Spec date: 2026-06-02
Status: Shipped ~2026-06-03 (Claude Code pass + Max's debugging). Commits `c15d980 phase 1 of
  stored darts currency`, `3277639 sound effects`, `754dbd7 working dart currency`.
Implementation: Claude Code, then hand-debugged by Max. Confirmed in code 2026-06-03.
Notes: Shipped faithfully to spec. As-built confirmations: persistent bank is `_banked_darts`
  (`main.gd:264`) — grows by `get_saved_darts()`, only shrinks by spending (shop or bailout),
  reset to 0 on run start; the `_end_shop` wipe is gone (it now banks the unspent remainder).
  Bailout is `_try_bailout()` (`main.gd:1053`), called from BOTH game-over interceptions
  (`main.gd:755/786`) as `is_game_over and not _try_bailout(...)`; Glass Cannon never bails;
  needs ≥ `darts_per_turn`; raises `max_turns` and spends the cost, with unused bailout darts
  refunding via the normal `get_saved_darts()` path on leg win; repeats until checkout or bank
  dry. HUD feedback shipped (`hud.bank_leg_savings`, `hud.show_bailout`) plus sound effects. The
  "Current state (confirmed in code 2026-06-02)" section below describes the PRE-implementation
  baseline (the plan), not the final state — see this header for what actually shipped. Phase B
  (typed shop rings) remains parked in `specs/future/darts-as-currency-economy.md`; the broader
  mid-game rebalance continues in `specs/future/map-pool-filtration.md` and
  `specs/future/scoring-on-the-board.md`.
---

# Spec: Darts as Currency — Phase A (Persistent Bank + Bailout + Rail UI)

**Status: ready to implement (2026-06-02).** Phase A is the *resource layer* of the darts-as-
currency economy: make banked darts persist and grow across a run, let them rescue you from a
lost leg, and show the whole thing on a dart-icon rail. **Typed shop rings are Phase B and are
explicitly out of scope here** (they need a separate design fork — see the exclusion note). Full
vision and rationale: `specs/future/darts-as-currency-economy.md`. The shipped accuracy rework
this builds on is archived at `specs/2026-06-02-accuracy-upgrades-as-shape.md`.

## Why this, why now

The accuracy rework removed accuracy as a power-progression axis (it's reshape-only now). Banked
darts + shop investment are the intended **replacement climb** — the run-spanning "I'm getting
stronger" engine. This phase builds the resource itself so we can playtest its feel before
layering the harder typed-shop work on top. It's a big chunk and needs real testing, so it ships
alone.

## Current state (confirmed in code 2026-06-02)

- **Leg front is 15.** `x01_game.gd`: `@export var max_turns: int = 5`, `var darts_per_turn: int
  = 3`. Set/reset in `main.gd` (`x01_game.max_turns = 5`, `darts_per_turn = 3`).
- **Per-leg savings already computed.** `x01_game.gd:149` `get_saved_darts()` returns
  `max(max_turns*darts_per_turn − darts_used_in_leg, 0)`. Busts already fold their wasted darts
  into `darts_used_in_leg` (`x01_game.gd:120-123`) — so **busting already forfeits those darts
  from savings.** (This is exactly what the rail's dimmed-red "busted darts" state should mirror.)
- **Loss condition exists.** `x01_game.gd:129` `is_game_over = (is_turn_over and current_turn >=
  max_turns and not is_leg_won) or (is_bust and glass_cannon_active)`. The branch Phase A
  intercepts is the **first** half (out of turns, no checkout) — NOT the Glass Cannon half.
  Handled in `main.gd:750` / `main.gd:781`: `if response["is_game_over"]: _run_over = true;
  _show_game_over(...)`.
- **Bank today is a per-shop-window accumulator, then wiped.** `main.gd` `_saved_darts_accumulator`
  (declared ~263, comment "across the current 3-leg window") accrues `get_saved_darts()` each leg
  (~873), seeds `_shop_darts_remaining` at `_start_shop` (~1231), and is **zeroed at `_end_shop`**
  (~1555) and on run start (~1160). So unspent darts do NOT persist past a shop today.
- **Throw-to-buy already exists.** Shop spends from `_shop_darts_remaining` via thrown darts
  (`hud.gd` `enter_shop_mode`, "Thrown: 0 / N").

## The three deltas

### 1. Make the bank persistent

Today's accumulator resets each shop. Change it to a **persistent run-long reserve** that only
ever goes down by spending (shop or bailout) and up by leg savings. Concretely: stop zeroing it at
`_end_shop` — instead decrement it by what was actually spent in the shop, and keep the remainder.
Leg savings continue to add via `get_saved_darts()`. Still reset to 0 on run start. Rename for
clarity is welcome (`_banked_darts` rather than `_saved_darts_accumulator`), but keep the shop's
existing read path working.

### 2. Bailout (decided rules — implement exactly)

When a leg would end in `is_game_over` via the **out-of-turns branch** (not Glass Cannon) and the
bank holds **≥ 3**, do NOT end the run. Instead:

- **Grant a bailout turn funded from the bank** (spend 3, raise the effective turn ceiling by one
  so the player throws another turn). Mechanically this is "let `max_turns` extend / add a turn"
  for this leg, paid for from the bank.
- **Repeat until the player checks out or the bank drops below 3** ("bail until checkout or bank
  dry"). No fixed per-leg cap — the bank is the only limit.
- **Automatic** — fire the instant they'd otherwise lose; no confirm prompt (declining is never
  correct, since a lost leg ends the run). Give clear feedback: a bank cluster visibly flies in to
  form the new turn (see UI).
- **Need a full 3.** With 1–2 banked, no bailout is possible → the run ends, and the stranded 1–2
  darts are lost with it.
- **Bailout turns refund like any turn.** Unused darts from a bailout turn return to the bank via
  the same `get_saved_darts()` path (check out on the first dart → the other two go back).

### 3. Rail UI (full design in the future spec; essentials here)

Replace the bottom-left revolving-three-darts element with a **left-rail dart tally** built from
the existing dart-component PNG (no new art):

- **5 sets of 3 icons** = the 15 fronted darts, grouped in threes so "3 = a turn" is spatial.
  Collapses "darts this turn" + "turns left" into one array. Relics reshape it and it self-
  explains (+1 Dart/Turn → sets of 4; +1 Turn → 6 sets). Must flex to hold 18–20+ icons.
- **States:** bright = available; **white outline + slight scale-pop = active turn** (so
  darts-left-this-turn reads at a glance, subtle, no neighbor reflow); **dimmed/grey = spent**;
  **dimmed + red-tint = busted** (forfeited darts). Set completion plays a **cross-out slash as a
  transition animation**, not a persistent state. Red is reserved for busts (it already means the
  deep-imbalance accuracy zone and a per-ring board color — a plain spent dart must NOT be red).
- **Saved cache speaks the same language:** banked darts snap into **clusters of three**; each
  completed cluster lights a **bonus turn** (self-documenting; summarize past a threshold with
  "+N" so a big hoard doesn't overflow).
- **Beats:** leg start = quick, interruptible fill of the sets (full version only when the front
  differs from 15 via a relic); leg win = unused darts fly into the cache completing clusters,
  *then* the reward pick (pair with existing turn-end pitch-tension audio); during an active
  throw = rail stays calm (consistent with hover-off-during-throw).

## Touch points

- `scripts/x01_game.gd` — `is_game_over` (`:129`) and the turn-advance path; bailout extends the
  turn ceiling for the leg. `get_saved_darts()` (`:149`) is reused for bailout-turn refunds.
- `scripts/main.gd` — `_saved_darts_accumulator` → persistent bank (stop the `_end_shop` reset
  ~1555; decrement-by-spend instead); the game-over interception at `:750`/`:781` (offer bailout
  before `_run_over = true`); shop seed at `_start_shop` (~1231) reads the persistent bank.
- `scripts/hud.gd` — the dart rail (`update_darts`, `update_turn`, `enter_shop_mode`, the
  dart indicator / revolving-darts element) becomes the icon tally + saved-cache clusters.
- Audio: reuse `AuidoManager` turn-end pitch tension for the bank trickle/count-up (note the
  existing filename typo "auido").

## What Phase A does NOT do (and why)

- **No typed shop rings.** Making a ring grant an *accuracy* upgrade requires promoting accuracy
  out of its own system (`UPGRADE_TYPES` / `_show_accuracy_pick`) into the shop reward pool — the
  unresolved fork from `map-pool-filtration.md` (#2). That needs its own design pass. Phase A runs
  against the **existing untyped shop**.
- **No map, no boss-cadence change, no onboarding/tutorial work.** Teaching the new mental model
  is real and tracked in the future spec's "Still to design," but it's after the mechanic feels
  right.

## Acceptance

- Unspent darts persist across legs and across shops (no wipe at `_end_shop`); the bank only drops
  by spending.
- Running out of turns with ≥3 banked grants automatic bailout turns until checkout or bank < 3;
  with < 3 banked, the run ends as before. Glass Cannon busts still end the run immediately.
- Bailout-turn leftovers refund to the bank.
- The rail shows fronted darts in 3-groups with the four states, the active set popped, busts
  dimmed-red; the saved cache shows clusters/bonus-turns; leg-win trickles unused darts in.
- Vanilla feel during a throw is unchanged (rail calm, no per-dart prompts).
