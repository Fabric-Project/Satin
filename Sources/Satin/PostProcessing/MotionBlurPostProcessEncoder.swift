//
//  MotionBlurPostProcessEncoder.swift
//  Satin
//

import Metal
import MetalKit

/// Fullscreen post-process that consumes the renderer's color and velocity outputs.
/// Requires `RenderEncoder.activeOutputs` to include `.velocity`.
open class MotionBlurPostProcessEncoder: PostProcessEncoder {
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
    private let colorPixelFormat: MTLPixelFormat
    private var blueNoiseTexture: MTLTexture?
    private var fallbackDepthTexture: MTLTexture?
    private var frameCounter: Int32 = 0

    // Velocity dilation by jump flood (sphynx-owner, MIT; after McGuire 2012 and Guertin
    // 2014): every tile finds the front-most mover whose trail covers it, in any direction,
    // so pixels a moving object sweeps over (including transparent background) receive its
    // blur, and pieces moving different ways do not leave tile seams.

    /// Tile size in pixels for velocity dilation; smaller is finer but costs more.
    public let tileSize: Int = 16
    /// Jump-flood passes, with steps shrinking by 3 (9, 3, 1 tiles for 3 passes).
    public static let jumpFloodPassCount = 3
    /// How far off a mover's line a tile may sit and still be covered, relative to its motion.
    public var perpendicularTolerance: Float = 0.5

    /// Longest blur in pixels: the reach of the dilation.
    public var maxBlurRadius: Float {
        Float(Self.jumpFloodStep(pass: 0, passCount: Self.jumpFloodPassCount) * tileSize)
    }

    private let tileMaxMaterial: MotionBlurTileMaxMaterial
    private let tileMaxEncoder: PostProcessEncoder
    private let jumpFloodMaterials: [MotionBlurJumpFloodMaterial]
    private let jumpFloodEncoders: [PostProcessEncoder]
    private let neighborMaxMaterial: MotionBlurNeighborMaxMaterial
    private let neighborMaxEncoder: PostProcessEncoder
    private var tileMaxTexture: MTLTexture?
    /// Ping-pong pointer textures for the jump-flood passes.
    private var jumpFloodTextures: [MTLTexture] = []
    private var neighborMaxTexture: MTLTexture?

    // MARK: - Init

    public required init(context: Context) {
        // Pipeline must not expect a depth attachment — use a depth-free context.
        let blurContext = Context(device: context.device, sampleCount: 1, colorPixelFormat: context.colorPixelFormat)
        colorPixelFormat = context.colorPixelFormat
        motionBlurMaterial = MotionBlurMaterial(context: blurContext)
        let tileMaxContext = Context(device: context.device, sampleCount: 1, colorPixelFormat: Self.tileMaxPixelFormat)
        tileMaxMaterial = MotionBlurTileMaxMaterial(context: tileMaxContext)
        tileMaxEncoder = PostProcessEncoder(label: "Motion Blur Tile Max", context: tileMaxContext, material: tileMaxMaterial,
                                            depthLoadAction: .dontCare, depthStoreAction: .dontCare)
        // One material and encoder per pass, so each keeps its own uniforms within a frame.
        let pointerContext = Context(device: context.device, sampleCount: 1, colorPixelFormat: Self.pointerPixelFormat)
        let jumpFloodMaterials = (0 ..< Self.jumpFloodPassCount).map { _ in MotionBlurJumpFloodMaterial(context: pointerContext) }
        self.jumpFloodMaterials = jumpFloodMaterials
        jumpFloodEncoders = jumpFloodMaterials.enumerated().map { pass, material in
            PostProcessEncoder(label: "Motion Blur Jump Flood \(pass)", context: pointerContext, material: material,
                               depthLoadAction: .dontCare, depthStoreAction: .dontCare)
        }
        neighborMaxMaterial = MotionBlurNeighborMaxMaterial(context: pointerContext)
        neighborMaxEncoder = PostProcessEncoder(label: "Motion Blur Neighbor Max", context: pointerContext, material: neighborMaxMaterial,
                                                depthLoadAction: .dontCare, depthStoreAction: .dontCare)
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
    }

    // MARK: - Draw

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard let outputTexture else { return }

