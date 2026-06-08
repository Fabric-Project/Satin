# Satin Threading Plan

> Historical note: this document reflects an earlier branch model. The current source of truth is `Docs/ThreadingPlanRefresh.md`.

## Starting Point

<<<<<<< HEAD
**Do not implement from the current `feature/2.0-Multithreading` branch.** That branch contains a series of partial, conflicting experiments. The code in it is not authoritative. Start from `main` and apply the changes below incrementally on a fresh branch.
=======
**Do not implement from the `feature/2.0-Multithreading-Failed` branch.** That branch contains a series of partial, conflicting experiments. The code in it is not authoritative. Start from `Feature/2.0-Multithreading` which is a fresh branch off of 2.0 - and apply the changes below incrementally on a fresh branch.
>>>>>>> 8a10919e199e261453a392cb39fc594b45f59085

---

## Scope

This document reviews `ThreadingConcerns.md` and `ThreadingProposal.md` against the actual code, identifies corrections to the framing, fills gaps the proposal left unspecified, and produces a prescriptive implementation plan at the file+method level.

---

## Corrected Mental Model

### The actual thread boundary

`ViewRenderer.draw(metalLayer:drawable:)` dispatches **both** `update()` and `_renderFrame()` to `renderQueue.async` in sequence:

```swift
// ViewRenderer.swift:78
func draw(metalLayer: CAMetalLayer, drawable: CAMetalDrawable) {
    guard isSetup else { return }
    renderQueue.async { [weak self] in
        self?.update()          // ← renderQueue
        self?._renderFrame(drawable: drawable)  // ← renderQueue
    }
}
```

`update()` and `draw()` are already serialized — they share the same queue and run back-to-back in the same async block. **The thread boundary is not `update()` vs `draw()`; it is main-thread event handlers vs. renderQueue.**

Concretely:
- NSEvent monitors, gesture recognizer callbacks → **main thread**
- `update()`, `updateLists()`, `updateScene()`, encoding → **renderQueue**

The proposal's Change 3 fix is still correct, but the problem framing is slightly wrong. Event handlers race against renderQueue, not against `draw()` racing against `update()`.

### Default configuration is single-threaded

`Renderer.renderQueue` defaults to `DispatchQueue.main`. In this configuration everything runs on main and none of these races exist. The threading work is specifically for the configuration where `renderQueue` is set to a background queue. The plan should be implemented so the default remains safe and single-threaded use sees zero overhead.

---

## Code vs. Proposal Verification

### Change 1 — ValueCache / eager world matrices

**Confirmed.** `ValueCache.get()` is `mutating` (Object.swift:19, ValueCache.swift:19). Every derived `Object` property — `worldMatrix`, `localMatrix`, `normalMatrix`, `worldPosition`, `worldOrientation`, `worldScale`, all direction vectors — lazily computes and caches via this mutating getter. Two threads "reading" the same property concurrently both call `_worldMatrix.modify` and crash (TSAN).

**Gap: full ValueCache chain.** `computeWorldMatrices()` will call `localMatrix.get {}` on each object, which calls `translationMatrix.get {}`, `rotationMatrix.get {}`, `scaleMatrix.get {}`. All are ValueCache-backed. During the update pass on a single thread this is correct and safe. The plan just needs to name these as in-scope for Change 1 so none are overlooked.

**Gap: bounds system uses a parallel but different pattern.** `_updateLocalBounds`, `_updateWorldBounds`, and `_updateBounds` are Bool flags (not ValueCache), set in `didSet` chains. They are guarded by `if flag { compute; flag = false }` in the getter. Same concurrent-mutating-getter exposure as ValueCache. These should be migrated or protected as part of Change 1 scope.

### Change 2 — Combine dirty flags

**Confirmed.** `PassthroughSubject.send()` runs all subscribers synchronously on the calling thread. Satin's internal sinks (material uniform rebuilds, PSO recompilation, shadow texture reallocation, IBL swaps, light data buffer invalidation) currently execute on whatever thread fires the mutation.

