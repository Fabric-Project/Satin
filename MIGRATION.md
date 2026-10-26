# Migrating to render packets

Satin now records every draw into plain-data render packets and encodes them per pass, instead of each object encoding itself into the live render encoder. Rendering the same scene more than once a frame (an Iterator, a render-to-texture) uses one **submission** with a **record** per iteration, in place of repeated encoding. This guide lists every public change and what to write instead.

## Encoding happens on the thread that draws

Satin encodes into the command buffer you pass, at the point you call `draw`, on whichever thread calls it. There is no encoding queue: `renderQueue` on `RenderEncoder` and `PostProcessEncoder` is gone, as are `GPUCommandRecording`, `RecordedGPUCommands`, `RecordedGPUWork`, `RecordedComputeWork`, `ComputeCommandEncoder`, `ComputeEncodingContext` and `holdUntilCompleted(_:)`. To keep rendering off the main thread, draw the whole frame on another thread; raw Metal and MPS work encoded into the same command buffer keeps its order with Satin's passes.

- **Drawing off the main thread:** give the renderer a serial queue when you make it, `super.init(context: context, renderQueue: DispatchQueue(label: "Render", qos: .userInteractive))`. Frames, resize, appearance and cleanup then run on that queue; setup and events stay on main. Anything else a frame reads must reach the renderer through `renderQueue.async { … }`, never by writing it from main.
- **Parameters and UI:** with a render queue, give the renderer's parameter groups the same queue (`group.renderQueue = renderQueue`) before frames run. UI writes with `parameter.submit(value)` instead of assigning `value`, shows `mainValue`, and subscribes to `mainValuePublisher` instead of `valuePublisher.receive(on: .main)`. Engine code keeps reading and writing `value` on the owner. Without a queue, the new API behaves exactly like the old.
- **Camera controllers:** call `update(frame:)` every frame, as before; it now also applies the mouse and gesture input queued since the last frame. Subscribers to the controller's publishers are called from `update(frame:)`, on the renderer's queue when it has one.
- **Custom GPU work:** encode it into the command buffer, before or after the Satin draw it belongs with.
- **Compute:** `update(commandBuffer, iterations:)` and `update(computeEncoder, iterations:)`; overrides of `bind`, `bindUniforms`, `dispatchThreads` and `dispatchThreadgroups`, and the `preCompute` / `preUpdate` / `preReset` hooks, take an `MTLComputeCommandEncoder`. The generators' encoder-taking overloads take the `MTLComputeCommandEncoder` again (`encode(computeEncoder:…)`, and `encode(commandEncoder:…)` on `DiffuseIBLGenerator`).
- **External resource lifetime** (a `CVMetalTexture`, a pooled `CVPixelBuffer` or `IOSurface`): keep the owner alive until the GPU is done with `commandBuffer.addCompletedHandler { _ in withExtendedLifetime(owner) {} }`.
- **Post-processing:** `PostProcessEncoder.draw(…)` throws, as `RenderEncoder.draw(…)` does, and stays `open`. Overrides are `throws` and call `try super.draw(…)`.

## Renderer subclasses

Drawing now takes the frame being drawn, so your renderer needs its `frameTime` current. **An `update(frame:)` override must call `super` first**: it stores the frame as `frameTime`, and without it every draw sees frame 0 and motion never advances.

```swift
override func update(frame: FrameTime) throws {
    try super.update(frame: frame)
    // your per-frame work
}

override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
    try renderEncoder.draw(
        frame: frameTime,
        renderPassDescriptor: renderPassDescriptor,
        commandBuffer: commandBuffer,
        scene: scene,
        camera: camera
    )
}
```

## Drawing

| Before | Now |
|---|---|
| `RenderEncoder.draw(renderPassDescriptor:commandBuffer:scene:…)` | `try draw(frame:renderPassDescriptor:commandBuffer:scene:…)`. Every overload, `renderTarget:` ones included, takes the frame and throws. |
| `PostProcessEncoder.draw(renderPassDescriptor:commandBuffer:…)` and its subclasses (SSAO, SSGI, motion blur, bokeh, AR post) | `try draw(frame:renderPassDescriptor:commandBuffer:…)`. All overloads throw. |
| `ARMatteEncoder.encode(commandBuffer:)` | `try encode(frame:commandBuffer:)` |
| `ARBackgroundDepthEncoder` draws | `try draw(frame:…)` like `PostProcessEncoder`; inner depth errors propagate. |

