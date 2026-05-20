# Satin Threading Concerns

## Goals

- **Snappy main thread UI**: input events, camera controller gestures, parameter sliders respond immediately without waiting for GPU or encoding work.
- **Non-blocking command encoding**: Metal CPU encoding cost (scene traversal, uniform uploads, render pass setup) must not block the main thread.
- **Async GPU execution**: `commandBuffer.commit()` returns immediately; GPU executes frame N while CPU works on frame N+1. This is free from Metal — we must not accidentally serialize CPU against GPU.
- **No pipeline bubbles**: CPU should be preparing the next frame while the GPU executes the current one. Ideally, scene traversal and uniform prep for frame N+1 begin before frame N's GPU work completes.
- **No crashes from concurrent access**: TSAN-clean. No torn reads, no mutating-getter races, no array mutation during iteration.

---

## 1. Parameters → Combine Chain

### What happens
`FloatParameter`, `Float4Parameter`, etc. are class-based objects with a stored value and a `PassthroughSubject` (`valuePublisher`). When a UI slider changes `param.value`, `valuePublisher.send()` fires **synchronously on the calling thread** (main thread). All Combine sinks subscribed to that publisher run immediately on main thread.

Those sinks include:
- Material uniform buffer "needs rebuild" marks
- Shader pipeline invalidation (e.g. changing blending mode triggers PSO recompile)
- `ParameterGroup.objectWillChange` → SwiftUI view refreshes

### The race
`material.update()` → `updateUniforms()` → `uniforms?.update()` runs on renderQueue during `updateScene()`. It calls `parameter.writeData()` which reads `parameter.value`. If a slider fires on main thread at the same moment, you have a concurrent read/write.

For scalar types:
- `Float` (32-bit): single store on arm64, effectively atomic. Stale-by-one-frame at worst.
- `simd_float2` (8 bytes): 64-bit aligned, atomic.
- `simd_float4` (16 bytes): 128-bit aligned Q-register store on arm64, atomic.
- `simd_float3` (12 bytes): **NOT atomic**. Three separate 32-bit stores. Can tear.
- `simd_float4x4` (64 bytes): **NOT atomic**. Multiple stores.

### Secondary concern
Sinks triggered by a parameter change can do non-trivial work on main thread (pipeline recompilation, texture swaps, buffer reallocation) while renderQueue is mid-encode. These are not just data races — they can corrupt pipeline state.

### What needs addressing
- Satin's internal Combine sinks should use `.receive(on: renderQueue)` so side effects land on renderQueue after the current draw block.
- `simd_float3` and matrix parameter writes need protection (lock or staged write) if concurrent with renderQueue reads.

---

## 2. Camera Controller

### What happens
`PerspectiveCameraController` (and others) separate input accumulation from application:
- **Input event handlers** (`leftMouseDragged`, `scrollWheel`, gesture recognizers): fire on **main thread** via NSEvent monitors or UIGestureRecognizer callbacks. Write to accumulation state: `rotationAngle: Float`, `rotationAxis: simd_float3`, `translation: simd_float3`, `zoom: Float`.
- **`update()`**: called from the renderer's `override func update()`. Reads accumulation state, applies it to `target.orientation`, `camera.position`, `camera.position.z`, etc. via `tweenRotation()`, `tweenTranslation()`, `tweenZoom()`.

### The race
If `update()` runs on renderQueue and event handlers fire on main thread, there is a concurrent read (renderQueue reading `translation`, `rotationAxis`) and write (main thread writing them). `simd_float3` writes are not atomic — they can tear.

Additionally, applying deltas calls e.g. `target.orientation *=` which fires `transformPublisher` synchronously on the calling thread. If that's renderQueue, the Combine cascade (including `PointShadow.update(light:)`) runs on renderQueue — correct. If `update()` somehow ends up on main thread, the cascade fires on main thread and races with renderQueue.

