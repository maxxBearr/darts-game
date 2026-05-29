---
Spec date: 2026-05-28
Status: **FUTURE WORK — not scheduled**
Trigger to revisit: late-game `_update_checkout_helper` regularly exceeds ~500ms in playtesting, OR before any public release where stacked-modifier endgame is a featured experience.
---

# Async Checkout Solver via WorkerThreadPool

**Captured during:** 2026-05-28 perf-pass sprint, immediately after Cache Key Hotfix + Recursive Prune shipped. Context loaded; future-self should reload the relevant code before implementing.

## Why this spec exists (and why it's not active)

After the 2026-05-28 perf passes, worst-case `_update_checkout_helper` latency is around **~740ms** on a stacked late-game build (verified in playtest). Most calls are sub-200ms. That's within shippable territory — players can perceive a brief hitch but not a freeze.

Threading the solver would push the remaining freeze to invisible: the work happens on a background thread while the scoring tween plays, and the helper panel updates async when results arrive. The solver is a clean candidate because it's pure data manipulation — no node access, no scene-tree mutation, no signals fired mid-call. Thread-safe by construction once we deep-copy the input state.

We're not implementing this now because:
- Current perf is acceptable; threading is polish, not a fix.
- The codebase is still adding modifier types and boss mechanics; threading in isolation is easy, threading around a shifting surface area is the actual design problem.
- Maintenance and debugging burden of threading is real — not worth carrying through ongoing feature work.

This document exists so future-Max (and future-Claude) don't redesign from scratch when the trigger fires.

## Trigger criteria

Implement when **any** of:
- Late-game `_update_checkout_helper` regularly tops 500ms in real playtesting (not just one-off worst cases).
- A new modifier type or boss mechanic pushes solver hot path costs measurably higher.
- Approaching a public release / showcase where stacked-modifier endgame is a featured experience.
- `compute_preferred_remainders` becomes a freeze again despite the existing prune (e.g., new modifier shapes that defeat `_max_single_dart_score` bounding).

Do **not** implement just because "more performance is better." The current setup is good enough until one of the above is true.

## Architecture sketch

### High-level flow

```
[dart hits]
   ↓
calculate score, apply to remaining_score
   ↓
kick solver task on WorkerThreadPool ──→ [bg thread runs solve_checkout]
   ↓                                            │
start scoring tween on main thread              │
   ↓                                            │
tween plays, frames render normally             │
   ↓                                            │
solver completes, emits signal ←────────────────┘
   ↓
hud.update_checkout_display() on main thread
```

### Components

**`ScoringModifierManager` gets two new public methods:**

```gdscript
## Kick an async checkout solve. Returns immediately. Result delivered via
## `checkout_solve_complete` signal. If another solve is already in flight,
## the new request supersedes it (the older result is discarded on arrival).
func solve_checkout_async(remaining: int, darts_left: int) -> void

## Emitted on the main thread when an async solve completes.
## Carries the same Array[Array] payload as the sync solve_checkout.
signal checkout_solve_complete(paths: Array[Array], remaining: int, darts_left: int)
```