**Gap: mechanism unspecified.** The proposal says "atomic stores" but Swift doesn't have built-in atomic booleans. `Locks.swift` already provides `UnfairLock` (wraps `os_unfair_lock`). Use that. An `UnfairLock`-guarded Bool is held for nanoseconds (two assignments) and has zero contention on the happy path. No new dependencies needed.

### Change 3 — Camera controllers

**Confirmed.** Event handlers call `updateRotation()`, `updateTranslation()`, `updateZoom()` directly, mutating `target.orientation`, `target.position`, and `camera.position.z` on the main thread. `PerspectiveCameraController.update()` is only called by the renderer's `override func update()`, which runs on renderQueue — so the camera mutation path runs on two threads simultaneously during a drag.

The fix is smaller than the proposal makes it look. The accumulation vars (`rotationAxis: simd_float3`, `rotationAngle: Float`, `translation: simd_float3`, `zoom: Float`, `roll: Float`) already exist. Only `simd_float3` writes are non-atomic (12-byte store); `Float` writes are atomic on arm64. Add one `UnfairLock` to protect `simd_float3` accumulation writes, remove the direct `update*()` calls from event handlers, add a `.rotating` / `.panning` / `.zooming` case to `update()` that reads accumulators under lock and then calls `updateRotation()` etc.

### Change 4 — Frame lifecycle

**Confirmed structurally.** `ViewRenderer` already enforces update-then-encode order within a single renderQueue.async block. What is missing is the explicit `computeWorldMatrices()` call at the top of the update sequence — before `updateLists()`.

The insertion point is `RenderEncoder.swift`, in the method that calls `updateLists()` then `updateScene()` (around line 1849). A single `scene.computeWorldMatrices()` call at the top of that sequence is the entire structural change.

### Change 5 — Structural mutation queue

**Confirmed.** `updateLists()` iterates `object.children` (plain Swift Array) with no protection. `add(_:)` / `remove(_:)` on main thread during traversal on renderQueue is a mutation-during-iteration crash. A `renderer.schedule {}` queue drained before traversal is the fix.

---

## Implementation Plan

### Step 1 — Replace ValueCache with eager computation (highest leverage)

**Why first:** eliminates the `_worldMatrix.modify` TSAN crash class — the most common crash reported. Makes all subsequent changes easier because world-space state is stable during encoding.

**Files:**

| File | Change |
|---|---|
| `Sources/Satin/Utilities/ValueCache.swift` | Delete or tombstone |
| `Sources/Satin/Core/Object.swift` | Replace all `ValueCache`-backed stored properties |

**Object.swift changes:**

1. Replace every `var _worldMatrix = ValueCache<matrix_float4x4>()` with `var _worldMatrix: matrix_float4x4 = .identity`. Same for: `_worldMatrixInverse`, `_normalMatrix`, `_localMatrix`, `_localMatrixInverse`, `_translationMatrix`, `_rotationMatrix`, `_scaleMatrix`, `_worldPosition`, `_worldOrientation`, `_worldScale`, `_forwardDirection`, `_upDirection`, `_rightDirection`, `_worldForwardDirection`, `_worldUpDirection`, `_worldRightDirection`.

2. Replace every `var foo: T { _foo.get { compute() } }` with `var foo: T { _foo }`.

3. Add a single top-down eager computation pass:

