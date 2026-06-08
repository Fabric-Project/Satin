import Metal

public final class BokehDepthOfFieldCompositeMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var colorTexture: MTLTexture? {
        didSet { set(colorTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var cocTexture: MTLTexture? {
        didSet { set(cocTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var farRTexture: MTLTexture? {
        didSet { set(farRTexture, index: FragmentTextureIndex.Custom2) }
    }

    public unowned var farGTexture: MTLTexture? {
        didSet { set(farGTexture, index: FragmentTextureIndex.Custom3) }
    }

    public unowned var farBTexture: MTLTexture? {
        didSet { set(farBTexture, index: FragmentTextureIndex.Custom4) }
    }

    public unowned var nearRTexture: MTLTexture? {
        didSet { set(nearRTexture, index: FragmentTextureIndex.Custom5) }
    }

    public unowned var nearGTexture: MTLTexture? {
        didSet { set(nearGTexture, index: FragmentTextureIndex.Custom6) }
    }

    public unowned var nearBTexture: MTLTexture? {
        didSet { set(nearBTexture, index: FragmentTextureIndex.Custom7) }
    }

    public unowned var nearCoCTexture: MTLTexture? {
        didSet { set(nearCoCTexture, index: FragmentTextureIndex.Custom8) }
    }

    public unowned var farWeightsTexture: MTLTexture? {
        didSet { set(farWeightsTexture, index: FragmentTextureIndex.Custom9) }
    }

    public unowned var nearCoCBoxTexture: MTLTexture? {
        didSet { set(nearCoCBoxTexture, index: FragmentTextureIndex.Custom10) }
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
