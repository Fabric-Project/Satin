# Satin Threading Plan Refresh

`Docs/ThreadingPlan.md` is historical context for an older branch model. This document is the current source of truth for threading work in this branch and should be kept aligned with the code as implementation progresses.

---

## Summary

The threading problem in Satin is not fundamentally about Metal command buffer lifetime or in-flight uniform slots. Those systems already exist and mostly work. The real problem is that Satin's authoring objects are still the render data source, and many "reads" on those objects are lazy mutating computations. As soon as render work and authoring work happen on different threads, those lazy getters and synchronous side effects become race surfaces.

The design direction for this branch is:

- make render-time reads come from a stable per-frame snapshot,
- move render-critical side effects onto the render owner,
- keep the public scene-authoring API intact where possible,
- preserve synchronous single-threaded behavior for `ViewRenderer`,
- and make the threaded path correct for `SpatialRenderer` and any future threaded renderer.

---

## Current Execution Model

### Actual thread boundary in this branch

The earlier threading documents assume a shared `renderQueue` abstraction. That is no longer accurate in this branch.

- `ViewRenderer` is synchronous on the caller thread. `draw(metalLayer:drawable:)` calls `update()`, `draw(texture:commandBuffer:)`, and `postDraw(...)` inline.
- `MetalView` drives `ViewRenderer` from the main-thread display loop.
- `SpatialRenderer` owns a dedicated render thread and runs its own update/draw loop there.

That means Satin currently has two execution modes:

1. **Synchronous mode**
   Used by `ViewRenderer`.
   Authoring and rendering typically both happen on main.

2. **Threaded mode**
   Used by `SpatialRenderer`.
   Render traversal, CPU encoding, and render-side mutation happen on a dedicated render thread while app/input code may still run elsewhere.

### Consequence

The source-of-truth threading contract cannot be "everything happens on `renderQueue`" because there is no such universal queue in this branch. The contract must instead be:

- synchronous renderers execute mutations immediately because they are already on the render owner,
- threaded renderers must serialize structural mutations and render-side state updates onto the render owner,
- and render-time reads must not depend on lazy mutable caches shared with authoring code.

---

## First-Principles Findings

### 1. Lazy derived state is the primary crash surface

`Object` still exposes many derived values through `ValueCache`-backed getters:

- `worldMatrix`
- `worldMatrixInverse`
- `normalMatrix`
- `worldPosition`
- `worldOrientation`
- `worldScale`
- direction vectors
- local transform matrices

`ValueCache.get()` is mutating. Two threads "reading" the same property are actually racing to write the cached value.

This is the highest-leverage threading fix because these values are read everywhere:

- vertex uniform upload,
- shadow rendering,
- lighting data generation,
- projector camera updates,
- instancing,
- and any world-space scene traversal logic.

### 2. Render transforms must be computed after `object.update()`

The older plan placed eager transform computation at the top of the frame before traversal. That is wrong for the current renderer implementation.

`RenderEncoder.updateLists()` currently calls `object.update()` during traversal. If an object mutates `position`, `orientation`, `scale`, or parent/child state in `update()`, any transforms computed before that call are already stale.

So the correct ordering is:

1. run object updates,
2. compute render transforms from final frame-authoring state,
3. derive render-only camera/light/shadow state from those transforms,
4. then encode.

### 3. The parameter race is in the upload data path, not just dirty flags

The dangerous read is not only "material needs rebuild". The dangerous read is the raw parameter value copied during uniform upload.

`GenericParameter.writeData()` reads `value` directly and `ParameterGroup.data` materializes the backing bytes on demand. If UI writes happen at the same time:

- `simd_float3` can tear,
- matrix types can tear,
- and `ParameterGroup`'s internal data/cache bookkeeping can race with buffer rebuild/materialization.

That means the fix must cover:

- `GenericParameter.value`,
- `ParameterGroup` storage and cached byte generation,
- not just `Material.uniformsNeedsUpdate`.

### 4. "Combine is the problem" is too broad

The earlier proposal correctly identified synchronous Combine delivery, but in this branch not every sink is doing expensive work.

Material parameter sinks mostly just set `uniformsNeedsUpdate`. The more important wrong-thread side effects are:

- light transform subscribers updating shadow state immediately,
- property setters that mutate shadow or projector state immediately,
- live shadow texture allocation from property changes,
- and `IBLScene` publishing generated environment textures directly from a background queue.

