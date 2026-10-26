# Satin 2.0 Changelog

## Frame contract: target-wide scene occurrences

- Recorded scenes contribute lights and shadow casters alongside colour draws. All occurrences in
  one target share lighting and shadows, while each keeps its transforms, material inputs and pose.
- Shadow passes replay captured commands with each light's views instead of revisiting live objects.
  Custom shadow pipelines and bindings remain intact. Colour pipelines resolve complete lighting
  counts after collection; renderOrder sorting includes both root and recorded draws.
- Captured shadow maps are versioned. Pending unencoded maps cannot become another submission's
  cache dependency, and abandoning a recording invalidates its own pending versions. Static maps
  remain reusable after encoding. Failure to create a render encoder now throws a SubmissionError.

## Tessellation example

- The example uses dynamic per-mesh tessellation preparation, rather than freezing the first factors. Animated factors stay above zero so starting at time zero does not discard every patch.

## Dynamic geometry bounds

- Culling no longer builds a triangle BVH just to compute bounds. Bounds reuse an already-current hierarchy or scan positions, so morphing and regenerated meshes avoid a hierarchy build per frame. Spatial queries still build the hierarchy lazily. Bounds scans respect interleaved position offsets.

## Stage 4: one drawing thread, plain command buffers

- Queued encoding is gone: `RenderEncoder.renderQueue`, `PostProcessEncoder.renderQueue`, submission
  admission, `GPUCommandRecording` / `RecordedGPUCommands`, `RecordedGPUWork`, `RecordedComputeWork`,
  `ComputeCommandEncoder`, `ComputeEncodingContext` and `holdUntilCompleted(_:)`.
  Satin encodes into the caller's command buffer on whichever thread draws. A host that wants rendering
  off the main thread moves the whole frame there; raw Metal and MPS work in the same command buffer
  then keeps call order with Satin's passes.
- Removed the unused render-queue experiment: `Renderer(context:renderQueue:)`, parameter UI
  channels and mirrors, the private display-link thread and queued camera input. View lifecycle,
  display ticks and input run directly on main. Threading is deferred; direct Satin callers keep
  one execution owner for their scene and renderer. Examples use ordinary parameter values again.
- Scenes owned by different threads no longer race: the process-wide transform epoch and structure
  token counters are atomic. A change in one scene only costs another scene's objects one extra
  ancestor walk.
- Read-only compute inputs Satin owns (automatic uniforms, registered `UniformBuffer` / `StructBuffer`
  inputs) are copied as they're bound: up to 4 KB with `setBytes`, larger into storage held until the
  command buffer completes. A processor updated more often than its ring has slots, inside an
  Iterator for instance, no longer rewrites what earlier dispatches read. Raw `MTLBuffer` and
  texture bindings are unchanged. Writable or unknown-access compute buffers bind their original
  storage. Large encoder-only read-only inputs use dedicated copies retained by Metal.
- `Satin.xcodeproj` and the Example now target macOS 15, iOS 18 and visionOS 2, as `Package.swift` does.
- Compute is plain Metal again: `update(_ commandBuffer:)`, `update(_ computeEncoder:)`, `bind`,
  `bindUniforms`, `dispatchThreads` / `dispatchThreadgroups` and the `pre…` hooks take an
  `MTLComputeCommandEncoder`.
- Post-processing draws throw, as scene draws do, and stay `open`; overrides call `super` with `try`.
- Per-view vertex uniforms are reserved while recording and written when the submission encodes.
  Hooks bind `vertexUniforms` as before; reading or copying its bytes while recording isn't supported.
- `PointShadow.recordsCastersOnceForAllFaces` and `PacketRecorder.alignsViewSlots` are gone. Casters
  are recorded once for every point-light face, and separately encoded views use 256-byte-aligned slots.


## Deferred shadow variants

- Deferred lighting keeps shadow support when a renderer first draws an unshadowed target and later records a shadowed one. Target-wide counts still control whether shadow resources and sampling are included.

## Material texture ownership

- Named texture properties on post-processing, motion-blur and AR post materials now share their retained binding slot. Generic slot replacement or removal updates the property too, preventing stale `unowned` texture access without adding duplicate ownership.

## Context Init

In Satin 1.0, an object’s `Context` could change out from under it (was a var) causing some subtle issues, and `Context` was assigned lazily. In Satin 2.0, all objects have a let `Context`, thus requiring new initializers. This change fixes a class of bugs, and for most use cases, a Satin `Context` does not change, so we decided this would be an acceptable change. 

## Renderer Clarification

In Satin 1.0, there were a few classes with the name ‘Renderer’ which served different roles. In Satin 2.0, we wanted to simplify and clarify class names by their responsibilities. We now have a suite of `RenderEncoder` objects, and a suite of `Renderer` objects.

