# Migrating to render packets

Satin now records every draw into plain-data render packets and encodes them per pass, instead of each object encoding itself into the live render encoder. Rendering the same scene more than once a frame (an Iterator, a render-to-texture) uses one **submission** with a **record** per iteration, in place of repeated encoding. This guide lists every public change and what to write instead.

## Queued scene submissions (Stage 4, opt-in)

`RenderEncoder.renderQueue` defaults to nil. Set it to an independently runnable serial
`DispatchQueue` to record on your producer and encode the sealed scene on that queue:

```swift
renderEncoder.renderQueue = DispatchQueue(label: "Scene encoding")
try renderEncoder.draw(frame: frameTime, renderPassDescriptor: descriptor,
                       commandBuffer: commandBuffer, scene: scene, camera: camera)
// Present and commit commandBuffer as usual after recording its downstream work.
```

Updates, traversal, input snapshots, command recording and admission waits happen on the producer.
Scene/effect GPU preparation commands now replay on the encoding queue as well.
One serial producer owns scene and encoder mutation, including resize and queue changes. The
encode queue must not be, or target, that producer queue; this is checked where possible in
Release. Already-recorded work can encode while the producer edits the scene. Long producer
work can still starve the render queue; this does not create an independent render loop.

Each queued draw creates a private command buffer from the caller's Metal command queue.
Preparation commands are captured before the scene and replayed into that same private buffer;
its GPU position is
reserved on the producer **after recording succeeds**. Different CPU encode queues may finish
in any order; buffers on one Metal command queue retain producer enqueue order.

**Ordering is not call-site transparent:**

- All work in the caller's buffer runs after its queued scene submissions, even work encoded
  before a queued draw. Keep readback and present there; preceding producers belong in a
  separately committed buffer on the same Metal queue, or require explicit synchronization.
- Mixing queued and immediate encoders in a dependency chain is caller error. In particular,
  immediate A in an uncommitted buffer followed by queued B runs B before A. Commit A's buffer
  first and use a new caller buffer for B. No GPU completion wait is needed on the same queue.
- Queue every scene/effect encoder in a dependent chain together. `PostProcessEncoder.renderQueue`
  uses the same scheduling boundary for the entire compound effect; private children stay immediate
  inside its private buffer. Standalone `ARMatteEncoder` remains immediate.
- Normally tracked resources on one Metal queue use Metal's hazard tracking. Untracked/aliased
  resources and work on different Metal queues need the caller's own synchronization.

One encoder admits at most `context.maxBuffersInFlight` outstanding queued submissions. Its
permit releases when its private GPU buffer completes, not when CPU encoding ends. This does
not bound complete frames, downstream consumers, other encoders or drawables. Frame admission
remains the frame owner's responsibility. `Context` now requires a count in `1...3`.

The caller's command buffer must be `.notEnqueued`; otherwise the queued draw throws
`SubmissionError.commandBufferAlreadyEnqueued` before scene updates. Failure to create the
private buffer throws `.commandBufferUnavailable`. Recording failure releases admission and
does not enqueue the failed buffer. Target-overload descriptor changes are restored on throws.

Scene values and managed input snapshots may change after recording. Raw buffer contents and
textures remain retained resources, not immutable copies. Caller-buffer completion is a
conservative release boundary for resources read by its preceding queued work, but targets
sampled by additional consumers must remain unavailable for reuse until every reader finishes.
Queue changes do not remove these ownership or ordering obligations. The explicit builder/seal/
encode API still leaves scheduling entirely to its caller; `renderQueue` affects convenience draws.

## Queued effects and Sponza comparison

`PostProcessEncoder.renderQueue` defaults to nil. Each public effect invocation uses one private
command buffer and one admission permit. With a queue set, **all recorded Metal encoding**—scene
preparation, compute dispatches, render passes, clears, blits and MPS—runs on that queue. Private
children append in order to the same recording; they do not schedule or take permits themselves.
Updates, pipeline preparation/compilation, snapshot copies and recording remain on the producer.
There is no independent render loop; long producer work can still delay submission.

