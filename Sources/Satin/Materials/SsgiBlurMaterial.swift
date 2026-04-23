import Metal
import simd

public final class SsgiBlurMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    private struct BlurPassUniforms {
        var direction: simd_float2
    }

    private lazy var passUniformsBuffer = StructBuffer<BlurPassUniforms>(
        device: context.device,
        count: 1,
        label: "SSGI Blur Pass Uniforms"
    )
    private var passUniformsNeedUpdate = true

    public unowned var ssgiTexture: MTLTexture? {
        didSet { set(ssgiTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom2) }
    }

    public var blurStrength: Float {
        get { get("Blur Strength", as: FloatParameter.self)?.value ?? 0.65 }
        set { set("Blur Strength", newValue) }
    }

    public var depthSharpness: Float {
        get { get("Depth Sharpness", as: FloatParameter.self)?.value ?? 500.0 }
        set { set("Depth Sharpness", newValue) }
    }

    public var normalSharpness: Float {
        get { get("Normal Sharpness", as: FloatParameter.self)?.value ?? 32.0 }
        set { set("Normal Sharpness", newValue) }
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

        if get("Blur Strength") == nil {
            parameters.append(
                FloatParameter(
                    "Blur Strength",
                    0.65,
                    0.0,
                    1.0,
                    .slider,
                    "Scales the bilateral denoise radius."
                )
            )
        }
        if get("Depth Sharpness") == nil {
            parameters.append(
                FloatParameter(
                    "Depth Sharpness",
                    500.0,
                    1.0,
                    2000.0,
                    .slider,
                    "Higher values preserve depth edges more aggressively."
                )
            )
        }
        if get("Normal Sharpness") == nil {
            parameters.append(
                FloatParameter(
                    "Normal Sharpness",
                    32.0,
                    1.0,
                    128.0,
                    .slider,
                    "Higher values preserve normal edges more aggressively."
                )
            )
        }

        set(passUniformsBuffer, index: FragmentBufferIndex.Custom0)
        set(ssgiTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
        set(normalTexture, index: FragmentTextureIndex.Custom2)
    }

    override public func update() {
        if passUniformsNeedUpdate {
            passUniformsBuffer.update(data: [BlurPassUniforms(direction: direction)])
            passUniformsNeedUpdate = false
        }
        super.update()
    }
}
