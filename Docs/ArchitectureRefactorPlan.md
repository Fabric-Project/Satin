# Satin 2.0 Architecture Refactor Plan

## Purpose

This document describes the structural and naming refactor that was applied on the `feature/2.0-Multithreading-Failed` branch. It is written for an agent starting from a **clean 2.0 base** (with the old names intact) that needs to apply these changes independently of any threading work.

**Scope: naming and structural changes only. Do not change any threading behaviour, dispatch queue configuration, or synchronization semantics.**

---

## What Is Changing

Two concerns:

1. **Encoder vs. Orchestrator split** — The old `Renderer` class was doing two unrelated jobs: encoding a scene graph into a `MTLCommandBuffer`, and owning the display link / render loop. These are separated into two distinct tiers.

2. **PostProcessor → PostProcessEncoder naming** — Consistent with the encoder tier naming.

---

## Tier 1 — Encoders

These classes encode work into a `MTLCommandBuffer`. They have no display link, no command queue, no frame index. They are called from within a frame.

| Old name | New name | File |
|---|---|---|
| `Renderer` | `RenderEncoder` | `Sources/Satin/Core/RenderEncoder.swift` |
| `PostProcessor` | `PostProcessEncoder` | `Sources/Satin/PostProcessing/PostProcessEncoder.swift` |
| `SsaoPostProcessor` | `SsaoPostProcessEncoder` | `Sources/Satin/PostProcessing/SsaoPostProcessEncoder.swift` |
| `SsgiPostProcessor` | `SsgiPostProcessEncoder` | `Sources/Satin/PostProcessing/SsgiPostProcessEncoder.swift` |
| `MotionBlurPostProcessor` | `MotionBlurPostProcessEncoder` | `Sources/Satin/PostProcessing/MotionBlurPostProcessEncoder.swift` |
| `BokehDepthOfFieldPostProcessor` | `BokehDepthOfFieldPostProcessEncoder` | `Sources/Satin/PostProcessing/BokehDepthOfFieldPostProcessEncoder.swift` |
| `ARBackgroundRenderer` | `ARBackgroundEncoder` | `Sources/Satin/AR/ARBackgroundEncoder.swift` |
| `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` | `Sources/Satin/AR/ARBackgroundDepthEncoder.swift` |
| `ARMatteRenderer` | `ARMatteEncoder` | `Sources/Satin/AR/ARMatteEncoder.swift` |
| `ARPostProcessor` | `ARPostProcessEncoder` | `Sources/Satin/AR/ARPostProcessEncoder.swift` |

---

## Tier 2 — Orchestrators

These classes own the render loop: display link, command queue, GPU sync semaphore, and frame index. A new abstract base `Renderer` consolidates the infrastructure that was previously duplicated between `MetalViewRenderer` and `MetalLayerRenderer`.

| Old name | New name | File |
|---|---|---|
| *(new)* | `Renderer` | `Sources/Satin/Views/Renderer.swift` |
| `MetalViewRenderer` | `ViewRenderer` | `Sources/Satin/Views/ViewRenderer.swift` |
| `MetalLayerRenderer` | `SpatialRenderer` | `Sources/Satin/Views/SpatialRenderer.swift` |

---

## Step-by-Step Changes

### Step 1 — Rename `Renderer` (the encoder) → `RenderEncoder`

The old `Renderer` class lives at `Sources/Satin/Core/Renderer.swift`. It encodes a scene graph. It is not a loop driver.

- Rename the file: `Sources/Satin/Core/Renderer.swift` → `Sources/Satin/Core/RenderEncoder.swift`
- Rename the class: `open class Renderer` → `open class RenderEncoder`
- Update all internal references within the file (`self`, label strings, etc.)
- Add a backward-compatibility typealias at the bottom of the file:
  ```swift
  // No typealias needed here — the name "Renderer" is taken by the new orchestrator base.
  // Callers must migrate to RenderEncoder.
  ```

