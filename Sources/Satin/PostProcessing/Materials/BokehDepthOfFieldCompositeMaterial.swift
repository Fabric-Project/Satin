import Metal

public final class BokehDepthOfFieldCompositeMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public var colorTexture: MTLTexture? {
        get { texture(at: .Custom0) }
        set { set(newValue, index: FragmentTextureIndex.Custom0) }
    }

    public var cocTexture: MTLTexture? {
        get { texture(at: .Custom1) }
        set { set(newValue, index: FragmentTextureIndex.Custom1) }
    }

    public var farRTexture: MTLTexture? {
        get { texture(at: .Custom2) }
        set { set(newValue, index: FragmentTextureIndex.Custom2) }
    }

    public var farGTexture: MTLTexture? {
        get { texture(at: .Custom3) }
        set { set(newValue, index: FragmentTextureIndex.Custom3) }
    }

    public var farBTexture: MTLTexture? {
        get { texture(at: .Custom4) }
        set { set(newValue, index: FragmentTextureIndex.Custom4) }
    }

    public var nearRTexture: MTLTexture? {
        get { texture(at: .Custom5) }
        set { set(newValue, index: FragmentTextureIndex.Custom5) }
    }

    public var nearGTexture: MTLTexture? {
        get { texture(at: .Custom6) }
        set { set(newValue, index: FragmentTextureIndex.Custom6) }
    }

    public var nearBTexture: MTLTexture? {
        get { texture(at: .Custom7) }
        set { set(newValue, index: FragmentTextureIndex.Custom7) }
    }

    public var nearCoCTexture: MTLTexture? {
        get { texture(at: .Custom8) }
        set { set(newValue, index: FragmentTextureIndex.Custom8) }
    }

    public var farWeightsTexture: MTLTexture? {
        get { texture(at: .Custom9) }
        set { set(newValue, index: FragmentTextureIndex.Custom9) }
    }

    public var nearCoCBoxTexture: MTLTexture? {
        get { texture(at: .Custom10) }
        set { set(newValue, index: FragmentTextureIndex.Custom10) }
    }

    public var maxBlurRadius: Float {
        get { get("Max Radius", as: FloatParameter.self)?.value ?? 6.0 }
        set { set("Max Radius", newValue) }
    }

    public var blend: Float {
        get { get("Blend", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Blend", newValue) }
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

        if get("Max Radius") == nil { set("Max Radius", Float(6.0)) }
        if get("Blend") == nil { set("Blend", Float(1.0)) }

        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(cocTexture, index: FragmentTextureIndex.Custom1)
        set(farRTexture, index: FragmentTextureIndex.Custom2)
        set(farGTexture, index: FragmentTextureIndex.Custom3)
        set(farBTexture, index: FragmentTextureIndex.Custom4)
        set(nearRTexture, index: FragmentTextureIndex.Custom5)
        set(nearGTexture, index: FragmentTextureIndex.Custom6)
        set(nearBTexture, index: FragmentTextureIndex.Custom7)
        set(nearCoCTexture, index: FragmentTextureIndex.Custom8)
        set(farWeightsTexture, index: FragmentTextureIndex.Custom9)
        set(nearCoCBoxTexture, index: FragmentTextureIndex.Custom10)
    }
}