Every `PostProcessEncoder.draw(...)` and `PostProcessRenderEncoder.draw(...)` throws. Add `try`
and handle errors at the frame owner. Effect subclasses now receive `GPUCommandRecording`
instead of a raw command buffer:

```swift
override func encodeEffect(frame: FrameTime, renderPassDescriptor: MTLRenderPassDescriptor,
                           commands: GPUCommandRecording, viewports: [MTLViewport],
                           viewMappings: [MTLVertexAmplificationViewMapping]) throws {
    // Preparation runs now; bindings, dispatch sizes and material values are captured now.
    commands.compute(processor)
    try commands.draw(child, frame: frame, renderPassDescriptor: intermediateDescriptor,
                      renderTarget: intermediateTexture)
    try super.encodeEffect(frame: frame, renderPassDescriptor: renderPassDescriptor,
                           commands: commands, viewports: viewports, viewMappings: viewMappings)
}
```

The public draw overloads are final. `super.encodeEffect` records the quad without a second permit.
An empty viewport list means the pass's configured viewport, resolved after preparation-time
resize. Explicit viewports/mappings describe the final destination; built-in SSAO/SSGI scale them
for intermediate textures. Explicit targets redirect the final composite only. Caller descriptors
are preserved. Nil queue preserves immediate encoding through the same command destination API.

`EncodingContext.commandBuffer` is replaced by `commands` and `device`. In object, geometry and
material GPU preparation hooks, append work to that destination:

**Custom GPU work: conform to `RecordedGPUWork`.** Blits, MPS kernels and any other Metal work Satin
doesn't encode itself are values with one method, `encode(into: MTLCommandBuffer)`:

```swift
struct CopyWork: RecordedGPUWork {
    let source: MTLBuffer
    let destination: MTLBuffer
    let length: Int

    func encode(into commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, sourceOffset: 0, to: destination, destinationOffset: 0, size: length)
        blit.endEncoding()
    }
}

context.commands.append(CopyWork(source: uploadBuffer, destination: outputBuffer, length: byteCount))
```

An MPS kernel works the same way: store a copy of the configured kernel (`kernel.copy()`) and its
textures, and encode them in `encode(into:)`. `ARDepthUpscaler` is an in-tree example.

The contract:
- **Values and Metal resources only.** A work value never reads or mutates a scene, material,
  encoder, node or parameter group once recorded. Its stored properties are everything that crosses
  to the encode queue.
- **Encoded exactly once,** in order with the operation's render and compute work: at once into the
  caller's buffer with no `renderQueue`, otherwise on that queue.
- **Released after its command buffer completes,** possibly on Metal's completion thread.
- **Holding a buffer or texture doesn't freeze its contents:** raw resources keep the existing
  synchronization contract.

`addCommands` (both the command-buffer and compute-encoder versions) is gone. Move each closure body
into a `RecordedGPUWork` (or `RecordedComputeWork`) value, turning what it captured into stored
properties.

**External resource lifetime: `holdUntilCompleted(_:)`** (replaces `retainUntilCompleted(_:)`). It
keeps an owner outside Satin alive until the operation's GPU work completes:
- object lifetime: a `CVMetalTexture`'s texture is invalid once the wrapper is released;
- content lifetime: a pooled `CVPixelBuffer` or `IOSurface` (movie, camera, Syphon frames) is
  recycled, and overwritten by a later frame, once its owner lets it go.

With a `renderQueue`, the GPU reads later than `draw` returns, so hold such owners for every frame
that reads them. Hold only owners whose `deinit` is safe on Metal's completion thread: CoreVideo and
IOSurface types are, scene objects aren't.

