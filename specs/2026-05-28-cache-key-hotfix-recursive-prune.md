---
Spec date: 2026-05-28
Status: Shipped 2026-05-29
Implementation: Code reflects both fixes — `_streak_state_hash()` present in scoring_modifier_manager.gd, `get_streak_state_hash()` overrides on streak modifiers, `_streak_version` fully removed (0 occurrences), upper-bound prune present in both `_solve_first` and `_solve_recursive`.
Notes: Both fixes landed. Cache hit rate and late-game `+1 dart` freeze were the target; verified against the 1501 playtest profile. Supersedes Fix #3 from specs/2026-05-28-late-game-perf-fix.md, which regressed.
---

# Cache Key Hotfix + Recursive Prune

**Spec date:** 2026-05-28
**Status:** Designed, ready for implementation
**Previous spec:** `specs/2026-05-28-late-game-perf-fix.md` (Fixes #1 and #2 shipped successfully; Fix #3 regressed). Diagnosis data captured during a 1501-level playtest (winning run, ~10+ minutes).

## What the data told us

Fix #1 (invalidation gate) and Fix #2 (upper-bound prune in `_solve_first`) both landed and worked. Most early- and mid-game freezes are gone. The data confirms it:

- `[PERF] invalidate_preferred_remainders` log frequency dropped sharply over the leg.
- `compute_preferred_remainders` worst case fell from ~5400ms → ~3500ms peak.

**But Fix #3 introduced a cache regression.** Every `[PERF] solve_checkout` line in the new log reports `cache_hits=0`. The cache I added is doing nothing.

Why: the `_streak_version` int counter is monotonic. The prior spec told `restore_all_streak_state` to bump it, which means after a snapshot+restore pair the version is higher than where it started, not back where it was. So same state → different version → cache key unique per call → 0% hit. Even fixing the restore-bump issue isn't sufficient: two iterations of the per-target loop that produce *different* states would end up with the *same* post-restore version, which would cause false cache hits. The counter approach is structurally wrong for this problem.

Consequences from the latest log:

| Metric | Before Fix #3 (diagnosis pass) | After Fix #3 (current) |
|---|---|---|
| `solve_checkout d=3` cache hit rate | 75–90% | **0%** |
| Worst d=3 solve duration | ~940ms (void boss) | **1413ms early-game, 4628ms late-game** |
| Worst d=4 solve duration (with `+1 dart`) | n/a (not measured) | **299094ms (~5 minutes)** at r=1201 leg transition |
| `compute_preferred_remainders` peak | 5401ms | 3473ms (Fix #2 is helping; Fix #3 also bloats it but less visibly because the prune fires first) |

The user reported the run shipped to completion eventually, with the worst freezes being the d=4 leg transitions at r=1201/1401/1501. Those are *recoverable* when the cache works, *catastrophic* when it doesn't.

## Summary

| # | Fix | Type | Touch | Expected win |
|---|---|---|---|---|
| 1 | Replace `_streak_version` counter with a per-modifier streak state hash | Cache correctness | `scoring_modifier.gd`, 5 streak modifier subclasses, `scoring_modifier_manager.gd` | Restore 75–90% cache hit rate; d=3 solves drop ~10–20× back to ~70–200ms |
| 2 | Apply Fix #2's upper-bound prune in `_solve_recursive` too | Solver pruning | `scoring_modifier_manager.gd` | High-remainder d=4 solves (r > _max_single_dart_score × 4) short-circuit instead of exploring 47M+ nodes |

Both target the same playtest pain point (late-game `+1 dart` freezes). Fix #1 is the cache regression — must land. Fix #2 is the safety net for the d=4 case where even a working cache may not be enough.

---

## 1. Real state hash for the solver cache key

### Why the counter approach failed

The previous spec used:

```gdscript
var _streak_version: int = 0

func speculative_score(...) -> Dictionary:
    ...
    _streak_version += 1
    return result

# Plus bumps in reset_for_turn, restore_all_streak_state, etc.
```

Two structural problems:

1. **Restore can't "un-bump" a counter.** A monotonic counter can't represent the inverse of a mutation. When state is restored to a prior snapshot, the counter stays in the future. So the cache key for state-after-restore never matches the cache key for state-before-mutation.

2. **The counter doesn't distinguish different states with the same number of mutations.** Iter 1 of a per-target loop applies modifier effects from target D20 → version V+1. Iter 2 applies effects from target D19 → version V+1 (if restored correctly). But D20's state ≠ D19's state. Same version, different state → false cache hit, wrong paths cached.

The fix is to compute the cache key from the *actual state*, cheaply.

### The fix — per-modifier streak state hash

Add a virtual method on `ScoringModifier` that returns a small integer hash of all the modifier's streak-state fields. Default returns 0 (for modifiers with no streak state). Streak-bearing subclasses override.

**`scoring_modifier.gd`:**

```gdscript
## Cheap hash of this modifier's current streak state.
## Used by the checkout solver to build cache keys without allocating a Dictionary per lookup.
## Override in subclasses that carry streak state; combine all streak-state fields into one int.
## Default returns 0 for modifiers without streak state (single-fire, board-mutation, etc.).
func get_streak_state_hash() -> int:
	return 0
```

**Streak-bearing modifier subclasses override.** Pattern: combine all streak-state fields into one int via `(field_a * 31 + field_b) & 0x7FFFFFFF`. Example for `StreakBonusModifier` (adjust field names to actuals):

```gdscript
func get_streak_state_hash() -> int:
	return (current_streak * 31 + (1 if streak_active else 0)) & 0x7FFFFFFF
```

Apply the override to every modifier that currently implements `save_streak_state` / `restore_streak_state_from`. From `[[project-modifier-lock-system]]` and the registry list, that's roughly: `StreakBonusModifier`, `ColorStreakModifier`, `EvenStreakModifier`, `OddStreakModifier`, and any `ParityStreakModifier`. The override is mechanical — each pulls in whatever fields `save_streak_state` already captures.

**`scoring_modifier_manager.gd`:**

```gdscript
## Cheap combined hash of all active modifiers' streak state.
## Used as the third component of solver cache keys.
## O(active_modifiers) per call, no allocation.
func _streak_state_hash() -> int:
	var h: int = 0
	for modifier: Resource in active_modifiers:
		if modifier is ScoringModifier:
			h = (h * 31 + modifier.get_streak_state_hash()) & 0x7FFFFFFF
	return h
```

Cache key in **both** `_solve_recursive` and `_solve_first`:

```gdscript
var cache_key: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
```

### Remove the broken counter

Delete `_streak_version`, the bumps inside `speculative_score`, and the bumps inside `reset_for_turn` / `reset_for_leg` / `reset_for_run` / `restore_all_streak_state`. The new hash function reads current state directly — no counter to maintain.

`_state_version` (board/modifier-set version, from Fix #1) stays — that one is fine. It's only compared against `_last_sync_version`, not used as a hash; monotonic is correct for that purpose.

### Why this is sound

- The hash is a pure function of current state. Two recursive calls with identical state produce identical keys → cache hits.
- Two calls with different state produce different keys (with overwhelmingly high probability — 32-bit hash collisions on real game states are negligible) → no false hits.
- Snapshot/restore round-trips are now invisible to the cache: restoring state restores the state, the next hash computation returns the original hash value.

### Acceptance

- `[PERF] solve_checkout` shows `cache_hits` > 0 — target 70%+ hit rate on d=3 calls, matching the pre-Fix-#3 baseline.
- d=3 solve times return to ~70–200ms range (vs current 1000–4000ms).
- `compute_preferred_remainders` worst case drops below ~1000ms (vs current ~3500ms) on stacked-modifier late-game builds.
- Regression: solver returns identical paths for identical inputs. If feasible, add a temporary debug toggle to dump paths and diff before/after.

---

## 2. Extend the upper-bound prune to `_solve_recursive`

### The problem

Fix #2 added an upper-bound prune to `_solve_first` (the precompute solver). The same prune was specified for `_solve_recursive` but doesn't appear to have shipped — the `r=1201, d=4` solve hit 322,526 recursive calls. With `_max_single_dart_score` typically around 60–80 in late game, `60 × 4 = 240`. Anything above 240 at d=4 is mathematically unfinishable. The solver should know that in one comparison.

### The fix

Mirror the `_solve_first` prune into `_solve_recursive` at the top of the function, immediately after the `darts_left <= 0` / `remaining <= 0` early returns:

```gdscript
func _solve_recursive(remaining: int, darts_left: int, cache: Dictionary) -> Array[Array]:
	if darts_left <= 0 or remaining <= 0:
		return []

	# Sound upper bound: even at the fattest possible dart, darts_left can't reach this remainder.
    # Catches the catastrophic high-r / high-d cases (e.g. r=1201 d=4 on a +1-dart leg transition).
    if _max_single_dart_score > 0 and remaining > _max_single_dart_score * darts_left:
        # Cache the negative result under the same key shape as below.
        var cache_key_neg: String = "%d_%d_%d" % [remaining, darts_left, _streak_state_hash()]
        cache[cache_key_neg] = []
        return []

    # ... existing logic ...
```

### Why this is safe

Same reasoning as Fix #2 in the previous spec. `_max_single_dart_score` is the absolute upper bound any single scoring dart can produce. The bound is sound — never prunes a finishable remainder. Looser than tight bounds (because the streak state after dart 1 reduces dart 2's max), but strictly correct.

### Acceptance

- `_update_checkout_helper r=1201 darts_left=4` returns in <100ms instead of 5 minutes — the prune fires at the top of the recursion and short-circuits the entire tree.
- Regression: clean leg-1 d=3 solves at r=170 (a legitimate finish) still find paths. The prune only fires when remainder genuinely exceeds the upper bound.

---

## 3. Out of scope

- Any change to `compute_preferred_remainders`. Fix #1 alone should bring it back into shape once cache hit rate is restored — the precompute uses `_solve_first` which shares the same cache mechanism. If late-game precompute still feels bad after this pass, that's the next spec.
- Depth-cap heuristics for `+1 dart` legs (e.g., "solve at d=3 and treat the extra dart as a freebie"). Premature — let the prune + working cache get us most of the way first.
- `modifier.affects(target)` short-circuit. Still deferred. With cache hit rates restored, per-call cost matters less.
- Async / threaded solving. Same as before — not until we know everything else is exhausted.

---

## 4. Implementation order

1. **Fix #1 (state hash cache key)** first. The cache regression is the dominant cause of every late-game slowdown the latest playtest showed. Land it, re-run the same playtest profile, confirm `[PERF] solve_checkout` shows non-zero `cache_hits`.
2. **Fix #2 (recursive prune extension)** second. Independent of #1; small change in `_solve_recursive`. Catches the d=4 leg-transition catastrophe even when Fix #1's cache isn't enough on its own.

After both: re-run the 1501 playtest. Target acceptance: worst-case `_update_checkout_helper` drops below ~2s on +1-dart legs. The `debug_perf_log` instrumentation stays in place for verification.
