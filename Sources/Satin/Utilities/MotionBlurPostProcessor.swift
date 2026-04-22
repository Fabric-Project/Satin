//
//  MotionBlurPostProcessor.swift
//  Satin
//

import Metal
import MetalKit

private final class TileMaxMaterial: Material {
    public unowned var velocityTexture: MTLTexture? {
        didSet { set(velocityTexture, index: FragmentTextureIndex.Custom0) }
    }

    public required init(context: Context) {
        super.init(context: context)
        blending = .disabled
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

private final class NeighborMaxMaterial: Material {
    public unowned var tileMaxTexture: MTLTexture? {
        didSet { set(tileMaxTexture, index: FragmentTextureIndex.Custom0) }
    }

    public required init(context: Context) {
        super.init(context: context)
        blending = .disabled
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

open class MotionBlurPostProcessor: PostProcessor {
    // MARK: - Inputs

    public var colorTexture: MTLTexture? {
        didSet { motionBlurMaterial.colorTexture = colorTexture }
    }

    public var velocityTexture: MTLTexture? {
        didSet { motionBlurMaterial.velocityTexture = velocityTexture }
    }

    public var depthTexture: MTLTexture? {
        didSet { motionBlurMaterial.depthTexture = depthTexture }
    }

    // MARK: - Output

    public private(set) var outputTexture: MTLTexture?
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)

    // MARK: - Owned internals

    public let motionBlurMaterial: MotionBlurMaterial
    private let tileMaxMaterial: TileMaxMaterial
    private let neighborMaxMaterial: NeighborMaxMaterial
    private let tileMaxPostProcessor: PostProcessor
    private let neighborMaxPostProcessor: PostProcessor
    private let colorPixelFormat: MTLPixelFormat
    private let hierarchyPixelFormat: MTLPixelFormat = .rg16Float
    private var blueNoiseTexture: MTLTexture?
    private var fallbackDepthTexture: MTLTexture?
    private var tileMaxTexture: MTLTexture?
    private var neighborMaxTexture: MTLTexture?
    private var frameCounter: Int32 = 0
    private var hierarchyTextureSize: (width: Int, height: Int) = (0, 0)

    // MARK: - Init

    public required init(context: Context) {
        // Pipeline must not expect a depth attachment — use a depth-free context.
        let blurContext = Context(device: context.device, sampleCount: 1, colorPixelFormat: context.colorPixelFormat)
        let hierarchyContext = Context(device: context.device, sampleCount: 1, colorPixelFormat: .rg16Float)
        colorPixelFormat = context.colorPixelFormat
        motionBlurMaterial = MotionBlurMaterial(context: blurContext)
        tileMaxMaterial = TileMaxMaterial(context: hierarchyContext)
        neighborMaxMaterial = NeighborMaxMaterial(context: hierarchyContext)
        tileMaxPostProcessor = PostProcessor(
            label: "Motion Blur Tile Max",
            context: hierarchyContext,
            material: tileMaxMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
        neighborMaxPostProcessor = PostProcessor(
            label: "Motion Blur Neighbor Max",
            context: hierarchyContext,
            material: neighborMaxMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
        super.init(
            label: "Motion Blur",
            context: blurContext,
            material: motionBlurMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
        blueNoiseTexture = loadBlueNoiseTexture(device: context.device)
    }

    // MARK: - Resize

    override open func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        super.resize(size: size, scaleFactor: scaleFactor)
        let w = Int(size.width), h = Int(size.height)
        if outputTextureSize.width != w || outputTextureSize.height != h {
            outputTexture = makeOutputTexture(device: context.device, width: w, height: h)
            outputTextureSize = (w, h)
        }

        if hierarchyTextureSize.width != w || hierarchyTextureSize.height != h {
            tileMaxTexture = makeVelocityHierarchyTexture(device: context.device, width: w, height: h, label: "Tile Max")
            neighborMaxTexture = makeVelocityHierarchyTexture(device: context.device, width: w, height: h, label: "Neighbor Max")
            hierarchyTextureSize = (w, h)
        }

        let hierarchySize = (width: Float(w), height: Float(h))
        tileMaxPostProcessor.resize(size: hierarchySize, scaleFactor: 1.0)
        neighborMaxPostProcessor.resize(size: hierarchySize, scaleFactor: 1.0)
    }

    // MARK: - Draw

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard
            let outputTexture,
            let velocityTexture,
            let tileMaxTexture,
            let neighborMaxTexture
        else { return }

        tileMaxMaterial.velocityTexture = velocityTexture
        tileMaxPostProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, renderTarget: tileMaxTexture)

        neighborMaxMaterial.tileMaxTexture = tileMaxTexture
        neighborMaxPostProcessor.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, renderTarget: neighborMaxTexture)

        motionBlurMaterial.blueNoiseTexture = blueNoiseTexture
        motionBlurMaterial.depthTexture = resolveDepthTexture(commandBuffer: commandBuffer)
        motionBlurMaterial.neighborMaxTexture = neighborMaxTexture
        motionBlurMaterial.frame = frameCounter
        frameCounter = frameCounter &+ 1
        super.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, renderTarget: outputTexture)
    }

    // MARK: - Helpers

    private func makeOutputTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let tex = device.makeTexture(descriptor: descriptor)
        tex?.label = label + " Output"
        return tex
    }

    private func makeVelocityHierarchyTexture(device: MTLDevice, width: Int, height: Int, label: String) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: hierarchyPixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = self.label + " " + label
        return texture
    }

    private func resolveDepthTexture(commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        if let depthTexture {
            return depthTexture
        }

        if fallbackDepthTexture == nil {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float,
                width: 1,
                height: 1,
                mipmapped: false
            )
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            fallbackDepthTexture = context.device.makeTexture(descriptor: descriptor)
            fallbackDepthTexture?.label = label + " Fallback Depth"
        }

        if let fallbackDepthTexture {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.depthAttachment.texture = fallbackDepthTexture
            renderPassDescriptor.depthAttachment.loadAction = .clear
            renderPassDescriptor.depthAttachment.storeAction = .store
            renderPassDescriptor.depthAttachment.clearDepth = 0.0
            commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)?.endEncoding()
        }

        return fallbackDepthTexture
    }

    private func loadBlueNoiseTexture(device: MTLDevice) -> MTLTexture? {
        guard let url = getTexturesURL("blue_noise_rgba.png") else { return nil }
        let loader = MTKTextureLoader(device: device)
        return try? loader.newTexture(URL: url, options: [
            .SRGB: false,
            .generateMipmaps: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ])
    }
}
