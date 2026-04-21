import Metal
import simd

public final class MotionBlurMaterial: Material {
    public unowned var colorTexture: MTLTexture? {
        didSet { set(colorTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var velocityTexture: MTLTexture? {
        didSet { set(velocityTexture, index: FragmentTextureIndex.Custom1) }
    }

    public var strength: Float {
        get { get("Strength", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Strength", newValue) }
    }

    public var samples: Int32 {
        get { get("Samples", as: IntParameter.self).map { Int32($0.value) } ?? 16 }
        set { set("Samples", Int(newValue)) }
    }

    public init(context: Context, colorTexture: MTLTexture? = nil, velocityTexture: MTLTexture? = nil) {
        self.colorTexture = colorTexture
        self.velocityTexture = velocityTexture
        super.init(context: context)
        configure()
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
        if get("Strength") == nil { set("Strength", Float(1.0)) }
        if get("Samples") == nil { set("Samples", 16) }
        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(velocityTexture, index: FragmentTextureIndex.Custom1)
    }
}
