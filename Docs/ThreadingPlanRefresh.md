# Satin Threading Plan Refresh

`Docs/ThreadingPlan.md` is historical context for an older branch model. This document is the current implementation plan for the code in this branch.

## Current Execution Model

- `ViewRenderer` is synchronous on the caller thread.
- `SpatialRenderer` owns the active threaded render loop.
- There is no shared `renderQueue` abstraction in this branch, so threading work must be attached to the actual execution owner.

## First-Principles Findings

- Render-time reads must come from a stable per-frame snapshot, not from lazy mutating getters.
- Scene `update()` happens during traversal, so render transforms must be computed after each object updates, not before traversal starts.
- Parameter safety requires locking the actual uniform upload data path, not just dirty booleans.
- The immediate wrong-thread side effects are light and shadow updates, projector camera updates, and environment texture swaps.

## Recommended Rollout

1. Stabilize render-critical derived state with a render snapshot pass for objects and cameras.
2. Synchronize parameter upload state in `GenericParameter` and `ParameterGroup`.
3. Stage thread-owned side effects for lights, shadows, projector cameras, and environment swaps.
4. Queue structural mutations onto the render owner and drain them at the top of a frame.

## Test Strategy

- Keep `swift build` green.
- Keep `swift test --filter 'ObjectTests|ParameterTests|MutexTests'` green.
- Add regression coverage for:
  - render snapshots after `object.update()`,
  - queued structural mutations draining before traversal,
  - parameter upload synchronization,
  - environment swap staging.

## Historical Note

- `Docs/ThreadingPlan.md` reflects earlier assumptions and should be treated as historical.
- `Docs/ThreadingPlanRefresh.md` is the current source of truth for the refreshed threading work.
