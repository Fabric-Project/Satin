import Metal
import simd

public final class MotionBlurMaterial: Material {
    public unowned var colorTexture: MTLTexture? {
        didSet { set(colorTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var velocityTexture: MTLTexture? {
        didSet { set(velocityTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var blueNoiseTexture: MTLTexture? {
        didSet { set(blueNoiseTexture, index: FragmentTextureIndex.Custom2) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom3) }
    }

    public var strength: Float {
        get { get("Strength", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Strength", newValue) }
    }

    public var samples: Int32 {
        get { get("Samples", as: IntParameter.self).map { Int32($0.value) } ?? 16 }
        set { set("Samples", Int(newValue)) }
    }

    public var deltaTime: Float {
        get { get("Delta Time", as: FloatParameter.self)?.value ?? (1.0 / 60.0) }
        set { set("Delta Time", newValue) }
    }

    public var jitter: Float {
        get { get("Jitter", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Jitter", newValue) }
    }

    public var frame: Int32 {
        get { get("Frame", as: IntParameter.self).map { Int32($0.value) } ?? 0 }
        set { set("Frame", Int(newValue)) }
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
        if get("Delta Time") == nil { set("Delta Time", Float(1.0 / 60.0)) }
        if get("Jitter") == nil { set("Jitter", Float(1.0)) }
        if get("Frame") == nil { set("Frame", 0) }
        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(velocityTexture, index: FragmentTextureIndex.Custom1)
        set(blueNoiseTexture, index: FragmentTextureIndex.Custom2)
        set(depthTexture, index: FragmentTextureIndex.Custom3)
    }
}
