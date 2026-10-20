# Migrating to render packets

Satin now records every draw into plain-data render packets and encodes them per pass, instead of each object encoding itself into the live render encoder. Rendering the same scene more than once a frame (an Iterator, a render-to-texture) uses one **submission** with a **record** per iteration, in place of repeated encoding. This guide lists every public change and what to write instead.

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
| `PostProcessEncoder.draw(renderPassDescriptor:commandBuffer:…)` and its subclasses (SSAO, SSGI, motion blur, bokeh, AR post) | `draw(frame:renderPassDescriptor:commandBuffer:…)`. These don't throw. |
| `ARMatteEncoder.encode(commandBuffer:)` | `try encode(frame:commandBuffer:)` |
| `ARBackgroundDepthEncoder` draws | `draw(frame:…)` like `PostProcessEncoder`; a failed inner depth draw is reported (an assertion in debug builds), not thrown. |

**Errors.** Draws throw `RenderSubmission.Error`:
- `.destinationMismatch(attachment:expected:found:)`: the descriptor supplies an attachment whose pixel format isn't the encoder's.
- `.alreadyDrawn`: a submission drawn (or recorded into) after it was drawn.
- `.foreignEncoder`: a submission drawn by an encoder other than the one that made it.

A rejected draw does no work and leaves your descriptor as it was.

**Settings are frozen per draw.** `clearColor`, the load/store actions, `sortObjects`, `renderingMode` and `activeOutputs` are read when a submission is made. Changing them mid-draw (from a callback, say) applies to later draws only.

## Rendering a scene more than once a frame

Removed: `prepareForRepeatedEncoding(count:)`, `selectRepeatedEncodingSlot/State`, `selectRecentSlot`, `captureRepeatedEncoding…`, `captureLatestSlot`, `setMinimumEncodesPerFrame(_:)` / `minimumEncodesPerFrame`, `loadRepeatedEncodingSourceStates`, `RenderEncoder.scheduleCurrentPassEncoding(…)` / `encodeCurrentPass(…)`, `maxSubPassesPerFrame`.

Now: make one submission, record the scene once per iteration, then draw it once. Each record snapshots transforms, material uniforms, instances and joint palettes as they are at that moment, so changing the scene between records doesn't change what was recorded.

```swift
let submission = renderEncoder.makeSubmission(frame: frameTime, commandBuffer: commandBuffer, cameras: [camera], viewports: [viewport])
for iteration in 0 ..< count {
    // Change the scene, and call update() on the objects you changed.
    applyIteration(iteration)
    // Only for objects that encode GPU work, such as a TessellationMesh.
    tessellatedMesh.encode(in: submission.encodingContext)
    try submission.record(scene: scene)
}
try renderEncoder.draw(submission: submission, renderPassDescriptor: renderPassDescriptor, scene: mainScene)
```

`record(scene:)` neither updates nor encodes: do both first, as above. `draw(submission:)` updates, encodes and draws its own scene first, then the records in order, per render layer. Records draw in the colour passes only. `submission.retainUntilCompleted(_:)` keeps an owner alive until the command buffer completes, for resources a recorded draw uses that nothing else holds.

`UniformBuffer(device:parameters:options:maxBuffersInFlight:encodesPerFrame:)` loses `encodesPerFrame`, and `encodesPerFrame` / `totalSlotCount` are gone: a uniform buffer has one slot per frame in flight.

**Motion** (velocity outputs) is tracked per occurrence: the first record of an object this frame pairs with its first record last frame, and so on. If you reorder or resize what you record so that ordinals no longer match, call `resetMotion()` on the affected renderables (or `InstancedMesh`, `JointPalette`): their next draws start still. Call `camera.resetMotion()` after a camera cut; resetting objects does not reset camera velocity. Camera history advances only on its first use in a frame, including after a cut reset.

**External buffer contents.** Recording retains bound buffers but does not freeze their bytes. Leave caller-owned buffer contents unchanged until the reading command buffer completes, or use versioned storage. The draw contexts' `setVertexBuffer` and `setFragmentBuffer` accept `copyOnRecord: true` to copy CPU-readable bytes from the supplied offset to the buffer's end into the frame arena. The default is `false`: Satin never chooses copying by size. Private GPU-only buffers require versioning or ordered GPU preparation rather than a CPU copy; managed buffers must have current CPU contents before copying.

Light, shadow and projector pass data now use arena snapshots instead of advancing `StructBuffer` rings. Several draws within one command buffer cannot overwrite an earlier draw's pass data. This does not yet make `RenderSubmission` safe for encoding on another thread: the existing immediate API and its caller-thread requirements remain.

## Renderables and meshes

| Removed | Instead |
|---|---|
| `isDrawable(renderContext:shadow:)` | A draw that records no draw call doesn't draw. |
| `update(renderContext:camera:viewport:index:)` | Nothing: per-view uniforms are written by the encoder into the frame. CPU work goes in `update()`. |
| `vertexUniforms`, `vertexUniforms(for:)`, `getVertexUniformBuffer(renderContext:)`, `setupVertexUniforms()`, `VertexUniformBuffer` | Nothing: vertex uniforms live in the frame's arena. A custom draw reads them from `RenderableDrawContext.vertexUniforms`. |
| `preDraw` | `material.set(_:index:)` for a buffer or texture, or override `draw(in: RenderableDrawContext)` and call `context.addCustomCommand`. |
| `InstancedMesh.instanceMatrixBuffer`, `InstanceMatrixUniformBuffer` | `setInstanceMatrices(_:)` / `setMatrixAt(index:matrix:)` as before; instance data is snapshotted per record. |

