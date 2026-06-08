import Metal
import MetalKit
import simd

open class SsgiPostProcessEncoder: PostProcessEncoder {
    private static let defaultResolutionScale: Float = 0.5
    private static let minResolutionScale: Float = 0.25
    private static let maxResolutionScale: Float = 1.0

    public var colorTexture: MTLTexture? {
        didSet {
            ssgiMaterial.colorTexture = colorTexture
            compositeMaterial.colorTexture = colorTexture
        }
    }

    public var depthTexture: MTLTexture? {
        didSet {
            ssgiMaterial.depthTexture = depthTexture
            blurMaterial.depthTexture = depthTexture
        }
    }

    public var normalTexture: MTLTexture? {
        didSet {
            ssgiMaterial.normalTexture = normalTexture
            blurMaterial.normalTexture = normalTexture
        }
    }

    public var albedoTexture: MTLTexture? {
        didSet { ssgiMaterial.albedoTexture = albedoTexture }
    }

    public var pbrTexture: MTLTexture? {
        didSet { ssgiMaterial.pbrTexture = pbrTexture }
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

    public private(set) var ssgiTexture: MTLTexture?
    public private(set) var outputTexture: MTLTexture?

    public let ssgiMaterial: SsgiMaterial
    public let blurMaterial: SsgiBlurMaterial
    public let compositeMaterial: SsgiCompositeMaterial

    private let blurProcessor: PostProcessEncoder
    private let compositeProcessor: PostProcessEncoder
    private var rawTexture: MTLTexture?
    private var denoisedTexture: MTLTexture?
    private var rawTextureSize: (width: Int, height: Int) = (0, 0)
    private var denoisedTextureSize: (width: Int, height: Int) = (0, 0)
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)
    private var lastSize: (width: Float, height: Float) = (0, 0)
    private var neutralTexture: MTLTexture?
    private var blueNoiseTexture: MTLTexture?
    private var _resolutionScale = SsgiPostProcessEncoder.defaultResolutionScale
    private var frameIndex: UInt32 = 0

    private static func clampResolutionScale(_ value: Float) -> Float {
        min(max(value, Self.minResolutionScale), Self.maxResolutionScale)
    }

    private static func makeSsgiContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: .rgba16Float)
    }

    private static func makeCompositeContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: context.colorPixelFormat)
    }

    public required init(context: Context) {
        let ssgiContext = Self.makeSsgiContext(context: context)
        let compositeContext = Self.makeCompositeContext(context: context)

        ssgiMaterial = SsgiMaterial(context: ssgiContext)
        blurMaterial = SsgiBlurMaterial(context: ssgiContext)
        compositeMaterial = SsgiCompositeMaterial(context: compositeContext)

        blurProcessor = PostProcessEncoder(
            label: "SSGI Denoise",
            context: ssgiContext,
            material: blurMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )

        compositeProcessor = PostProcessEncoder(
            label: "SSGI Composite",
            context: compositeContext,
            material: compositeMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )

        super.init(
            label: "SSGI",
            context: ssgiContext,
            material: ssgiMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )

        blueNoiseTexture = loadBlueNoiseTexture(device: context.device)
        blurMaterial.blueNoiseTexture = blueNoiseTexture
    }

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
        blurProcessor.resize(size: scaledSize, scaleFactor: 1.0)

        ssgiTexture = nil

        if scaledWidth > 0, scaledHeight > 0 {
            if rawTextureSize.width != scaledWidth || rawTextureSize.height != scaledHeight {
                rawTexture = makeTexture(
                    device: context.device,
                    width: scaledWidth,
                    height: scaledHeight,
                    pixelFormat: .rgba16Float,
                    usage: [.renderTarget, .shaderRead],
                    storageMode: .private,
                    label: "SSGI Raw"
                )
                rawTextureSize = (scaledWidth, scaledHeight)
            }

            if denoisedTextureSize.width != scaledWidth || denoisedTextureSize.height != scaledHeight {
                denoisedTexture = makeTexture(
                    device: context.device,
                    width: scaledWidth,
                    height: scaledHeight,
                    pixelFormat: .rgba16Float,
                    usage: [.renderTarget, .shaderRead],
                    storageMode: .private,
                    label: "SSGI Denoised"
                )
                denoisedTextureSize = (scaledWidth, scaledHeight)
            }
        } else {
            rawTexture = nil
            rawTextureSize = (0, 0)
            denoisedTexture = nil
            denoisedTextureSize = (0, 0)
        }

        let outputWidth = Int(max(lastSize.width.rounded(.up), 0.0))
        let outputHeight = Int(max(lastSize.height.rounded(.up), 0.0))
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
                label: "SSGI Output"
            )
            outputTextureSize = (outputWidth, outputHeight)
        }
    }

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        let hasInputs = colorTexture != nil &&
            depthTexture != nil &&
            normalTexture != nil &&
            albedoTexture != nil &&
            pbrTexture != nil &&
            rawTexture != nil &&
            denoisedTexture != nil &&
            sceneCamera != nil

        ssgiTexture = hasInputs ? denoisedTexture : nil

        if hasInputs, let rawTexture, let denoisedTexture, let sceneCamera {
            ssgiMaterial.update(camera: sceneCamera, viewportHeight: Float(rawTexture.height))

            super.draw(
                renderPassDescriptor: MTLRenderPassDescriptor(),
                commandBuffer: commandBuffer,
                renderTarget: rawTexture
            )

            blurMaterial.ssgiTexture = rawTexture
            blurMaterial.blueNoiseTexture = blueNoiseTexture
            blurMaterial.noiseIndex = Int32(frameIndex & 3)
            blurMaterial.update(camera: sceneCamera)
            blurProcessor.draw(
                renderPassDescriptor: MTLRenderPassDescriptor(),
                commandBuffer: commandBuffer,
                renderTarget: denoisedTexture
            )

            frameIndex &+= 1
        }

        guard let colorTexture, let outputTexture else { return }
        guard let compositeSsgiTexture = hasInputs ? ssgiTexture : fallbackNeutralTexture() else { return }

        compositeMaterial.colorTexture = colorTexture
        compositeMaterial.ssgiTexture = compositeSsgiTexture
        compositeProcessor.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: outputTexture
        )
    }

    private func fallbackNeutralTexture() -> MTLTexture? {
        if let neutralTexture {
            return neutralTexture
        }

        let texture = makeTexture(
            device: compositeProcessor.context.device,
            width: 1,
            height: 1,
            pixelFormat: .rgba8Unorm,
            usage: [.shaderRead],
            storageMode: .shared,
            label: "SSGI Neutral"
        )

        if let texture {
            let value: [UInt8] = [0, 0, 0, UInt8.max]
            value.withUnsafeBytes { bytes in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, 1, 1),
                    mipmapLevel: 0,
                    withBytes: bytes.baseAddress!,
                    bytesPerRow: value.count
                )
            }
        }

        neutralTexture = texture
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

    private func loadBlueNoiseTexture(device: MTLDevice) -> MTLTexture? {
        if let url = getTexturesURL("blue_noise_rgba.png") {
            let loader = MTKTextureLoader(device: device)
            if let texture = try? loader.newTexture(URL: url, options: [
                .SRGB: false,
                .generateMipmaps: false,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
            ]) {
                return texture
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "SSGI Noise Fallback"

        let value: [UInt8] = [64, 128, 192, 255]
        value.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: value.count
            )
        }

        return texture
    }
}
