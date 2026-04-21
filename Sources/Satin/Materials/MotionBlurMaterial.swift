import Metal
import simd

public final class MotionBlurMaterial: Material {
    private static let shutterAngleRange: ClosedRange<Float> = 0.0 ... 720.0
    private static let defaultShutterAngle: Float = 180.0
    private static let legacyDefaultDeltaTime: Float = 1.0 / 60.0

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

    public var shutterAngle: Float {
        get { get("Shutter Angle", as: FloatParameter.self)?.value ?? Self.defaultShutterAngle }
        set {
            let clamped = clampShutterAngle(newValue)
            if let param = get("Shutter Angle", as: FloatParameter.self) {
                param.value = clamped
            }
        }
    }

    public var samples: Int32 {
        get { get("Samples", as: IntParameter.self).map { Int32($0.value) } ?? 16 }
        set { set("Samples", Int(newValue)) }
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
        let orderedParameters = ParameterGroup()
        orderedParameters.append(
            FloatParameter(
                "Shutter Angle",
                resolveShutterAngle(),
                Self.shutterAngleRange.lowerBound,
                Self.shutterAngleRange.upperBound,
                .slider,
                "Exposure as degrees of one frame interval. 180 degrees is standard; values above 360 are stylized."
            )
        )
        orderedParameters.append(IntParameter("Samples", get("Samples", as: IntParameter.self)?.value ?? 16, 1, 32))
        orderedParameters.append(FloatParameter("Jitter", get("Jitter", as: FloatParameter.self)?.value ?? 1.0, 0.0, 1.0, .slider))
        orderedParameters.append(IntParameter("Frame", get("Frame", as: IntParameter.self)?.value ?? 0))
        parameters.setFrom(orderedParameters, setValues: true, setOptions: true, setControls: true)

        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(velocityTexture, index: FragmentTextureIndex.Custom1)
        set(blueNoiseTexture, index: FragmentTextureIndex.Custom2)
        set(depthTexture, index: FragmentTextureIndex.Custom3)
    }

    private func resolveShutterAngle() -> Float {
        if let shutterAngle = get("Shutter Angle", as: FloatParameter.self)?.value {
            return clampShutterAngle(shutterAngle)
        }

        if let legacyStrength = get("Strength", as: FloatParameter.self)?.value {
            let legacyDeltaTime = max(get("Delta Time", as: FloatParameter.self)?.value ?? Self.legacyDefaultDeltaTime, 1e-4)
            return clampShutterAngle((legacyStrength / legacyDeltaTime) * 360.0)
        }

        return Self.defaultShutterAngle
    }

    private func clampShutterAngle(_ value: Float) -> Float {
        min(max(value, Self.shutterAngleRange.lowerBound), Self.shutterAngleRange.upperBound)
    }
}
