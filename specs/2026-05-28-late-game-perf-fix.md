---
Spec date: 2026-05-28
Status: Partially shipped 2026-05-28 — Fix #3 regressed and is replaced in follow-up spec
Implementation: Claude Code
Notes:
  - **Fix #1 (invalidation gate)** — shipped and worked. `_sync_board_and_solver` invalidation now only fires when state actually changed. `[PERF] invalidate_preferred_remainders` log frequency dropped sharply over a leg; turn-end "next turn" presses now no-op the precompute when boss didn't mutate state.
  - **Fix #2 (upper-bound prune in `_solve_first`)** — shipped and worked. `compute_preferred_remainders` worst case dropped from 5401ms → ~3500ms. Prune does its job on degraded boards.
  - **Fix #3 (integer state-version cache key)** — REGRESSED. The monotonic `_streak_version` counter never returns to a prior value (`restore_all_streak_state` was specified to bump it, but should have restored it — and even with that fix, the counter approach is fundamentally flawed because two iterations of the per-target loop produce different state but identical post-restore versions). Result: cache_hits=0 on every solve. d=3 solves jumped from ~70ms to ~1400ms; the d=4 leg-transition freeze at r=1201 took 299 seconds.
  - **Replacement** for Fix #3 plus an extension of Fix #2 into `_solve_recursive`: `specs/2026-05-28-cache-key-hotfix-and-recursive-prune.md`.
---

# Late-Game Perf Fix Pass

**Spec date:** 2026-05-28
**Previous spec:** `specs/2026-05-28-late-game-crash-and-perf-diagnosis.md` (shipped 2026-05-28). Diagnosis data captured during leg-5 → 501 (void boss) playtest.

## What the data told us

`compute_preferred_remainders` is the dominant cost. Worst single call observed: **5401ms**. The `solve_checkout` cap was ~940ms at d=3. So the 4–5 second freezes Max felt on the void boss were almost entirely the precompute, not the live solver.

Two compounding reasons:

1. **Over-invalidation.** Every `invalidate_preferred_remainders` stack frame after leg start traced to `_sync_board_and_solver` → `_on_next_turn` / `_on_next_leg` (`main.gd:1956`). That's an unconditional cache-wipe firing every turn-end, even when no scoring-relevant state actually changed. The next `_update_checkout_helper` call then pays the 4-5s recompute tax.

2. **Precompute is genuinely expensive on degraded boards.** Void boss collapsed `_one_dart_finishable` entries from 21 → 9. With most doubles wiped, `_solve_first` can't find a checkout for many remainders and walks the full depth-3 tree before returning false. 179 sub-problems × that work = the multi-second cost.

`solve_checkout` itself shows healthy 75–90% cache hit rates at d=3. The cache works; it's the cache misses that explode into ~30–70k `speculative_score` calls each, because every active modifier in the chain runs against every candidate target whether it could affect that target or not.

## Summary

| # | Fix | Type | Touch | Expected win |
|---|---|---|---|---|
| 1 | Gate `_sync_board_and_solver` invalidation on actual state change | Behavioral guard | `scoring_modifier_manager.gd`, `main.gd` | Most 5s freezes → <1ms (no-op) |
| 2 | Upper-bound prune in `_solve_first` using `_max_single_dart_score` | Solver pruning | `scoring_modifier_manager.gd` | Slow precomputes (when they do run) drop substantially |
| 3 | Integer state-version cache key for both solvers | Cache key cost | `scoring_modifier_manager.gd` | `solve_checkout` d=3 calls drop noticeably; cache hit rate stays high without `str().hash()` overhead |

Three independent fixes, ordered by impact. (1) alone should eliminate the playtest-felt freezes. (2) and (3) cover the residual cases when invalidation legitimately needs to fire (mid-leg boss mutations, modifier toggles).

A fourth idea — `modifier.affects(target)` short-circuit in `speculative_score` — is **deferred**. It would touch all 9 modifier scripts for a smaller marginal win once (1)–(3) are in. Revisit only if perf still feels bad after this pass.

---

## 1. Invalidation gate on `_sync_board_and_solver`

### The problem

`main.gd::_sync_board_and_solver` (line 1956) unconditionally calls:
1. `scoring_modifier_manager._build_solver_candidates()` — rebuilds the 83-candidate target list from `effective_wedge_values` / `effective_wedge_colors`.
2. `scoring_modifier_manager.invalidate_preferred_remainders()` — marks the 179-problem precompute dirty.

It's called from:
- `_on_next_turn()` (line 708)
- `_on_next_leg()` (line 758)
- `_show_game_over()` (line 773)
- Boss spawn at run start (line 1542)
- Boss spawn on leg start (line 758)
- `_on_modifier_toggled()` indirectly

Most of these fire when nothing scoring-relevant has actually changed. The boss `on_turn_start` *might* mutate `effective_wedge_values`, but if it doesn't (or applies an identical mutation), we still pay the recompute cost on the next checkout-helper call.

