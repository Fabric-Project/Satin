# Satin Threading Architecture Proposal

## Context

`ThreadingConcerns.md` documents the symptoms. This document identifies the root causes and proposes a minimal architectural direction that makes Satin threading-safe without changing the public API and without precluding synchronous single-threaded execution.

---

## The Three Root Problems

Everything in `ThreadingConcerns.md` is a symptom of three deep structural issues.

### 1. ValueCache conflates "read" with "write"

`worldMatrix`, `localMatrix`, `worldPosition`, and every other derived property on `Object` lazily computes and stores its result via `ValueCache<T>.get()`. The function is `mutating` — a "read" from any thread is simultaneously a write. Two threads "reading" the same property concurrently both call `_worldMatrix.modify` and crash.

The deeper problem isn't purely about threading. There is no moment in Satin's current lifecycle where you can say "all world matrices are computed and stable." They are always computed on demand. Encoding a frame requires reading `worldMatrix` many times across many objects, and any of those results can be invalidated mid-read if any ancestor's transform changes on another thread — or even on the same thread if a Combine sink fires.

### 2. Combine synchronous dispatch couples mutation thread to render thread

`PassthroughSubject.send()` runs all subscribers synchronously on the calling thread, with no exceptions. This means:

- Setting `light.position` on main thread immediately runs shadow camera updates, uniform invalidation, and potentially PSO recompilation — all on main thread.
- There is no deferred execution. You cannot push a mutation through Combine and have its effects land on a different thread without explicitly wiring every sink through `.receive(on:)`.
- Satin's internal sinks (shadow updates, light data buffer rebuild, pipeline invalidation) were never wired to a specific thread. They run wherever the mutation originates.

The consequence: render-side effects are entangled with the calling thread. You cannot have a clean "main thread authors, render thread reads" model because every mutation carries immediate render-side effects that execute on the authoring thread.

### 3. Scene objects serve dual purpose: authoring API and render data source

`Object`, `Material`, `Geometry` — these are the things you build your scene with AND the things the encoder reads directly during frame production. There is no separation between "the description of your scene" and "the state the GPU pipeline consumes."

In single-threaded usage this is invisible. When authoring and encoding share one thread, every mutation happens in a defined order. When you want to author on one thread and encode on another, every mutation to every object at any time is a potential crash because the encoder is reading live objects with no stability guarantee.

---

## Design Direction

The core principle: **separate the scene as a description from the scene as render state**.

The authoring API stays the same — `Object`, `Mesh`, `Material`, `Geometry`, `RenderEncoder`, shadows, lights. A lightweight "render state" layer sits between the scene and the encoder. An explicit pass populates render state from the scene once per frame before encoding begins. The encoder reads only from render state, never from live scene objects.

---

### Change 1 — Eager world matrix computation (replaces ValueCache)

Instead of `worldMatrix` lazily computing and caching on the calling thread, an explicit top-down pass walks the scene tree and writes all world matrices into a per-object slot before encoding begins.

**Today (lazy mutating getter — crashes on concurrent reads):**
```swift
public var worldMatrix: simd_float4x4 {
    _worldMatrix.get { (parent?.worldMatrix ?? .identity) * localMatrix }
}
```

**Proposed (eager slot — pure read during encoding, pure write during update pass):**
```swift
// Written once per frame during the update pass, top-down:
internal var _worldMatrix: simd_float4x4 = .identity

// Pure read during encoding — no mutation, safe from any thread:
public var worldMatrix: simd_float4x4 { _worldMatrix }

// Called once per frame, top-down, on one thread, before encoding:
func computeWorldMatrices(parentMatrix: simd_float4x4 = .identity) {
    _worldMatrix = parentMatrix * localMatrix
    for child in children { child.computeWorldMatrices(parentMatrix: _worldMatrix) }
}
```

