import Metal
import simd

public final class SsaoBlurMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    private struct BlurPassUniforms {
        var direction: simd_float2
    }

    private lazy var passUniformsBuffer = StructBuffer<BlurPassUniforms>(
        device: context.device,
        count: 1,
        label: "SSAO Blur Pass Uniforms"
    )
    private var passUniformsNeedUpdate = true

    public unowned var ssaoTexture: MTLTexture? {
        didSet { set(ssaoTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom2) }
    }

    public var depthPhi: Float {
        get { get("Depth Phi", as: FloatParameter.self)?.value ?? 0.1 }
        set { set("Depth Phi", newValue) }
    }

    public var normalPhi: Float {
        get { get("Normal Phi", as: FloatParameter.self)?.value ?? 8.0 }
        set { set("Normal Phi", newValue) }
    }

    public var blurRadius: Int32 {
        get { get("Blur Radius", as: IntParameter.self).map { Int32($0.value) } ?? 4 }
        set { set("Blur Radius", Int(newValue)) }
    }

    var direction: simd_float2 = simd_float2(1.0, 0.0) {
        didSet { passUniformsNeedUpdate = true }
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
        if get("Inverse Projection Matrix") == nil { set("Inverse Projection Matrix", matrix_identity_float4x4) }
        if get("View Matrix") == nil { set("View Matrix", matrix_identity_float4x4) }
        if get("Depth Phi") == nil { set("Depth Phi", Float(0.1)) }
        if get("Normal Phi") == nil { set("Normal Phi", Float(8.0)) }
        if get("Blur Radius") == nil { set("Blur Radius", 4) }
        set(passUniformsBuffer, index: FragmentBufferIndex.Custom0)
        set(ssaoTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
        set(normalTexture, index: FragmentTextureIndex.Custom2)
    }

    public func update(camera: Camera) {
        set("Inverse Projection Matrix", camera.projectionMatrix.inverse)
        set("View Matrix", camera.viewMatrix)
    }

    override public func update() {
        if passUniformsNeedUpdate {
            passUniformsBuffer.update(data: [BlurPassUniforms(direction: direction)])
            passUniformsNeedUpdate = false
        }
        super.update()
    }
}
