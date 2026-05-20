# Satin 2.0 Changelog

## Sync / Async Renderer Execution

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