The signal carries `remaining` and `darts_left` so the receiver can verify the result is still relevant (player hasn't thrown again in the meantime).

**`main.gd::_update_checkout_helper`** becomes a kick-and-forget call. The actual HUD update happens in a `_on_checkout_solve_complete` handler.

### Threading mechanics

- `WorkerThreadPool.add_task(callable)` for the task itself.
- Task callable runs `_solve_recursive` on a snapshot of state passed in via captured closure variables.
- On completion, the task calls `call_deferred` to emit `checkout_solve_complete` back on the main thread.
- Track the in-flight task ID on the manager; when a new solve is kicked, just bump a "current request ID" — on completion, compare; if stale, drop.

## Key design questions (decide at implementation time)

### Q1: How is solver state snapshotted into the task?

The solver reads:
- `_solver_candidates` (rebuilt from board state)
- `effective_wedge_values`, `effective_wedge_colors`
- `active_modifiers` (the instances themselves, mutated by `speculative_score`)
- `_max_single_dart_score`, `_max_preferred_remainder`
- `allow_triple_checkout`, `glass_cannon_active`

Two approaches:

**(A) Deep-copy into task payload.** Build a `SolverState` Dictionary/Resource at kick time, pass into the task. Solver operates on the copy. Original modifier instances stay untouched on the main thread.
- Pro: trivially safe. No locking, no shared state.
- Con: deep-copying modifier instances (especially streak state) is non-trivial. Modifier subclasses would need a `clone()` method.

**(B) Refactor streak state out of modifier instances.** Streak state lives in a separate data structure (e.g., `Dictionary[ScoringModifier, Dictionary]`) that the solver receives a copy of. Modifier instances become stateless function objects.
- Pro: cleaner long-term design. Multiple solvers could run in parallel without conflict.
- Con: invasive refactor — every modifier that uses `save_streak_state` / `restore_streak_state_from` needs reworking. Hit history pipeline (`process_score`) also touches modifier internals.

**Recommendation: (A) at implementation time.** Lower blast radius. Revisit (B) if multiple parallel solvers become useful (e.g., a "preview" solver showing what-if scenarios).

### Q2: What does the helper panel show while a solve is in flight?

The dart resolved, the player sees the score tween, and the helper panel is showing the *previous* result for ~200–700ms. Three UX options:

- **(a) Keep previous result, add subtle "..." indicator.** Player sees old paths briefly but knows it's updating. Least jarring.
- **(b) Blank the panel during solve.** Clean but disorienting — the helper appears to "flash" on every dart.
- **(c) Optimistic update.** Show the previous result with no indicator, swap on completion. Cleanest visually but technically lying for a moment.

**Recommendation: (a)** — subtle "..." or a thin progress shimmer. Players intuit "computing" without feeling like they lost the helper.

### Q3: What happens when a new throw arrives before the solver finishes?

Player throws dart 2 while dart 1's solve is still in flight. Two paths:

- **Discard on arrival.** When task completes, check if its `(remaining, darts_left)` matches the current state. If not, drop the result. Kick a new task for the new state.
- **Cancel the task.** Godot's `WorkerThreadPool` doesn't support cancellation directly — you'd need a flag the task polls. Possible but adds complexity to the solver hot path.

**Recommendation: discard on arrival.** Simpler. Wasted CPU on the worker thread is invisible.

### Q4: `compute_preferred_remainders` — also async?

The 179-problem precompute can spike to ~370ms even after Fix #2. Whether to async this depends on call frequency:
- It only runs when `_preferred_remainders_dirty` is true (modifier add/toggle, leg start with state change).
- These are user-initiated events with natural pauses, so a 370ms spike is less perceptible.
- But: if a modifier-pick happens and the next throw is immediate, the player will feel it.

**Recommendation:** thread `compute_preferred_remainders` too, using the same pattern. Both methods become async via the same mechanism. Saves a second pass.

### Q5: Save/load and main-thread guarantees

If save/load can fire while a solver task is running, state mutation on the main thread could conflict with the task's read. Approach (A) (deep-copy) sidesteps this — the task has its own snapshot. Confirm at implementation time that save/load doesn't mutate modifier instances mid-game (it shouldn't — saves serialize state, don't mutate during normal play).

## UX trade-offs to think about

- **Helper feels less authoritative.** A "..." indicator nudges the player to wait before acting on a path suggestion. Most players won't notice, but power players might.
- **First throw after a modifier change.** Modifier add invalidates the precompute. The first throw after acquiring a modifier kicks a fresh solve from cold cache — likely the slowest single solve in any given session. With threading, the player throws and the panel shows "..." briefly. Without threading, the panel just freezes the same way it does today.
- **+1 dart legs.** With working cache and threading, d=4 solves are async too. Even if they take a couple seconds, the player never sees a freeze.

## The alternative worth comparing first

**Chunked precompute via `_process`.** Refactor `compute_preferred_remainders` into a resumable loop: do 10–20 remainders per frame, store partial results, resume next frame. Spreads the cost across many frames, each tiny.

- Pro: no threading, no signals, no UX rework. Implementable in a couple hours.
- Con: doesn't help `solve_checkout` (recursive, hard to chunk cleanly). Only addresses the precompute spike.

Worth implementing first if `compute_preferred_remainders` is the only remaining freeze when this spec gets unparked. If `solve_checkout` is also painful, threading is the right answer for both.

## What is NOT in scope

- Threading anything beyond the checkout solver (scoring pipeline, rendering, save/load).
- Parallelizing multiple solver tasks (preview "what if I hit this?" solvers running alongside the main helper solve). Possible later, but Approach (A) leaves it on the table without committing.
- Replacing the recursive solver with an iterative one for better chunking. Major rewrite, not justified by the data.
- GPU compute. Comically overengineered for this problem.

## Implementation order when reactivated

1. Confirm the trigger criterion that justified reactivation. Capture fresh `[PERF]` data before changing anything.
2. Decide Q1 (snapshot strategy) and Q2 (panel UX) before writing code.
3. Implement Approach (A) snapshot + `solve_checkout_async` + signal first. Keep the sync `solve_checkout` as a fallback for non-time-critical callers (or remove if no callers remain).
4. Migrate `compute_preferred_remainders` to the same pattern.
5. Wire the "..." indicator in the helper panel.
6. Re-run the perf playtest. Confirm worst-case frame-time during solver activity is normal (16ms target).

## Open question to answer at reactivation

Does Godot 4.6 have any caveats around `WorkerThreadPool` + `Resource` mutation safety we should verify before committing? Last checked: 4.6 stable, no known issues for read-only-from-worker / write-only-from-main patterns. Re-verify against the current Godot version when implementing.
