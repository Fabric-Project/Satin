# Satin 2.0 Changelog

<<<<<<< HEAD
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

## Bug Fixes

* Fix a bug in text tessellation, improving some edge cases with certain fonts not rendering correctly
* Fix a bug with Parametric Geometry having reversed normals
* Fix bug with anisotropic rendering
* Fix a bug with some UV’s in geometry generators
* Add texture matrix support for all materials which consume textures.

## Experimental Async Renderer Execution

Satin now separates render-loop ownership from scene encoding:

- `Renderer` owns sync vs async execution and render-owner scheduling.
- `RenderEncoder` remains the scene traversal / command encoding core.
- `ViewRenderer` and `SpatialRenderer` now run on top of that execution model.

### API

- `Renderer` now supports `.sync` and `.async` modes.
- Async renderers expose `schedule(_:)` and `scheduleAndWait(_:)` for render-owned mutation.
- Example `BaseRenderer` can switch default execution mode with a single mode flag.

### Threading / Render State

- Render-time camera, object, light, and shadow updates now use render snapshot state instead of live transform caches in the critical paths.
- Camera controller event hookup / teardown is main-thread confined, while controller motion is still applied during frame updates.
- Async resize no longer uses a blocking render-queue handoff.
- Light movement now correctly refreshes shadow and projector state during render preparation.