```swift
func computeMatrices(parentMatrix: matrix_float4x4 = .identity) {
    _translationMatrix = translationMatrix3f(position)
    _rotationMatrix = matrix_float4x4(orientation)
    _scaleMatrix = scaleMatrix3f(scale)
    _localMatrix = simd_mul(simd_mul(_translationMatrix, _rotationMatrix), _scaleMatrix)
    _localMatrixInverse = _localMatrix.inverse
    _worldMatrix = simd_mul(parentMatrix, _localMatrix)
    _worldMatrixInverse = _worldMatrix.inverse
    let n = _worldMatrixInverse.transpose
    _normalMatrix = simd_matrix(simd_make_float3(n.columns.0), simd_make_float3(n.columns.1), simd_make_float3(n.columns.2))
    _worldPosition = simd_make_float3(_worldMatrix.columns.3)
    // world orientation and scale computed from worldMatrix as today, but stored rather than lazily cached
    let c0 = _worldMatrix.columns.0; let c1 = _worldMatrix.columns.1; let c2 = _worldMatrix.columns.2
    let sx = length(simd_make_float3(c0)); let sy = length(simd_make_float3(c1)); let sz = length(simd_make_float3(c2))
    _worldScale = simd_make_float3(sx, sy, sz)
    _worldOrientation = simd_quatf(simd_float3x3(
        simd_make_float3(c0.x, c0.y, c0.z) / sx,
        simd_make_float3(c1.x, c1.y, c1.z) / sy,
        simd_make_float3(c2.x, c2.y, c2.z) / sz
    ))
    _rightDirection = simd_normalize(orientation.act(Satin.worldRightDirection))
    _upDirection = simd_normalize(orientation.act(Satin.worldUpDirection))
    _forwardDirection = simd_normalize(orientation.act(Satin.worldForwardDirection))
    _worldRightDirection = simd_normalize(_worldOrientation.act(Satin.worldRightDirection))
    _worldUpDirection = simd_normalize(_worldOrientation.act(Satin.worldUpDirection))
    _worldForwardDirection = simd_normalize(_worldOrientation.act(Satin.worldForwardDirection))

    for child in children {
        child.computeMatrices(parentMatrix: _worldMatrix)
    }
}
```

4. `updateWorldMatrix.didSet` still fires `transformPublisher` and propagates `updateWorldMatrix` to children (for notifying subscribers), but no longer clears any caches. The dirty bits used to trigger recompute are now irrelevant for encoding — `computeMatrices()` recomputes everything unconditionally. Dirty bits can stay for downstream Combine subscribers that care about transform changes.

5. **Bounds system:** `_updateLocalBounds`, `_updateWorldBounds`, `_updateBounds` are Bool flags with `if flag { compute; flag = false }` in their getters. These are written on main thread and read on renderQueue — same exposure. For now: add an assertion or comment that bounds should not be read during encoding (bounds are used for raycasting and UI, not in the encoding path). A full fix follows in a later step.

**RenderEncoder.swift change:**

In the method around line 1840 (the one that calls `updateLists` and `updateScene`), add `scene.computeMatrices()` as the very first call:

```swift
scene.computeMatrices()           // ← add this
objectList.removeAll(keepingCapacity: true)
// ... existing code follows
updateLists(object: scene, visible: true)
updateScene(...)
updateLights()
```

**Result after Step 1:** encoding reads `worldMatrix` as a plain stored property from any thread, safely. `computeMatrices()` is the only writer and runs before traversal.

---

### Step 2 — Parameter value thread safety

**Why here:** `GenericParameter.writeData()` reads `self.value` directly via `data.storeBytes(of: value, as: ValueType.self)` (`GenericParameter.swift:135`). This runs on renderQueue during `material.update()` inside `updateScene()`. A UI slider sets `param.value` on main thread at the same time. For `simd_float3` (12 bytes) and matrix types, this is a non-atomic torn read — a genuine crash class, independent from the dirty-flag buffer-rebuild race in Step 3.

**Step 3's dirty flags do not fix this.** They defer `uniformBuffer.rebuild()` (buffer reallocation). Per-frame uniform data upload (`writeData()`) still happens every frame unconditionally and still reads the raw value.

**Files:** `Sources/Satin/Parameters/GenericParameter.swift`

**Change:** Add an `UnfairLock` to `GenericParameter` protecting the `value` stored property:

```swift
import Foundation  // already imported

public class GenericParameter<T: Codable & Equatable>: Parameter {
    private let _valueLock = UnfairLock()   // ← add

    public var value: ValueType {
        get {
            _valueLock.unbalancedLock()
            defer { _valueLock.unbalancedUnlock() }
            return _value
        }
        set {
            _valueLock.unbalancedLock()
            let old = _value
            _value = newValue
            _valueLock.unbalancedUnlock()
            if old != newValue {
                valueDidChange = true
                valuePublisher.send(newValue)
            }
        }
    }
    private var _value: ValueType   // renamed backing store
    ...
}
```

`writeData()` calls `value` (the getter) which takes the lock, copies the value into a local, releases the lock, then stores it. Lock held for one word load — negligible cost on the hot path.

**Scope:** `Float3Parameter` and `Float4x4Parameter` are the only crash-risk types (non-atomic stores). `Float`, `simd_float2`, `simd_float4` are arm64-atomic. But `GenericParameter` is the common base — adding the lock once there covers all parameter types without per-type changes.

**Note on `valueDidChange` and `valuePublisher.send()`:** these are called outside the lock in the setter above. That is intentional — `valuePublisher.send()` runs Combine sinks synchronously and those sinks may re-enter `value`. Calling Combine under lock would deadlock. The `valueDidChange` Bool is only read on renderQueue (during `material.update()`) so a brief stale read is acceptable.

---

### Step 3 — Camera controller accumulate pattern

**Why third:** eliminates the main→renderQueue data race on `target.orientation` during encoding. No API changes.

**Files:** `Sources/Satin/CameraControllers/PerspectiveCameraController.swift` (and equivalents for `OrbitPerspectiveCameraController`, `OrthographicCameraController`)

**Changes:**

1. Add `private var _inputLock = UnfairLock()` (import from Locks.swift already available).

2. In every event handler that currently calls `updateRotation()`, `updateTranslation()`, `updateZoom()`, `updateRoll()` directly:
   - Lock `_inputLock`
   - Write to the accumulation var
   - Unlock
   - **Do not call** `updateRotation()` etc. from the event handler

3. In `update()`, add a `.rotating` case (and equivalent cases for panning/dolly/zoom/roll):

```swift
public func update() {
    updateTime()
    switch state {
    case .rotating:
        _inputLock.unbalancedLock()
        let axis = rotationAxis; let angle = rotationAngle
        _inputLock.unbalancedUnlock()
        guard !axis.x.isNaN, !angle.isNaN else { break }
        target.orientation *= simd_quatf(angle: rotationScalar * angle, axis: axis)
        onChangePublisher.send(self)
    case .tweening:
        // existing tween logic unchanged
        ...
    }
}
```

4. The existing `.tweening` path in `update()` already calls `tweenRotation()` etc. — no change needed there.

**Note on simd_float3 atomicity:** `rotationAxis: simd_float3` is a 12-byte non-atomic store. The `UnfairLock` for just this field is held for two assignments. `Float` accumulators (`rotationAngle`, `zoom`, `roll`) are arm64-atomic and don't strictly need the lock, but wrapping them under the same lock is simpler and has zero measurable overhead.

---

### Step 4 — Combine sinks mark dirty only

**Why fourth:** cleans up render-side effects executing on the wrong thread. Lower urgency than Steps 1 and 2 because in the `renderQueue = background` configuration, sinks fired on main thread writing an atomic dirty flag is safe — the actual rebuild deferred to renderQueue's update pass is already serialized. Steps 1 and 2 prevent crashes; Step 3 prevents stalls and wrong-thread PSO compilation.

**Mechanism:** `UnfairLock`-guarded Bool or a simple `AtomicBool` wrapper around `os_unfair_lock` (already in Locks.swift):