### The fix — state fingerprint comparison

Add a cheap state fingerprint to `ScoringModifierManager`:

```gdscript
## Monotonic counter — increments whenever any scoring-relevant state mutates.
## Used as a cheap "did anything actually change?" signal for cache gating.
var _state_version: int = 0

## Version observed by `_sync_board_and_solver` on its last invocation.
## When matched on the next call, the sync is a no-op.
var _last_sync_version: int = -1

func _bump_state_version() -> void:
    _state_version += 1
```

Bump `_state_version` from:
- `add_modifier()` (after appending to `active_modifiers`)
- `remove_modifier()` (after removing)
- `set_modifier_enabled()` / wherever the toggleable flag is flipped
- After any mutation to `effective_wedge_values` or `effective_wedge_colors`. Add a small setter helper:

```gdscript
## Sets effective board state and bumps the version. Callers should use this
## rather than mutating effective_wedge_values / effective_wedge_colors directly.
func set_effective_board(values: Array[int], colors: Array[Dictionary]) -> void:
    effective_wedge_values = values
    effective_wedge_colors = colors
    _bump_state_version()
```

- `allow_triple_checkout` and `glass_cannon_active` setters — wrap each in a small setter that bumps. (Currently just `var` fields; change to property setters or add explicit `set_allow_triple_checkout(value)` helpers.)

Now `_sync_board_and_solver` becomes:

```gdscript
func _sync_board_and_solver() -> void:
    _sync_board_state()  # cheap — just pushes to dartboard for redraw
    if scoring_modifier_manager._state_version == scoring_modifier_manager._last_sync_version:
        return  # nothing scoring-relevant changed; cached precompute still valid
    scoring_modifier_manager._build_solver_candidates()
    scoring_modifier_manager.invalidate_preferred_remainders()
    scoring_modifier_manager._last_sync_version = scoring_modifier_manager._state_version
```

`_sync_board_state()` stays unconditional because dartboard rendering doesn't have a stale-cache concern — it just pushes current values to the dartboard and queues a redraw. Cheap.

### Why this is safe

- Any code path that mutates scoring-relevant state bumps the version. Missed bumps would cause stale precompute results — false negatives where the helper shows old paths.
- The 8 mutation sites are well-localized (modifier add/remove/toggle, board value/color setters, the two flag setters). Each is documented and easy to grep for.
- If a future code path mutates state without bumping the version, the symptom is a stale checkout helper — not a crash. We catch it in playtest.

### Acceptance

- `_on_next_turn` followed immediately by `_update_checkout_helper` runs in <1ms (no recompute) when boss didn't mutate state.
- Modifier add/toggle still triggers a fresh precompute on the next helper call.
- Boss leg with state-mutating turn-start (e.g., a boss that rotates wedges each turn) still gets invalidated correctly.
- `[PERF] invalidate_preferred_remainders` log line frequency drops by an order of magnitude over a typical leg.

---

## 2. Upper-bound prune in `_solve_first`

### The problem

In `compute_preferred_remainders`, each `_solve_first(r, 3, cache)` call has to either find a finishing path or prove none exists. When the board is degraded (void boss → `_one_dart_finishable` drops to 9 entries), most remainders 100+ aren't finishable in 3 darts, but the solver doesn't know that without exhaustive search.

`_max_single_dart_score` already tracks the highest score any single scoring dart produces under current modifiers. We can use it as a sound upper bound: **if `remaining > _max_single_dart_score * darts_left`, no checkout path exists**, return false immediately.

### The fix

Two changes inside `scoring_modifier_manager.gd`:

**Ensure `_max_single_dart_score` is computed before the precompute runs.** Currently it's set inside `_compute_one_dart_finishable`. Add an explicit call at the top of `compute_preferred_remainders`:

```gdscript
func compute_preferred_remainders() -> void:
	if _solver_candidates.is_empty():
		_build_solver_candidates()

	# Ensure _max_single_dart_score is current — used by the prune below.
	if _one_dart_finishable_dirty:
		_compute_one_dart_finishable()

	# ... existing logic ...
```

**Add the prune at the top of `_solve_first`:**

```gdscript
func _solve_first(remaining: int, darts_left: int, cache: Dictionary) -> bool:
	if darts_left <= 0 or remaining <= 0:
		return false

	# Upper bound: even the fattest possible dart times darts_left can't reach
    # this remainder. Catches the common late-game / degraded-board case where
	# high remainders simply aren't finishable.
	if _max_single_dart_score > 0 and remaining > _max_single_dart_score * darts_left:
		cache[...] = false  # (same cache key as below)
		return false

	# ... existing logic ...
```

Same prune applies in `_solve_recursive` — if `remaining > _max_single_dart_score * darts_left`, the entire branch is dead, return `[]` early.