**Errors.** Draws, records, seals and encodes throw `SubmissionError`:
- `.destinationMismatch(attachment:expected:found:)`: the descriptor supplies an attachment whose pixel format isn't the encoder's.
- `.alreadyDrawn`: a builder recorded into or sealed after it was sealed, or a sealed submission encoded twice or after `abandon`.
- `.notRecorded`: a builder sealed before its operation was recorded.

A rejected draw does no work and leaves your descriptor as it was.

**Settings are frozen per draw.** `clearColor`, the load/store actions, `sortObjects`, `renderingMode` and `activeOutputs` are read when a submission is made. Changing them mid-draw (from a callback, say) applies to later draws only.

## Rendering a scene more than once a frame

Removed: `prepareForRepeatedEncoding(count:)`, `selectRepeatedEncodingSlot/State`, `selectRecentSlot`, `captureRepeatedEncoding…`, `captureLatestSlot`, `setMinimumEncodesPerFrame(_:)` / `minimumEncodesPerFrame`, `loadRepeatedEncodingSourceStates`, `RenderEncoder.scheduleCurrentPassEncoding(…)` / `encodeCurrentPass(…)`, `maxSubPassesPerFrame`.

Now: make one submission builder, record the scene once per iteration, then record the main scene, seal and encode once. Each record snapshots transforms, material uniforms, instances and joint palettes as they are at that moment, so changing the scene between records doesn't change what was recorded.

```swift
let builder = renderEncoder.makeSubmissionBuilder(frame: frameTime, cameras: [camera], viewports: [viewport])
for iteration in 0 ..< count {
    // Change the scene, and call update() on the objects you changed.
    applyIteration(iteration)
    // Only for objects that encode GPU work, such as a TessellationMesh.
    tessellatedMesh.encode(in: builder.encodingContext(commandBuffer: commandBuffer))
    try builder.record(scene: scene)
}
try builder.record(scene: mainScene, renderPassDescriptor: renderPassDescriptor, preparationCommandBuffer: commandBuffer)
try builder.seal().encode(into: commandBuffer)
```

`RenderSubmission`, `makeSubmission(frame:commandBuffer:cameras:viewports:)` and `draw(submission:…)` are gone; the builder above replaces them. `record(scene:)` neither updates nor encodes: do both first, as above. `record(scene:renderPassDescriptor:)` updates, encodes (into `preparationCommandBuffer`, when given) and records its own scene first, then the earlier records in order, per render layer. Records contribute colour draws, lights and shadow casters to this target. Each occurrence keeps its captured state, and all target lights illuminate the combined root and recorded scene. With sorting enabled, renderOrder applies across both root and recorded objects within each layer and route; equal orders retain root-first, then recording order. A recorded draw holds the Metal resources it binds and nothing else, so no scene object needs to outlive it: `retainUntilCompleted(_:)` is gone.

`UniformBuffer(device:parameters:options:maxBuffersInFlight:encodesPerFrame:)` loses `encodesPerFrame`, and `encodesPerFrame` / `totalSlotCount` are gone: a uniform buffer has one slot per frame in flight.

**Motion** (velocity outputs) is tracked per occurrence: the first record of an object this frame pairs with its first record last frame, and so on. If you reorder or resize what you record so that ordinals no longer match, call `resetMotion()` on the affected renderables (or `InstancedMesh`, `JointPalette`): their next draws start still. Call `camera.resetMotion()` after a camera cut; resetting objects does not reset camera velocity. Camera history advances only on its first use in a frame, including after a cut reset.

**External buffer contents.** Recording retains bound buffers but does not freeze their bytes. Leave caller-owned buffer contents unchanged until the reading command buffer completes, or use versioned storage. The draw contexts' `setVertexBuffer` and `setFragmentBuffer` accept `copyOnRecordLength:` to copy that many CPU-readable bytes from the supplied offset into the frame arena. The default is `nil`, no copy: Satin never chooses copying by size. Private GPU-only buffers require versioning or ordered GPU preparation rather than a CPU copy; managed buffers must have current CPU contents before copying.

Light, shadow and projector pass data now use arena snapshots instead of advancing `StructBuffer` rings. Several draws within one command buffer cannot overwrite an earlier draw's pass data.