        motionBlurMaterial.blueNoiseTexture = blueNoiseTexture
        let depthTexture = resolveDepthTexture(commandBuffer: commandBuffer)
        motionBlurMaterial.depthTexture = depthTexture
        encodeVelocityDilation(depthTexture: depthTexture, commandBuffer: commandBuffer)
        motionBlurMaterial.frame = frameCounter
        frameCounter = frameCounter &+ 1
        super.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, renderTarget: outputTexture)
    }

    // MARK: - Velocity Dilation

    /// Tile max keeps velocity and depth; full float, since reverse-Z depth gets very small.
    private static let tileMaxPixelFormat: MTLPixelFormat = .rgba32Float
    /// Pointers are UV coordinates, so they need more precision than half floats give.
    private static let pointerPixelFormat: MTLPixelFormat = .rg32Float

    /// Step of `pass` in tiles: 3^(passCount - 1 - pass), so 9, 3, 1 for three passes.
    private static func jumpFloodStep(pass: Int, passCount: Int) -> Int {
        var step = 1
        for _ in 0 ..< max(passCount - 1 - pass, 0) { step *= 3 }
        return step
    }

    /// Tile max, the jump-flood passes, then neighbor max, at tile resolution. Hands the
    /// blur its tile max and neighbor-max pointers; without a velocity texture there are none.
    private func encodeVelocityDilation(depthTexture: MTLTexture?, commandBuffer: MTLCommandBuffer) {
        guard let velocityTexture else {
            motionBlurMaterial.tileMaxTexture = nil
            motionBlurMaterial.neighborMaxTexture = nil
            return
        }
        let tileWidth = (velocityTexture.width + tileSize - 1) / tileSize
        let tileHeight = (velocityTexture.height + tileSize - 1) / tileSize
        if tileMaxTexture?.width != tileWidth || tileMaxTexture?.height != tileHeight {
            tileMaxTexture = makeTileTexture(pixelFormat: Self.tileMaxPixelFormat, width: tileWidth, height: tileHeight, label: "Tile Max")
            jumpFloodTextures = ["Jump Flood A", "Jump Flood B"].compactMap {
                makeTileTexture(pixelFormat: Self.pointerPixelFormat, width: tileWidth, height: tileHeight, label: $0)
            }
            neighborMaxTexture = makeTileTexture(pixelFormat: Self.pointerPixelFormat, width: tileWidth, height: tileHeight, label: "Neighbor Max")
            let tileGridSize = (Float(tileWidth), Float(tileHeight))
            tileMaxEncoder.resize(size: tileGridSize, scaleFactor: 1)
            jumpFloodEncoders.forEach { $0.resize(size: tileGridSize, scaleFactor: 1) }
            neighborMaxEncoder.resize(size: tileGridSize, scaleFactor: 1)
        }
        guard let tileMaxTexture, let neighborMaxTexture, jumpFloodTextures.count == 2 else { return }

        tileMaxMaterial.velocityTexture = velocityTexture
        tileMaxMaterial.depthTexture = depthTexture
        tileMaxMaterial.tileSize = tileSize
        tileMaxEncoder.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, renderTarget: tileMaxTexture)

        let shutterFraction = motionBlurMaterial.shutterAngle / 360
        for (pass, material) in jumpFloodMaterials.enumerated() {
            let output = jumpFloodTextures[pass % 2]
            material.tileMaxTexture = tileMaxTexture
            // The first pass seeds from tile max and never reads this; it is bound regardless.
            material.previousTexture = jumpFloodTextures[(pass + 1) % 2]
            material.stepSize = Self.jumpFloodStep(pass: pass, passCount: Self.jumpFloodPassCount)
            material.isFirstPass = pass == 0
            material.shutterFraction = shutterFraction
            material.perpendicularTolerance = perpendicularTolerance
            jumpFloodEncoders[pass].draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, renderTarget: output)
        }

        neighborMaxMaterial.tileMaxTexture = tileMaxTexture
        neighborMaxMaterial.jumpFloodTexture = jumpFloodTextures[(Self.jumpFloodPassCount - 1) % 2]
        neighborMaxEncoder.draw(renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer, renderTarget: neighborMaxTexture)

        motionBlurMaterial.tileMaxTexture = tileMaxTexture
        motionBlurMaterial.neighborMaxTexture = neighborMaxTexture
        motionBlurMaterial.maxBlurRadius = maxBlurRadius
    }

    private func makeTileTexture(pixelFormat: MTLPixelFormat, width: Int, height: Int, label textureLabel: String) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = context.device.makeTexture(descriptor: descriptor)
        texture?.label = label + " " + textureLabel
        return texture
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