### What needs addressing
- Input event handlers must dispatch their state writes to renderQueue (compute delta on main thread, write to controller state on renderQueue).
- Or: protect accumulation vars with `os_unfair_lock`.
- `update()` must run on renderQueue so the Combine cascade from camera mutations lands there.

---

## 3. ValueCache

### What it is
`ValueCache<T>` is a simple `struct` with `var value: T?` and a `mutating func get(_ compute: () -> T) -> T`. If the value is nil, it computes and caches it. `clear()` sets `value = nil`.

Used pervasively on `Object` for every derived property:
- `_worldMatrix`, `_worldMatrixInverse`, `_normalMatrix`
- `_worldPosition`, `_worldOrientation`, `_worldScale`
- `_translationMatrix`, `_rotationMatrix`, `_scaleMatrix`
- `_localMatrix`, `_localMatrixInverse`
- `_forwardDirection`, `_upDirection`, `_rightDirection`
- `_worldForwardDirection`, `_worldUpDirection`, `_worldRightDirection`
- `_bounds`, `_worldBounds` (on some paths)

### The race — mutating getter
`ValueCache.get()` is `mutating`. A "read" of `worldMatrix` is also a write (it stores the computed result). Two threads "reading" the same object's `worldMatrix` concurrently both call `_worldMatrix.modify`. This is the TSAN race that crashed in `sortedRenderables`: the renderQueue was calling `worldMatrix.getter` (mutating) while main thread was clearing the cache via a property setter.

### The cascade — `updateWorldMatrix.didset`
Setting any transform property (`position`, `orientation`, `scale`) on `Object`:
1. Sets `updateLocalMatrix = true` → `didset` clears `_localMatrix`, `_localMatrixInverse`, sets `updateWorldMatrix = true`
2. `updateWorldMatrix.didset` clears `_worldMatrix`, `_worldMatrixInverse`, `_normalMatrix`, fires `transformPublisher`, propagates `updateWorldMatrix = true` down the entire child subtree

All of this runs synchronously on the calling thread. If a light moves on main thread and renderQueue is reading a child object's worldMatrix — the parent's cache is cleared mid-read.

### Recursive dependency
`worldMatrix.getter` computes via `parent.worldMatrix` — which calls the parent's `ValueCache.get()`. Any solution (N-slot buffering, dirty bits) must propagate the frame index or slot assignment top-down through the tree. A child cannot compute its slot-N worldMatrix before its parent's slot-N worldMatrix is available.

### What needs addressing
Options under consideration:
- **Epoch snapshot**: after all mutations in `update()`, walk tree top-down and eagerly compute world matrices into a plain stored slot per object. `draw()` reads the slot, never calls `ValueCache.get()`.
- **N-slot dirty-bit buffering**: `clear()` marks all slots dirty (atomic bitmask, no frame ID needed). `get(slot:)` checks dirty bit, recomputes if needed. Requires atomic dirty tracking and top-down traversal order.
- **Single queue**: all `ValueCache` access on one serial queue eliminates the concurrent-mutating-getter problem entirely.

---

## 4. Uniform Buffer Updates and In-Flight Buffers

### Metal in-flight buffer pattern
The GPU reads from an MTLBuffer while the CPU may be writing the next frame's data into a different region of the same buffer. Standard Metal pattern: allocate `maxInflightBuffers` (typically 2–3) slots per uniform buffer, use a semaphore (initial value = maxInflightBuffers) to prevent the CPU from overwriting a slot the GPU is still reading.

`commandBuffer.addCompletedHandler { semaphore.signal() }` releases a slot when GPU finishes with it.

### Where Satin does this
`VertexUniformBuffer`, material uniform buffers (via `UniformBuffer`/`StructBuffer`) are already slot-indexed. `object.encode(commandBuffer)` uploads the current frame's model/view/projection matrices into the current slot.

