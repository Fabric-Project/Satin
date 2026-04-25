import Metal
import simd

public final class BokehDepthOfFieldCompositeMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public unowned var colorTexture: MTLTexture? {
        didSet { set(colorTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var farBlurTexture: MTLTexture? {
        didSet { set(farBlurTexture, index: FragmentTextureIndex.Custom2) }
    }

    public unowned var nearBlurTexture: MTLTexture? {
        didSet { set(nearBlurTexture, index: FragmentTextureIndex.Custom3) }
    }

    public var inverseProjectionMatrix: simd_float4x4 {
        get { get("Inverse Projection Matrix", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("Inverse Projection Matrix", newValue) }
    }

    public var focusDistance: Float {
        get { get("Focus Distance", as: FloatParameter.self)?.value ?? 4.0 }
        set { set("Focus Distance", newValue) }
    }

    public var focusRange: Float {
        get { get("Focus Range", as: FloatParameter.self)?.value ?? 1.5 }
        set { set("Focus Range", newValue) }
    }

    public var maxBlurRadius: Float {
        get { get("Max Blur Radius", as: FloatParameter.self)?.value ?? 12.0 }
        set { set("Max Blur Radius", newValue) }
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
        if get("Focus Distance") == nil { set("Focus Distance", Float(4.0)) }
        if get("Focus Range") == nil { set("Focus Range", Float(1.5)) }
        if get("Max Blur Radius") == nil { set("Max Blur Radius", Float(12.0)) }

        set(colorTexture, index: FragmentTextureIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom1)
        set(farBlurTexture, index: FragmentTextureIndex.Custom2)
        set(nearBlurTexture, index: FragmentTextureIndex.Custom3)
    }

    public func update(camera: Camera) {
        inverseProjectionMatrix = camera.projectionMatrix.inverse
    }
}