## Renderables and meshes

| Removed | Instead |
|---|---|
| `isDrawable(renderContext:shadow:)` | A draw that records no draw call doesn't draw. |
| `update(renderContext:camera:viewport:index:)` | Nothing: per-view uniforms are written by the encoder into the frame. CPU work goes in `update()`. |
| `vertexUniforms`, `vertexUniforms(for:)`, `getVertexUniformBuffer(renderContext:)`, `setupVertexUniforms()`, `VertexUniformBuffer` | Nothing: vertex uniforms live in the frame's arena. A custom draw reads them from `RenderableDrawContext.vertexUniforms`. |
| `preDraw` | `material.set(_:index:)` for a buffer or texture, or override `draw(in: RenderableDrawContext)` and record bindings and draws on the context (see "Typed draw commands"). |
| `InstancedMesh.instanceMatrixBuffer`, `InstanceMatrixUniformBuffer` | `setInstanceMatrices(_:)` / `setMatrixAt(index:matrix:)` as before; instance data is snapshotted per record. |

## Materials and shaders

| Removed | Instead |
|---|---|
| `onBind` | `set(_:index:)` (buffers and textures, vertex or fragment), or a `draw(in: MaterialDrawContext)` override that calls `super` then records its bindings on the context. |
| `uniforms`, `setupUniforms()`, `updateUniforms()` | Uniforms are snapshotted per draw. `uniformsBinding(in:)` gives a custom draw the current slice. |
| `vertexUniformBuffers`, `vertexStructBuffers`, `vertexBuffers`, `vertexTextures`, `fragmentUniformBuffers`, `fragmentStructBuffers`, `fragmentBuffers`, `fragmentTextures` | Set bindings with `set(_:index:)`; the material records them on each draw. |
| `setMinimumEncodesPerFrame(_:)` | Nothing (see "Rendering a scene more than once a frame"). |
| `Shader.pipelines`, `shadowPipelines`, `configurations` | `Shader.pipeline(for:shadow:)`. |


`MaterialDelegate` and `Material.delegate` are removed: subscribe to `Material.updatedPublisher`, which sends the same event.

## Geometry

- `encode(_ commandBuffer:)` → `encode(in: EncodingContext)` on `Object`, `Mesh`, `Submesh`, `Geometry` and `Material`. The context carries the command buffer, the frame, the views, and `allocate(length:)` for per-encode GPU output. Work that only touches the CPU belongs in `update()`.
- `draw(in: GeometryDrawContext)` is the one place a geometry customises its draw: every draw of it comes through there, a submesh's included. Override it to add bindings or replace the draw call, and call `super` for the defaults. A replaced draw call draws `context.elements`' indices when they're given (a submesh's range).
- `recordBindings(in:)` / `recordDrawCall(in:)` are no longer overridable, and `Submesh.recordDrawCall` / `Submesh.draw(in:instanceCount:layout:)` are gone: override `Geometry.draw(in:)`.
- **Geometry bindings now follow the material's.** A slot both bind takes the geometry's. Satin's own slots don't overlap; check custom material bindings at vertex attribute slots.
- `JointPalette(device:jointCount:maxBuffersInFlight:encodesPerFrame:)` → `JointPalette(jointCount:)`. `buffer`, `offset`, `index` and `joints` are gone; `matrices` holds the pose. `update(matrices:)` and `reset(matrices:)` are unchanged at the call site.
- Tessellation: `TessellationProcessor.factorsBuffer` is gone. A `Tessellator` writes to `factorsDestination` (set by `TessellationMesh` per encode). Turning `tessellate` off freezes the factors into a buffer of their own.


`Mesh.geometry` is a `Geometry`, no longer `Geometry!`: every mesh has one, a decoded mesh an empty geometry of its context. Drop `?` and `!` where you read it. `BindableBuffer.buffer` is a `let` set by `init(buffer:)`, no longer `MTLBuffer!`. `Renderable.opaque` no longer traps for a renderable without a material of its own (a mesh whose submeshes carry the materials): it counts as opaque.

## Transforms, cameras and lights: revisions instead of publishers

Transform changes no longer push through the hierarchy. A change bumps the object's `localRevision`; world-derived values (world matrices, world bounds, camera views, light data, instance uniforms) check `worldRevision` when read, and `worldRevision` itself validates against the ancestors when read. Descendant changes still mark ancestor bounds dirty, so a parent's `bounds` / `worldBounds` read sees a child's change at once. `update()` and `onUpdate` still run every frame.

