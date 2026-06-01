import Metal

public final class SsaoCompositeMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var colorTexture: MTLTexture? {
        didSet { set(colorTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var aoTexture: MTLTexture? {
        didSet { set(aoTexture, index: FragmentTextureIndex.Custom1) }
    }

    public var intensity: Float {
        get { get("Intensity", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Intensity", newValue) }
    }

    public var lift: Float {
        get { get("Lift", as: FloatParameter.self)?.value ?? 0.0 }
        set { set("Lift", newValue) }
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
        if get("Intensity") == nil { set("Intensity", Float(1.0)) }
        if get("Lift") == nil { set("Lift", Float(0.0)) }
        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(aoTexture, index: FragmentTextureIndex.Custom1)
    }
}