### 5. Structural scene mutation still needs an execution owner

`Object.children` is still a plain Swift array. Traversal and mutation cannot happen concurrently.

The renderer needs a mutation staging point so threaded renderers can drain pending `add/remove/attach/removeAll` work at a safe point each frame.

---

## Scope of This Refresh

This refreshed plan covers:

- render-critical transform stability,
- parameter upload synchronization,
- render-owned staging for light/shadow/projector side effects,
- environment swap staging,
- and structural mutation serialization.

It does **not** attempt in this branch to introduce:

- a fully separate immutable scene snapshot type,
- pervasive Swift actors across the rendering stack,
- or a full redesign of the public scene graph API.

The goal is to make the existing architecture thread-safe enough for the current threaded renderer model without destabilizing the public API.

---

## Plan by Phase

## Phase 1 — Stabilize Render-Critical Derived State

### Goal

Make render-time reads pure stored-value reads for the duration of a frame, rather than lazy mutating cache accesses into authoring objects.

### Design

Add a render snapshot path to `Object` and `Camera`:

- store render-local and render-world transforms separately from the legacy lazy getters,
- compute them once per object per frame after `object.update()`,
- and make render upload/encoding read from those render snapshot fields.

This is intentionally narrower than "delete `ValueCache.swift` entirely". Some non-render uses can stay lazy for now if they are thread-confined.

### Files

- `Sources/Satin/Core/Object.swift`
- `Sources/Satin/Core/Camera.swift`
- `Sources/Satin/Buffers/VertexUniformBuffer.swift`
- `Sources/Satin/Core/RenderEncoder.swift`
- `Sources/Satin/Protocols/Shadow.swift`
- `Sources/Satin/Objects/InstancedMesh.swift`

### Status

**Implemented.**

### Implemented behavior

- `Object` now maintains render snapshot fields for:
  - translation/rotation/scale matrices,
  - local/world matrices and inverses,
  - normal matrix,
  - world position/orientation/scale,
  - local/world direction vectors.
- `Object.computeRenderTransforms(parentMatrix:)` computes those values eagerly.
- `Camera` now maintains render snapshot fields for:
  - render view matrix,
  - render projection matrix,
  - render view-projection matrix,
  - render view direction.
- `RenderEncoder` now:
  - drains pending mutations,
  - runs `object.update()`,
  - computes render transforms,
  - calls `prepareForRender()`,
  - and then encodes.
- `VertexUniformBuffer` reads render snapshot fields instead of lazy world/camera properties.
- Shadow matrix access now uses render snapshot camera state.
- `InstancedMesh` refreshes instance matrices during `prepareForRender()`, after the world snapshot is available.

### Important correction vs. old plan

The snapshot pass is not a single `scene.computeMatrices()` call before traversal. It happens after object update, during render-owned traversal, so the frame sees final authoring state.

### Remaining caveats

This phase does **not** remove every lazy or mutable cache in the codebase. Examples that still exist and may need later treatment:

- `Camera.viewDirection` legacy getter,
- `Geometry.vertexDescriptor`,
- `Geometry.bounds` / BVH rebuild paths,
- object/world bounds getters,
- and other non-render lazy state.

That is acceptable for now because this phase is about render-critical correctness first.

---

## Phase 2 — Synchronize Parameter Upload State

### Goal

Prevent torn reads and internal cache races while materials generate uniform bytes for the current frame.

### Design

Protect the actual shared parameter data path:

- lock parameter get/set at `GenericParameter`,
- lock `ParameterGroup` mutation and data materialization state,
- keep `Material.uniformsNeedsUpdate` as a coarse rebuild marker,
- but do not rely on it for thread safety.

### Files

- `Sources/Satin/Parameters/GenericParameter.swift`
- `Sources/Satin/Parameters/ParameterGroup.swift`

### Status

**Implemented.**

### Implemented behavior

- `GenericParameter` now has a locked backing store for `value`.
- `ParameterGroup` now guards:
  - `params`,
  - `paramsMap`,
  - `paramSubscriptions`,
  - `_updateData`,
  - `_reallocateData`,
  - and backing byte materialization in `data`.

### Why this was necessary

Locking only `GenericParameter.value` would still leave `ParameterGroup` racing its own internal bookkeeping and byte buffer generation during material uniform uploads.

---

