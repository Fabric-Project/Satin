import Metal
import simd

public final class SsgiMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var colorTexture: MTLTexture? {
        didSet { set(colorTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom2) }
    }

    public unowned var albedoTexture: MTLTexture? {
        didSet { set(albedoTexture, index: FragmentTextureIndex.Custom3) }
    }

    public unowned var pbrTexture: MTLTexture? {
        didSet { set(pbrTexture, index: FragmentTextureIndex.Custom4) }
    }

    public var projectionMatrix: simd_float4x4 {
        get { get("Projection Matrix", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("Projection Matrix", newValue) }
    }

    public var inverseProjectionMatrix: simd_float4x4 {
        get { get("Inverse Projection Matrix", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("Inverse Projection Matrix", newValue) }
    }

    public var viewMatrix: simd_float4x4 {
        get { get("View Matrix", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("View Matrix", newValue) }
    }

    public var radius: Float {
        get { get("Radius", as: FloatParameter.self)?.value ?? 12.0 }
        set { set("Radius", newValue) }
    }

    public var thickness: Float {
        get { get("Thickness", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Thickness", newValue) }
    }

    public var expFactor: Float {
        get { get("Distribution Exponent", as: FloatParameter.self)?.value ?? 2.0 }
        set { set("Distribution Exponent", newValue) }
    }

    public var jitterStrength: Float {
        get { get("Jitter Strength", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Jitter Strength", newValue) }
    }

    public var halfProjectionScale: Float {
        get { get("Half Projection Scale", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Half Projection Scale", newValue) }
    }

    public var sliceCount: Int32 {
        get { get("Slice Count", as: IntParameter.self).map { Int32($0.value) } ?? 3 }
        set { set("Slice Count", Int(newValue)) }
    }

    public var stepCount: Int32 {
        get { get("Step Count", as: IntParameter.self).map { Int32($0.value) } ?? 8 }
        set { set("Step Count", Int(newValue)) }
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

        if get("Projection Matrix") == nil { set("Projection Matrix", matrix_identity_float4x4) }
        if get("Inverse Projection Matrix") == nil { set("Inverse Projection Matrix", matrix_identity_float4x4) }
        if get("View Matrix") == nil { set("View Matrix", matrix_identity_float4x4) }
        if get("Radius") == nil {
            parameters.append(
                FloatParameter(
                    "Radius",
                    12.0,
                    1.0,
                    25.0,
                    .slider,
                    "Effective sampling radius in world space."
                )
            )
        }
        if get("Thickness") == nil {
            parameters.append(
                FloatParameter(
                    "Thickness",
                    1.0,
                    0.01,
                    10.0,
                    .slider,
                    "Constant world-space thickness used to reject screen-space leaks."
                )
            )
        }
        if get("Distribution Exponent") == nil {
            parameters.append(
                FloatParameter(
                    "Distribution Exponent",
                    2.0,
                    1.0,
                    3.0,
                    .slider,
                    "Biases more samples toward the current pixel when increased."
                )
            )
        }
        if get("Jitter Strength") == nil {
            parameters.append(
                FloatParameter(
                    "Jitter Strength",
                    1.0,
                    0.0,
                    1.0,
                    .slider,
                    "Offsets sample positions along each slice to trade banding for denoisable noise."
                )
            )
        }
        if get("Half Projection Scale") == nil { set("Half Projection Scale", Float(1.0)) }
        if get("Slice Count") == nil {
            parameters.append(IntParameter("Slice Count", 3, 1, 4, .slider, "Angular sampling slices across the hemisphere."))
        }
        if get("Step Count") == nil {
            parameters.append(IntParameter("Step Count", 8, 1, 32, .slider, "Steps traced along each slice direction."))
        }

        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
        set(normalTexture, index: FragmentTextureIndex.Custom2)
        set(albedoTexture, index: FragmentTextureIndex.Custom3)
        set(pbrTexture, index: FragmentTextureIndex.Custom4)
    }

    public func update(camera: Camera, viewportHeight: Float) {
        projectionMatrix = camera.renderSnapshotProjectionMatrix
        inverseProjectionMatrix = camera.renderSnapshotProjectionMatrix.inverse
        viewMatrix = camera.renderSnapshotViewMatrix

        if let perspectiveCamera = camera as? PerspectiveCamera {
            let fovRadians = perspectiveCamera.fov * (.pi / 180.0)
            let denominator = max(tan(fovRadians * 0.5) * 4.0, 1.0e-4)
            halfProjectionScale = viewportHeight / denominator
        } else {
            halfProjectionScale = viewportHeight * 0.5
        }
    }
}
