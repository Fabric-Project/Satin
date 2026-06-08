//
//  SsaoPostProcessEncoder.swift
//  Satin
//

import Metal
import MetalKit
import simd

/// XeGTAO-inspired SSAO pipeline:
/// 1. prefilter hardware depth into a linear view-space depth buffer
/// 2. generate raw AO from linear depth + normals
/// 3. denoise AO with edge-aware blue-noise-rotated filtering
/// 4. composite AO over the color buffer
///
/// Public controls stay intentionally narrow: radius, quality, intensity, and resolution scale.
open class SsaoPostProcessEncoder: PostProcessEncoder {
    private static let defaultResolutionScale: Float = 0.5
    private static let minResolutionScale: Float = 0.25
    private static let maxResolutionScale: Float = 1.0

    public var depthTexture: MTLTexture? {
        didSet { prefilterMaterial.depthTexture = depthTexture }
    }

    public var normalTexture: MTLTexture? {
        didSet {
            ssaoMaterial.normalTexture = normalTexture
            denoiseMaterial.normalTexture = normalTexture
        }
    }

    public var colorTexture: MTLTexture? {
        didSet { compositeMaterial.colorTexture = colorTexture }
    }

    public var sceneCamera: Camera?

    public let parameters: ParameterGroup = ParameterGroup("SSAO", [
        FloatParameter(
            "Radius",
            0.75,
            0.05,
            3.0,
            .slider,
            "View-space radius used for ambient occlusion sampling."
        ),
        IntParameter(
            "Quality",
            2,
            1,
            3,
            .slider
        ),
        FloatParameter(
            "Intensity",
            1.0,
            0.0,
            2.0,
            .slider,
            "Strength of the ambient-occlusion darkening."
        ),
        FloatParameter(
            "Resolution Scale",
            defaultResolutionScale,
            minResolutionScale,
            maxResolutionScale,
            .slider,
            "Internal SSAO resolution relative to the main color buffer."
        ),
    ])

    public var radius: Float {
        get { parameters.get("Radius", as: FloatParameter.self)?.value ?? 0.75 }
        set { parameters.get("Radius", as: FloatParameter.self)?.value = newValue }
    }

    public var quality: Int32 {
        get { parameters.get("Quality", as: IntParameter.self).map { Int32($0.value) } ?? 2 }
        set { parameters.get("Quality", as: IntParameter.self)?.value = Int(newValue) }
    }

    public var intensity: Float {
        get { parameters.get("Intensity", as: FloatParameter.self)?.value ?? 1.0 }
        set { parameters.get("Intensity", as: FloatParameter.self)?.value = newValue }
    }

    public var resolutionScale: Float {
        get { parameters.get("Resolution Scale", as: FloatParameter.self)?.value ?? Self.defaultResolutionScale }
        set {
            let clamped = Self.clampResolutionScale(newValue)
            guard let param = parameters.get("Resolution Scale", as: FloatParameter.self) else { return }
            guard param.value != clamped else { return }
            param.value = clamped
            resizeResources()
        }
    }

    public private(set) var aoTexture: MTLTexture?
    public private(set) var outputTexture: MTLTexture?

    public let prefilterMaterial: SsaoPrefilterMaterial
    public let ssaoMaterial: SsaoMaterial
    public let denoiseMaterial: SsaoDenoiseMaterial
    public let compositeMaterial: SsaoCompositeMaterial