**Note:** There is no typealias bridge for this rename because the name `Renderer` is reused for the new abstract orchestrator base (Step 2). Callers in Fabric and elsewhere must update `Renderer(context:)` → `RenderEncoder(context:)`.

---

### Step 2 — Create new abstract `Renderer` base class

Create `Sources/Satin/Views/Renderer.swift` as a new file. This class holds the shared infrastructure that was previously in `MetalViewRenderer` (and duplicated in `MetalLayerRenderer`).

**What moves into `Renderer`:**

- `id: String` — computed from subclass type name
- `context: Context` — set at init
- `isSetup: Bool`
- `frameIndex: Int` — starts at -1, incremented in `preDraw()`
- `inFlightSemaphore: DispatchSemaphore` — value = `maxBuffersInFlight`
- `renderQueue: DispatchQueue` — **leave this as-is from MetalViewRenderer; do not change its default or behaviour**
- Per-slot texture caches: `colorMultisampleTextures`, `depthTextures`, `depthMultisampleTextures`, `stencilTextures`, `stencilMultisampleTextures`
- Storage mode / usage overrides: `colorTextureStorageMode`, `depthTextureStorageMode`, `stencilTextureStorageMode`, etc.
- Frame encoding: `preDraw() -> MTLCommandBuffer?`, `draw(texture:commandBuffer:)`, `draw(renderPassDescriptor:commandBuffer:)`, `postDraw(commandBuffer:)`
- Texture helpers: `getDepthTexture(ref:index:)`, `getMultisampleDepthTexture(ref:index:)`, `getStencilTexture(ref:index:)`, `getMultisampleStencilTexture(ref:index:)`, `getMultisampleColorTexture(ref:index:)`
- Lifecycle stubs: `setup()`, `update()`, `cleanup()`, `resize(size:scaleFactor:)`
- `deinit` — signals `inFlightSemaphore` `maxBuffersInFlight` times to unblock any waiting renderQueue threads

**`Renderer.init` signature:**
```swift
public init(context: Context)
```

**Important:** Do not alter any dispatch queue or semaphore logic relative to what was in MetalViewRenderer. This is a mechanical extraction, not a threading change.

---

### Step 3 — Rename `MetalViewRenderer` → `ViewRenderer`, make it subclass `Renderer`

File: `Sources/Satin/Views/MetalViewRenderer.swift` → `Sources/Satin/Views/ViewRenderer.swift`

- Rename class: `open class MetalViewRenderer` → `open class ViewRenderer: Renderer`
- Remove all properties and methods that moved to the `Renderer` base (Step 2). `ViewRenderer` now only contains:
  - `metalView: MetalView`
  - `appearance` and `updateAppearance()`
  - Input event stubs (all the `mouseDown`, `touchesBegan`, `scrollWheel`, etc. methods)
  - `draw(metalLayer:drawable:)` — the display-link bridge that calls `renderQueue.async { update(); _renderFrame() }`
  - `drawableResized(size:scaleFactor:)`
- Add backward-compatibility typealias at the bottom:
  ```swift
  @available(*, deprecated, renamed: "ViewRenderer")
  public typealias MetalViewRenderer = ViewRenderer
  ```

---

### Step 4 — Rename `MetalLayerRenderer` → `SpatialRenderer`, make it subclass `Renderer`

File: `Sources/Satin/Views/MetalLayerRenderer.swift` → `Sources/Satin/Views/SpatialRenderer.swift`

- Rename class: `open class MetalLayerRenderer` → `open class SpatialRenderer: Renderer`
- Same extraction as Step 3 — remove shared infrastructure that now lives in `Renderer`
- Add backward-compatibility typealias:
  ```swift
  @available(*, deprecated, renamed: "SpatialRenderer")
  public typealias MetalLayerRenderer = SpatialRenderer
  ```

---

### Step 5 — Update `MetalViewController`

`MetalViewController` holds a reference to the renderer. Update the stored property type:

```swift
// Before
public let renderer: MetalViewRenderer

// After
public let renderer: ViewRenderer
```

The init signature changes from `MetalViewRenderer` to `ViewRenderer` as the parameter type.