The parent-before-child dependency is naturally satisfied by top-down recursion. No epoch tracking, no slot indexing, no dirty bitmask. During encoding, `worldMatrix` is a pure stored-property read — safe from any number of concurrent readers.

`transformPublisher` still fires when properties are set (for downstream subscribers like shadow cameras and Combine chains), but it no longer clears a lazy cache. The transform data that encoding reads is only written during the explicit `computeWorldMatrices()` call.

All other `ValueCache`-backed properties (`worldPosition`, `worldOrientation`, `worldScale`, `localMatrixInverse`, `worldBounds`, direction vectors) follow the same pattern: computed eagerly in the update pass, stored as plain values, read as plain properties during encoding.

**Eliminates:** the `Object._worldMatrix.modify` TSAN crash class, all concurrent mutating-getter crashes, and the possibility of encoding reading a partially-invalidated transform mid-frame.

---

### Change 2 — Combine sinks mark dirty only; render work defers to update pass

Instead of Combine sinks executing render-side work synchronously on the calling thread, sinks set atomic dirty flags. The actual work (buffer rebuilds, PSO recompilation, texture swaps) happens at the start of the next frame's update pass on the render thread.

**Today (sink runs buffer rebuild on calling thread):**
```swift
parameterGroup.sink { [weak self] in
    self?.uniformBuffer.rebuild()  // executes immediately on calling thread
}
```

**Proposed (sink marks dirty only):**
```swift
parameterGroup.sink { [weak self] in
    self?._uniformsDirty.store(true, ordering: .relaxed)  // atomic, safe from any thread
}
// Rebuild happens at the start of updateScene() on the render thread:
if _uniformsDirty.load(ordering: .acquiring) {
    uniformBuffer.rebuild()
    _uniformsDirty.store(false, ordering: .releasing)
}
```

This applies to:
- Material uniform buffer rebuilds triggered by parameter changes
- Pipeline state recompilation triggered by blending/depth setting changes
- Shadow texture reallocation triggered by resolution changes
- IBL texture swaps triggered by environment changes
- Light data buffer invalidation

Parameters, material settings, blending mode changes, shadow resolution — all can fire from main thread freely and immediately. The expensive work defers to the render thread's update pass. A single-threaded caller sees no behavioral difference: the dirty flag is set and processed in the same frame.

**Eliminates:** render-side effects executing on the wrong thread, PSO compilation blocking main thread, uniform rebuild racing with encoding.

---

### Change 3 — Camera controllers: pure accumulate pattern

Event handlers write only to accumulation state (deltas, new axis/angle values). `update()` is the single place where accumulated state is applied to the camera and target. Zero direct camera mutations from event handlers.

**Today (event handler directly mutates camera):**
```swift
// macOS mouseDragged — runs on main thread:
rotationAxis = angleAxis.axis
rotationAngle = angleAxis.angle
updateRotation()  // → target.orientation *= ... fires transformPublisher on main thread
```

**Proposed (event handler accumulates only):**
```swift
// macOS mouseDragged — runs on main thread:
os_unfair_lock_lock(&_inputLock)
rotationAxis = angleAxis.axis
rotationAngle = angleAxis.angle
os_unfair_lock_unlock(&_inputLock)
// update() on render thread reads these and applies:
```

```swift
// update() — runs on render thread:
public func update() {
    updateTime()
    switch state {
    case .rotating:
        os_unfair_lock_lock(&_inputLock)
        let axis = rotationAxis; let angle = rotationAngle
        os_unfair_lock_unlock(&_inputLock)
        applyRotation(axis: axis, angle: angle)
    case .tweening:
        // ... damped tween as today ...
    // etc.
    }
}
```

`os_unfair_lock` (not a mutex, not a semaphore) protects only the non-atomic SIMD3 accumulation vars (`rotationAxis: simd_float3`, `translation: simd_float3`). The lock is held for nanoseconds — two stores on main thread, two loads on render thread.