    private let prefilterProcessor: PostProcessEncoder
    private let denoiseProcessor: PostProcessEncoder
    private let compositeProcessor: PostProcessEncoder
    private var linearDepthTexture: MTLTexture?
    private var rawTexture: MTLTexture?
    private var denoisedTexture: MTLTexture?
    private var linearDepthTextureSize: (width: Int, height: Int) = (0, 0)
    private var rawTextureSize: (width: Int, height: Int) = (0, 0)
    private var denoisedTextureSize: (width: Int, height: Int) = (0, 0)
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)
    private var lastSize: (width: Float, height: Float) = (0, 0)
    private var whiteAOTexture: MTLTexture?
    private var blueNoiseTexture: MTLTexture?
    private var appliedResolutionScale: Float = 0.5

    private static func clampResolutionScale(_ value: Float) -> Float {
        min(max(value, Self.minResolutionScale), Self.maxResolutionScale)
    }

    private static func makeDepthContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: .r16Float)
    }

    private static func makeAoContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: .r8Unorm)
    }

    private static func makeCompositeContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: context.colorPixelFormat)
    }

    public required init(context: Context) {
        let depthContext = Self.makeDepthContext(context: context)
        let aoContext = Self.makeAoContext(context: context)
        let compositeContext = Self.makeCompositeContext(context: context)

        prefilterMaterial = SsaoPrefilterMaterial(context: depthContext)
        ssaoMaterial = SsaoMaterial(context: aoContext)
        denoiseMaterial = SsaoDenoiseMaterial(context: aoContext)
        compositeMaterial = SsaoCompositeMaterial(context: compositeContext)

        prefilterProcessor = PostProcessEncoder(
            label: "SSAO Prefilter",
            context: depthContext,
            material: prefilterMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )

        denoiseProcessor = PostProcessEncoder(
            label: "SSAO Denoise",
            context: aoContext,
            material: denoiseMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
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
            context: aoContext,
            material: ssaoMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )

        blueNoiseTexture = loadBlueNoiseTexture(device: context.device) ?? makeFallbackBlueNoiseTexture(device: context.device)
        ssaoMaterial.blueNoiseTexture = blueNoiseTexture
        denoiseMaterial.blueNoiseTexture = blueNoiseTexture
    }

    override open func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        lastSize = size
        compositeProcessor.resize(size: size, scaleFactor: scaleFactor)
        resizeResources()
    }

    private func resizeResources() {
        appliedResolutionScale = resolutionScale
        let scaledWidth = Int(max((lastSize.width * resolutionScale).rounded(.up), 0.0))
        let scaledHeight = Int(max((lastSize.height * resolutionScale).rounded(.up), 0.0))
        let scaledSize = (width: Float(scaledWidth), height: Float(scaledHeight))

        prefilterProcessor.resize(size: scaledSize, scaleFactor: 1.0)
        super.resize(size: scaledSize, scaleFactor: 1.0)
        denoiseProcessor.resize(size: scaledSize, scaleFactor: 1.0)

        aoTexture = nil

        if scaledWidth > 0, scaledHeight > 0 {
            if linearDepthTextureSize.width != scaledWidth || linearDepthTextureSize.height != scaledHeight {
                linearDepthTexture = makeTexture(
                    device: prefilterProcessor.context.device,
                    width: scaledWidth,
                    height: scaledHeight,
                    pixelFormat: .r16Float,
                    usage: [.renderTarget, .shaderRead],
                    storageMode: .private,
                    label: "SSAO Linear Depth"
                )
                linearDepthTextureSize = (scaledWidth, scaledHeight)
            }

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

            if denoisedTextureSize.width != scaledWidth || denoisedTextureSize.height != scaledHeight {
                denoisedTexture = makeTexture(
                    device: denoiseProcessor.context.device,
                    width: scaledWidth,
                    height: scaledHeight,
                    pixelFormat: .r8Unorm,
                    usage: [.renderTarget, .shaderRead],
                    storageMode: .private,
                    label: "SSAO Denoised"
                )
                denoisedTextureSize = (scaledWidth, scaledHeight)
            }
        } else {
            linearDepthTexture = nil
            linearDepthTextureSize = (0, 0)
            rawTexture = nil
            rawTextureSize = (0, 0)
            denoisedTexture = nil
            denoisedTextureSize = (0, 0)
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

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        syncMaterialParameters()

        let hasAOInputs = depthTexture != nil &&
            normalTexture != nil &&
            linearDepthTexture != nil &&
            rawTexture != nil &&
            denoisedTexture != nil &&
            sceneCamera != nil

        aoTexture = hasAOInputs ? denoisedTexture : nil

        if hasAOInputs,
           let linearDepthTexture,
           let rawTexture,
           let denoisedTexture,
           let sceneCamera
        {
            prefilterMaterial.update(camera: sceneCamera)
            ssaoMaterial.depthTexture = linearDepthTexture
            ssaoMaterial.update(camera: sceneCamera)
            denoiseMaterial.depthTexture = linearDepthTexture
            denoiseMaterial.update(camera: sceneCamera)

            prefilterProcessor.draw(
                renderPassDescriptor: MTLRenderPassDescriptor(),
                commandBuffer: commandBuffer,
                renderTarget: linearDepthTexture
            )

            super.draw(
                renderPassDescriptor: MTLRenderPassDescriptor(),
                commandBuffer: commandBuffer,
                renderTarget: rawTexture
            )

            denoiseMaterial.aoTexture = rawTexture
            denoiseProcessor.draw(
                renderPassDescriptor: MTLRenderPassDescriptor(),
                commandBuffer: commandBuffer,
                renderTarget: denoisedTexture
            )
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

    private func syncMaterialParameters() {
        let desiredResolutionScale = Self.clampResolutionScale(resolutionScale)
        if desiredResolutionScale != appliedResolutionScale {
            parameters.get("Resolution Scale", as: FloatParameter.self)?.value = desiredResolutionScale
            resizeResources()
        }

        ssaoMaterial.radius = radius
        ssaoMaterial.quality = quality
        denoiseMaterial.aoRadius = radius
        denoiseMaterial.quality = quality
        compositeMaterial.intensity = intensity
    }

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

    private func makeFallbackBlueNoiseTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "SSAO Fallback Blue Noise"

        let pixel: [UInt8] = [128, 192, 255, 64]
        pixel.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: pixel.count
            )
        }

        return texture
    }
}
