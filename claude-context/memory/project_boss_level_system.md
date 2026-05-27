---
name: project-boss-level-system
description: "Boss encounters + level select + rule-modifier rewards — full system shipped 2026-05-26. Six boss families with scaled variants, three starter levels (501/1001/1501), eight rewards including Glass Cannon as the canonical trade."
metadata: 
  node_type: memory
  type: project
  originSessionId: 08056db4-575e-4779-b21c-72c057113b67
---

**Shipped 2026-05-26** (commits across 2026-05-26/27). All 5 phases of the spec landed in a single implementation pass rather than incrementally. Spec archived at `specs/2026-05-25-boss-encounters-and-level-select.md` — read that for the full design rationale.

**Run structure is now level-gated.** Players pick from 501 / 1001 / 1501 at run start (more can be added by dropping new `LevelDefinition.tres` resources — nothing assumes the level count). Each `LevelDefinition` carries: `max_score_target`, `boss_count`, `boss_pool: Array[Resource]`, `rarity_weight_shift` (-0.025 / 0.0 / +0.025 for the three starter levels), `display_name`, and an optional `unlock_condition`. Clearing the level is the win state — runs are no longer endless.

**Boss scheduling.** `BossManager` (Node) handles every-5-legs cadence (export `boss_cadence: int = 5`), capped at `LevelDefinition.boss_count` per run. Boss type is rolled from the level pool at boss-leg start. **No advance preview** — that's an intentional design hold; with the current modifier pool there's not much meaningful prep the player could do anyway. May revisit as the pool grows.

**Six boss families, each one script + multiple `.tres` variants** differing only in `tuning: Dictionary` and `difficulty_tier`:

- `VoidBoss` — N random wedges score 0 each turn (variants: easy 6 / medium 12 / hard 18 voids).
- `PrismBoss` — wedge color reshuffle (easy: every 2 turns / medium: every turn). No hard variant yet.
- `RecessionBoss` — color value reduction locked at leg-start (easy 25% / medium 50% / hard 75%). Locked-at-start is the deliberate exception to per-turn mutation — re-rolling color would make planning impossible.
- `RotationBoss` — board rotates random angle per turn (medium 45-90° / hard 90-135°). Strictly broader than Prism — moves colors AND values AND parity together. Disrupts stat-based aiming heuristics (top/bottom V favor, sides H favor).
- `NarrowDoubleRingBoss` — double ring narrowed geometrically (medium 50% / hard 75%). The geometry-debuff family; pairs thematically with Recession on checkout disruption.
- `TwoDartsBoss` — fewer darts per turn (default 2; `one_dart.tres` variant = 1, hard tier only).

**Pool curation by tier.** Manually curated via `LevelDefinition.boss_pool` arrays:
- 501 = easy only (`void_easy`, `prism_easy`, `two_darts`, `recession_easy`).
- 1001 = easy + medium.
- 1501 = medium only (intentional — 1501 has a distinct identity, not just "wider pool").

`BossDefinition.difficulty_tier` is documentation/sorting only — no runtime filtering. If the pool grows past ~15 variants and per-`LevelDefinition` arrays get painful to maintain, refactor to tag-based filtering (`accepted_tiers: Array[StringName]`) — the `difficulty_tier` field is already there to make that a low-cost change. Not worth doing preemptively.

**Visual theme exports on `BossDefinition`:** `title_color`, `description_color`, `status_color`, `background_tint` — every boss tunes its presentation. The leg shows a start announcement + persistent status text via `Boss.get_status_text()`. Visual mutations (voids, ring narrowing, rotation animation) render via `Boss.get_visual_overlay()` interpreted by the dartboard.

**Rule-modifier reward system** (the resolution of [[project-open-questions]] #6 — the "rule-modifier category" that was sidelined in 2026-05-22). `RuleModifierReward` base Resource. `RewardRegistry.generate_picks(count, run_state)` filters by `is_applicable` and returns N distinct cards. Active rewards live on `main._active_rewards`. The 8 initial rewards:
- **Additives:** Extra Dart, Extra Turn, Streak Slot Extension, Lucky Eye (+2% rare roll), Pool Widener (+1 shop option), Frequent Shopping (every 2 legs vs. 3), Triple Outs (checkout on triples).
- **Trade:** Glass Cannon — any zero-landing dart wins the leg, but any bust ends the run. Canonical trade-item per the design lean (target: 30-40% of any future expansion should be trades, not pure additives).

**Glass Cannon implementation note.** Sets `x01_game.glass_cannon_active = true` AND `allow_triple_checkout = true` AND mirrors both on `scoring_modifier_manager`. Bust handling in `x01_game.gd` checks `glass_cannon_active` and ends the run instead of reverting score. Triple Outs is filtered out of the pool when Glass Cannon is active (`is_applicable` supersession).

**Rarity shift plumbing.** `ModifierRegistry.current_rarity_shift` (static var) is set from the chosen `LevelDefinition.rarity_weight_shift` at run start. `_shifted_weights()` redistributes weight between common/rare in the `[common, uncommon, rare]` arrays — positive shifts toward rare, negative toward common.

**Progression tracking.** `PlayerProgress.cleared_levels: Dictionary` keyed by `level_definition.resource_path`, value = `{cleared: true, fewest_darts: int}`. `record_level_clear(level, dart_count)` updates fewest-darts on new bests only. `level_cleared` signal fires for UI. `LevelClearedCondition` (8th `UnlockCondition` subclass) reads this to gate higher levels behind lower-level clears.

**How to apply.**

- When designing new bosses, follow the family-with-variants pattern: one script + tuning dict + multiple `.tres`. Don't extend `Boss` for trivially-tunable differences.
- When designing new rewards, ask whether it's a trade or additive — bias toward trades per the design lean. Glass Cannon is the model.
- Reward pool expansion should follow the `is_applicable` pattern so non-stackables and superseded rewards drop out automatically.
- When proposing per-leg cadence changes, remember the "+1 boss per level with uniform every-5-legs cadence" design call — accelerating cadence at higher levels was considered and dropped, because muscle-memory consistency beats variety here.

**Deferred / known limitations:**
- No boss foreknowledge / preview before the boss leg (intentional, may revisit as modifier pool grows).
- Hard-tier Prism not designed — Prism-medium (every-turn reshuffle) is already disruptive; if a hard variant is wanted, candidates include pairing with one floating Void wedge per turn, or shuffling colors *and* parity together.
- Mega-final-boss for endgame levels (2001+) is open design space — could be a stacked-debuff encounter rather than a normal one.
- Speedrun milestones/achievements ("Beat 501 in <30 darts") are easy to add now that fewest-darts is tracked.
- Boss-specific component unlocks (component unlock conditions that require beating certain bosses) — supported by the `LevelClearedCondition` precedent; just needs a `BossClearedCondition` subclass when wanted.

See also: [[project-component-unlock-system]], [[project-modifier-lock-system]], [[project-architecture-rules]], [[project-open-questions]], [[reference-design-notes]]
