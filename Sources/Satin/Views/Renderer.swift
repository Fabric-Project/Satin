//
//  Renderer.swift
//  Satin
//
//  Abstract base class for Satin render loop drivers.
//

import Foundation
import Metal

open class Renderer {
    open var id: String {
        var result = String(describing: type(of: self)).replacingOccurrences(of: "Renderer", with: "")
        if let bundleName = Bundle(for: type(of: self)).displayName, bundleName != result {
            result = result.replacingOccurrences(of: bundleName, with: "")
        }
        result = result.replacingOccurrences(of: ".", with: "")
        return result
    }

    public let context: Context

    /// Setting up, or cleaning up, starts frame time over.
    public internal(set) var isSetup = false {
        didSet {
            resetFrameTime()
        }
    }

    /// The frame being rendered, `.zero` before the first: stored by `update(frame:)`, whoever
    /// drives the frame. Its `frameNumber` also picks the in-flight slot.
    public private(set) var frameTime: FrameTime = .zero

    /// The host time of the first frame since frame time started over, which `frameTime.time`
    /// counts from; nil until that frame.
    private var firstFrameHostTime: TimeInterval?

    public var device: MTLDevice { context.device }
    public var commandQueue: MTLCommandQueue { context.commandQueue }

    open var sampleCount: Int { context.sampleCount }
    open var colorPixelFormat: MTLPixelFormat { context.colorPixelFormat }
    open var depthPixelFormat: MTLPixelFormat { context.depthPixelFormat }
    open var stencilPixelFormat: MTLPixelFormat { context.stencilPixelFormat }

    open var colorTextureStorageMode: MTLStorageMode { .memoryless }
    open var colorTextureUsage: MTLTextureUsage { .renderTarget }

    open var depthTextureStorageMode: MTLStorageMode { .memoryless }
    open var depthTextureUsage: MTLTextureUsage { .renderTarget }

    open var stencilTextureStorageMode: MTLStorageMode { .memoryless }
    open var stencilTextureUsage: MTLTextureUsage { .renderTarget }

    public internal(set) var colorMultisampleTextures: [MTLTexture?] = []

    public internal(set) var depthTextures: [MTLTexture?] = []
    public internal(set) var depthMultisampleTextures: [MTLTexture?] = []

    public internal(set) var stencilTextures: [MTLTexture?] = []
    public internal(set) var stencilMultisampleTextures: [MTLTexture?] = []

    private lazy var cachedDefaultContext = makeDefaultContext()

    public var defaultContext: Context {
        cachedDefaultContext
    }

    private let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    private var inFlightSemaphoreWait = 0
    private var inFlightSemaphoreRelease = 0

    /// The serial queue that owns this renderer's frames; nil draws on the main thread.
    ///
    /// With a queue, a `MetalViewController`'s display link ticks on a thread of its own and the
    /// renderer runs each frame on this queue, skipping a tick while the frame before is still
    /// running, so a busy main thread doesn't stop frames. Resize, appearance and cleanup reach it
    /// on this queue too, in order. Setup and events stay on main.
    ///
    /// Anything else a frame reads must reach the renderer on this queue (`renderQueue.async`),
    /// never by writing it from main. It's an ordinary queue, so renderers compose with GCD: groups,
    /// barriers and target queues.
    public let renderQueue: DispatchQueue?

    public init(context: Context) {
        self.context = context
        renderQueue = nil
    }

    public init(context: Context, renderQueue: DispatchQueue?) {
        self.context = context
        self.renderQueue = renderQueue
    }

    deinit {
#if DEBUG_VIEW
        print("\ndeinit - Renderer: \(id)\n")
#endif
        let delta = inFlightSemaphoreWait + inFlightSemaphoreRelease
        for _ in 0 ..< delta {
            inFlightSemaphore.signal()
        }
    }

    open func makeDefaultContext() -> Context {
        Context(
            device: context.device,
            sampleCount: sampleCount,
            colorPixelFormat: colorPixelFormat,
            depthPixelFormat: depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat
        )
    }

    func waitForAvailableFrameSlot() {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
    }