### The race on source data
`VertexUniformBuffer.update(object:camera:viewport:index:)` reads:
- `object.worldMatrix` (calls `ValueCache.get()` — mutating)
- `camera.viewMatrix`, `camera.projectionMatrix` (also ValueCache-backed on some paths)

If these are called on renderQueue while main thread is mutating the object's transform, the source data is racy even though the destination buffer slot is correctly managed.

### The missing global config
`maxInflightBuffers` and the renderQueue are implicitly per-renderer but not globally accessible to subsystems (camera controllers, parameters, Combine sinks). A global `SatinConfig` exposing these is load-bearing for any cross-subsystem threading solution.

### What needs addressing
- Source data (worldMatrix, camera matrices) must be stable when `VertexUniformBuffer.update()` runs.
- `SatinConfig` with `renderQueue` and `maxInflightBuffers` needed for subsystems to coordinate.
- Semaphore (value = `maxInflightBuffers`) on command buffer completion gives true triple-buffered CPU/GPU overlap without CPU stalls.

---

## 5. Scene Graph Iteration — updateLists / update

### What updateLists does
`updateLists(object:visible:)` recursively walks `object.children`, checks `object.visible`, classifies objects into `objectList`, `renderLists`, `lightList`, `shadowCasters`, `shadowReceivers`, `lightReceivers`. This is a full scene graph traversal.

### The races

**Children array mutation**: `object.children` is a plain Swift Array. `scene.add(child)` or `scene.remove(child)` on main thread modifies the array. If `updateLists()` is iterating `children` on another thread simultaneously, this is an Array mutation-during-iteration crash — same severity as the `sortedRenderables` crash.

**Object property reads during traversal**: `updateLists()` reads `object.visible`, `object.castShadow`, `object.receiveShadow`, `object.renderOrder`. These are plain Bool/Int stored properties. Bool and Int are atomic on arm64 — stale-by-one-frame at worst, not a crash.

**Visibility-triggered geometry**: if `object.visible = false` is set on main thread while `updateLists()` is classifying that object, the worst case is the object appears one extra frame. Not a crash.

### Dynamic scene graph changes
Any structural mutation — `add(child:)`, `remove(child:)`, loading a USD model and attaching it, spawning a particle system, removing a destroyed object — is hazardous if it happens on a different thread from traversal. These changes must be serialized with the render loop. Options:
- Require structural mutations to happen on renderQueue.
- Provide `renderer.schedule { }` to safely enqueue mutations between frames.
- Use a pending-mutations queue drained at the start of each frame before traversal.

---

## 6. Additional Concerns

### Material and texture swaps
`mesh.material = newMaterial` changes a reference. `draw()` reads `renderable.materials` and calls `material.update()`, `bindPipeline()`, `bindBuffers()` on the materials array. A reference swap mid-encode can cause encoding with a partially-initialized material or the wrong shader. Texture swaps (`material.texture = newTexture`) during encoding can bind the wrong texture to the render pass.

### Dynamic geometry / MTLBuffer rebuilds
Geometries that regenerate their vertex/index buffers on update (`TextGeometry`, `SuperShapeGeometry`, any procedural geometry) may call `MTLBuffer.contents()` and write new vertex data. If this happens on main thread while the GPU is reading from the same buffer (because a previous frame's command buffer hasn't completed), you corrupt in-flight vertex data. Metal's `storageMode` matters here: `.managed` and `.shared` buffers are writable from CPU at any time, but writing while the GPU reads is undefined behavior outside of the slot-indexed pattern.

