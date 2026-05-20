//
//  Renderer.swift
//  Satin
//
//  Abstract base class for all Satin render loop drivers.
//
//  Follows the same Context-first convention as the rest of Satin: the caller
//  constructs a Context (with the desired device, pixel formats, sample count,
//  and rendering mode) and passes it to init(context:). Renderer makes no
//  assumptions about any of those values.
//
//  Clients embedding Satin in their own render loop (e.g. Fabric) do not use
//  Renderer at all — they drive RenderEncoder directly from their own queue.
//

import Metal

open class Renderer {
    // MARK: - Identity

    open var id: String {
        var result = String(describing: type(of: self)).replacingOccurrences(of: "Renderer", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != result {
            result = result.replacingOccurrences(of: bundleName, with: "")
        }
        result = result.replacingOccurrences(of: ".", with: "")
        return result
    }

    // MARK: - Context

    /// The authoritative configuration for this renderer: device, command queue,
    /// pixel formats, sample count, and all rendering-mode flags.
    ///
    /// Set once at init time and immutable thereafter. Use `Context.makePlatformDefault()`
    /// for common platform defaults, or construct a full `Context` for custom formats,
    /// MSAA, deferred rendering, etc.
    public let context: Context

    // MARK: - State

    public internal(set) var isSetup: Bool = false

    /// Current frame index, starting at 0 on the first encoded frame.
    ///
    /// Incremented on **renderQueue** inside `preDraw()`, just before `draw()` is called.
    /// Use it in `draw()` to index into triple-buffered resources:
    ///
    ///     let slot = frameIndex % maxBuffersInFlight
    ///
    /// Do **not** read `frameIndex` from `update()` — at that point it still reflects
    /// the previous frame and will be out of sync with what `draw()` sees.
    public var frameIndex: Int = -1

    // MARK: - GPU Sync

    // Prevents the CPU from encoding more than maxBuffersInFlight frames ahead of the GPU.
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    // MARK: - Render Queue

    /// Serial queue on which Metal encoding runs when using Satin's built-in `MetalView` loop.
    ///
    /// **Threading contract — built-in loop (MetalView + MetalViewController):**
    /// - `setup()`, `cleanup()`, and `resize()` are called on the **main thread** by
    ///   `MetalViewController` and `MetalView`'s UIKit/AppKit layout callbacks.
    /// - `update()` is called on whatever thread drives `draw(metalLayer:drawable:)` —
    ///   which is the **main thread** when using `MetalView`'s display link, but is
    ///   not required to be main by `Renderer` itself.
    /// - `draw()`, `preDraw()`, and `postDraw()` are always dispatched to **renderQueue**
    ///   by `ViewRenderer.draw(metalLayer:drawable:)`.
    /// - State written in `update()` and read in `draw()` may race across the thread
    ///   boundary. This is accepted practice for Metal renderers; use triple-buffered
    ///   uniform buffers (keyed by `frameIndex % maxBuffersInFlight`) to avoid
    ///   GPU-visible corruption.
    ///
    /// **Custom loop driver:** if you call `draw(metalLayer:drawable:)` from your own
    /// serial queue, `update()` runs on your queue and encoding still runs on `renderQueue`.
    ///
    /// **Direct embedding:** if you bypass `MetalView` entirely and call
    /// `draw(renderPassDescriptor:commandBuffer:)` directly, `renderQueue` is not
    /// involved at all. You own the serialisation. Any serial queue or thread suffices.
    ///
    /// **Single-threaded mode:** assign `DispatchQueue.main` to this property *before*
    /// `setup()` is called so that both `update()` (already on main via MetalView) and
    /// all encoding share the same queue.
    public lazy var renderQueue = DispatchQueue.main //DispatchQueue(label: "graphics.fabric.satin.render", qos: .userInteractive)

    // MARK: - Auxiliary Texture Cache

    /// Cached per-slot textures for the current drawable size. Automatically recreated when
    /// the drawable dimensions change (lazy, checked in each `draw(texture:commandBuffer:)` call).
    public internal(set) var colorMultisampleTextures: [MTLTexture?] = []
    public internal(set) var depthTextures: [MTLTexture?] = []
    public internal(set) var depthMultisampleTextures: [MTLTexture?] = []
    public internal(set) var stencilTextures: [MTLTexture?] = []
    public internal(set) var stencilMultisampleTextures: [MTLTexture?] = []

    // Override these in subclasses to change storage/usage for auxiliary render targets.
    open var colorTextureStorageMode: MTLStorageMode { .memoryless }
    open var colorTextureUsage: MTLTextureUsage { .renderTarget }
    open var depthTextureStorageMode: MTLStorageMode { .memoryless }
    open var depthTextureUsage: MTLTextureUsage { .renderTarget }
    open var stencilTextureStorageMode: MTLStorageMode { .memoryless }
    open var stencilTextureUsage: MTLTextureUsage { .renderTarget }

    // MARK: - Init

    public init(context: Context) {
        self.context = context
    }

    // MARK: - Deinit

    deinit {
        // Signal maxBuffersInFlight times so any renderQueue thread blocked in preDraw() can exit.
        // Over-signalling is harmless — the renderer is gone and no further waits will occur.
        for _ in 0 ..< maxBuffersInFlight { inFlightSemaphore.signal() }
    }

    // MARK: - Frame Encoding

    /// Waits for a free in-flight buffer slot, increments `frameIndex`, creates a command buffer,
    /// and registers a GPU completion handler that signals `inFlightSemaphore`.
    ///
    /// Called on **renderQueue**. Returns `nil` only if the device cannot allocate a command buffer (rare).
    /// On `nil`, the acquired semaphore slot is released before returning.
    open func preDraw() -> MTLCommandBuffer? {
        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        frameIndex += 1
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return nil
        }
        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }
        return commandBuffer
    }

    /// Builds the render pass descriptor for the given color texture (with MSAA and depth/stencil
    /// from the texture cache), then calls `draw(renderPassDescriptor:commandBuffer:)`.
    ///
    /// `ViewRenderer` calls this with `drawable.texture`. Override if you need to customise
    /// how the render pass is assembled before the subclass encoding hook is invoked.
    open func draw(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let index = frameIndex % maxBuffersInFlight

        if context.sampleCount > 1 {
            renderPassDescriptor.colorAttachments[0].texture = getMultisampleColorTexture(ref: texture, index: index)
            renderPassDescriptor.colorAttachments[0].resolveTexture = texture
            renderPassDescriptor.depthAttachment.texture = getMultisampleDepthTexture(ref: texture, index: index)
            renderPassDescriptor.depthAttachment.resolveTexture = getDepthTexture(ref: texture, index: index)
            renderPassDescriptor.stencilAttachment.texture = getMultisampleStencilTexture(ref: texture, index: index)
            renderPassDescriptor.stencilAttachment.resolveTexture = getStencilTexture(ref: texture, index: index)
        } else {
            renderPassDescriptor.colorAttachments[0].texture = texture
            renderPassDescriptor.depthAttachment.texture = getDepthTexture(ref: texture, index: index)
            renderPassDescriptor.stencilAttachment.texture = getStencilTexture(ref: texture, index: index)
        }

        renderPassDescriptor.renderTargetWidth = texture.width
        renderPassDescriptor.renderTargetHeight = texture.height
        renderPassDescriptor.stencilAttachment.loadAction = .clear
        renderPassDescriptor.stencilAttachment.storeAction = .store
        renderPassDescriptor.stencilAttachment.clearStencil = 0

        draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    /// Override to encode Metal commands for the current frame.
    /// Called on **renderQueue** — do not access UIKit/AppKit state here.
    /// `frameIndex` reflects the current frame and is stable for the duration of this call.
    open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {}

    /// Called on **renderQueue** after `draw()` completes.
    /// Default implementation commits the command buffer. Override to add timing stamps,
    /// debug captures, or other post-encode work — call `super.postDraw` to commit.
    open func postDraw(commandBuffer: MTLCommandBuffer) {
        commandBuffer.commit()
    }

    // MARK: - Texture Cache

    open func getDepthTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard context.depthPixelFormat != .invalid, ref.width > 0, ref.height > 0 else { return nil }
        if depthTextures.count > index, let t = depthTextures[index], t.width == ref.width && t.height == ref.height { return t }
        let d = MTLTextureDescriptor()
        d.pixelFormat = context.depthPixelFormat; d.width = ref.width; d.height = ref.height
        d.sampleCount = 1; d.textureType = .type2D
        d.usage = depthTextureUsage; d.storageMode = depthTextureStorageMode
        d.allowGPUOptimizedContents = true; d.resourceOptions = .storageModePrivate
        let t = context.device.makeTexture(descriptor: d)
        t?.label = "\(id) Depth Texture \(index + 1)/\(maxBuffersInFlight)"
        if depthTextures.count > index { depthTextures[index] = t } else { depthTextures.append(t) }
        return t
    }

    open func getMultisampleDepthTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard context.sampleCount > 1, context.depthPixelFormat != .invalid, ref.width > 0, ref.height > 0 else { return nil }
        if depthMultisampleTextures.count > index, let t = depthMultisampleTextures[index], t.width == ref.width && t.height == ref.height { return t }
        let d = MTLTextureDescriptor()
        d.pixelFormat = context.depthPixelFormat; d.sampleCount = context.sampleCount; d.textureType = .type2DMultisample
        d.width = ref.width; d.height = ref.height
        d.usage = depthTextureUsage; d.storageMode = depthTextureStorageMode
        d.allowGPUOptimizedContents = true; d.resourceOptions = .storageModePrivate
        let t = context.device.makeTexture(descriptor: d)
        t?.label = "\(id) Multisample Depth Texture \(index + 1)/\(maxBuffersInFlight)"
        if depthMultisampleTextures.count > index { depthMultisampleTextures[index] = t } else { depthMultisampleTextures.append(t) }
        return t
    }

    open func getStencilTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard context.stencilPixelFormat != .invalid, ref.width > 0, ref.height > 0 else { return nil }
        if stencilTextures.count > index, let t = stencilTextures[index], t.width == ref.width && t.height == ref.height { return t }
        let d = MTLTextureDescriptor()
        d.pixelFormat = context.stencilPixelFormat; d.width = ref.width; d.height = ref.height
        d.sampleCount = 1; d.textureType = .type2D
        d.usage = stencilTextureUsage; d.storageMode = stencilTextureStorageMode
        d.allowGPUOptimizedContents = true; d.resourceOptions = .storageModePrivate
        let t = context.device.makeTexture(descriptor: d)
        t?.label = "\(id) Stencil Texture \(index + 1)/\(maxBuffersInFlight)"
        if stencilTextures.count > index { stencilTextures[index] = t } else { stencilTextures.append(t) }
        return t
    }

    open func getMultisampleStencilTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard context.sampleCount > 1, context.stencilPixelFormat != .invalid, ref.width > 0, ref.height > 0 else { return nil }
        if stencilMultisampleTextures.count > index, let t = stencilMultisampleTextures[index], t.width == ref.width && t.height == ref.height { return t }
        let d = MTLTextureDescriptor()
        d.pixelFormat = context.stencilPixelFormat; d.sampleCount = context.sampleCount; d.textureType = .type2DMultisample
        d.width = ref.width; d.height = ref.height
        d.usage = stencilTextureUsage; d.storageMode = stencilTextureStorageMode
        d.allowGPUOptimizedContents = true; d.resourceOptions = .storageModePrivate
        let t = context.device.makeTexture(descriptor: d)
        t?.label = "\(id) Multisample Stencil Texture \(index + 1)/\(maxBuffersInFlight)"
        if stencilMultisampleTextures.count > index { stencilMultisampleTextures[index] = t } else { stencilMultisampleTextures.append(t) }
        return t
    }

    open func getMultisampleColorTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        if colorMultisampleTextures.count > index, let t = colorMultisampleTextures[index], t.width == ref.width && t.height == ref.height { return t }
        let d = MTLTextureDescriptor()
        d.pixelFormat = context.colorPixelFormat; d.sampleCount = context.sampleCount; d.textureType = .type2DMultisample
        d.width = ref.width; d.height = ref.height
        d.usage = colorTextureUsage; d.storageMode = colorTextureStorageMode
        d.resourceOptions = .storageModePrivate; d.allowGPUOptimizedContents = true
        let t = context.device.makeTexture(descriptor: d)
        t?.label = "\(id) Multisample Color Texture \(index + 1)/\(maxBuffersInFlight)"
        if colorMultisampleTextures.count > index { colorMultisampleTextures[index] = t } else { colorMultisampleTextures.append(t) }
        return t
    }

    // MARK: - Lifecycle

    /// Called once by `MetalViewController` during `viewDidLoad` — always on the **main thread**
    /// when using Satin's provided view stack.
    open func setup() {}

    /// Called before each frame is encoded, on whatever thread drives the render loop.
    /// When using `MetalView`, this is the **main thread** (display link posts to main queue).
    /// If you drive the loop from your own queue, this runs on that queue instead.
    /// Either way it is safe to access UIKit/AppKit state here because `MetalView` guarantees
    /// it fires on main; a custom driver must make that guarantee itself.
    open func update() {}

    /// Called by `MetalViewController` when the renderer is torn down — always on the
    /// **main thread** when using Satin's provided view stack.
    open func cleanup() {}

    /// Called by `MetalView`'s layout callbacks (frame/bounds changes, backing scale changes)
    /// — always on the **main thread** because UIKit/AppKit layout is main-thread-only.
    /// A `draw()` call may be in-flight on renderQueue concurrently; keep resize work
    /// limited to scalar updates (camera aspect, encoder viewport) that tolerate one
    /// frame of transient inconsistency.
    open func resize(size: (width: Float, height: Float), scaleFactor: Float) {}
}
