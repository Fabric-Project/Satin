import Metal
import simd

public final class BokehDepthOfFieldNearMaxMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    private struct PassUniforms {
        var direction: simd_float2
    }

    private lazy var passUniformsBuffer = StructBuffer<PassUniforms>(
        device: context.device,
        count: 1,
        label: "Bokeh DOF Near Max Pass Uniforms"
    )
    private var passUniformsNeedUpdate = true

    public unowned var radiusTexture: MTLTexture? {
        didSet { set(radiusTexture, index: FragmentTextureIndex.Custom0) }
    }

    public var maxRadius: Int32 {
        get { get("Max Radius", as: IntParameter.self).map { Int32($0.value) } ?? 8 }
        set { set("Max Radius", Int(newValue)) }
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

        if get("Max Radius") == nil { set("Max Radius", 8) }

        set(passUniformsBuffer, index: FragmentBufferIndex.Custom0)
        set(radiusTexture, index: FragmentTextureIndex.Custom0)
    }

    override public func update() {
        if passUniformsNeedUpdate {
            passUniformsBuffer.update(data: [PassUniforms(direction: direction)])
            passUniformsNeedUpdate = false
        }
        super.update()
    }
}
