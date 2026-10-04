import Metal
import simd

public final class MotionBlurMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }
    private struct MotionBlurUniformPayload: Equatable {
        var shutterAngle: Float
        var samples: Int32
        var jitter: Float
        var frame: Int32
    }

    private static let shutterAngleRange: ClosedRange<Float> = 0.0 ... (720.0 * 64)
    private static let defaultShutterAngle: Float = 180.0
    private static let legacyDefaultDeltaTime: Float = 1.0 / 60.0
    private static let uniformLayoutLabels = ["Shutter Angle", "Samples", "Jitter", "Frame"]
    private static let uniformLayoutSize = MemoryLayout<MotionBlurUniformPayload>.size
    private static let uniformLayoutAlignment = MemoryLayout<MotionBlurUniformPayload>.alignment

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

    /// Per tile, a pointer (UV) into `tileMaxTexture` at the mover whose trail covers it.
    public unowned var neighborMaxTexture: MTLTexture? {
        didSet { set(neighborMaxTexture, index: FragmentTextureIndex.Custom4) }
    }

    /// Longest velocity per tile, read through `neighborMaxTexture`.
    public unowned var tileMaxTexture: MTLTexture? {
        didSet { set(tileMaxTexture, index: FragmentTextureIndex.Custom5) }
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

    /// Longest blur in pixels: the reach of the jump-flood dilation. Set by
    /// `MotionBlurPostProcessEncoder`.
    public var maxBlurRadius: Float {
        get { get("Max Blur Radius", as: FloatParameter.self)?.value ?? 144 }
        set { set("Max Blur Radius", newValue) }
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
        orderedParameters.append(FloatParameter("Max Blur Radius", get("Max Blur Radius", as: FloatParameter.self)?.value ?? 144))
        parameters.setFrom(orderedParameters, setValues: true, setOptions: true, setControls: true)

        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(velocityTexture, index: FragmentTextureIndex.Custom1)
        set(blueNoiseTexture, index: FragmentTextureIndex.Custom2)
        set(depthTexture, index: FragmentTextureIndex.Custom3)
        set(neighborMaxTexture, index: FragmentTextureIndex.Custom4)
        set(tileMaxTexture, index: FragmentTextureIndex.Custom5)
    }

    override public func updateUniforms() {
        super.updateUniforms()
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

    private func makeUniformPayload() -> MotionBlurUniformPayload {
        MotionBlurUniformPayload(
            shutterAngle: shutterAngle,
            samples: samples,
            jitter: jitter,
            frame: frame
        )
    }
}