No other functional changes — `MetalViewController` calls `renderer.setup()`, `renderer.resize()`, `renderer.cleanup()`, and connects the display link. All of these are now on the `Renderer` base.

---

### Step 6 — Rename `PostProcessor` → `PostProcessEncoder`

File: `Sources/Satin/PostProcessing/PostProcessor.swift` → `Sources/Satin/PostProcessing/PostProcessEncoder.swift`

- Rename class: `open class PostProcessor` → `open class PostProcessEncoder`
- Add backward-compatibility typealias:
  ```swift
  @available(*, deprecated, renamed: "PostProcessEncoder")
  public typealias PostProcessor = PostProcessEncoder
  ```

---

### Step 7 — Rename `PostProcessor` subclasses

For each subclass, rename the class. No typealiases needed for subclasses — they are internal to Satin. Callers should update call sites.

| Old class | New class | File rename |
|---|---|---|
| `SsaoPostProcessor` | `SsaoPostProcessEncoder` | `SsaoPostProcessor.swift` → `SsaoPostProcessEncoder.swift` |
| `SsgiPostProcessor` | `SsgiPostProcessEncoder` | `SsgiPostProcessor.swift` → `SsgiPostProcessEncoder.swift` |
| `MotionBlurPostProcessor` | `MotionBlurPostProcessEncoder` | `MotionBlurPostProcessor.swift` → `MotionBlurPostProcessEncoder.swift` |
| `BokehDepthOfFieldPostProcessor` | `BokehDepthOfFieldPostProcessEncoder` | `BokehDepthOfFieldPostProcessor.swift` → `BokehDepthOfFieldPostProcessEncoder.swift` |

In each file: rename the class declaration and update the superclass reference from `PostProcessor` to `PostProcessEncoder`.

---

### Step 8 — Rename AR classes

For each AR class, rename and add a typealias.

| Old class | New class | File |
|---|---|---|
| `ARBackgroundRenderer` | `ARBackgroundEncoder` | `ARBackgroundRenderer.swift` → `ARBackgroundEncoder.swift` |
| `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` | `ARBackgroundDepthRenderer.swift` → `ARBackgroundDepthEncoder.swift` |
| `ARMatteRenderer` | `ARMatteEncoder` | `ARMatteRenderer.swift` → `ARMatteEncoder.swift` |
| `ARPostProcessor` | `ARPostProcessEncoder` | `ARPostProcessor.swift` → `ARPostProcessEncoder.swift` |

Each gets a `@available(*, deprecated, renamed:)` typealias at the bottom of its file.

`ARBackgroundEncoder` subclasses `PostProcessEncoder` (not `PostProcessor`). `ARPostProcessEncoder` subclasses `PostProcessEncoder`. Update superclass references accordingly.

---

### Step 9 — Update `Satin.swift` / public re-exports

If `Satin.swift` re-exports class names or has a public API surface file, update any references from old names to new names. The typealiases ensure backward source compatibility but the primary names should be the new ones.

---

## What Does Not Change

- **No threading behaviour changes.** `renderQueue`, `inFlightSemaphore`, and how they are used in `ViewRenderer.draw(metalLayer:drawable:)` must be preserved exactly as-is from the old `MetalViewRenderer`. This is a lift-and-shift, not a rewrite.
- **No DispatchQueue configuration changes.** Do not change the default value of `renderQueue`, do not change how it is assigned, do not add `.async` or `.sync` calls.
- **No semaphore logic changes.** The wait/signal pattern around `inFlightSemaphore` in `preDraw()` and the command buffer completion handler must be identical to what was in `MetalViewRenderer`.
- **`RenderEncoder` internals unchanged.** The old `Renderer` class body is copied verbatim to `RenderEncoder.swift`. The only change is the class name.

---

### Step 10 — Update examples

All example renderers inherit from two utility base classes in `Example/Example/Utilities/Renderers/`. Update those two files and the small number of examples that directly instantiate old encoder names.

#### 10a — Utility base classes (two files, one line each)

