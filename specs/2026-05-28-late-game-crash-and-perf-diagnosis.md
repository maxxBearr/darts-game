---
Spec date: 2026-05-28
Status: Shipped 2026-05-28
Implementation: Claude Code
Notes: Crash fix worked — no recurrence in leg 5–8 playtest. Perf data captured shows `compute_preferred_remainders` dominates: up to **5401ms per call** during the void boss leg, vs `solve_checkout` at d=3 capping at ~940ms. Root cause is `_sync_board_and_solver` invalidating unconditionally on every `_on_next_turn` / `_on_next_leg`, even when board state hasn't actually changed. Fix in `specs/2026-05-28-late-game-perf-fix.md`.
---

# Late-Game Crash + Perf Diagnosis Pass

**Spec date:** 2026-05-28
**Previous spec:** `specs/2026-05-28-pool-dedup-skew-continuity.md` (shipped 2026-05-28).
**Trigger:** Leg-8 playtest. One crash in the post-leg modifier offering; multi-second hitches throughout late-game (worst ~20s on a `+1 dart per turn` build). Crash gets a real fix; perf gets instrumentation before we commit to a structural change.

## Summary

| # | Fix | Type | Touch |
|---|---|---|---|
| 1 | `generate_distinct` returns short array when reroll budget exhausts → hud out-of-bounds at idx 2 | Bug | `modifier_registry.gd`, `hud.gd` |
| 2 | Instrument checkout solver + setup precompute to identify late-game perf bottleneck | Diagnostic | `scoring_modifier_manager.gd`, `main.gd` |

Fix #2 is measurement only — gated behind a debug flag, no live behavior change, no cost when off. The actual perf fix becomes the next spec once we have numbers.

---

## 1. Pool-exhaustion crash fix

### Root cause
In `modifier_registry.gd::generate_distinct`, the outer loop is `for _n in range(count)`. When a slot's type has every variant already owned (8-attempt reroll budget exhausts), the code drops the type from `available_indices` and `continue`s — but the iteration still counts against `count`. So a request for 3 modifiers can return 2, then 1.

`hud.gd::show_modifier_choices_with_replacement` loops `for i in range(3)` and indexes `modifiers[i]` blindly. Short array → `Out of bounds get index '2'`.

Playtest stack:
```
hud.gd:1360 @ show_modifier_choices_with_replacement()
main.gd:1588 @ _on_upgrade_selected()
hud.gd:1338 @ _select_upgrade()
```

Same shape exists in `generate_distinct_at_rarity` (shop path).

### Fix — two layers

**Registry (`modifier_registry.gd`):** Change the outer loop from `for _n in range(count)` to `while results.size() < count and not available_indices.is_empty()`. When a slot's type exhausts (budget runs out), we drop the type and re-roll for the same slot from the remaining types, instead of silently losing the slot.

**Duplicate-tolerant top-up:** If `available_indices` empties before `results.size() == count`, fill the remainder by re-rolling with the exclusion filter disabled (allow duplicate fingerprints). This is the "graceful degradation" the previous spec promised but didn't actually code. Practically unreachable in a single run, but guarantees the contract.

Shape for `generate_distinct`:

```gdscript
while results.size() < count and not available_indices.is_empty():
    # ... existing weighted type-roll over available_indices ...
    var chosen_global_idx: int = available_indices[chosen_local]
    var mod: ScoringModifier = generate_of_type(chosen_global_idx)
    if excluded_fingerprints.size() > 0:
        var attempts: int = 0
        while mod.get_config_fingerprint() in excluded_fingerprints and attempts < 8:
            mod = generate_of_type(chosen_global_idx)
            attempts += 1
        if mod.get_config_fingerprint() in excluded_fingerprints:
            available_indices.remove_at(chosen_local)
            continue  # try a different type for this slot
    results.append(mod)
    available_indices.remove_at(chosen_local)

# Duplicate-tolerant top-up — only reached if every type's variants exhausted.
# Allows duplicate fingerprints to preserve the count contract.
while results.size() < count:
    results.append(generate_random())
```

`generate_distinct_at_rarity` gets the parallel treatment — top-up rolls a random type at the forced rarity (no exclusion).

**Caller (`hud.gd`):** Defensive — the contract is now sound but the hud assumption was unsafe regardless.

- `show_modifier_choices_with_replacement`: change `for i in range(3)` to `for i in range(modifiers.size())`. Assert `modifiers.size() == replacement_info.size()` at top. Explicitly hide unused buttons (`for i in range(modifiers.size(), 3): buttons[i].visible = false`).
- `show_reward_choices`: same shape — boss rewards array can also be short.

**Shop path audit (`main.gd::_generate_shop_picks`):** Already handles `mods.size() == 0` by falling through to an accuracy pick. With the registry fix, that fallthrough should rarely trigger, but keep it as-is — covers the edge where every modifier type is exhausted at the rolled rarity.

### Acceptance
- Player owns enough modifier configs to exhaust common-tier pool; the post-leg offering still produces 3 cards (last one may be a duplicate fingerprint as graceful degradation).
- Playtest crash stack (`hud.gd:1360`) does not reproduce.
- Regression: fresh run shows 3 distinct-typed offerings, no behavior change visible to player.
- Shop still renders correctly when only one of its two slots produces a modifier.

---

