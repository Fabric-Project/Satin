import Metal
import simd

public final class SsaoMaterial: Material {
    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom1) }
    }

    public var radius: Float {
        get { get("Radius", as: FloatParameter.self)?.value ?? 0.5 }
        set { set("Radius", newValue) }
    }

    public var bias: Float {
        get { get("Bias", as: FloatParameter.self)?.value ?? 0.025 }
        set { set("Bias", newValue) }
    }

    public var kernelSize: Int32 {
        get { get("Kernel Size", as: IntParameter.self).map { Int32($0.value) } ?? 16 }
        set { set("Kernel Size", Int(newValue)) }
    }

    public init(context: Context, depthTexture: MTLTexture? = nil, normalTexture: MTLTexture? = nil) {
        self.depthTexture = depthTexture
        self.normalTexture = normalTexture
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
        if get("Radius") == nil { set("Radius", Float(0.5)) }
        if get("Bias") == nil { set("Bias", Float(0.025)) }
        if get("Kernel Size") == nil { set("Kernel Size", 16) }
        set(depthTexture, index: FragmentTextureIndex.Custom0)
        set(normalTexture, index: FragmentTextureIndex.Custom1)
    }

    public func update(camera: Camera) {
        set("Projection Matrix", camera.projectionMatrix)
        set("Inverse Projection Matrix", camera.projectionMatrix.inverse)
        set("View Matrix", camera.viewMatrix)
    }
}