**`Example/Example/Utilities/Renderers/BaseRenderer.swift`**

```swift
// Before
class BaseRenderer: MetalViewRenderer { … }

// After
class BaseRenderer: ViewRenderer { … }
```

This single change covers all ~50 example renderers that subclass `BaseRenderer` — they inherit the new name transitively and need no individual changes.

**`Example/Example/Utilities/Renderers/ImmersiveBaseRenderer.swift`**

```swift
// Before
class ImmersiveBaseRenderer: MetalLayerRenderer { … }

// After
class ImmersiveBaseRenderer: SpatialRenderer { … }
```

This covers `ImmersiveSuperShapesRenderer`, `ImmersivePostRenderer`, `Immersive3DRenderer`.

#### 10b — Direct `PostProcessor` instantiation (3 files)

These files instantiate `PostProcessor(` directly. Because the typealias exists they compile, but update to the canonical name for clarity.

| File | Change |
|---|---|
| `Renderers/Vision/ImmersivePostRenderer.swift:62` | `PostProcessor(` → `PostProcessEncoder(` |
| `Renderers/AR/ARBloomRenderer.swift:108` | `PostProcessor(` → `PostProcessEncoder(` |
| `Renderers/AR/ARPBRRenderer.swift:338` | `PostProcessor(` → `PostProcessEncoder(` |

#### 10c — AR encoder type annotations (8 files)

These files declare properties typed as the old AR names. The typealiases make them compile, but update to the canonical names.

| File | Old type | New type |
|---|---|---|
| `AR/ARRenderer.swift` | `ARBackgroundRenderer` | `ARBackgroundEncoder` |
| `AR/ARLidarMeshRenderer.swift` | `ARBackgroundRenderer` | `ARBackgroundEncoder` |
| `AR/ARContactShadowRenderer.swift` | `ARBackgroundRenderer` | `ARBackgroundEncoder` |
| `AR/ARPlanesRenderer.swift` | `ARBackgroundRenderer` | `ARBackgroundEncoder` |
| `AR/ARPeopleOcclusionRenderer.swift` | `ARBackgroundRenderer`, `ARMatteRenderer` | `ARBackgroundEncoder`, `ARMatteEncoder` |
| `AR/ARDrawingRenderer.swift` | `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` |
| `AR/ARBloomRenderer.swift` | `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` |
| `AR/ARPBRRenderer.swift` | `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` |
| `AR/ARPointCloudRenderer.swift` | `ARBackgroundDepthRenderer` | `ARBackgroundDepthEncoder` |

For each file: update the `var backgroundencoder: ARBackgroundRenderer!` (and equivalent) declaration and the corresponding constructor call.

#### 10d — Verify nothing references `Renderer` as a superclass

After applying 10a–10c, do a final grep to confirm no example file still refers to the old `Renderer` (encoder) class or `MetalViewRenderer`/`MetalLayerRenderer` directly:

```bash
grep -rn ": Renderer\b\|MetalViewRenderer\|MetalLayerRenderer\|PostProcessor\b\|ARBackgroundRenderer\|ARBackgroundDepthRenderer\|ARMatteRenderer\|ARPostProcessor\b" Example/Example --include="*.swift"
```

The only remaining hits should be inside typealias definitions in the Satin source — not in the examples.

---

## Verification

After applying all steps:

1. All files compile with zero errors.
2. The public API surface (from a caller's perspective) is backward-compatible via the `@available(*, deprecated, renamed:)` typealiases for: `MetalViewRenderer`, `MetalLayerRenderer`, `PostProcessor`, `ARBackgroundRenderer`, `ARBackgroundDepthRenderer`, `ARMatteRenderer`, `ARPostProcessor`.
3. `RenderEncoder` has no `@available` typealias — callers must update from `Renderer` to `RenderEncoder` explicitly, since `Renderer` is now the orchestrator base.
4. `MetalViewController` accepts a `ViewRenderer` and works as before.
5. No threading tests, TSAN tests, or queue-behaviour tests are in scope for this refactor.