## 2. Perf diagnosis pass

### Background

Late-game (leg 5+) hitches on:
- Throwing a dart (mid-turn).
- Pressing "next leg" / advancing turn.
- Boss load-in at the start of a boss leg.
- Worst observed: ~20s, on a build with `+1 dart per turn` rule modifier.

Top suspects in `scoring_modifier_manager.gd`:

1. **`solve_checkout` recursion** — 83 candidate targets × depth = `darts_left`. `+1 dart` pushes depth 3 → 4, expanding the search by ~83×.
2. **Cache key cost** — `"%d_%d_%s" % [remaining, darts_left, str(streak_snap).hash()]` per recursive call. `str()` on `Array[Dictionary]` is slow when many streak modifiers are active.
3. **Redundant snapshots inside the per-target loop** — `_solve_recursive` line 443, `_solve_first` line 601. Each candidate iteration snapshots state identical to the one taken at function entry for the cache key.
4. **`compute_preferred_remainders`** — 179 sub-problems re-run on every modifier toggle / state change. Cached, but the dirty bit may bump more often than necessary.
5. **`_update_checkout_helper` is unconditional** — called from `_advance_turn`, `_on_next_leg`, throw-response, and modifier add/toggle. No memoization on identical `(remaining, darts_left, state_version)` inputs.

We don't know which dominates. The 20s freeze could be any of these, or a combination. Instrumentation tells us where to spend the structural fix.

### Instrumentation

Add an `@export var debug_perf_log: bool = false` flag on `ScoringModifierManager`. When true, the following functions emit `[PERF]`-tagged log lines. When false, zero overhead (early-return inside a single `if`).

**`solve_checkout(remaining, darts_left)`**

```
[PERF] solve_checkout r=<remaining> d=<darts_left>  <duration_ms>ms  recursive_calls=<n>  spec_calls=<n>  cache_hits=<n>  cache_misses=<n>  paths=<size>
```

- `recursive_calls`: increments on every `_solve_recursive` entry. Pass through recursion as `Array[int]` (single-element, mutable by reference — GDScript ints are pass-by-value).
- `spec_calls`: count of `speculative_score` invocations during this solve. Same pattern.
- `cache_hits` / `cache_misses`: tracked around the cache lookup in `_solve_recursive`.

**`compute_preferred_remainders()`**

```
[PERF] compute_preferred_remainders  <duration_ms>ms  results=<count>
```

**`_compute_one_dart_finishable()`**

```
[PERF] _compute_one_dart_finishable  <duration_ms>ms  entries=<count>
```

**`invalidate_preferred_remainders()`**

```
[PERF] invalidate_preferred_remainders
[PERF]   stack: <print_stack output>
```

Tells us who's bumping the dirty bit and how often. If it fires once per dart, that's a structural over-invalidation.

**`main.gd::_update_checkout_helper`** — wrap entry/exit:

```
[PERF] _update_checkout_helper r=<remaining> darts_left=<n>  <duration_ms>ms
```

Pins whether the helper itself or its callees dominate.

### Implementation notes

- Use `Time.get_ticks_usec()` for sub-millisecond resolution; divide by 1000.0 for the printed ms.
- All `[PERF]` emission goes through a single private helper `_perf_log(msg: String)` that no-ops when the flag is false. Keeps call sites clean.
- `print_stack()` only inside `invalidate_preferred_remainders` and only when the flag is on — it's expensive and noisy.
- No log lines on the gameplay-critical hot path (e.g., inside `_solve_recursive` body or the per-target loop). Only at function boundaries and at the public API.

### Reading the output

Max plays a late-game leg — debug-skip to leg 6+ with a stacked build, ideally with `+1 dart per turn` — captures `[PERF]` lines for a few darts plus one "next leg" press, and pastes them back. Likely outcomes:

- **`solve_checkout` dominates:** next spec kills the redundant inner snapshot and replaces `str().hash()` with a `state_version: int` counter bumped in `speculative_score` / streak mutations. Cache keys become `(remaining, darts_left, version)`.
- **`compute_preferred_remainders` fires too often:** next spec consolidates invalidation triggers — currently called from multiple sites that may not all need it (boss-spawn cycle, modifier add, modifier toggle, leg start).
- **`_update_checkout_helper` over-called:** next spec adds a memoized last-input cache, skip the work when inputs match the previous call.

### Acceptance

- With `debug_perf_log = false`: no observable behavior or perf change, no log spam.
- With `debug_perf_log = true`: log lines emit at the right call sites with non-zero durations and counters.
- One playtest pass captures enough data to identify the dominant bottleneck. Numbers go into the next spec.

### Out of scope for this spec

- Any actual perf fix. This is measurement only.
- Optimizing `_compute_one_dart_finishable` — already cheap (22 candidates, no recursion).
- Async / threaded solving. The recursive shape isn't a clean fit for `WorkerThreadPool` without deeper restructure; out of scope until we know it's needed.

---

## 3. Implementation order

1. **Fix #1 (crash)** first — small, isolated, unblocks late-game playtesting. ~30 lines across `modifier_registry.gd` and `hud.gd`.
2. **Fix #2 (instrumentation)** second — gated by debug flag, lands without changing live behavior. Max collects data on the next playtest.
3. Open a new spec with the measured numbers and the targeted perf fix.