***Render Encoder Class Responsibilities***
* Handling Satin specific scene graph traversal
* Ordering passes based on material, lighting and shadow needs
* Encoding commands to a command buffer

***Renderer Responsibilities***
* Handling draw loops / display links and eventually threading
* Handling Metal Surfaces 
* Integrating with platform specific views

### RenderEncoders

Classes that encode work into a `MTLCommandBuffer`. They have no display link, no command queue, and no frame index.

| Old name | New name |
|---|---|
| `Renderer` | `RenderEncoder` |
| `PostProcessor` | `PostProcessEncoder` |
| `ARBackgroundRenderer` | `ARBackgroundEncoder` |
| `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` |
| `ARMatteRenderer` | `ARMatteEncoder` |
| `ARPostProcessor` | `ARPostProcessEncoder` |

New Render Post Process Encoders

| Class | Description |
|---|---|
| `SsaoPostProcessEncoder` | Applies Screen Space Ambient Occlusion |
| `MotionBlurPostProcessEncoder` | Applies velocity map motion blur |
| `BokehDepthOfFieldPostProcessEncoder` | Applies fast separable depth of field blur |
| `SsgiPostProcessEncoder` | Applies experimental Screen Space Global Illumination | 


### Renderers

Classes that own the render loop: display link, command queue, GPU sync semaphore, and frame index.

**New `Renderer` abstract base** (`Sources/Satin/Views/Renderer.swift`) consolidates the shared infrastructure that was previously duplicated between `MetalViewRenderer` and `MetalLayerRenderer`:

| Old name | New name | Notes |
|---|---|---|
| *(new)* | `Renderer` | Abstract base; owns render loop infrastructure |
| `MetalViewRenderer` | `ViewRenderer` | Subclasses `Renderer`; owns `MetalView` and input event stubs |
| `MetalLayerRenderer` | `SpatialRenderer` | Subclasses `Renderer`; owns `LayerRenderer` and visionOS AR session |

`MetalViewController` now accepts a `ViewRenderer` (previously `MetalViewRenderer`).

---

## Updated Lighting / Shadows

All three light types — `DirectionalLight`, `PointLight`, and `SpotLight` — now support shadow casting. Enable shadows on any light by setting `castShadow = true`. Each light type gets its own shadow class (`DirectionalShadow`, `PointShadow`, `SpotShadow`) with tunable parameters:

```swift
let spot = SpotLight(context: context, color: .one, intensity: 2.0, radius: 8.0, angleInner: 30.0, angleOuter: 45.0)
spot.castShadow = true
spot.shadow.resolution = (width: 2048, height: 2048)
spot.shadow.bias = 0.00005
spot.shadow.strength = 0.8
```

`SpotLight` additionally supports a `projectionTexture` for cookie and projector effects, controlled by `projectionMode`:

- `.mask` — the texture modulates the spot's intensity (cookie / gobo effect)
- `.color` — the texture's RGB is projected as colored light onto shadow-receiving geometry

```swift
spot.projectionTexture = myTexture
spot.projectionMode = .color   // or .mask
```

---

## Render Mode support

Satin now supports three rendering modes: `forward`, `forwardPlus`, and `deferredGeometry`.

**`forward`** is the simplest mode: one pass, one color output. Use it when you don't need any post-processing that requires surface data (normals, PBR properties, velocity).

**`forwardPlus`** renders geometry in a single pass but simultaneously writes auxiliary surface data — albedo, normals, PBR, velocity, emissive — to additional render targets alongside color. Use this when you want post-process effects (SSAO, SSGI, motion blur, depth of field) without the overhead of a separate geometry prepass.

**`deferredGeometry`** splits rendering into two passes: a geometry pass that writes surface properties to a G-buffer, followed by a fullscreen lighting resolve pass. Unlit materials always render in a subsequent forward pass on top. Use this for scenes with many dynamic lights where the deferred lighting model reduces per-fragment work.

Enabling `forwardPlus` or `deferredGeometry` unlocks auxiliary G-buffer outputs alongside the color attachment. Only enable outputs that are actually consumed by a post-processor — each active flag costs a texture allocation and a color attachment write per fragment.

```swift
let context = Context(
    device: device,
    sampleCount: 1,
    colorPixelFormat: .bgra8Unorm,
    depthPixelFormat: .depth32Float,
    renderingMode: .forwardPlus,
    activeOutputs: [.color, .normals, .velocity]
)
```

`activeOutputs` is an `OptionSet` (`RendererOutputs`). Available flags: `.color` (always present), `.albedo`, `.normals`, `.pbr`, `.velocity`, `.emissive`. The `RenderEncoder` inherits `activeOutputs` from the Context; you can reassign it after construction, but doing so triggers pipeline recompilation on the next frame. MRT output requires `sampleCount == 1`.

