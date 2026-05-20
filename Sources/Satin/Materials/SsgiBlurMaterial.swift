import Metal
import simd

public final class SsgiBlurMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var ssgiTexture: MTLTexture? {
        didSet { set(ssgiTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom2) }
    }

    public unowned var blueNoiseTexture: MTLTexture? {
        didSet { set(blueNoiseTexture, index: FragmentTextureIndex.Custom3) }
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
        get { get("Denoise Radius", as: FloatParameter.self)?.value ?? 4.0 }
        set { set("Denoise Radius", newValue) }
    }

    public var lumaPhi: Float {
        get { get("Luma Phi", as: FloatParameter.self)?.value ?? 5.0 }
        set { set("Luma Phi", newValue) }
    }

    public var depthPhi: Float {
        get { get("Depth Phi", as: FloatParameter.self)?.value ?? 5.0 }
        set { set("Depth Phi", newValue) }
    }

    public var normalPhi: Float {
        get { get("Normal Phi", as: FloatParameter.self)?.value ?? 5.0 }
        set { set("Normal Phi", newValue) }
    }

    public var noiseIndex: Int32 {
        get { get("Noise Index", as: IntParameter.self).map { Int32($0.value) } ?? 0 }
        set { set("Noise Index", Int(newValue)) }
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

        if get("Inverse Projection Matrix") == nil { set("Inverse Projection Matrix", matrix_identity_float4x4) }
        if get("View Matrix") == nil { set("View Matrix", matrix_identity_float4x4) }
        if get("Denoise Radius") == nil {
            parameters.append(
                FloatParameter(
                    "Denoise Radius",
                    4.0,
                    1.0,
                    16.0,
                    .slider,
                    "Radius of the rotated Poisson denoise kernel in low-resolution SSGI texels."
                )
            )
        }
        if get("Luma Phi") == nil {
            parameters.append(
                FloatParameter(
                    "Luma Phi",
                    5.0,
                    0.1,
                    20.0,
                    .slider,
                    "Tolerance for luminance variation between neighboring SSGI samples."
                )
            )
        }
        if get("Depth Phi") == nil {
            parameters.append(
                FloatParameter(
                    "Depth Phi",
                    5.0,
                    0.1,
                    20.0,
                    .slider,
                    "Tolerance for view-space depth variation along the center normal."
                )
            )
        }
        if get("Normal Phi") == nil {
            parameters.append(
                FloatParameter(
                    "Normal Phi",
                    5.0,
                    0.1,
                    64.0,
                    .slider,
                    "Exponent used to preserve normal discontinuities during denoising."
                )
            )
        }
        if get("Noise Index") == nil { set("Noise Index", 0) }

        set(ssgiTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
        set(normalTexture, index: FragmentTextureIndex.Custom2)
        set(blueNoiseTexture, index: FragmentTextureIndex.Custom3)
    }

    public func update(camera: Camera) {
        inverseProjectionMatrix = camera.renderProjectionMatrix.inverse
        viewMatrix = camera.renderViewMatrix
    }
}
