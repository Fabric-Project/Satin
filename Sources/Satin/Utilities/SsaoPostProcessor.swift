//
//  SsaoPostProcessor.swift
//  Satin
//

import Metal

open class SsaoPostProcessor: PostProcessor {
    // MARK: - Inputs

    public var depthTexture: MTLTexture? {
        didSet { ssaoMaterial.depthTexture = depthTexture }
    }

    public var normalTexture: MTLTexture? {
        didSet { ssaoMaterial.normalTexture = normalTexture }
    }

    // Scene camera needed for projection/view uniforms
    public var sceneCamera: Camera?

    // MARK: - Output

    public private(set) var outputTexture: MTLTexture?
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)

    // MARK: - Owned internals

    public let ssaoMaterial: SsaoMaterial

    private static func makeSsaoContext(context: Context) -> Context {
        Context(device: context.device, sampleCount: 1, colorPixelFormat: .r8Unorm)
    }

    // MARK: - Init

    public required init(context: Context) {
        let ssaoContext = SsaoPostProcessor.makeSsaoContext(context: context)
        ssaoMaterial = SsaoMaterial(context: ssaoContext)
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
        let w = Int(size.width), h = Int(size.height)
        if outputTextureSize.width != w || outputTextureSize.height != h {
            outputTexture = makeOutputTexture(device: context.device, width: w, height: h)
            outputTextureSize = (w, h)
        }
    }

    // MARK: - Draw

    override open func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard let outputTexture else { return }
        if let cam = sceneCamera { ssaoMaterial.update(camera: cam) }
        super.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, renderTarget: outputTexture)
    }

    // MARK: - Helpers

    private func makeOutputTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let tex = device.makeTexture(descriptor: descriptor)
        tex?.label = label + " Output"
        return tex
    }
}
