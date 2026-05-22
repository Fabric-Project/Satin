import Metal

final class SeparablePostProcessEncoder {
    enum Pass {
        case horizontal
        case vertical
    }

    private let label: String
    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let horizontalProcessor: PostProcessEncoder
    private let verticalProcessor: PostProcessEncoder

    private(set) var outputTexture: MTLTexture?
    private var intermediateTexture: MTLTexture?
    private var textureSize: (width: Int, height: Int) = (0, 0)

    init(
        label: String,
        context: Context,
        horizontalMaterial: Material,
        verticalMaterial: Material? = nil
    ) {
        self.label = label
        device = context.device
        pixelFormat = context.colorPixelFormat
        horizontalProcessor = PostProcessEncoder(
            label: label + " Horizontal",
            context: context,
            material: horizontalMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
        verticalProcessor = PostProcessEncoder(
            label: label + " Vertical",
            context: context,
            material: verticalMaterial ?? horizontalMaterial,
            depthLoadAction: .dontCare,
            depthStoreAction: .dontCare
        )
    }

    func resize(size: (width: Float, height: Float), resolutionScale: Float) {
        let width = Int(max((size.width * resolutionScale).rounded(.up), 0.0))
        let height = Int(max((size.height * resolutionScale).rounded(.up), 0.0))

        guard width > 0, height > 0 else {
            textureSize = (0, 0)
            intermediateTexture = nil
            outputTexture = nil
            return
        }

        let scaledSize = (width: Float(width), height: Float(height))
        horizontalProcessor.resize(size: scaledSize, scaleFactor: 1.0)
        verticalProcessor.resize(size: scaledSize, scaleFactor: 1.0)

        guard textureSize.width != width || textureSize.height != height else { return }

        intermediateTexture = makeTexture(width: width, height: height, label: label + " Intermediate")
        outputTexture = makeTexture(width: width, height: height, label: label + " Output")
        textureSize = (width, height)
    }

    func draw(
        commandBuffer: MTLCommandBuffer,
        inputTexture: MTLTexture,
        configurePass: (Pass, MTLTexture) -> Void
    ) {
        guard let intermediateTexture, let outputTexture else { return }

        configurePass(.horizontal, inputTexture)
        horizontalProcessor.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: intermediateTexture
        )

        configurePass(.vertical, intermediateTexture)
        verticalProcessor.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            renderTarget: outputTexture
        )
    }

    private func makeTexture(width: Int, height: Int, label: String) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.sampleCount = 1
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }
}
