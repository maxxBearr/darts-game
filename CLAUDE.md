# Active Spec

_No active spec right now. The most recent spec has been archived to `specs/2026-05-24-flight-modifier-additions.md`._

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
