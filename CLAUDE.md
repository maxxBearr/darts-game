# ACTIVE: Run consolidation — one continuous run, x01 ladder = acts (spec 2026-06-12)

**Goal.** Collapse the three menu-launched x01 levels (501/1001/1501) into ONE continuous
roguelike run. The x01 values become the ante ramp across three acts: Act 1 = 501 draw-down →
clear its boss → ante ramps to 1001 (Act 2) → 1501 (Act 3) → clearing 1501 = final boss / run win.
No more replaying earlier x01 from the home screen.

**Why.** Separate level entries were forced repetition, not more game — one run + stakes is the real
StS/Balatro structure. Build resets each run; benchmarks persist. The head-to-head CPU mode is a
SEPARATE later spec (sparring parked it) — do NOT fold it in here. This pass is structural
consolidation + benchmarks only, so it stays cleanly testable and unblocks real playtesting.

**Run-end condition — UNCHANGED from today (Max, 2026-06-12).** Do NOT build a new loss system.
The run ends on the existing `is_game_over` (`x01_game.gd` ~L213): dart budget exhausted without
clearing the leg (after bailout draws from the bank — see [[project-darts-currency-economy]]), plus
the Glass-Cannon-bust case. The only change is that this now ends the *whole continuous run* and
records the furthest point reached, rather than ending a single menu-launched level.

**Scope.**
1. Act ladder + the new seam = the between-act ante ramp. Preserve existing within-act leg/boss
   cadence (every-5-legs, the 4 reactive families stay as the boss roster — their later
   demotion-to-elite belongs to the head-to-head spec, not this one). DEFINE what carries across the
   seam: build/items (yes — the point), banked darts (?), board geometry/color state (?).
2. Run-end condition (above).
3. Home/menu collapse: one Play button, the old level-select surface becomes the records screen.
4. Benchmarks (persist across runs):
   - Best run: furthest act/node reached + darts taken to reach it. **Cumulative from run start**
	 (a run is one continuous count); per-act is the rejected alt.
   - Per-tier high scores: times each x01 tier cleared + fewest darts to clear it, e.g.
	 "501 ×3 — best 27 darts", "1001 ×1 — best 64", "1501 — not yet".

**Out of scope (later specs):** CPU / head-to-head, elite tier, ascension/stakes ladder (that's the
"more game" follow-up — one run is enough game once unlocks + stakes give replay reasons).

**Test.** A run actually ramps 501→1001→1501 with build/state carried; losing ends the run and
records furthest point; benchmarks persist + display; old level-select is gone. Per
[[feedback-rolled-generator-spread]]: verify benchmark numbers actually vary across runs, not a
default-inert display.

**Up next in the queue (behind this spec):** codex (Phase 03 remainder, part 2 — the
family-literacy exposure layer; reuses the five `sprites/Icons/` family icons from the typed-shop
slice, don't build a second set). Program index: `specs/map/00-overview.md`.

**Watch item (not an active spec, but don't lose it):** the brush ↔ Color Territory resize
report. Claude Code's headless harness (`tests/repro_brush.tscn`, run by scene path — it needs
autoloads, so it is NOT in the `--script` auto-suite) drove BOTH orderings and the wedge band
resized correctly every time (0.0700→0.0885); §4a now makes the hotspot smoke track the reflow
too. So the likely-real symptom (overlay sitting at the old size) is fixed — BUT this is a
couldn't-reproduce, not a found-root-cause. If the *wedge band itself* (not just an overlay) is
ever seen failing to grow in live play, the bug is still live; re-open with `debug_geometry_log`.

**Recently shipped (archived, newest first):**
- Reward cleanup + geometry stacking — geometry stacks again w/ per-stack decay, cut +dart/+turn
  rewards, 2/3 bailout floor, All In→Tunnel Vision (suppress-accuracy), global Pool Widener, gold
  bull relic channel — `specs/2026-06-08-reward-cleanup-geometry-stacking.md` (on-disk uncommitted,
  pending live confirm)
- Typed shop + family icons + map-quality rules (Phase 03 remainder, part 1) —
  `specs/map/04-typed-shop-impl.md` (shipped 2026-06-07, 2026-06-08 follow-ups tested green:
  brush ungated+unbiased, shop graph-spacing, drought breaker, branch divergence, density pass)
- Leg lattice — per-act monotone (score, turns) frontier for act legs — `specs/2026-06-07-leg-lattice.md`
- Geometry items — the GEOMETRY family + Parity Out + streaks-in-challenge-draw — `specs/2026-06-07-geometry-items.md`

Conventions as always: static-type everything, comment frequently, exported tunables with `##` hover
descriptions. When a change touches an existing system, scan `specs/` for any prior decision that
constrains the new work.

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