| Removed | Instead |
|---|---|
| `Object.transformPublisher`, `positionPublisher`, `scalePublisher`, `orientationPublisher`, `boundsPublisher`, `localBoundsPublisher`, `worldBoundsPublisher`, `childAddedPublisher`, `childRemovedPublisher`, `idPublisher`, `labelPublisher`, `visiblePublisher` | Compare `worldRevision` (or `localRevision`) with the one you last saw, when you need the value. |
| `Renderable`'s `doubleSided`/`renderOrder`/`renderLayer`/`receiveShadow`/`castShadow`/`cullMode`/`triangleFillMode` publishers | Read the properties. |
| `Object.updateLocalMatrix`, `Camera.updateViewMatrix`, `Camera.updateProjectionMatrix` | Nothing: caches validate themselves. |
| `@Published` on `Camera.near`/`far`, `PerspectiveCamera.fov`/`aspect` (`$near` …) | Plain properties; `projectionInputsRevision` advances when one changes. |
| `Light.publisher` | `lightRevision` (colour, intensity, radius, angles, projection) and `worldRevision`. |

**Assigned camera matrices.** A `viewMatrix` you assign is kept exactly until the camera moves after it; a `projectionMatrix` you assign (or `setProjectionMatrixFromARKit`) until a projection input (`near`, `far`, `fov`, `aspect`, lens shift, orthographic extents) changes after it. There is no flag to set. Note: the ARKit projection is now actually kept; before, the `fov` / `aspect` it set made the next read rebuild a plain perspective matrix.

Custom camera subclasses override `computeProjectionMatrix()` and call `projectionInputsDidChange()` when one of their own projection inputs changes. This invalidates both projection caches and replaces any previously assigned projection on the next read.

**`localMatrix =`** is one change now, not three. Equal-value assignments change nothing.

## Loading models

- **Meshes loaded from one asset share materials** when their source materials are identical in every property (names aside), and every image loads once per set of loading options. Editing `mesh.material` edits every mesh sharing it; to change one mesh, assign it `mesh.material?.clone()` first.
- **Culling follows the asset:** single-sided meshes load with `cullMode = .back`, double-sided ones with `.none` (it was `.none` for everything). Meshes mirrored by their loaded transform get their winding flipped so their outside faces survive culling.
- Shared materials receive one environment: if you place meshes from one model under different IBL environments, clone their materials.

### Merging static meshes

`loadAsset` and `loadAnimatedAsset` take `mergeStaticMeshes` (default `false`). When set, meshes that draw exactly alike join into one: the same material, cull mode, vertex layout and world transform, opaque, unskinned, unanimated (no animated transform on the mesh or above it), with one triangle submesh and no children. The merged mesh takes the first member's name and place; the other members are removed, so code that looks meshes up by name, or moves one on its own, must load without merging. Vertices are copied as they are, never transformed, so the model renders the same pixels with fewer draws. Ignored with `instanced`. `mergeCells` (default 4) splits merging by a grid of that many cells along the model's longest side, by the centre of each mesh's bounds, which keeps merged meshes mostly local (a mesh can still extend past its cell); 1 merges across the whole model.

## Typed draw commands

`addCustomCommand` and `addCustomDraw` are gone: a recorded draw is plain data, so nothing runs on the live encoder and nothing reaches back into the object that recorded it. Record the same work as typed commands on the draw contexts:

| Was a custom command for | Now |
|---|---|
| Vertex / fragment buffers | `setVertexBuffer(_:offset:index:)`, `setFragmentBuffer(_:offset:index:)` |
| Object / mesh stage buffers | `setObjectBuffer(_:offset:index:)`, `setMeshBuffer(_:offset:index:)` |
| Tessellation factors | `setTessellationFactorBuffer(_:offset:instanceStride:)` |
| Patch draws (geometry) | `drawPatches(controlPointCount:patchCount:instanceCount:)`, `drawIndexedPatches(controlPointCount:patchCount:controlPointIndexBuffer:instanceCount:)` |
| Mesh shader draws (renderable or geometry) | `drawMeshThreadgroups(_:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:)` |