Compute binding/dispatch hooks and `preCompute`/`preReset`/`preUpdate` closures now receive a
`ComputeCommandEncoder` value facade. Usual `setBuffer`, `setTexture`, `setBytes`, sampler and
dispatch calls either encode immediately or capture values for replay. These hooks execute on the
producer, never on the worker. For other compute encoder commands, append a `RecordedComputeWork`
value (`encode(into: MTLComputeCommandEncoder)`), with the same contract as `RecordedGPUWork`. Never
save a compute recording context beyond its callback.
`ComputeEncodingContext` no longer exposes the raw command buffer.

Custom multi-encoder processors can override `update(_ commands: GPUCommandRecording, iterations:)`.
Move custom GPU logic from command-buffer update overrides into this hook to participate in queued
composition. The existing raw command-buffer update overload remains an explicit immediate API, now final.
It routes through these same hooks. A subclass overriding that old entry must migrate (the final
entry makes a missed migration a compile error rather than silently skipping custom logic).
Managed uniform/struct bytes are copied from the uploaded slot; dispatch/reset pipelines, textures,
buffers and sizes are resolved before returning from recording. Large copies keep their arena leases
until replay transfers them to GPU completion. The convenience draw seals and schedules as one
operation. A caller using `GPUCommandRecording` directly must encode a sealed recording once.

