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

        let orderedParameters = ParameterGroup()
        orderedParameters.append(
            FloatParameter(
                "Intensity",
                get("Intensity", as: FloatParameter.self)?.value ?? 1.0,
                0.0,
                2.0,
                .slider,
                "Strength of the ambient-occlusion darkening."
            )
        )
        parameters.setFrom(orderedParameters, setValues: true, setOptions: true, setControls: true)
        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(aoTexture, index: FragmentTextureIndex.Custom1)
    }
}
