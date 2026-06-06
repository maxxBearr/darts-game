# Map Program — Substrate Slice 3 + Event Nodes (ACTIVE: two impl specs ready to build, in order)

**Active specs (build in this order):**
1. `specs/map/01-substrate-slice3-impl.md` — **topology v2**: ~12-node *per-act traversed* paths, multi-node
   branch segments (two parallel 3–5 node runs that reconverge), challenges re-homed inline onto branch runs
   (skip = the other run; hard invariant: a challenge never sits without a parallel). Supersedes the single-node
   `_add_fork` and `02-challenge-nodes-impl.md` §17. Frame before furniture — this hosts the events.
2. `specs/map/03-events-impl.md` — **event nodes** (the events slice of Phase 03): inline, **free**, 1-of-3 picks
   within one icon-advertised family. Replaces the per-leg free accuracy pick (removed).

Design finalized in a Cowork session (2026-06-05). Program index + status: `specs/map/00-overview.md`.

**Core resolved decisions:**
- **Trades are free (events); flats are earned (shop/challenge).** The spine's "no free typed picks" refined: a
  trade's `−` governs its `+`, so free trades deepen commitment instead of climbing power. Event pool =
  trade-shaped families only (accuracy now; geometry when built — see memory, don't forget geometry items).
- **Three surfaces tier routing < currency < skill:** event = free trade, family by routing (map icon); shop =
  darts for control; challenge = rarity earned by skill. A won challenge must out-rank a free event.
- **Event reward = diagonal swing**, not the old near-net-zero reshape: common +6–8/−2–4, uncommon +9–11/−3–5,
  rare +12–14/−4–5 (gain rolled, penalty rolled). Reuses `UPGRADE_TYPES` + `_apply_upgrade`.
- **Rarity ramps by section, events only:** 85/10/5 → 65/20/15 → 45/30/25 (act 0/1/2; +10 unc & rare per boss
  cleared, common absorbs). Shop/challenge keep their own rarity systems.
- **No bank interaction at events** (shop + challenge already tax it); cost is the trade + the forgone parallel run.
- **Agency is path-level:** you pick a *branch* (its whole composition), not "event vs leg" at a fork. Branch runs
  get contrasting type mixes (`branch_contrast` knob). Per-traversal budget: 1–3 shops / 1–3 events / 1–3
  challenges, rest legs. Icon scaffold (`EventFamilyIcons`) is the shared Phase-03 glyph — Max drops art in later.

**Status of what came before:** Phase 02 challenge nodes BUILT + PLAYTESTED (takeaway: they need this fuller map
to be judged — that's this work). Substrate slices 1+2 shipped. Later: rest of Phase 03 (typed shop rings +
codex), 04 pool filtration, 05 boss cadence.

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