### Custom Material Shader API

All Satin surface materials have been updated to write to a `SurfaceOutput` struct. Custom surface materials implement `evaluateSurface()` and populate it — the framework handles lighting and routes the result to the correct G-buffer attachments via `buildFragmentOutput()`. Unlit materials skip `SurfaceOutput` entirely and return a `FragmentOutput` directly using `buildColorFragmentOutput()`. The active attachments in `FragmentOutput` are controlled at compile time by `OUTPUT_*` preprocessor defines injected from the Context, so custom shaders don't need to conditionally compile against each mode manually.

---

## Alpha Order-Independent Transparency

Satin now supports Apple image-block order-independent transparency (OIT), which solves the classic problem of alpha-blended objects rendering incorrectly without CPU depth sorting. Enable it by passing `alphaOitEnabled: true` to `Context`.

When enabled, `blending = .alpha` uses Apple’s tile-memory image-block API on `MTLGPUFamilyApple4` GPUs (A11 Bionic / M1 and later). Alpha-blended content renders correctly in `forward`, `forwardPlus`, and `deferredGeometry` without requiring CPU depth sorting. On unsupported hardware, `.alpha` falls back to classic hardware alpha blending (order-dependent).

### Behavior

| Blend mode | Internal path | Notes |
|---|---|---|
| `disabled` | Opaque | Existing behavior |
| `alpha` | Apple image-block alpha OIT | Apple4+ only; unsupported hardware falls back to classic alpha |
| `additive` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |
| `subtract` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |
| `custom` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |


### Notes

- Alpha OIT writes only to the `color` attachment. Transparent alpha materials still do not contribute to `albedo`, `normals`, `pbr`, `velocity`, or `emissive`.
- Bucket order is fixed: `opaque → alpha OIT → classic transparent`. Classic transparent draws always appear over resolved alpha-OIT content regardless of `renderOrder`.
- Custom `SourceMaterial` shaders can opt into alpha OIT by defining `SATIN_ALPHA_OIT_ENABLED`, including `FragmentOutput.metal`, and returning `FragmentOutput` through `buildColorFragmentOutput(...)`.

## Point Geometry Rendering

All core materials now support point primitive rendering. Set `geometry.primitiveType = .point` on any mesh — no material swap required.

### API

Every material gains a `pointSize: Float` property (default `1.0`):

```swift
let mesh = Mesh(context: context, geometry: myGeo, material: BasicColorMaterial(context: context))
mesh.geometry.primitiveType = .point
mesh.material.pointSize = 8.0
```

### Supported Materials

| Material | Opt-in required | Notes |
|---|---|---|
| `BasicColorMaterial` | No | Solid color points |
| `BasicTextureMaterial` | No | Samples texture at vertex UV |
| `DepthMaterial` | No | Depth-encoded points |
| `UVColorMaterial` | No | UV-as-color points |
| `NormalColorMaterial` | No | Normal-as-color points |
| `StandardMaterial` | No | Full PBR — each point lit by its vertex normal |
| `PhysicalMaterial` | No | Full advanced PBR — inherits from Standard |

> For circular/masked points with per-fragment UV control, `BasicPointMaterial` remains the dedicated option.

`[[point_size]]` is ignored by the Metal rasterizer for non-point primitives, so all existing triangle rendering is unaffected. `pointSize` serializes automatically via the `ParameterGroup` Codable path — no migration needed.

## Text Rendering

Satin 2.0 gets the now open source SLUG rendering API ported from Warren Moore’s MetalSlug example. 

This is a great option to replace 1d SDF surface text rendering. See `SlugTextMesh` `SlugTextGeometry` `SlugTextMaterial` and `SlugFontAtlas` or the example `SlugTextRenderer`

## Performance Improvements

Satin 2.0 replaces some protocol-based types with concrete base classes on performance-critical paths, eliminating Swift Protocol Witness Table overhead.

Satin 2.0 adopts `CAMetalDisplayLink` on our new Mac based views, which removes some overhead of CAMetalDrawable creation. 

Internally to our main `RenderEncoder` class, we remove some cases of temporary array creation, optimize object hashing, and optimize some dictionaries and keys for pass management. 

Model loading now collapses object hierarchies which do not have meshes, reducing the graph size / object traversal and matrix calculations needed for rendering larger more complicated models substantially. 

## Render Packets

Satin 2.0 records each draw into plain-data render packets and encodes them per pass, in place of objects encoding themselves into the live encoder. See [MIGRATION.md](MIGRATION.md) for every API change.

