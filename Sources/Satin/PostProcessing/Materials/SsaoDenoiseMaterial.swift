import Metal
import simd

public final class SsaoDenoiseMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    private struct Uniforms {
        var inverseProjectionMatrix: simd_float4x4
        var viewMatrix: simd_float4x4
        var radius: Float
        var depthPhi: Float
        var normalPhi: Float
        var _padding: Float
    }

    private lazy var uniformsBuffer = StructBuffer<Uniforms>(
        device: context.device,
        count: 1,
        label: "SSAO Denoise Uniforms"
    )

    private var inverseProjectionMatrix = matrix_identity_float4x4
    private var viewMatrix = matrix_identity_float4x4
    private var uniformsNeedUpdate = true

    public unowned var aoTexture: MTLTexture? {
        didSet { set(aoTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom2) }
    }

    public unowned var blueNoiseTexture: MTLTexture? {
        didSet { set(blueNoiseTexture, index: FragmentTextureIndex.Custom3) }
    }

    public var quality: Int32 = 2 {
        didSet { uniformsNeedUpdate = true }
    }

    public var aoRadius: Float = 0.75 {
        didSet { uniformsNeedUpdate = true }
    }

    public required init(context: Context) {
        super.init(context: context)
        configure()
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        configure()
    }

    private func configure() {
        blending = .disabled
        depthWriteEnabled = false
        depthCompareFunction = .always
        set(uniformsBuffer, index: FragmentBufferIndex.Custom0)
        set(aoTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
        set(normalTexture, index: FragmentTextureIndex.Custom2)
        set(blueNoiseTexture, index: FragmentTextureIndex.Custom3)
    }

    public func update(camera: Camera) {
        inverseProjectionMatrix = camera.projectionMatrix.inverse
        viewMatrix = camera.viewMatrix
        uniformsNeedUpdate = true
    }

    override public func update() {
        if uniformsNeedUpdate {
            uniformsBuffer.update(data: [Uniforms(
                inverseProjectionMatrix: inverseProjectionMatrix,
                viewMatrix: viewMatrix,
                radius: filterRadius(for: quality),
                depthPhi: max(aoRadius * 0.5, 0.05),
                normalPhi: 32.0,
                _padding: 0.0
            )])
            uniformsNeedUpdate = false
        }

        super.update()
    }

    private func filterRadius(for quality: Int32) -> Float {
        switch max(1, min(quality, 3)) {
        case 1:
            return 2.5
        case 2:
            return 4.0
        default:
            return 5.5
        }
    }
}
