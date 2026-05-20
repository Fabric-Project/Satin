//
//  SsaoPostProcessEncoder.swift
//  Satin
//

import Metal
import simd

/// Full SSAO pipeline: raw ambient-occlusion, separable bilateral blur, and color composite.
/// Requires `RenderEncoder.activeOutputs` to include `.normals`.
open class SsaoPostProcessEncoder: PostProcessEncoder {
    private static let defaultResolutionScale: Float = 0.5
    private static let minResolutionScale: Float = 0.25
    private static let maxResolutionScale: Float = 1.0

    // MARK: - Inputs

    public var depthTexture: MTLTexture? {
        didSet {
            ssaoMaterial.depthTexture = depthTexture
            blurMaterial.depthTexture = depthTexture
        }
    }

    public var normalTexture: MTLTexture? {
        didSet { ssaoMaterial.normalTexture = normalTexture }
    }

    public var colorTexture: MTLTexture? {
        didSet { compositeMaterial.colorTexture = colorTexture }
    }

    public var sceneCamera: Camera?

    public var resolutionScale: Float {
        get { _resolutionScale }
        set {
            let clamped = Self.clampResolutionScale(newValue)
            guard clamped != _resolutionScale else { return }
            _resolutionScale = clamped
            resizeResources()
        }
    }

    // MARK: - Output

    public private(set) var aoTexture: MTLTexture?
    public private(set) var outputTexture: MTLTexture?

    // MARK: - Materials

    public let ssaoMaterial: SsaoMaterial
    public let blurMaterial: SsaoBlurMaterial
    public let compositeMaterial: SsaoCompositeMaterial

    // MARK: - Internals

    private let blurProcessor: SeparablePostProcessEncoder
    private let compositeProcessor: PostProcessEncoder
    private var rawTexture: MTLTexture?
    private var rawTextureSize: (width: Int, height: Int) = (0, 0)
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)
    private var lastSize: (width: Float, height: Float) = (0, 0)
    private var whiteAOTexture: MTLTexture?
    private var _resolutionScale = SsaoPostProcessEncoder.defaultResolutionScale

    // MARK: - Init

    private static func clampResolutionScale(_ value: Float) -> Float {
        min(max(value, Self.minResolutionScale), Self.maxResolutionScale)
    }

    private static func makeSsaoContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: .r8Unorm)
    }

    private static func makeCompositeContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: context.colorPixelFormat)
    }

    public required init(context: Context) {
        let ssaoContext = Self.makeSsaoContext(context: context)
        let compositeContext = Self.makeCompositeContext(context: context)
        ssaoMaterial = SsaoMaterial(context: ssaoContext)
        blurMaterial = SsaoBlurMaterial(context: ssaoContext)
        compositeMaterial = SsaoCompositeMaterial(context: compositeContext)
        blurProcessor = SeparablePostProcessEncoder(
            label: "SSAO Blur",
            context: ssaoContext,
            horizontalMaterial: blurMaterial,
            verticalMaterial: blurMaterial
        )
        compositeProcessor = PostProcessEncoder(
            label: "SSAO Composite",
            context: compositeContext,
            material: compositeMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
        super.init(
            label: "SSAO",
            context: ssaoContext,
            material: ssaoMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
    }

    // MARK: - Resize

    override open func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        lastSize = size
        compositeProcessor.resize(size: size, scaleFactor: scaleFactor)
        resizeResources()
    }

    private func resizeResources() {
        let scaledWidth = Int(max((lastSize.width * resolutionScale).rounded(.up), 0.0))
        let scaledHeight = Int(max((lastSize.height * resolutionScale).rounded(.up), 0.0))
        let scaledSize = (width: Float(scaledWidth), height: Float(scaledHeight))

        super.resize(size: scaledSize, scaleFactor: 1.0)
        blurProcessor.resize(size: lastSize, resolutionScale: resolutionScale)

        aoTexture = nil

        if scaledWidth > 0, scaledHeight > 0 {
            if rawTextureSize.width != scaledWidth || rawTextureSize.height != scaledHeight {
                rawTexture = makeTexture(
                    device: context.device,
                    width: scaledWidth,
                    height: scaledHeight,
                    pixelFormat: .r8Unorm,
                    usage: [.renderTarget, .shaderRead],
                    storageMode: .private,
                    label: "SSAO Raw"
                )
                rawTextureSize = (scaledWidth, scaledHeight)
            }
        } else {
            rawTexture = nil
            rawTextureSize = (0, 0)
        }

        let outputWidth = Int(max(lastSize.width, 0.0))
        let outputHeight = Int(max(lastSize.height, 0.0))
        guard outputWidth > 0, outputHeight > 0 else {
            outputTexture = nil
            outputTextureSize = (0, 0)
            return
        }

        if outputTextureSize.width != outputWidth || outputTextureSize.height != outputHeight {
            outputTexture = makeTexture(
                device: compositeProcessor.context.device,
                width: outputWidth,
                height: outputHeight,
                pixelFormat: compositeProcessor.context.colorPixelFormat,
                usage: [.renderTarget, .shaderRead],
                storageMode: .private,
                label: "SSAO Output"
            )
            outputTextureSize = (outputWidth, outputHeight)
        }
    }

    // MARK: - Draw

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        let blurOutputTexture = blurProcessor.outputTexture
        let hasAOInputs = depthTexture != nil && normalTexture != nil && rawTexture != nil && blurOutputTexture != nil
        aoTexture = hasAOInputs ? blurOutputTexture : nil

        if hasAOInputs, let rawTexture {
            if let cam = sceneCamera {
                ssaoMaterial.update(camera: cam)
            }

            super.draw(
                renderPassDescriptor: MTLRenderPassDescriptor(),
                commandBuffer: commandBuffer,
                renderTarget: rawTexture
            )

            blurProcessor.draw(commandBuffer: commandBuffer, inputTexture: rawTexture) { [blurMaterial] pass, inputTexture in
                blurMaterial.ssaoTexture = inputTexture
                blurMaterial.direction = pass == .horizontal ? simd_float2(1.0, 0.0) : simd_float2(0.0, 1.0)
            }
        }

        guard let colorTexture, let outputTexture else { return }
        guard let compositeAOTexture = hasAOInputs ? aoTexture : fallbackAOTexture() else { return }

        compositeMaterial.colorTexture = colorTexture
        compositeMaterial.aoTexture = compositeAOTexture
        compositeProcessor.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: outputTexture
        )
    }

    // MARK: - Helpers

    private func fallbackAOTexture() -> MTLTexture? {
        if let whiteAOTexture {
            return whiteAOTexture
        }

        let texture = makeTexture(
            device: compositeProcessor.context.device,
            width: 1,
            height: 1,
            pixelFormat: .r8Unorm,
            usage: [.shaderRead],
            storageMode: .shared,
            label: "SSAO White AO"
        )

        if let texture {
            let value: [UInt8] = [UInt8.max]
            value.withUnsafeBytes { bytes in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, 1, 1),
                    mipmapLevel: 0,
                    withBytes: bytes.baseAddress!,
                    bytesPerRow: 1
                )
            }
        }

        whiteAOTexture = texture
        return texture
    }

    private func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat,
        usage: MTLTextureUsage,
        storageMode: MTLStorageMode,
        label: String
    ) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = usage
        descriptor.storageMode = storageMode
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
