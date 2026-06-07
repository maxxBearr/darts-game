---
Spec date: 2026-06-07
Status: ACTIVE — promoted to CLAUDE.md's active slot 2026-06-07 (same day, after geometry items
  shipped and archived to specs/2026-06-07-geometry-items.md). This file is the reserved archive
  slot; the full spec lands back here with a Shipped header once the pass runs.
Implementation: pending (queued for Claude Code)
Notes: Single source of truth is CLAUDE.md until shipped — do not edit this stub.
---

# Leg lattice — monotone (score, turns) frontier for act legs

See `CLAUDE.md` for the active spec. One-line summary: per-act (score × turns) lattice with
frontier unlocking (loose turns before tight, score rows ascend) + a cull rule (cells at/below
max cleared pressure expire) → strictly monotone leg difficulty, lattice-exhaustion leg cap,
`path_leg_budget` per-path cap, leg identity drawn from the frontier at node arrival.