### Shader / Pipeline compilation
`material.updateShader()` → `shader?.update()` → `getPipeline()` may trigger MTLRenderPipelineState compilation if the pipeline is dirty (blending changed, depth settings changed, vertex descriptor changed). Pipeline compilation is expensive and happens on the calling thread. If triggered from main thread (e.g., enabling a post effect changes a material's blending mode which fires a publisher), this blocks main thread. If triggered from renderQueue, it delays encoding. Pipelines should be compiled eagerly or asynchronously, not lazily during encoding.

### Shadow system
`PointShadow`, `SpotShadow`, `DirectionalShadow` maintain their own shadow cameras (`PerspectiveCamera` array, `OrthographicCamera`). `PointLight.setup()` subscribes to `transformPublisher` and calls `PointShadow.update(light:)` synchronously in the sink — this sets shadow camera `position`, `lookAt`, etc. on the calling thread. If this subscriber fires on main thread while renderQueue is inside `shadow.draw()` reading shadow camera matrices, it's a ValueCache race on the shadow camera. Same root cause as the main scene camera, just harder to spot.

Shadow texture reallocation: `light.shadow.resolution = (1024, 1024)` can trigger `MTLTexture` reallocation. If renderQueue is writing into the shadow texture (during `shadow.draw()`) while main thread reallocates it, you alias the texture pointer.

### IBL / Environment
`scene.setEnvironment(texture:)` swaps the cubemap, reflection, irradiance, and BRDF textures. `updateScene()` reads these and assigns them to materials' texture slots. A runtime environment swap (user picks a new HDR) races with `updateScene()` reading the texture references.

### PostProcessEncoders
`SsaoPostProcessEncoder`, `MotionBlurPostProcessEncoder`, `BokehDepthOfFieldPostProcessEncoder` each wrap a `RenderEncoder` with their own internal scene (fullscreen quad). Their input textures (`colorTexture`, `depthTexture`, `velocityTexture`, etc.) are set as properties just before `draw()` is called. If these are set from one thread and `draw()` is called from another, you race on the texture reference assignment.

### Object.encode(commandBuffer)
Called in `updateScene()` for non-renderable objects (lights, cameras, etc.). Uploads the object's current transform state into its uniform buffer slot. Reads `worldMatrix` (ValueCache.get() — mutating). Subject to the same ValueCache race as VertexUniformBuffer if the object's transform is being mutated concurrently.

### Bounds
`object.bounds`, `object.worldBounds` are ValueCache-backed computed properties. Used for culling, camera framing, UI display. If renderQueue ever uses bounds for culling decisions, same mutating-getter race applies.

### Combine subscription setup / teardown
`setupLightDataBuffer()` creates and stores `AnyCancellable` subscriptions. If lights are added or removed from the scene (main thread) while `setupLightDataBuffer()` is running (renderQueue), the `lightDataSubscriptions` array is mutated concurrently. The subscriptions array is not thread-safe.

---

## Summary Table

| Concern | Crash risk | Root cause |
|---|---|---|
| `object.children` mutation during traversal | **Crash** | Array mutated while iterated |
| `ValueCache.get()` concurrent access | **Crash** | Mutating getter |
| Combine cascade from transform on wrong thread | **Crash** | Synchronous sink fires on calling thread |
| Shadow camera mutation during `shadow.draw()` | **Crash** | ValueCache on shadow camera |
| Material/geometry reference swap mid-encode | **Crash / corrupt** | Non-atomic reference |
| Dynamic geometry MTLBuffer rebuild in-flight | **GPU corrupt** | CPU write during GPU read |
| Shadow texture reallocation mid-draw | **Crash** | Pointer aliased |
| `simd_float3` parameter writes | **Torn read** | 12-byte non-atomic write |
| `simd_float4x4` parameter writes | **Torn read** | 64-byte non-atomic write |
| Pipeline compilation from wrong thread | **Stall / corrupt** | Lazy compile on calling thread |
| `lightDataSubscriptions` mutation | **Crash** | Array mutated concurrently |
| `Float`, `Bool`, `Int` parameter writes | **Stale value** | Atomic on arm64, no crash |
| `simd_float4`, `simd_float2` parameter writes | **Stale value** | Atomic on arm64 (aligned) |
| `object.visible`, `renderOrder` changes | **Stale value** | Atomic on arm64, no crash |
