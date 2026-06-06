# ACTIVE: Playtest round 3 — challenge feel + transition cleanup (2026-06-06)

Four items from Max's first live challenge playtest (rounds 1+2 build, still uncommitted on top of
`529c1e4` — archived at `specs/2026-06-06-playtest-tuning-rounds-1-2.md`). Items are independent;
suggested order is as listed (1 and 4 touch the same intro seam, do them in this order so the intro
contract is settled before the transition cut). Conventions as always: static-type everything, comment
frequently, exported tunables with hover descriptions.

## 1. Leg intro: rail fill becomes its own final step (sequencing fix)

Max's note: the fronted-rail trickle-fill runs *simultaneously* with the readout flights, so the player
never sees what's happening on the rail.

- `scripts/hud.gd::play_leg_intro`: move `dart_indicator.play_intro_fill()` from before the three
  `_fly_intro_label` awaits to AFTER them. The rail fill becomes the fourth sequential, skippable step
  (click already routes to `skip_intro_fill()` once `_intro_step_tween` is null — that path now becomes
  the normal one rather than the long-budget fallback). The `is_intro_fill_active()` guard before the
  await can simplify to a straight `await dart_indicator.intro_fill_finished` after starting the fill —
  but keep a zero-row safety (a fill with no rows must still emit, or be guarded, so the intro can't hang).
- REWRITE the "Rail fill runs alongside the label flights — overlapping keeps the intro short" comment:
  the rationale inverted (Max 2026-06-06) — the fill is the payoff being *presented*, so it now waits for
  the readouts; sequential beats short.
- Budget: sequential adds the fill's full duration (~+1 s on a 5-turn leg). Tighten the
  `intro_fill_row_interval` default in dart_indicator.gd to keep the default total ≤ ~3.5 s; it's
  exported, so document the trade in its hover description.
- No main.gd changes — `leg_intro_finished` / `conceal_for_leg_intro` contracts are untouched.

## 2. Challenge deposit cap: max deposit ≤ 12, enforced by capping the TARGET

Max's note: an early act-0 challenge offered a 12–17 deposit band — "no way you are going to be able to
do that most of the time". (Rounds-1+2 §Round-2.3 predicted this: "report silly bands".) Design decision
(Max's pick): cap the **target** so the race stays fair — deposit = wager = race budget is the
load-bearing rule (02-challenge-nodes-impl §5), so clamping only the band would offer a race whose budget
is below what its target fairly needs. Early challenges become *concise rematches* of cheaper numbers.

- `scripts/map/challenge_node.gd`: new export `max_deposit_cap: int = 12` with hover description (hard
  ceiling on the band's top end; enforced upstream by clamping target_score, NOT by squeezing the band —
  see compute_challenge_params).
- `scripts/map/map_graph.gd::compute_challenge_params`: after the anchored target roll/snap/clamp,
  apply the affordability clamp BEFORE deriving the band:
  - `reliable_cap := maxi(c.max_deposit_cap - c.deposit_cushion, 1)` — so the derived
    `max_deposit = reliable + cushion` lands ≤ the cap.
  - `cap_target := reliable_cap × expected_per_dart(node.depth)`, snapped **DOWN** to the leg lattice
    (nearest-snap could round up and break the cap — add a snap-down helper or floor the `n` in `_snap`'s
    math locally), floored at `_starting_target`.
  - `c.target_score = mini(c.target_score, cap_target)`.
  - Derive `reliable` / band from the clamped target exactly as today.
- **Degenerate corner (this IS the early game, document it):** when `cap_target` falls below
  `_starting_target`, the lattice floor wins (targets must stay checkout-legal), `reliable` recomputes
  above `reliable_cap`, and the band would still blow past the cap. Safety net: after the band derivation,
  `c.max_deposit = mini(c.max_deposit, c.max_deposit_cap)` and `c.min_deposit = mini(c.min_deposit,
  c.max_deposit)`. These early races are deliberately lean (pressure > 1) because `_starting_target` is
  the cheapest legal number — acceptable per Max ("never want more than ~12"); the finer sub-251 lattice
  stays deferred (02 §15). Comment the why at the clamp site.
- The existing `min_deposit_floor ≤ min ≤ max` contract and `challenge_entry_view` need no changes (the
  picker just reads the band) — but verify the §4 hover docs on `lean_factor` / `deposit_cushion` still
  read true and mention the cap.
- **Tests** (`tests/test_challenge_nodes.gd`): across the existing seeds × depths × highest_cleared grid
  assert (a) `max_deposit ≤ max_deposit_cap` ALWAYS; (b) the clamp is NOT inert — at early
  highest_cleared values (~101–301) some rolls must actually get pulled down vs the unclamped derivation
  (distribution check, not just bounds — a default tuning value can ship a feature inert); (c) it doesn't
  bind everywhere — report (or assert, if stable across seeds) that some late/cheap configs pass through
  unclamped; (d) target stays ≤ highest_cleared, lattice-legal, ≥ `_starting_target`.

## 3. Challenge loss: banner + click-to-continue (no more instant boot)

Max's note: the last dart hits and the screen just changes — no beat, totally unclear. Today
`main.gd::_fail_challenge` is `show_bust("CHALLENGE FAILED — wager forfeit")` + a 1.6 s timer → `_show_map()`.

- New `hud.show_challenge_lost(forfeit: int, bank_left: int)`: centre-screen banner in the
  `show_bailout` / leg-won visual register (scale-in + outline; red-leaning palette) — headline
  "CHALLENGE LOST", sub-line "Wager forfeit: N darts  —  Bank: M". It HOLDS until a left click anywhere,
  then fades out. Reuse the `_intro_blocker` full-rect pattern for the click capture (`move_to_front`;
  separate active flag or a shared one — but don't let intro skip-state and loss-dismiss state cross).
  Exports for font size / colors / fade timing with hover descriptions (follow the `leg_won_*` pattern).
  Expose dismissal as an awaitable signal (e.g. `challenge_lost_dismissed`).
- `main.gd::_fail_challenge`: keep the teardown exactly as is (handicap end, dpt restore, budget zero,
  `AuidoManager.on_leg_lost()`, bank label update) — then set `_leg_phase = "challenge_lost"` (gate
  aiming/hover/checkout-path cycling like "leg_intro" does), call the banner with `_challenge_deposit`
  (already stored at confirm) + `_banked_darts`, await dismissal, then `set_remaining_bust(false)` and
  `_show_map()`, clearing `_leg_phase`. Drop the `show_bust` call and the `create_timer` entirely (the
  bust label is the wrong register for a race loss; in-race busts that merely end a turn are untouched).
- Seam to watch: `_fail_challenge` runs as a `score_tween` callback — awaiting inside a tween callback is
  the same known-good pattern as the slide-in intro await. Also verify a loss on the very last banked
  dart (bank 0 after forfeit) renders sanely ("Bank: 0").

## 4. "Return to Map" + cut the map→leg board slide

Max's note: the button leads to the map now, not a next leg — and with the leg intro doing the
presentation work, the old leg-to-leg board slide is a vestige.

- `scripts/hud.gd`: `reset_next_leg_button()` and `show_shop_complete()` set text "Return to Map"
  (was "Next Leg"). Shop entry/leave texts ("Enter Shop (...)", "Leave Shop (...)") unchanged. Keep the
  `%NextLegButton` node name and `next_leg_pressed` signal (scene rename not worth the churn) but update
  the comments at `_on_next_leg` / the signal docs to say "return to map".
- `main.gd`: remove the board slide from the map→leg path. Restructure `_on_map_node_chosen` +
  `_slide_to_leg_node` (rename to `_enter_leg_node`; update the no-repeat comment that names
  `_slide_to_leg_node`): for LEG/BOSS nodes, do ALL the arrival work that used to hide behind the
  slide-out — `claim_unplayed_leg_params`, `reset_for_leg`, `_clear_darts`, `start_leg_with`,
  `_update_all_hud`, streak section, `conceal_for_leg_intro`, boss setup — **while the map overlay is
  still visible** (the overlay is the new off-screen moment), THEN `map_view.visible = false`, then
  checkout highlights/helper, `_leg_phase = "leg_intro"`, `play_leg_intro` → await → boss announcement /
  `_start_new_throw` (unchanged tail). Note `_on_map_node_chosen` currently hides the map up front for
  ALL node types — only the leg path defers hiding; shop/challenge/event keep their current order.
- **Challenge races keep their slide** (`_start_challenge_race`): they have no leg intro, so the slide is
  their only transition. `leg_transition_duration` therefore STAYS exported — re-document its hover text
  as the challenge-race slide duration (don't rename the export; scene-stored values).
- Verify the first-leg entry point (`_on_run_confirmed`) still concedes/intros correctly — it never slid,
  so it should be untouched, but it shares the intro contract item 1 just changed.
- Live check: picking a leg node must not visibly pop darts off the board — if MapView turns out not to
  fully cover the board area, fall back to clearing at the map-hide frame (still no slide).

## Tests + checklist (all items)

- Suites: `test_map_graph.gd`, `test_events.gd`, `test_challenge_nodes.gd` (item-2 asserts added) +
  `--check-only` parse pass on every changed script.
- Live: intro = three readouts THEN rail fill, per-step click-skip still works on all four steps, default
  total ≤ ~3.5 s; debug an early challenge (highest_cleared ~101–301) → band tops out ≤ 12; lose a
  challenge → banner holds until click, no aiming during it, map after; win path + leftover-wager banking
  unchanged; leg win → "Return to Map" → map → pick leg → intro starts with NO board slide and no visible
  dart-pop; shop enter/leave texts + shop slide unchanged; challenge race still slides in; boss
  announcement still lands after the intro.
- Known seams: `_leg_phase` values now include "challenge_lost" — sweep the phase-gated inputs (bailout,
  checkout cycling, hover) for the new value; awaits inside tween callbacks (two sites now).

**After this ships:** archive per Workflow Notes (`specs/2026-06-06-playtest-round-3.md`), then the queue
resumes: more tuning dials if playtest demands, **geometry items**, **typed shop + codex**. Program index:
`specs/map/00-overview.md`. Challenge context: `specs/map/02-challenge-nodes-impl.md`. Rounds 1+2:
`specs/2026-06-06-playtest-tuning-rounds-1-2.md`.

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
