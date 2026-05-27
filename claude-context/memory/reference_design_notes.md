---
name: reference-design-notes
description: Pointer to DesignNotes.md at Dart Game repo root — the canonical design document. ProjectOverview.txt is deprecated.
metadata: 
  node_type: memory
  type: reference
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

**Canonical design doc:** `DesignNotes.md` at the Dart Game repo root. Read this when you need the full concept, scene tree, file descriptions, stat tables, balance specifics, or phase status.

**Deprecated:** `ProjectOverview.txt` — earlier design doc, kept for history but stale. The phase status in it is significantly behind reality. A header at the top marks it deprecated and points to `DesignNotes.md`.

**Workflow doc:** `CLAUDE.md` at the Dart Game repo root holds the active feature spec (whatever is currently being designed or implemented). Auto-loads into every Claude conversation in the repo. Specs get archived to `specs/YYYY-MM-DD-feature-slug.md` after shipping. See the "Workflow Notes" section at the bottom of `CLAUDE.md` for the archive flow.

**Throw modifier system spec:** `ThrowModifierGuide.txt` — implementation spec for the conditional throw stat bonus system (ThrowModifier resources attached to dart components, e.g., "Nervous Sweater" / "Ice Veins"). Still useful as the design reference for that subsystem.

**Dart component + unlock system reference (added 2026-05-23):** Two living docs at the repo root for the dart component progression system. `DartComponentGuide.md` covers architecture, full field reference, integration points, and the "how to add a new component" checklist. `UnlockConditionRecipes.md` is the cookbook — one section per unlock intent from Max's original 15-item design list, with subclass + suggested filename + exact field values. Design rationale archived in `specs/2026-05-23-dart-component-unlock-system.md`. Prefer these refs over memory when the user asks about IDs, PlayerProgress, UnlockCondition subclasses, or how a specific recipe works.

**When DesignNotes.md drifts:** the doc gets stale as features ship. Periodically refresh it — either by hand or by asking Claude.ai (which keeps a separate project memory) for an updated writeup, then merging. Don't blindly trust phase-status markers in the doc; cross-check against `git log` and actual code state.

See also: [[project-dart-game-concept]]