## Phase 3 — Move Wrong-Thread Render Side Effects onto the Render Owner

### Goal

Stop mutating render-critical light/shadow/projector state directly from arbitrary authoring threads.

### Design

Change render-side object reactions from "mutate immediately" to:

1. mark render-side state dirty when authoring state changes,
2. recompute shadow/projector/render-only state during render-owned preparation,
3. encode from those prepared values.

### Files

- `Sources/Satin/Protocols/Light.swift`
- `Sources/Satin/Lights/PointLight.swift`
- `Sources/Satin/Lights/SpotLight.swift`
- `Sources/Satin/Lights/DirectionalLight.swift`
- `Sources/Satin/Shadows/PointShadow.swift`
- `Sources/Satin/Shadows/SpotShadow.swift`
- `Sources/Satin/Shadows/DirectionalShadow.swift`
- `Sources/Satin/Core/RenderEncoder.swift`

### Status

**Partially implemented.**

### Implemented behavior

- `Light` now has render-preparation hooks and dirty flags.
- Light subclasses no longer rely on transform subscribers to push shadow updates immediately.
- Shadow camera updates are now driven from render snapshot state.
- `RenderEncoder` no longer uses light publisher subscriptions to decide when to rebuild light data; it refreshes the light data buffer each frame from current prepared light state.

### What remains

- Camera controllers still mutate camera/target state directly in event handlers.
- Some light/property setters still publish immediately for higher-level notification, which is acceptable, but the remaining direct render-side consequences should continue to be audited.
- Environment texture publication is not yet staged; see Phase 4.

### Why this phase is only partial

The most visible remaining wrong-thread side effect is camera controller input. Until that is converted to an accumulate-only model, threaded rendering still has an input-path race surface.

---

## Phase 4 — Stage Environment Swaps

### Goal

Prevent background texture generation from swapping live environment texture references directly into scene objects while rendering reads them.

### Design

`IBLScene` can continue generating cubemap / irradiance / reflection / BRDF data on a background queue, but the handoff into live scene-visible texture references should be staged onto the render owner at the top of a frame.

### Files

- `Sources/Satin/Objects/IBLScene.swift`
- potentially `Sources/Satin/Core/RenderEncoder.swift`

### Status

**Partially implemented.**

### Implemented behavior

- `IBLScene` no longer publishes generated textures directly onto live scene state from the background queue.
- Environment generation now builds textures off-thread, waits for command-buffer completion, stages the completed results in a pending slot, and adopts them from `prepareForRender()`.
- Direct cubemap replacement now follows the same staged adoption path.

### What remains

- The staging point is local to `IBLScene`; if future environment-producing objects are added, they should follow the same render-owned adoption pattern.
- A full end-to-end async integration regression that exercises the background queue and command-buffer completion path still needs to be added.

### Reason this is next

This is still one of the clearest remaining thread-safety holes in the branch because the current code publishes new environment textures from a background queue directly onto live scene state.

---

## Phase 5 — Camera Controllers Become Accumulate-Only

### Goal

Make camera controller event handlers author input state only. All camera/target mutation must happen from the render owner in `update()`.

### Files

- `Sources/Satin/CameraControllers/PerspectiveCameraController.swift`
- `Sources/Satin/CameraControllers/OrbitPerspectiveCameraController.swift`
- `Sources/Satin/CameraControllers/OrthographicCameraController.swift`

### Status

**Partially implemented.**

### Implemented behavior

- `PerspectiveCameraController`, `OrbitPerspectiveCameraController`, and `OrthographicCameraController` now accumulate the latest interaction deltas in event handlers instead of mutating camera/target state immediately.
- `update()` is now the mutation point that applies the accumulated deltas, emits change notifications, and preserves the existing tween/inertia path.

### What remains

- Higher-level renderer ownership is still informal; examples already call `cameraController.update()` from the frame loop, but the renderer-level contract is not yet explicit.
- This phase still needs a focused controller regression that proves no camera/target mutation occurs until `update()` runs.

### Why it still matters after Phase 1

The render snapshot path protects encoding from many lazy getter races, but direct cross-thread camera mutation is still conceptually wrong and can still race with authoring/render preparation in threaded mode.

---

## Phase 6 — Promote Structural Mutation Scheduling to the Render Owner Contract

### Goal

Give scene graph mutation a consistent execution model across synchronous and threaded renderers.