### Why this is safe

It's a sound bound (no false pruning). `_max_single_dart_score` is the maximum any candidate can produce under current modifiers including streak bonuses computed from turn-fresh state. If the remainder exceeds that × darts_left, no combination of darts can reach it. The prune may miss tighter bounds (e.g., the second dart can't usually score `_max_single_dart_score` again because streak state changed) but it's strictly correct.

### Acceptance

- Void boss leg precompute drops from 4000–5000ms to a small fraction of that (the unfinishable high remainders short-circuit at the top of `_solve_first`).
- Regression: clean-board precompute (leg 1, no modifiers) result count is unchanged — the prune only triggers on degraded boards.

---

## 3. Integer state-version cache key for both solvers

### The problem

Both `_solve_recursive` (line 430) and `_solve_first` (line 587) build their cache key with:

```gdscript
var streak_snap: Array[Dictionary] = snapshot_all_streak_state()
var cache_key: String = "%d_%d_%s" % [remaining, darts_left, str(streak_snap).hash()]
```

`str()` on an `Array[Dictionary]` walks every modifier's streak dictionary and stringifies it. At thousands of recursive calls per solve with many active modifiers, that's measurable overhead. It also burns a snapshot allocation purely for keying.

### The fix

Maintain a streak-state version counter alongside `_state_version`. Bump it whenever any modifier's streak state mutates — which happens inside `speculative_score()` (when modifiers append modifications and update internal counters) and in any `reset_streak_state()` call.

Implementation sketch:

```gdscript
## Bumps whenever any active modifier's streak state mutates.
## Cheap cache-key replacement for `str(streak_snap).hash()`.
var _streak_version: int = 0

func speculative_score(raw_result: Dictionary) -> Dictionary:
    # ... existing logic ...
    _streak_version += 1  # any modifier in the chain may have mutated state
    return result

# Plus bumps in reset_for_turn / reset_for_leg / reset_for_run / restore_all_streak_state.
```

Cache key becomes:

```gdscript
var cache_key: String = "%d_%d_%d" % [remaining, darts_left, _streak_version]
```

Or even cheaper, an `Array[int]` key (Godot Dictionaries support array keys):

```gdscript
var cache_key: Array[int] = [remaining, darts_left, _streak_version]
```

This eliminates the `snapshot_all_streak_state()` call that was made solely for the key. The per-target loop still snapshots (it needs to restore after each candidate), but that's once per loop iteration, not twice.

### Important caveat — cache invariant

The cache key must uniquely identify the *streak state at this recursion point*. With the version-counter approach, two recursive calls with the same `_streak_version` had identical state at the moment the key was built. That holds as long as nothing mutates streak state between the snapshot-restore boundaries of the per-target loop — which is true today: the loop snapshots before `speculative_score`, restores after, so net mutation per iteration is zero.

The version increments inside `speculative_score`, then the restore wipes the change, so two iterations of the same per-target loop see different versions mid-iteration but the same version at the top of the next recursive call. That's fine because the cache lookup happens at the *top* of `_solve_recursive` / `_solve_first`, before any per-target mutation.

### Acceptance

- `solve_checkout` d=3 calls at ~200–900ms drop a meaningful fraction (target: ~30% off, exact number TBD by re-running [PERF] logs).
- Cache hit rate stays at 75–90% — the version key is no less specific than the old hash key.
- Regression: solver returns identical paths for identical inputs. Add a debug toggle to dump paths and diff against the prior implementation if needed.

---

## 4. Out of scope

- `modifier.affects(target)` short-circuit in `speculative_score`. Deferred — only revisit if perf still feels bad after fixes 1–3.
- Async / threaded solving. The recursive shape doesn't fit `WorkerThreadPool` cleanly without deeper restructure.
- UI-side changes to the checkout helper. Game feel and helper usefulness stay identical; this is internal-only.
- Optimizing `_build_solver_candidates`. Not on the critical path per the data — measured at the start of a leg only.

---

## 5. Implementation order

1. **Fix #1 (invalidation gate)** first. Biggest single win, smallest blast radius. Land and playtest — most freezes should disappear immediately.
2. **Fix #2 (upper-bound prune)** second. Independent of #1. Helps the cases where invalidation legitimately fires (modifier add, boss leg with actual state mutation).
3. **Fix #3 (state-version cache key)** last. Slightly trickier — careful about which mutation sites need to bump `_streak_version`. Easy to verify by re-running the `[PERF]` instrumentation with `debug_perf_log = true` and comparing numbers before/after.

After all three: re-run the same playtest profile (debug-skip to 501 or 1501, void boss build), capture `[PERF]` output, confirm the worst-case `_update_checkout_helper` drops below ~100ms. If yes, ship. If no, the data tells us what's left and we open a follow-up.

The `debug_perf_log` instrumentation stays in place — useful for the verification pass and future regressions.