With camera mutations happening only in `update()` on the render thread, `transformPublisher` fires on the render thread, and the Combine cascade (shadow cameras, uniform invalidation) runs there too. This is correct — it runs before encoding begins in the same frame.

**Eliminates:** `target.orientation` mutations racing with encoding, shadow camera mutation during `shadow.draw()`, Combine cascade on wrong thread.

---

### Change 4 — Defined frame lifecycle

```
UPDATE PHASE  (render thread, before encoding)
  1. Drain structural mutation queue (add/remove children — see below)
  2. computeWorldMatrices()  — top-down tree walk, all objects
  3. updateScene()           — process dirty flags, rebuild uniforms, upload data
  4. updateLights()          — light data buffer

ENCODE PHASE  (render thread, immediately after update phase)
  5. Encode shadow passes
  6. Encode main pass
  7. Encode post-process passes
  8. Commit command buffer → GPU

AUTHOR PHASE  (any thread, between frames)
  - Mutations mark dirty flags (atomic stores)
  - Structural changes enqueue to mutation queue
  - Camera controller accumulation vars written (with short locks for SIMD3)
  - No render-side effects execute immediately
```

For synchronous single-threaded execution: update and encode phases run on the same thread sequentially. The mutation queue drains at the top of each frame. Zero overhead compared to today.

For threaded execution: main thread authors freely while the render thread works through its frame. No locks on the critical path — authoring writes atomic dirty flags and accumulation vars; rendering reads pre-computed stable render state.

---

### Change 5 — Structural mutation queue

`Object.children` is a plain Swift Array. `add(child:)` or `remove(child:)` from main thread while the render thread is traversing `children` in `updateLists()` is a crash.

The fix: structural mutations (add/remove) submit a closure to a simple queue. The queue is drained at the top of the update phase (Step 1 above), before any tree traversal.

```swift
// Any thread:
renderer.schedule { scene.add(newMesh) }

// Or, as a documented contract:
// "Call add() and remove() from within your update() override — that runs on the render thread."
```

For single-threaded usage, `schedule` just executes the closure immediately. For threaded usage, it enqueues. The public API for `add` and `remove` does not change — just when they execute.

---

## What Stays the Same vs. What Changes

| | Today | Proposed |
|---|---|---|
| Public API | `Object`, `Mesh`, `Material`, etc. | Unchanged |
| `worldMatrix` read | `ValueCache.get()` — mutating | Plain stored property — pure read |
| `worldMatrix` write | Lazy, on first read after invalidation | Explicit `computeWorldMatrices()` before encoding |
| Combine sinks | Execute render work on calling thread | Mark dirty only; render work defers to update pass |
| Camera controller input | Direct camera mutations from event handlers | Pure accumulate; `update()` is only mutation point |
| Scene structure mutations | Any thread, any time | Queued, drained at top of update phase |
| Frame lifecycle | Implicit (mixed into `draw()`) | Explicit four-phase contract |
| Single-threaded use | Works | Works identically |
| Threaded use | TSAN crashes | Safe |

---

## Minimum Viable First Step

The highest-leverage single change is **replacing `ValueCache` with eager world matrix computation** (Change 1).

This alone:
- Eliminates the `Object._worldMatrix.modify` TSAN crash class
- Makes encoding reads of `worldMatrix` safe from any concurrent reader
- Requires no public API changes
- Does not require camera controller restructuring
- Does not require Combine sink rewiring
- Makes the subsequent changes (2–5) easier because the foundation is stable

Scope: `Sources/Satin/Utilities/ValueCache.swift` is deleted or repurposed. `Sources/Satin/Core/Object.swift` replaces all `_worldMatrix.get { }` accessors with stored properties and adds `computeWorldMatrices()`. `Sources/Satin/Core/RenderEncoder.swift` calls `computeWorldMatrices()` at the top of the update pass before `updateScene()`.

Changes 2–5 can follow incrementally, each independently reviewable.