### Current state

`Renderer` now exposes the public mutation queue contract via `schedule(_:)`.

- immediate-mode renderers execute scheduled mutations inline,
- threaded renderers queue scheduled mutations and drain them at the top of the frame update,
- `RenderEncoder` still keeps its traversal-local queue for render-graph staging.

### Status

**Partially implemented.**

### Implemented behavior

- `Renderer.schedule(_:)` is now the renderer-owned contract.
- `ViewRenderer` drains renderer-scheduled mutations on the synchronous frame path.
- `SpatialRenderer` queues renderer-scheduled mutations and drains them before `update()` on the dedicated render thread.
- Async AR and vision example callbacks that mutate scene structure or render-owned object state have started migrating onto the renderer-owned scheduling path.
- `RenderEncoder.schedule(_:)` is now back to an internal primitive for render-graph-local staging.

### What remains

- Higher-level examples and app code still contain direct off-frame object mutation sites; migration has started but is not complete.
- The renderer-level contract still is not enforced by type system or diagnostics; correctness depends on call-site discipline.

### Files likely involved

- `Sources/Satin/Views/Renderer.swift`
- `Sources/Satin/Views/ViewRenderer.swift`
- `Sources/Satin/Views/SpatialRenderer.swift`
- `Sources/Satin/Core/RenderEncoder.swift`

---

## Status Table

| Phase | Title | Status |
|---|---|---|
| 1 | Stabilize render-critical derived state | Implemented |
| 2 | Synchronize parameter upload state | Implemented |
| 3 | Move wrong-thread render side effects onto render owner | Partially implemented |
| 4 | Stage environment swaps | Partially implemented |
| 5 | Camera controllers become accumulate-only | Partially implemented |
| 6 | Promote structural mutation scheduling contract | Partially implemented |

---

## Code References for Implemented Work

Primary implementation files:

- `Sources/Satin/Core/Object.swift`
- `Sources/Satin/Core/Camera.swift`
- `Sources/Satin/Core/RenderEncoder.swift`
- `Sources/Satin/Buffers/VertexUniformBuffer.swift`
- `Sources/Satin/Parameters/GenericParameter.swift`
- `Sources/Satin/Parameters/ParameterGroup.swift`
- `Sources/Satin/Protocols/Light.swift`
- `Sources/Satin/Lights/PointLight.swift`
- `Sources/Satin/Lights/SpotLight.swift`
- `Sources/Satin/Lights/DirectionalLight.swift`
- `Sources/Satin/Shadows/PointShadow.swift`
- `Sources/Satin/Shadows/SpotShadow.swift`
- `Sources/Satin/Shadows/DirectionalShadow.swift`
- `Sources/Satin/Objects/InstancedMesh.swift`

Regression coverage:

- `Tests/SatinTests/ThreadingPlanTests.swift`

---

## Test Strategy

### Must stay green

- `swift build`
- `swift test --filter 'ObjectTests|ParameterTests|MutexTests|ThreadingPlanTests'`

### Implemented tests

`ThreadingPlanTests` currently covers:

- render snapshot computation after `object.update()`,
- scheduled mutation drain before traversal,
- camera render-state refresh consistency.

### Additional tests still needed

1. A parameter concurrency regression that exercises:
   - value writes,
   - parameter add/remove,
   - and `ParameterGroup.data` materialization under load.

2. A visual or integration test covering:
   - light/shadow correctness under the new render-owned shadow preparation path.

3. An environment swap regression covering:
   - staged adoption of generated textures once Phase 4 is implemented.

4. A camera controller regression covering:
   - threaded input accumulation and render-thread application once Phase 5 is implemented.

---

## Defaults and Assumptions

- We are not introducing a fully separate immutable render scene type in this branch.
- The render snapshot fields are internal implementation detail, not a new public API.
- Single-threaded `ViewRenderer` behavior should remain effectively unchanged for callers.
- Threaded correctness is primarily judged against `SpatialRenderer` and future threaded renderers.
- `ValueCache.swift` may remain in the repo until every remaining non-render use is either migrated or intentionally left thread-confined.

---

## Historical Note

- `Docs/ThreadingPlan.md` reflects earlier assumptions about a `renderQueue`-based architecture and should be treated as historical.
- `Docs/ThreadingPlanRefresh.md` is the current source of truth for the refreshed plan and implementation status.