Binding the render event's `vertexUniforms` to any stage follows the view being encoded, as before. `MeshShaderRenderer` in the example app shows a mesh-shader renderable recorded this way.

`RenderEncoderState` no longer restores pass state between draws: with no custom commands, nothing a draw records can disturb it. `invalidate()` and the `begin(renderTargetSize:)` / `begin(renderPassDescriptor:)` variants are gone; `begin(renderEncoder:)` starts a pass, `end()` finishes it.

## Shadows

`Shadow.draw(context:commandBuffer:renderables:)` is no longer public: shadows render inside `RenderEncoder`'s draw.

`needsUpdate` is cleared when a shadow's passes are recorded, not when they finish on the GPU. Use `renderEncoder.abandon(sealed)` to release an unencoded submission explicitly; dropping an unencoded builder or sealed submission also invalidates its pending shadow versions. Invalidation is carried by the recording itself, without a bounded history. A map prepared but not yet encoded is not reused as a clean cache by another recording. An encoded producer must be submitted before work that samples its cached map, on the same ordered command queue. A submitted command buffer that fails is a device error, not something shadows recover from.

## Culling

Every pass now skips a renderable whose world bounds are wholly outside its views: each colour view (a multiview pass keeps it if any view may see it), each spot or directional shadow camera, and each point-light face. Only the four side planes of a view are tested, never near or far, and empty or non-finite bounds are never culled, so a renderable whose bounds cover what it draws renders exactly as before.

A renderable that draws outside its geometry's bounds must opt out with `frustumCulled = false`: vertex displacement (tessellation with a displacement map included), billboards, shaders that place vertices in clip space themselves, or custom renderables whose bounds don't describe what they draw.

## Point-light shadows

A point light records each caster once for all six faces and encodes that recording in each face it reaches, as that face's view: binding the render event's `vertexUniforms` (from `RenderableDrawContext`) through `setVertexBuffer` / `setFragmentBuffer` follows the face being drawn. In a context that amplifies vertices, casters are recorded per face, since their views are laid out for the shaders.

## Post-processing

`PostProcessEncoder` no longer owns a `RenderEncoder`: its `renderer` property is gone, along with the initialiser's `sortObjects`, `clearDepth`, `depthLoadAction`, `depthStoreAction`, `clearStencil`, `stencilLoadAction` and `stencilStoreAction`. Its quad always drew through `postProcessRenderer`, so those settings never reached its pass. Set clear colour, colour load and store actions and `frameBufferOnly` on `postProcessRenderer` instead. `PostProcessRenderEncoder.colorTexture` is now public: the texture a pass draws into when its descriptor supplies none (`ARBackgroundEncoder.colorTexture` returns it).


## Recording before a command buffer exists

`RenderEncoder.makeSubmissionBuilder(frame:cameras:viewports:)` freezes the views and renderer settings. Record the complete render operation on the producer, then seal it:

```swift
let builder = renderer.makeSubmissionBuilder(frame: frame, cameras: cameras, viewports: viewports)
try builder.record(scene: scene, renderPassDescriptor: descriptor)
let sealed = try builder.seal()
// Other scenes/frames can now update and record before this operation encodes.
try sealed.encode(into: commandBuffer)
```

`record` captures packets, pass bindings, private pass descriptors, shadow passes and deferred resolve inputs. `seal()` only transfers that work; it does not sample the scene again. A builder records one complete operation and seals once. A sealed submission encodes once; repeated use throws `SubmissionError.alreadyDrawn`. Sealing before recording throws `.notRecorded`. Abandoning recorded work releases its storage; encoded storage and arena contents remain leased through command-buffer completion. Keeping a consumed builder does not prolong those leases.

The one-line `draw(...)` overloads make a builder, record, seal and encode it back to back. `PostProcessRenderEncoder.seal(frame:renderPassDescriptor:mesh:cameras:viewports:viewMappings:)` records and seals a post-processing quad in one call.

CPU `update()` / `onUpdate` still run while recording. GPU preparation through custom `encode(in:)` hooks is encoded into `preparationCommandBuffer` when you pass one to `record`; without one, encode that preparation yourself before the command buffer the sealed scene is encoded into. The one-line `draw(...)` overloads pass the command buffer they draw into.

