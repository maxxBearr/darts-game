# ACTIVE: (none — between specs)

No feature is currently being designed or implemented. Drop the next spec here when a Cowork
sparring session locks one; it auto-loads into every Claude conversation in this repo, so keep it
lean and focused on one thing at a time.

**Up next in the queue:** codex (Phase 03 remainder, part 2 — the family-literacy exposure layer;
reuses the five `sprites/Icons/` family icons from the typed-shop slice, don't build a second
set). Program index: `specs/map/00-overview.md`.

**Watch item (not an active spec, but don't lose it):** the brush ↔ Color Territory resize
report. Claude Code's headless harness (`tests/repro_brush.tscn`, run by scene path — it needs
autoloads, so it is NOT in the `--script` auto-suite) drove BOTH orderings and the wedge band
resized correctly every time (0.0700→0.0885); §4a now makes the hotspot smoke track the reflow
too. So the likely-real symptom (overlay sitting at the old size) is fixed — BUT this is a
couldn't-reproduce, not a found-root-cause. If the *wedge band itself* (not just an overlay) is
ever seen failing to grow in live play, the bug is still live; re-open with `debug_geometry_log`.

**Recently shipped (archived, newest first):**
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
