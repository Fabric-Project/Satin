import Metal

/// After the jump flood: across each tile's 3x3 neighborhood, the pointer whose mover has
/// the longest motion.
public final class MotionBlurNeighborMaxMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var tileMaxTexture: MTLTexture? {
        didSet { set(tileMaxTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var jumpFloodTexture: MTLTexture? {
        didSet { set(jumpFloodTexture, index: FragmentTextureIndex.Custom1) }
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
        set(tileMaxTexture, index: FragmentTextureIndex.Custom0)
        set(jumpFloodTexture, index: FragmentTextureIndex.Custom1)
    }
}