## Materials and shaders

| Removed | Instead |
|---|---|
| `onBind` | `set(_:index:)` (buffers and textures, vertex or fragment), or a `draw(in: MaterialDrawContext)` override that calls `super` then `context.addCustomCommand`. |
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

## Custom commands

`addCustomCommand` and `addCustomDraw` (on renderable, material and geometry draw contexts) run on the live encoder when the draw executes.
- **Copy what a command uses into locals before recording it.** Reading through `self` when it runs sees the object as it is then.
- **What a command sets lasts for its own draw.** From the next draw, Satin restores its pass state (viewports, vertex amplification, light, shadow and projector bindings) and resets scissor, stencil reference, blend colour and visibility results to their defaults.

`RenderEncoderState.invalidateBufferBindings()` is now `invalidate()`, which forgets every cached state, not only buffers.

## Shadows

`Shadow.draw(context:commandBuffer:renderables:)` is no longer public: shadows render inside `RenderEncoder`'s draw.

## Culling

Every pass now skips a renderable whose world bounds are wholly outside its views: each colour view (a multiview pass keeps it if any view may see it), each spot or directional shadow camera, and each point-light face. Only the four side planes of a view are tested, never near or far, and empty or non-finite bounds are never culled, so a renderable whose bounds cover what it draws renders exactly as before.

A renderable that draws outside its geometry's bounds must opt out with `frustumCulled = false`: vertex displacement (tessellation with a displacement map included), billboards, shaders that place vertices in clip space themselves, or custom renderables whose bounds don't describe what they draw.

## Point-light shadows

A point light records each caster once for all six faces and encodes that recording in each face it reaches, as that face's view: binding the render event's `vertexUniforms` (from `RenderableDrawContext`) through `setVertexBuffer` / `setFragmentBuffer` follows the face being drawn. A caster whose shadow recording runs a custom command is recorded per face as before, because the command may have captured the first face's uniforms.

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

`record` captures packets, pass bindings, private pass descriptors, shadow passes and deferred resolve inputs. `seal()` only transfers that work; it does not sample the scene again. A builder records one complete operation and seals once. A sealed submission encodes once; repeated use throws `RenderSubmission.Error.alreadyDrawn`. Sealing before recording throws `.notRecorded`. Abandoning recorded work releases its storage; encoded storage and arena contents remain leased through command-buffer completion. Keeping a consumed builder does not prolong those leases.

The existing `makeSubmission` / `draw(submission:...)` and one-line `draw(...)` APIs use the same replay implementation. Their additional `record(scene:)` calls retain their existing colour-only semantics. `PostProcessRenderEncoder.seal(frame:renderPassDescriptor:mesh:cameras:viewports:viewMappings:)` records and seals a post-processing quad in one call.

CPU `update()` / `onUpdate` still run while recording. GPU preparation through custom `encode(in:)` hooks needs a command buffer: schedule it separately before recording draws on the new path. The existing immediate draw APIs continue invoking those hooks automatically.

Holding a Metal resource keeps its identity alive, not its contents immutable. External buffers/textures must remain unchanged until completion, or use versioned resources. Draw-context buffer setters accept explicit `copyOnRecord: true` for CPU-readable buffer snapshots; the default retains the supplied buffer. Custom commands must capture stable values. Renderer-owned output textures still follow the immediate reuse policy: callers recording distinct render-to-texture results must supply distinct targets and keep them unavailable for reuse until every GPU reader completes. Frame-level output leases and scheduling come next.

## Pipeline-specific resource bindings

Finished packets now keep only direct buffers, textures and samplers their resolved pipeline uses. Usage is cached from compilation reflection for each context/layout variant, including shadow variants, and rebuilt on shader reload. Binding decisions no longer borrow the colour shader's usage for a shadow pass. Separate normal/UV buffers and material uniforms disappear from a position-only shadow; a custom shadow that reads them keeps them. Texture arrays preserve every reflected element.

Material, mesh and geometry draw methods gather available bindings before the packet finishes. Inspect finished packets when diagnosing bindings. Packets containing custom encoder commands keep all their bindings, because a command may change the pipeline or issue its own draw. Pipelines returned without known matching reflection also remain conservative. Existing pipeline override signatures are unchanged; base shadow setup now honours `makeShadowPipeline()` consistently with layout variants.

There is no position-only shadow assumption: custom displacement, skinning, instance data, alpha-cutout fragment textures and uniforms, and future colour or monochrome cookies retain their declared resources. Pass-level light/shadow/projector bindings are unchanged. This does not add built-in alpha-cutout or coloured shadow rendering; it preserves the resource path for those features. Sampler arrays and future slots beyond the compact usage mask are intentionally conservative.