* Drawing takes the frame being drawn (`draw(frame:…)`) and throws on a mismatched or misused submission. Renderers' `update(frame:)` overrides must call `super` first.
* Rendering a scene more than once a frame uses one `SubmissionBuilder` with a `record(scene:)` per iteration, replacing repeated encoding; `RenderSubmission` and `draw(submission:)` are gone. Each record snapshots its transforms, uniforms, instances and joint palettes.
* Motion vectors are tracked per occurrence of an object, so iterated and recorded draws get correct velocity.
* Customisation goes through `draw(in:)` on renderables, materials and geometry, recording typed bindings and draws (vertex, fragment, object and mesh stage buffers, tessellation factors, patch and mesh-threadgroup draws); `preDraw`, `onBind` and custom command closures are gone.
* Recorded work is self-contained: values, frame-arena slices and Metal resources. `retainUntilCompleted(_:)` is gone, and completion never touches a scene object.
* `Shadow.needsUpdate` clears when the shadow's passes are recorded; `RenderEncoder.abandon(_:)` releases sealed work that will never be encoded and marks its shadows dirty again.
* `RenderEncoderState` drops its pass-state restore machinery (`invalidate()` and the other `begin` variants).
* GPU work per frame goes through `encode(in: EncodingContext)`, writing to per-frame arena slices so repeated encodes never overwrite each other.

## Model Loading

* Meshes loaded from one asset share a material when their source materials are identical, and each texture loads once per set of loading options.
* Culling follows the asset's sidedness instead of drawing back faces everywhere; mirrored meshes keep their winding correct.
* `mergeStaticMeshes` (off by default) joins loaded meshes that draw exactly alike (one material, cull mode, vertex layout and world transform; opaque and static) into one mesh each, copying vertices as they are: fewer draws, the same pixels. Merging stays within each cell of a grid over the model (`mergeCells` along its longest side, 4 by default), by the centre of each mesh's bounds, which keeps merged meshes mostly local so culling can skip more of them.

## Transform Revisions

* Transform changes no longer push through the scene graph via Combine. Objects carry revisions; world matrices, bounds, camera views and light data validate when read. Moving a parent costs nothing until something reads its descendants.
* Removed the per-object Combine subjects that had no subscribers, and `@Published` from camera properties, which cost key-path and metadata lookups on every access.
* Parent and container links, and the subscriptions meshes, materials, posed geometries and parameter groups hold on their sources, are checked `unowned` instead of `weak`, so the objects a frame retains most no longer take the slow, side-table retain path. A parent clears its children's links as it lets them go and as it deallocates; assigning `children` now also clears the parent of each child it removes.

## Culling and Shadow Recording

* Passes skip renderables whose world bounds are wholly outside their views: colour views, shadow cameras and each point-light face. `Renderable.frustumCulled` (default `true`) opts out, for shaders that draw beyond the geometry's bounds.
* Shadows record each caster once for every shadow pass of the frame (all lights, a point light's six faces each) instead of once per pass, and each pass encodes it as its own view.
* `ParameterGroup.structureRevision` advances when parameters are added, removed or replaced; `StandardMaterial` uses it to write the environment intensity and texture transforms the renderer sets every frame without a lookup by name.

## Post-Processing

* `PostProcessEncoder` no longer creates and resizes a `RenderEncoder` it never drew with. Settings that were made on that encoder, and so ignored (`ARBloomRenderer`'s and `ARCompositor`'s load actions, `ARBackgroundEncoder`'s clear colour and texture), now apply to the pass that draws.

## Bug Fixes

* Fix a bug in text tessellation, improving some edge cases with certain fonts not rendering correctly
* Fix a bug with Parametric Geometry having reversed normals
* Fix bug with anisotropic rendering
* Fix a bug with some UV’s in geometry generators
* Add texture matrix support for all materials which consume textures.

## Frame contract correctness

- Frame-arena and immutable compute-input allocation failures now throw `GPUError.allocationFailed`.
  Recording/preparation hooks and compute encoding propagate failures; owned encoders close on error,
  partial recordings return their storage, and pending preparation keeps its arena memory alive.
- Asynchronous IBL scene loading now requires a Result completion callback, reporting preparation
  errors or success after GPU completion.


- Preserve captured point-shadow reach and cull recorded casters outside it, matching root casters.

* Bind tessellation factors only after successful preparation. Skip draws without valid factors and retry freezes after missing pipelines or allocation failures.
* Preserve GPU writes to registered compute buffers. Snapshot only reflected read-only inputs; writable or unknown-access buffers bind their original storage. Release the processor's command-buffer context after encoding.
* Keep renderer frame permits until the final command-buffer segment completes, including MPS continuation. Return an admission slot if command-buffer creation fails.
* Copy large encoder-only compute inputs rather than allowing later ring updates to overwrite dispatch contents.
