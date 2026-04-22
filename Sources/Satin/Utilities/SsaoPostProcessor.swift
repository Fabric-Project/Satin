//
//  SsaoPostProcessor.swift
//  Satin
//

import Metal

/// Two-pass SSAO: raw ambient-occlusion followed by a depth-aware bilateral blur.
/// Requires `Renderer.activeOutputs` to include `.normals`.
open class SsaoPostProcessor: PostProcessor {
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

    public var sceneCamera: Camera?

    // MARK: - Output

    public private(set) var outputTexture: MTLTexture?
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)

    // MARK: - Materials

    public let ssaoMaterial: SsaoMaterial
    public let blurMaterial: SsaoBlurMaterial

    // MARK: - Internals

    private let blurProcessor: PostProcessor
    private var rawTexture: MTLTexture?
    private var rawTextureSize: (width: Int, height: Int) = (0, 0)

    // MARK: - Init

    private static func makeSsaoContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: .r8Unorm)
    }

    public required init(context: Context) {
        let ssaoContext = SsaoPostProcessor.makeSsaoContext(context: context)
        ssaoMaterial = SsaoMaterial(context: ssaoContext)
        blurMaterial = SsaoBlurMaterial(context: ssaoContext)
        blurProcessor = PostProcessor(
            label: "SSAO Blur",
            context: ssaoContext,
            material: blurMaterial,
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
        super.resize(size: size, scaleFactor: scaleFactor)
        blurProcessor.resize(size: size, scaleFactor: scaleFactor)

        let w = Int(max(size.width, 0)), h = Int(max(size.height, 0))
        guard w > 0, h > 0 else {
            rawTexture = nil
            outputTexture = nil
            rawTextureSize = (0, 0)
            outputTextureSize = (0, 0)
            return
        }

        if rawTextureSize.width != w || rawTextureSize.height != h {
            rawTexture = makeAOTexture(device: context.device, width: w, height: h, label: "SSAO Raw")
            rawTextureSize = (w, h)
        }

        if outputTextureSize.width != w || outputTextureSize.height != h {
            outputTexture = makeAOTexture(device: context.device, width: w, height: h, label: "SSAO Output")
            outputTextureSize = (w, h)
        }
    }

    // MARK: - Draw

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard let rawTexture, let outputTexture else { return }

        if let cam = sceneCamera { ssaoMaterial.update(camera: cam) }

        // Pass 1 — raw SSAO into intermediate texture
        super.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: rawTexture
        )

        // Pass 2 — bilateral blur into final output texture
        blurMaterial.ssaoTexture = rawTexture
        blurProcessor.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: outputTexture
        )
    }

    // MARK: - Helpers

    private func makeAOTexture(device: MTLDevice, width: Int, height: Int, label: String) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let tex = device.makeTexture(descriptor: descriptor)
        tex?.label = label
        return tex
    }
}
