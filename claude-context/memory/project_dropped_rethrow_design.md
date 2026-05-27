---
name: project-dropped-rethrow-design
description: Rethrow-style verbs (free retry on a thrown dart) are a design landmine — they create intentional-miss exploits. Dropped 2026-05-24.
metadata: 
  node_type: memory
  type: project
  originSessionId: 4cd9e318-da6a-47f4-8585-2444f9fc216b
---

**Rule:** Don't propose rethrow-style flight or modifier verbs (free retry on a thrown dart, conditional or unconditional) without an explicit solution for the intentional-miss exploit.

**The exploit:** Any rethrow verb that triggers on a "bad" outcome (broken streak, missed double, etc.) gives the player an incentive to deliberately throw badly to bank a free retry on a high-value target. Example: a "rethrow on broken streak" effect lets the player aim for a double, miss intentionally, and get a free shot at the same double off-streak. The bonus fires *because* the player created the failure condition the bonus rewards.

**Why this matters:** The exploit can't be patched cleanly without hollowing out the verb. Gating rethrows behind "must have been a genuine attempt at a streak target" requires intent inference that's both fragile and feel-bad when wrong. Gating by run-wide charge caps (e.g., "3 rethrows per run") doesn't fix it — it just turns the exploit into a resource to hoard for the best moment.

**What we landed on instead (2026-05-24):** The Momentum Marksman flight replaces the discarded "streak saver" rethrow with a proactive scaling accuracy bonus that rewards keeping the streak alive in the first place. See [[project-flight-archetype]] and the archived spec at `specs/2026-05-24-flight-modifier-additions.md`.

**How to apply:** When the user proposes a rethrow verb (or any "free retry on bad outcome" mechanic), surface this landmine immediately. Don't sketch the design until the intentional-miss path is closed. Acceptable directions: proactive scaling that rewards the desired playstyle directly, charge meters that build on success and discharge as score multipliers, or reshaping the verb away from rethrow entirely.

See also: [[project-flight-archetype]], [[project-open-questions]]
