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

    public var sharpness: Float {
        get { get("Sharpness", as: FloatParameter.self)?.value ?? 500.0 }
        set { set("Sharpness", newValue) }
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
        if get("Sharpness") == nil { set("Sharpness", Float(500.0)) }
        if get("Blur Radius") == nil { set("Blur Radius", 4) }
        set(passUniformsBuffer, index: FragmentBufferIndex.Custom0)
        set(ssaoTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
    }

    override public func update() {
        if passUniformsNeedUpdate {
            passUniformsBuffer.update(data: [BlurPassUniforms(direction: direction)])
            passUniformsNeedUpdate = false
        }
        super.update()
    }
}
