import Metal
import simd

public final class SsaoPrefilterMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    private struct Uniforms {
        var inverseProjectionMatrix: simd_float4x4
    }

    private lazy var uniformsBuffer = StructBuffer<Uniforms>(
        device: context.device,
        count: 1,
        label: "SSAO Prefilter Uniforms"
    )

    private var inverseProjectionMatrix = matrix_identity_float4x4
    private var uniformsNeedUpdate = true

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom0) }
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
        set(depthTexture, index: FragmentTextureIndex.Custom0)
    }

    public func update(camera: Camera) {
        inverseProjectionMatrix = camera.projectionMatrix.inverse
        uniformsNeedUpdate = true
    }

    override public func update() {
        if uniformsNeedUpdate {
            uniformsBuffer.update(data: [Uniforms(inverseProjectionMatrix: inverseProjectionMatrix)])
            uniformsNeedUpdate = false
        }

        super.update()
    }
}
