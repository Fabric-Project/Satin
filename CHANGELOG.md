# Satin 2.0 Changelog

## Architecture Refactor — Encoder / Orchestrator Split (Breaking)

The old `Renderer` class was conflating two unrelated responsibilities: encoding a scene graph into a `MTLCommandBuffer`, and owning the render loop (display link, command queue, semaphore, frame index). These are now separated into two distinct tiers.

### Tier 1 — Encoders

Classes that encode work into a `MTLCommandBuffer`. They have no display link, no command queue, and no frame index.

| Old name | New name |
|---|---|
| `Renderer` | `RenderEncoder` |
| `PostProcessor` | `PostProcessEncoder` |
| `SsaoPostProcessor` | `SsaoPostProcessEncoder` |
| `SsgiPostProcessor` | `SsgiPostProcessEncoder` |
| `MotionBlurPostProcessor` | `MotionBlurPostProcessEncoder` |
| `BokehDepthOfFieldPostProcessor` | `BokehDepthOfFieldPostProcessEncoder` |
| `ARBackgroundRenderer` | `ARBackgroundEncoder` |
| `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` |
| `ARMatteRenderer` | `ARMatteEncoder` |
| `ARPostProcessor` | `ARPostProcessEncoder` |

`RenderEncoder` has no backward-compatibility typealias — the name `Renderer` is taken by the new orchestrator base. All call sites must migrate from `Renderer(context:)` to `RenderEncoder(context:)`.

### Tier 2 — Render Drivers

Classes that own the render loop: display link, command queue, GPU sync semaphore, and frame index.

**New `Renderer` abstract base** (`Sources/Satin/Views/Renderer.swift`) consolidates the shared infrastructure that was previously duplicated between `MetalViewRenderer` and `MetalLayerRenderer`:

- `context: Context` — set at init
- `frameIndex: Int` — starts at -1, incremented each frame
- `inFlightSemaphore` — GPU/CPU synchronisation, value = `maxBuffersInFlight`
- Per-slot texture caches: `colorMultisampleTextures`, `depthTextures`, `depthMultisampleTextures`, `stencilTextures`, `stencilMultisampleTextures`
- Storage mode / usage overrides for color, depth, and stencil textures
- Frame encoding: `preDraw() -> MTLCommandBuffer?`, `draw(texture:commandBuffer:)`, `draw(renderPassDescriptor:commandBuffer:)`, `postDraw(commandBuffer:)`
- Texture helpers: `getDepthTexture`, `getMultisampleDepthTexture`, `getStencilTexture`, `getMultisampleStencilTexture`, `getMultisampleColorTexture`
- Lifecycle stubs: `setup()`, `update()`, `cleanup()`, `resize(size:scaleFactor:)`
- `defaultContext` — convenience accessor for a single-sample context derived from the renderer's context

| Old name | New name | Notes |
|---|---|---|
| *(new)* | `Renderer` | Abstract base; owns render loop infrastructure |
| `MetalViewRenderer` | `ViewRenderer` | Subclasses `Renderer`; owns `MetalView` and input event stubs |
| `MetalLayerRenderer` | `SpatialRenderer` | Subclasses `Renderer`; owns `LayerRenderer` and visionOS AR session |

`MetalViewController` now accepts a `ViewRenderer` (previously `MetalViewRenderer`).

### Migration

- Replace `Renderer(context:)` with `RenderEncoder(context:)` at all call sites.
- Replace `MetalViewRenderer` with `ViewRenderer`.
- Replace `MetalLayerRenderer` with `SpatialRenderer`.
- Replace `PostProcessor` with `PostProcessEncoder` and its subclasses accordingly.
- Replace all `AR*Renderer` / `ARPostProcessor` references with the `*Encoder` equivalents.
- Example utility base classes: `BaseRenderer: MetalViewRenderer` → `BaseRenderer: ViewRenderer`; `ImmersiveBaseRenderer: MetalLayerRenderer` → `ImmersiveBaseRenderer: SpatialRenderer`.

---

## Alpha Order-Independent Transparency

`blending = .alpha` now uses Apple image-block order-independent transparency on `MTLGPUFamilyApple4` GPUs (A11 Bionic / M1 and later) for Satin's built-in alpha-capable materials. This keeps the Fabric-side API unchanged while making alpha-blended content render correctly in `forward`, `forwardPlus`, and `deferredGeometry` without requiring CPU depth sorting.

On unsupported hardware, `.alpha` falls back to classic hardware alpha blending (order-dependent).

### Behavior

| Blend mode | Internal path | Notes |
|---|---|---|
| `disabled` | Opaque | Existing behavior |
| `alpha` | Apple image-block alpha OIT | Apple4+ only; unsupported hardware falls back to classic alpha |
| `additive` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |
| `subtract` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |
| `custom` | Classic hardware blending | Always order-dependent; drawn after alpha OIT |

### Layer budget and overflow

The implementation stores up to **4 depth-sorted transparent layers** per pixel in tile memory (32×16 tile, ~12 KB). If a pixel receives more than 4 overlapping transparent fragments, the farthest are silently discarded. For most scenes — geometry, UI, particles — 4 layers is sufficient. Dense volumetric or multi-layered glass may show artifacts at layer overflow.

### Alpha output

The blend pass correctly propagates output alpha using the over operator (`αout = αsrc + (1 − αsrc) × αdst`). Rendering to a transparent target with `clearColor = (0, 0, 0, 0)` preserves meaningful alpha in the composited result.

### Depth ordering

The depth sort accounts for Satin's reversed-Z depth buffer (`clearDepth = 0`, `depthCompare = .greaterEqual`). Near fragments are stored at low layer indices and composited last, producing correct front-over-back blending.

### Scope

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
