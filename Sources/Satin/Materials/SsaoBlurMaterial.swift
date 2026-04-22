import Metal

public final class SsaoBlurMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var ssaoTexture: MTLTexture? {
        didSet { set(ssaoTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    public var sharpness: Float {
        get { get("Sharpness", as: FloatParameter.self)?.value ?? 10.0 }
        set { set("Sharpness", newValue) }
    }

    public var blurRadius: Int32 {
        get { get("Blur Radius", as: IntParameter.self).map { Int32($0.value) } ?? 2 }
        set { set("Blur Radius", Int(newValue)) }
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
        if get("Sharpness") == nil { set("Sharpness", Float(10.0)) }
        if get("Blur Radius") == nil { set("Blur Radius", 2) }
        set(ssaoTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
    }
}