```swift
private var _uniformsDirty: Bool = false
private let _dirtyLock = UnfairLock()

// In the Combine sink (called from any thread):
parameterGroup.sink { [weak self] in
    self?._dirtyLock.unbalancedLock()
    self?._uniformsDirty = true
    self?._dirtyLock.unbalancedUnlock()
}

// In updateScene() on renderQueue:
_dirtyLock.unbalancedLock()
let needsRebuild = _uniformsDirty
_uniformsDirty = false
_dirtyLock.unbalancedUnlock()
if needsRebuild { uniformBuffer.rebuild() }
```

**Systems that need dirty flags:**

| System | Current behavior | Dirty flag location |
|---|---|---|
| Material uniform buffer | Rebuilt in sink on calling thread | `Material` or `UniformBuffer` |
| PSO recompilation | `shader.update()` called lazily during encode | `Shader` |
| Shadow texture reallocation | `resolution` setter triggers MTLTexture alloc | `PointShadow`, `SpotShadow`, `DirectionalShadow` |
| IBL environment swap | `setEnvironment()` swaps texture references | `RenderEncoder` |
| Light data buffer invalidation | `_updateLightDataBuffer` bool (already exists) | Already correct — just needs thread protection |

**Note on single-threaded use:** dirty flag is set and checked in the same frame — no behavioral difference. The flag is just set before being checked.

---

### Step 5 — Structural mutation queue

**Why last:** lowest urgency. Scene add/remove from main thread during renderQueue traversal is a latent crash, not an active one for most use cases. Also the simplest conceptual fix.

**Files:** `Sources/Satin/Core/RenderEncoder.swift`, `Sources/Satin/Core/Object.swift` (or a new `StructuralMutationQueue`)

**Change:**

```swift
// On Renderer or RenderEncoder:
private var _pendingMutations: [() -> Void] = []
private let _mutationLock = UnfairLock()

public func schedule(_ mutation: @escaping () -> Void) {
    if renderQueue === DispatchQueue.main || Thread.isMainThread {
        mutation()  // single-threaded: execute immediately
    } else {
        _mutationLock.unbalancedLock()
        _pendingMutations.append(mutation)
        _mutationLock.unbalancedUnlock()
    }
}

// At the top of the update-encode block on renderQueue (before computeMatrices):
_mutationLock.unbalancedLock()
let mutations = _pendingMutations
_pendingMutations.removeAll(keepingCapacity: true)
_mutationLock.unbalancedUnlock()
mutations.forEach { $0() }
```

---

## Summary Table

| Step | Root problem solved | Files touched | Crash class eliminated |
|---|---|---|---|
| 1 — Eager matrices | `ValueCache` mutating getter | `ValueCache.swift`, `Object.swift`, `RenderEncoder.swift` | `_worldMatrix.modify` TSAN crash |
| 2 — Parameter value lock | `simd_float3`/matrix torn reads during uniform upload | `GenericParameter.swift` | Torn-read on `writeData()` |
| 3 — Camera accumulators | Main-thread camera mutation during encoding | `PerspectiveCameraController.swift`, others | `target.orientation` / shadow camera race |
| 4 — Combine dirty flags | Wrong-thread render side effects | `Material.swift`, `Shader.swift`, shadows | PSO stall, uniform rebuild on wrong thread |
| 5 — Mutation queue | Children array mutation-during-iteration | `RenderEncoder.swift` | `updateLists` traversal crash |

## Execution Order

Steps are intentionally independent and incrementally reviewable. Each can be built, TSAN-tested, and merged separately. Recommended order: **1 → 2 → 3 → 4 → 5**.

Step 1 is the highest-leverage single change and should be done first. It does not require any of the other steps. Steps 2–5 can follow in order; 2 and 3 are both crash-class fixes and should come before 4 and 5.

## What Does Not Change

- Public API: `Object`, `Mesh`, `Material`, `Geometry` surfaces are unchanged.
- Single-threaded usage: identical behavior. `computeMatrices()` replaces lazy cache invalidation with an eager pass — same result, no behavioral change.
- `renderQueue = DispatchQueue.main` (default): all of these changes are no-ops in practice under the default, so no regressions for existing callers.
