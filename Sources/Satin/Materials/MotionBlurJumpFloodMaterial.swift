import Metal

/// One jump-flood pass of motion blur velocity dilation: each tile keeps a pointer to the
/// front-most tile whose motion trail covers it.
public final class MotionBlurJumpFloodMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var tileMaxTexture: MTLTexture? {
        didSet { set(tileMaxTexture, index: FragmentTextureIndex.Custom0) }
    }

    /// The previous pass's pointers; unused on the first pass, which seeds from tile max.
    public unowned var previousTexture: MTLTexture? {
        didSet { set(previousTexture, index: FragmentTextureIndex.Custom1) }
    }

    /// Distance to the neighbors this pass checks, in tiles.
    public var stepSize: Int {
        get { get("Step Size", as: IntParameter.self)?.value ?? 1 }
        set { set("Step Size", newValue) }
    }

    public var isFirstPass: Bool {
        get { (get("Is First Pass", as: IntParameter.self)?.value ?? 0) != 0 }
        set { set("Is First Pass", newValue ? 1 : 0) }
    }

    /// Fraction of a frame's motion the shutter captures; bounds how far trails reach.
    public var shutterFraction: Float {
        get { get("Shutter Fraction", as: FloatParameter.self)?.value ?? 0.5 }
        set { set("Shutter Fraction", newValue) }
    }

    /// How far off a mover's line a tile may sit and still count, relative to its motion.
    public var perpendicularTolerance: Float {
        get { get("Perpendicular Tolerance", as: FloatParameter.self)?.value ?? 0.5 }
        set { set("Perpendicular Tolerance", newValue) }
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
        orderedParameters.append(IntParameter("Step Size", get("Step Size", as: IntParameter.self)?.value ?? 1))
        orderedParameters.append(IntParameter("Is First Pass", get("Is First Pass", as: IntParameter.self)?.value ?? 0))
        orderedParameters.append(FloatParameter("Shutter Fraction", get("Shutter Fraction", as: FloatParameter.self)?.value ?? 0.5))
        orderedParameters.append(FloatParameter("Perpendicular Tolerance", get("Perpendicular Tolerance", as: FloatParameter.self)?.value ?? 0.5))
        parameters.setFrom(orderedParameters, setValues: true, setOptions: true, setControls: true)
        set(tileMaxTexture, index: FragmentTextureIndex.Custom0)
        set(previousTexture, index: FragmentTextureIndex.Custom1)
    }
}