    func registerInFlight(_ commandBuffer: MTLCommandBuffer) {
        inFlightSemaphoreWait += 1
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
            self?.inFlightSemaphoreRelease -= 1
        }
    }

    /// The frame after `frameTime`, for the render loop to pass to `update(frame:)`, made from its
    /// clock: `hostTime` is the host time (`CACurrentMediaTime`) its display link targets for this
    /// frame, and `presentationHostTime` when the frame is expected on screen, nil when unknown.
    /// Time, delta and display time all come from those timestamps.
    func nextFrameTime(hostTime: TimeInterval, presentationHostTime: TimeInterval?) -> FrameTime {
        let isFirstFrame = self.firstFrameHostTime == nil
        let firstFrameHostTime = self.firstFrameHostTime ?? hostTime
        self.firstFrameHostTime = firstFrameHostTime

        return FrameTime(
            time: hostTime - firstFrameHostTime,
            deltaTime: isFirstFrame ? 0 : hostTime - frameTime.hostMediaTime,
            displayTime: presentationHostTime.map { $0 - firstFrameHostTime },
            systemTime: Date.timeIntervalSinceReferenceDate,
            hostMediaTime: hostTime,
            frameNumber: isFirstFrame ? 0 : frameTime.frameNumber + 1
        )
    }

    /// The next frame is the first again: frame 0, at time 0.
    func resetFrameTime() {
        frameTime = .zero
        firstFrameHostTime = nil
    }

    open func preDraw() -> MTLCommandBuffer? {
        waitForAvailableFrameSlot()

        if let commandBuffer = commandQueue.makeCommandBuffer() {
            return commandBuffer
        }

        inFlightSemaphore.signal()
        return nil
    }

    open func draw(texture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let index = frameTime.frameNumber % maxBuffersInFlight

        if sampleCount > 1 {
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
        renderPassDescriptor.stencilAttachment.storeAction = .store
        renderPassDescriptor.stencilAttachment.loadAction = .clear
        renderPassDescriptor.stencilAttachment.clearStencil = 0

        try draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {}

    open func postDraw(commandBuffer: MTLCommandBuffer) {
        // MPS may have committed intermediate segments during draw. The frame slot protects
        // the whole logical frame, so return it only after its final segment completes.
        registerInFlight(commandBuffer)
        commandBuffer.commit()
    }

    open func setup() throws {}

    /// Updates for `frame`, once per frame before drawing it. Overrides must call `super` first:
    /// it stores the frame as `frameTime`.
    open func update(frame: FrameTime) throws {
        frameTime = frame
    }

    open func cleanup() throws {}

    open func resize(size: (width: Float, height: Float), scaleFactor: Float) {}

    open func getDepthTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard depthPixelFormat != .invalid else { return nil }
        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if depthTextures.count > index,
           let depthTexture = depthTextures[index]
        {
            if depthTexture.width == ref.width && depthTexture.height == ref.height {
                return depthTexture
            } else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = depthPixelFormat
        descriptor.width = ref.width
        descriptor.height = ref.height
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        descriptor.usage = depthTextureUsage
        descriptor.storageMode = depthTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Depth Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            depthTextures[index] = texture
        } else {
            depthTextures.append(texture)
        }

        return texture
    }

    open func getMultisampleDepthTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard sampleCount > 1, depthPixelFormat != .invalid else { return nil }
        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if depthMultisampleTextures.count > index,
           let depthMultisampleTexture = depthMultisampleTextures[index]
        {
            if depthMultisampleTexture.width == ref.width && depthMultisampleTexture.height == ref.height {
                return depthMultisampleTexture
            } else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = depthPixelFormat
        descriptor.sampleCount = sampleCount
        descriptor.textureType = .type2DMultisample
        descriptor.width = ref.width
        descriptor.height = ref.height
        descriptor.usage = depthTextureUsage
        descriptor.storageMode = depthTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Multisample Depth Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            depthMultisampleTextures[index] = texture
        } else {
            depthMultisampleTextures.append(texture)
        }

        return texture
    }

    open func getStencilTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard stencilPixelFormat != .invalid else { return nil }
        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if stencilTextures.count > index,
           let stencilTexture = stencilTextures[index]
        {
            if stencilTexture.width == ref.width && stencilTexture.height == ref.height {
                return stencilTexture
            } else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = stencilPixelFormat
        descriptor.width = ref.width
        descriptor.height = ref.height
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        descriptor.usage = stencilTextureUsage
        descriptor.storageMode = stencilTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Stencil Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            stencilTextures[index] = texture
        } else {
            stencilTextures.append(texture)
        }

        return texture
    }

    open func getMultisampleStencilTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        guard sampleCount > 1, stencilPixelFormat != .invalid else { return nil }
        guard ref.width > 0, ref.height > 0 else { return nil }

        var replace = false

        if stencilMultisampleTextures.count > index,
           let stencilMultisampleTexture = stencilMultisampleTextures[index]
        {
            if stencilMultisampleTexture.width == ref.width && stencilMultisampleTexture.height == ref.height {
                return stencilMultisampleTexture
            } else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = stencilPixelFormat
        descriptor.sampleCount = sampleCount
        descriptor.textureType = .type2DMultisample
        descriptor.width = ref.width
        descriptor.height = ref.height
        descriptor.usage = stencilTextureUsage
        descriptor.storageMode = stencilTextureStorageMode
        descriptor.allowGPUOptimizedContents = true
        descriptor.resourceOptions = .storageModePrivate

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Multisample Stencil Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            stencilMultisampleTextures[index] = texture
        } else {
            stencilMultisampleTextures.append(texture)
        }

        return texture
    }

    open func getMultisampleColorTexture(ref: MTLTexture, index: Int) -> MTLTexture? {
        var replace = false

        if colorMultisampleTextures.count > index,
           let colorMultisampleTexture = colorMultisampleTextures[index]
        {
            if colorMultisampleTexture.width == ref.width && colorMultisampleTexture.height == ref.height {
                return colorMultisampleTexture
            } else {
                replace = true
            }
        }

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = colorPixelFormat
        descriptor.sampleCount = sampleCount
        descriptor.textureType = .type2DMultisample
        descriptor.width = ref.width
        descriptor.height = ref.height
        descriptor.usage = colorTextureUsage
        descriptor.storageMode = colorTextureStorageMode
        descriptor.resourceOptions = .storageModePrivate
        descriptor.allowGPUOptimizedContents = true

        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "\(id) Multisample Color Texture \(index + 1)/\(maxBuffersInFlight)"

        if replace {
            colorMultisampleTextures[index] = texture
        } else {
            colorMultisampleTextures.append(texture)
        }

        return texture
    }
}
