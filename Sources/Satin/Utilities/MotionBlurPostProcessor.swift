//
//  MotionBlurPostProcessor.swift
//  Satin
//

import CoreFoundation
import Metal
import MetalKit

open class MotionBlurPostProcessor: PostProcessor {
    // MARK: - Inputs

    public var colorTexture: MTLTexture? {
        didSet { motionBlurMaterial.colorTexture = colorTexture }
    }

    public var velocityTexture: MTLTexture? {
        didSet { motionBlurMaterial.velocityTexture = velocityTexture }
    }

    // MARK: - Output

    public private(set) var outputTexture: MTLTexture?
    private var outputTextureSize: (width: Int, height: Int) = (0, 0)

    // MARK: - Owned internals

    public let motionBlurMaterial: MotionBlurMaterial
    private let colorPixelFormat: MTLPixelFormat
    private var blueNoiseTexture: MTLTexture?
    private var frameCounter: Int32 = 0
    private var lastDrawTime: CFAbsoluteTime = 0

    // MARK: - Init

    public required init(context: Context) {
        // Pipeline must not expect a depth attachment — use a depth-free context.
        let blurContext = Context(device: context.device, sampleCount: 1, colorPixelFormat: context.colorPixelFormat)
        colorPixelFormat = context.colorPixelFormat
        motionBlurMaterial = MotionBlurMaterial(context: blurContext)
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
        updateDeltaTime()
        motionBlurMaterial.blueNoiseTexture = blueNoiseTexture
        motionBlurMaterial.frame = frameCounter
        frameCounter = frameCounter &+ 1
        super.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer, renderTarget: outputTexture)
    }

    // MARK: - Helpers

    private func updateDeltaTime() {
        let now = CFAbsoluteTimeGetCurrent()
        motionBlurMaterial.deltaTime = lastDrawTime > 0 ? Float(now - lastDrawTime) : Float(1.0 / 60.0)
        lastDrawTime = now
    }

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
