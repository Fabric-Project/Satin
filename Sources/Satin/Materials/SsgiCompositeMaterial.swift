import Metal

public final class SsgiCompositeMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var colorTexture: MTLTexture? {
        didSet { set(colorTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var ssgiTexture: MTLTexture? {
        didSet { set(ssgiTexture, index: FragmentTextureIndex.Custom1) }
    }

    public var giIntensity: Float {
        get { get("GI Intensity", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("GI Intensity", newValue) }
    }

    public var aoIntensity: Float {
        get { get("AO Intensity", as: FloatParameter.self)?.value ?? 0.35 }
        set { set("AO Intensity", newValue) }
    }

    public var aoLift: Float {
        get { get("AO Lift", as: FloatParameter.self)?.value ?? 0.2 }
        set { set("AO Lift", newValue) }
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

        if get("GI Intensity") == nil {
            parameters.append(FloatParameter("GI Intensity", 1.0, 0.0, 4.0, .slider, "Scales the indirect diffuse contribution."))
        }
        if get("AO Intensity") == nil {
            parameters.append(FloatParameter("AO Intensity", 0.35, 0.0, 1.0, .slider, "Scales the ambient-occlusion darkening."))
        }
        if get("AO Lift") == nil {
            parameters.append(FloatParameter("AO Lift", 0.2, 0.0, 1.0, .slider, "Minimum visibility preserved after AO darkening."))
        }

        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(ssgiTexture, index: FragmentTextureIndex.Custom1)
    }
}