Holding a Metal resource keeps its identity alive, not its contents immutable. External buffers/textures must remain unchanged until completion, or use versioned resources. Draw-context buffer setters accept an explicit `copyOnRecordLength:` for CPU-readable buffer snapshots; the default retains the supplied buffer. Renderer-owned output textures still follow the immediate reuse policy: callers recording distinct render-to-texture results must supply distinct targets and keep them unavailable for reuse until every GPU reader completes. Frame-level output leases and scheduling come next.

## Custom shadow resource bindings

Packet finishing records commands directly again; the experimental gather-and-compact pruning pass has been removed. Geometry keeps its normal bindings, and ordinary colour material recording uses the cached shader binding lists. The redundant-binding warning count may rise; this rollback is intended to isolate recording CPU cost before evaluating offset-only Metal buffer updates.

Cached pipeline requirements remain for correctness: custom shadow vertex and fragment functions must not depend on what the colour shader happens to read. Shadow-only buffers/textures, displacement, custom cutout fragment uniforms, and unreflected pipeline overrides retain their resources. StandardMaterial skips its maps for a known depth-only shadow, but keeps them available to unknown/custom shadow fragments. Base shadow setup honours makeShadowPipeline(), as layout variants do. Colour texture arrays include every reflected element, and reload rebuilds resource requirements.

Explicit draw-context bindings are preserved without packet filtering. Light/shadow/projector pass bindings, resource lifetimes, and frame scheduling are unchanged. This does not add built-in alpha-cutout or coloured shadow rendering, and does not assume future shadows or cookies are position-only or monochrome.


## Logical-frame completion

`Renderer` now returns its in-flight permit from the command buffer committed by `postDraw`, rather than the buffer created by `preDraw`. This keeps a logical frame admitted while an MPS wrapper commits intermediate segments. Hosts that override final submission must call `super.postDraw(commandBuffer:)`, as the standard display host does. The visionOS host registers its permit at its final submission too.

Compute inputs over 4 KB bound through an encoder-only update now get dedicated immutable buffer copies instead of retaining live ring bytes. With an unretained Metal command buffer, use the command-buffer update overload so Satin can supply explicit completion-owned storage.

## Target-wide recorded lighting and shadows

`record(scene:)` captures shadow draw commands through the same `draw(in:)` hooks as colour draws. Finalization replays those commands for the target's shadow views using the captured transforms, poses, geometry and custom bindings, without rerunning hooks against the last iteration's objects. CPU buffers that callers mutate still require `copyOnRecordLength` or independently versioned contents. Custom shadow shader pipelines and their texture bindings are preserved.

Lit colour pipelines are finalized using the complete target's light, shadow and projector counts. Source shader configuration and vertex descriptors are captured with each occurrence; no live material is consulted at finalization. Captured light occurrences keep independent shadow destinations when they need rendering. Unchanged, already-encoded maps with `autoUpdate == false` retain their cache behavior. A later native redraw detaches a destination still owned by a captured occurrence.

## Writable registered compute buffers

Compute bindings now distinguish read-only inputs from writable resources using cached reset/update pipeline reflection. Read-only `UniformBuffer` and `StructBuffer` bindings retain their per-dispatch snapshot behavior. If either kernel can write a binding, or access is unknown, Satin binds the original buffer and uploaded offset so the caller can observe GPU writes. Raw `MTLBuffer` bindings remain direct. No setter signature changes are required.

Writable resources are caller-owned GPU state: keep their bytes stable while pending work reads them, and use separate/versioned storage for distinct published outputs. Binding a buffer directly does not make CPU overwrites during GPU execution safe. Processor command-buffer context is now scoped to encoding and restored afterward, including nested updates; completed command buffers are no longer retained as the last update context.

## Tessellation preparation success

`Tessellator` now requires `encodeFactors(_:into:iterations:) -> Bool`. `TessellationMesh` uses this operation to prepare each destination and publishes it only when the tessellator reports success. A missing pipeline or unavailable encoder therefore leaves no factors bound, suppresses that draw, and keeps a requested freeze pending for retry. This reports encoding success, not GPU completion, and adds no wait.

`TessellationProcessor` implements the operation through its existing `update` path. Its standard implementation reports success only after a dispatch; the supplied destination is scoped to that preparation. Existing direct `update` calls remain available. Custom tessellators that produce factors through their own Metal/blit work must implement or override `encodeFactors` and return true only after encoding that work. They must not assume a Void update means factors exist.
