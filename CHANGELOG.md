# Satin 2.0 Changelog

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

The old `Renderer` class was conflating two unrelated responsibilities: encoding a scene graph into a `MTLCommandBuffer`, and owning the render loop (display link, command queue, semaphore, frame index). These are now separated into two distinct tiers.

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

|---|---|
| `SsaoPostProcessEncoder` | Applies Screen Space Ambient Occlusion |
| `MotionBlurPostProcessEncoder` | Applies velocity map motion blur |
| `BokehDepthOfFieldPostProcessEncoder` | Applies fast separable depth of field blur |
| `SsgiPostProcessEncoder` | Applies experimental Screen Space Global Illumination pass | 


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

In Satin 2.0, all lights now support shadows, and spotlight now supports cookies (masks) and projector modes (color image projection on to geometry that accepts shadows). See our updated Lighting examples. 

---

## Render Mode support

Satin now supports more than just `forward` rendering, but `forwardPlus` and `deferredGeometry`,

<claude write a short paragraph explaining the differences to a beginner audience />

For Satin updates `Context` and `RenderEncoder` path to support rendering to multiple render targets, including:

* Color
* Depth
* Albedo
* Normal
* Velocity
* PBR Map

This allows for new post processor passes, and for users to wire up their own unique passes. This is enabled via:

<claude add some sample code here />wire up Context and Render Encoder deferred support>

Note, that to support multiple render targets, all Satin Materials have been updated to write to a new Surface structure.

<claude simple note about surface structure for custom materials />

---

## Alpha Order-Independent Transparency

Satin now supports turning on a new Weight Blended Order Independent Transparency pass, using Apple GPU’s tile based image block API. 

OIT solves a class of problems for sorting and rendering lots of transparent objects efficiently. 

This is enabled via initializing a Satin `Context` with `alphaOitEnabled:True` passed at init,.

If enabled, `blending = .alpha` now uses Apple image-block order-independent transparency on `MTLGPUFamilyApple4` GPUs (A11 Bionic / M1 and later) for Satin's built-in alpha-capable materials. Alpha-blended content renders correctly in `forward`, `forwardPlus`, and `deferredGeometry` without requiring CPU depth sorting.

On unsupported hardware, `.alpha` falls back to classic hardware alpha blending (order-dependent).

### Behavior

| Blend mode | Internal path | Notes |
|---|---|---|
| `disabled` | Opaque | Existing behavior |
| `alpha` | Apple image-block alpha OIT | Apple4+ only; unsupported hardware falls back to classic alpha |
| `additive` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |
| `subtract` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |
| `custom` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |


### Notes with Deferred Rendering

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

Satin 2.0 walks back some usage of Protocols in the api in lieu of concrete base classes for performance critical paths. This removes a lot of Swift Protocol Witness Table lookups.

Satin 2.0 adopts `CAMetalDisplayLink` on our new Mac based views, which removes some overhead of CAMetalDrawable creation. 

Internally to our main `RenderEncoder` class, we remove some cases of temporary array creation, optimize object hashing, and optimize some dictionaries and keys for pass management. 

Model loading now collapses object hierarchies which do not have meshes, reducing the graph size / object traversal and matrix calculations needed for rendering larger more complicated models substantially. 

## Bug Fixes

* Fix a bug in text tessellation, improving some edge cases with certain fonts not rendering correctly
* Fix a bug with Parametric Geometry having reversed normals
* Fix bug with anisotropic rendering
* Fix a bug with some UV’s in geometry generators
* Add texture matrix support for all materials which consume textures.