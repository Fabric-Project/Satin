import Metal

/// Longest velocity per tile, with the depth where it was found; the input to the motion
/// blur jump-flood dilation.
public final class MotionBlurTileMaxMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var velocityTexture: MTLTexture? {
        didSet { set(velocityTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    /// Velocity texels per tile along each axis.
    public var tileSize: Int {
        get { get("Tile Size", as: IntParameter.self)?.value ?? 32 }
        set { set("Tile Size", newValue) }
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
        let orderedParameters = ParameterGroup()
        orderedParameters.append(IntParameter("Tile Size", get("Tile Size", as: IntParameter.self)?.value ?? 32))
        parameters.setFrom(orderedParameters, setValues: true, setOptions: true, setControls: true)
        set(velocityTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
    }
}
