---
name: project-dart-game-concept
description: "Dart Game high-level concept — Balatro-style roguelike with three-component dart customization, x01 scaling format, balance-as-tradeoff, and scoring modifiers as the run-defining items."
metadata: 
  node_type: memory
  type: project
  originSessionId: d4f2c00d-20ee-4f10-95d3-797e0915e52d
---

**Concept:** Balatro-style roguelike built around darts. Player customizes a dart from three components (barrel, shaft, flight — point was dropped) that affect six throw stats. Runs scale through x01 format (101 → 201 → 301...), with escalating score targets. Scoring modifiers acquired during the run change how the player sees and values the dartboard. The board stays the same; builds make you play it differently every run.

**Four core design pillars:**
1. **Throw Mechanic** — three-stage input (place aim ellipse → vertical release → horizontal release) where build stats affect each stage's precision. Skill axis on top: how close the locked release lands to the declared target's centroid drives a green/orange/red accuracy multiplier that shrinks or bloats the final dart's scatter. Gaussian distribution for the final landing sample.
2. **Build System** — Mario Kart-style stat spreads on components + Armored Core-inspired balance threshold that forces tradeoffs.
3. **Scoring Modifiers** — board-perception items: triples worth more, doubles worth 0, color bonuses, streak bonuses, wedge value boosts, etc.
4. **Form (deck equivalent)** — future feature. Throwing style chosen at run start that changes fundamental feel of the throw mechanic.

**Win/loss:** Leg 1 = 101, +100 each leg, 5 turns of 3 darts per leg, must double-out, standard bust rules. Fail to reach 0 in 5 turns → run over.

**Run-progression structure (shipped 2026-05-21):** Every third leg, the post-leg upgrade pick is replaced by a **shop** — the player throws their accumulated spare darts at lit-up board spots to earn rarity-tiered upgrades. Per-leg 2-of-3 picks continue unchanged on non-shop legs. Spare darts = `total_darts_in_leg - used_darts`, summed across the three-leg window. See [shop spec](../../../../../Documents/GitHub/darts-game/specs/2026-05-21-shop-system.md).

**The "three calculating interactions" principle.** A core design intent surfaced during the shop spec: every throw should have the player calculating three interacting systems — (1) the **board RNG read** (what's lit, where, what shape are the clusters), (2) their own **skill/confidence** (can I hit that triple under pressure), and (3) **stat-driven hit probability** (do my dart parts give me the precision to back the read). The shop's geometric placement rules (commons fill singles, uncommons/rares fill doubles/triples) was deliberately designed to invoke all three. Future features should preserve or extend this trinity rather than collapse it.

**Why this matters:** Max is building incrementally feature-by-feature; the design fiction ("same board, different ways to read it") is the load-bearing concept that any new feature should reinforce. Don't propose mechanics that would make the board's actual layout matter less.

**How to apply:** When discussing new features, check that they support at least one of the four pillars. New scoring modifiers should change how a player *reads* the board, not just add raw points. New build systems should respect the parts/balance dichotomy ([[project-balance-philosophy]], [[project-component-philosophy]]). Reward-delivery systems (shop-like beats) should keep the three calculating interactions active.

See also: [[user-role]], [[feedback-godot-conventions]], [[project-balance-philosophy]], [[project-component-philosophy]], [[project-architecture-rules]], [[project-open-questions]], [[reference-design-notes]]
