---
name: project-component-unlock-system
description: "Dart component unlock system shipped 2026-05-23 — manual StringName IDs, PlayerProgress autoload, UnlockCondition resource subclasses, queued unlock notifications."
metadata: 
  node_type: memory
  type: project
  originSessionId: d10c258c-58a5-4507-ac41-2ad8dda89766
---

**Shipped 2026-05-23.** Dart components can now be progression-locked behind player-facing earn conditions.

**Why:** The customization system shipped in Phase 5 with everything available from start. This adds the first real meta-progression hook — components survive across runs and runs have a reason to attempt unusual play patterns (clutch finishes, no-rare runs, etc.).

**How to apply:**

- When designing new dart components, consider whether the component is `default_unlocked = true` (always available, like the starting set) or `default_unlocked = false` with an `unlock_condition`. Locked components show up on the assembly screen as silhouettes with the unlock hint in grey.
- New unlock conditions follow the existing eight subclasses (LegWinHit, LegStat, CareerCount, RunConstraint, ShopAcquisition, SlotsFilled, RelicCount, LevelCleared). `LevelClearedCondition` was added 2026-05-26 alongside the boss/level system — used by 1001 and 1501 to gate behind clearing the prior level via its resource path. Adding a new family of conditions = new subclass mirroring the `ThrowModifier` pattern. Don't bolt unrelated semantics onto an existing subclass.
- IDs are `StringName`, slot-prefixed snake_case (`&"barrel_torpedo"`), manually assigned. **NEVER change an ID after a build ships** — orphans player save data. Validator catches authoring mistakes (`DartComponentRegistry._validate_components()` at startup); only released IDs are off-limits.
- Earned unlocks live in the `PlayerProgress` autoload (`user://progress.tres`), never on the resource itself. Resource declares the condition; player profile owns earned state.
- Notifications use a queue — multiple unlocks from one event are normal (e.g., a clutch leg-win can satisfy "double bullseye" AND "5th career leg" at once). `UnlockNotificationQueue` plays them sequentially.

**Key architectural decisions** (in [[reference-design-notes]] under "Key Design Decisions"):
- Manual `StringName` IDs over Godot UIDs — human-readable saves, survives file/display-name renames.
- `PlayerProgress` autoload owns runtime state; resources stay canonical.
- Subclass per condition family — type-safe per-family parameters, no enum-with-dispatch monster.
- Notifications queue, not overwrite.

**Living references** (canonical, prefer these over memory for specifics):
- `DartComponentGuide.md` — architecture, full field reference, integration points, how to add new components.
- `UnlockConditionRecipes.md` — cookbook with one section per unlock intent from the original 15-item design list.
- `specs/2026-05-23-dart-component-unlock-system.md` — design rationale (why decisions were made; alternatives considered).

**Deferred / known limitations:**
- Per-category caps on non-streak RELIC modifiers (color-bonus slot, parity-bonus slot, etc.) — `RelicCountCondition` is the coarse stand-in until then.
- Lock icon sprite overlay on assembly screen — visual treatment via dim + grey + text is fine for now.
- Stable IDs on `ScoringModifier` and `ThrowModifier` — same pattern available when needed; copy don't extract a base class.
- Save format migration in `PlayerProgress._load()` — currently no versioning. Add when format changes.

**Shells staged:** Nine `_unfilled_*.tres` files in `resources/dart_components/{slot}/` are intentionally not registered. The validator would refuse to start the game if they were (empty ID + locked-without-condition). Max fills them in and drags into the registry as content is ready.

See also: [[project-component-philosophy]], [[project-open-questions]], [[reference-design-notes]]