**Vertex uniforms are written when the submission encodes.** Recording reserves each render event's
`VertexUniforms` slot and records the occurrence's transforms and the views as values. The per-view
matrices are computed and written just before replay, on the encode queue with a `renderQueue`, on the
producer without one. Hooks keep binding `context.vertexUniforms` exactly as before. Its bytes aren't
written yet while recording, though: don't read them, and don't copy them with `copyOnRecordLength`
(that's a precondition failure).

**A throw fails the frame.**
- Satin's own errors are thrown before anything changes: a mismatched descriptor, an
  already-enqueued or unavailable command buffer.
- A throw from partway through preparation drops the whole operation. That can come from a custom
  `encodeEffect`, or from a later child in a compound effect.
- Nothing is rolled back. One-time state that preparation already advanced stays advanced, as if its
  GPU work had run:
  - a feedback compute's reset and ping-pong index;
  - a tessellated mesh's frozen factors;
  - motion blur's fallback-depth clear;
  - the cleaned flag of a static shadow.
- To recover after a failed `draw`, call `reset()` on affected compute systems and set
  `needsUpdate` on affected shadows.

`RenderEncoder.abandon(_:)` is unrelated: it's for a sealed submission you choose not to encode.

In the Sponza Example, press **P → Rendering → Dedicated Render Queue**. It defaults off and changes
scene, SSAO, motion blur, Bokeh and overlay together in update, after the previous frame's caller
buffer has been committed. Compare Release captures with the same scene settings. A background
capture should now place Bokeh dispatch and postprocess render encoding beneath
`RecordedGPUCommands.encode` on the worker. Preparation/recording remains on main. No performance
improvement has yet been established. Fabric's wider step-3 API adoption remains separate.

## Compute input snapshots (Stage 4 prerequisite)

`ComputeProcessor` and `ComputeSystem` now copy their automatic uniforms and registered
`UniformBuffer` / `StructBuffer` inputs when binding. Copies use the last uploaded slot, so
changing a parameter without uploading it does not change a registered buffer's contents.
Up to 4096 bytes use `setBytes` (copied into a value recording before deferred encoding); larger
copies use the processor's own arena, leased until the owning command buffer completes. Reusing or destroying the processor does not release
pending copies. No render queue is enabled by this change.

Plain `MTLBuffer` and texture bindings remain retained resources: their contents must be
versioned or protected until all readers finish. A `BindableBuffer` with no uploaded bytes
keeps its previous placeholder binding; reading unuploaded contents is still undefined.
Managed input buffers must have current CPU-visible contents before binding.

When supplying an existing compute encoder, also supply its owning command buffer:

```swift
let context = ComputeEncodingContext(commandBuffer: commandBuffer, computeEncoder: computeEncoder)
compute.update(context, iterations: 1) // replaces update(computeEncoder, iterations:)
```

`update(commandBuffer, iterations:)` is unchanged. `ComputeEncodingContext` neither ends
the encoder nor commits the command buffer; those remain the caller's responsibility.
Its compute encoder must belong to its command buffer, and both must be used on the producer.

Custom `bindUniforms` overrides now receive the same context:

```swift
override func bindUniforms(_ context: ComputeEncodingContext) {
    super.bindUniforms(context)
    // Additional bindings use context.computeEncoder.
}
```

The encoder-taking overloads of `BrdfGenerator`, `DiffuseIBLGenerator` and
`SpecularIBLGenerator` likewise become `encode(context:…)`. Their command-buffer overloads
are unchanged. `Tessellator`'s encoder-taking `update` now accepts `ComputeEncodingContext`.

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

`RenderSubmission`, `makeSubmission(frame:commandBuffer:cameras:viewports:)` and `draw(submission:…)` are gone; the builder above replaces them. `record(scene:)` neither updates nor encodes: do both first, as above. `record(scene:renderPassDescriptor:)` updates, encodes (into `preparationCommandBuffer`, when given) and records its own scene first, then the earlier records in order, per render layer. Records draw in the colour passes only. A recorded draw holds the Metal resources it binds and nothing else, so no scene object needs to outlive it: `retainUntilCompleted(_:)` is gone.

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

`needsUpdate` is cleared when a shadow's passes are recorded, not when they finish on the GPU. A producer that records a sealed submission and then drops it unencoded calls `renderEncoder.abandon(sealed)`: that releases the submission and marks the shadows it drew dirty again, so the next recording draws them. A submitted command buffer that fails is a device error, not something shadows recover from. `abandon` reaches back only through the last eight recordings.

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

CPU `update()` / `onUpdate` still run while recording. GPU preparation through custom `encode(in:)` hooks appends to an ordered command destination.
Pass `preparationCommands` when recording a builder to include those hooks, append the sealed scene
to the same recording, then submit it. `preparationCommandBuffer` remains an explicit immediate
compatibility path. Without either, schedule preparation yourself before encoding the sealed scene.
The one-line `draw(...)` overloads select the immediate or recorded destination automatically.

Holding a Metal resource keeps its identity alive, not its contents immutable. External buffers/textures must remain unchanged until completion, or use versioned resources. Draw-context buffer setters accept an explicit `copyOnRecordLength:` for CPU-readable buffer snapshots; the default retains the supplied buffer. Renderer-owned output textures still follow the immediate reuse policy: callers recording distinct render-to-texture results must supply distinct targets and keep them unavailable for reuse until every GPU reader completes. Frame-level output leases and scheduling come next.

## Custom shadow resource bindings

Packet finishing records commands directly again; the experimental gather-and-compact pruning pass has been removed. Geometry keeps its normal bindings, and ordinary colour material recording uses the cached shader binding lists. The redundant-binding warning count may rise; this rollback is intended to isolate recording CPU cost before evaluating offset-only Metal buffer updates.

Cached pipeline requirements remain for correctness: custom shadow vertex and fragment functions must not depend on what the colour shader happens to read. Shadow-only buffers/textures, displacement, custom cutout fragment uniforms, and unreflected pipeline overrides retain their resources. StandardMaterial skips its maps for a known depth-only shadow, but keeps them available to unknown/custom shadow fragments. Base shadow setup honours makeShadowPipeline(), as layout variants do. Colour texture arrays include every reflected element, and reload rebuilds resource requirements.

Explicit draw-context bindings are preserved without packet filtering. Light/shadow/projector pass bindings, resource lifetimes, and frame scheduling are unchanged. This does not add built-in alpha-cutout or coloured shadow rendering, and does not assume future shadows or cookies are position-only or monochrome.
