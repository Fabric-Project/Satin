import Metal
import simd

public final class SsaoMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    private struct Uniforms {
        var projectionMatrix: simd_float4x4
        var inverseProjectionMatrix: simd_float4x4
        var viewMatrix: simd_float4x4
        var radius: Float
        var bias: Float
        var sampleCount: Int32
        var _padding: Int32
    }

    private lazy var uniformsBuffer = StructBuffer<Uniforms>(
        device: context.device,
        count: 1,
        label: "SSAO Uniforms"
    )

    private var projectionMatrix = matrix_identity_float4x4
    private var inverseProjectionMatrix = matrix_identity_float4x4
    private var viewMatrix = matrix_identity_float4x4
    private var uniformsNeedUpdate = true

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var blueNoiseTexture: MTLTexture? {
        didSet { set(blueNoiseTexture, index: FragmentTextureIndex.Custom2) }
    }

    public var radius: Float {
        get { get("Radius", as: FloatParameter.self)?.value ?? 0.75 }
        set {
            set("Radius", newValue)
            uniformsNeedUpdate = true
        }
    }

    public var quality: Int32 {
        get { get("Quality", as: IntParameter.self).map { Int32($0.value) } ?? 2 }
        set {
            set("Quality", Int(newValue))
            uniformsNeedUpdate = true
        }
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
        depthWriteEnabled = false
        depthCompareFunction = .always

        let orderedParameters = ParameterGroup()
        orderedParameters.append(
            FloatParameter(
                "Radius",
                get("Radius", as: FloatParameter.self)?.value ?? 0.75,
                0.05,
                3.0,
                .slider,
                "View-space occlusion radius."
            )
        )
        orderedParameters.append(
            IntParameter(
                "Quality",
                get("Quality", as: IntParameter.self)?.value ?? 2,
                1,
                3,
                .slider
            )
        )
        parameters.setFrom(orderedParameters, setValues: true, setOptions: true, setControls: true)

        set(uniformsBuffer, index: FragmentBufferIndex.Custom0)
        set(depthTexture, index: FragmentTextureIndex.Custom0)
        set(normalTexture, index: FragmentTextureIndex.Custom1)
        set(blueNoiseTexture, index: FragmentTextureIndex.Custom2)
    }

    public func update(camera: Camera) {
        projectionMatrix = camera.projectionMatrix
        inverseProjectionMatrix = camera.projectionMatrix.inverse
        viewMatrix = camera.viewMatrix
        uniformsNeedUpdate = true
    }

    override public func update() {
        if uniformsNeedUpdate {
            uniformsBuffer.update(data: [Uniforms(
                projectionMatrix: projectionMatrix,
                inverseProjectionMatrix: inverseProjectionMatrix,
                viewMatrix: viewMatrix,
                radius: radius,
                bias: max(0.01, min(radius * 0.05, 0.05)),
                sampleCount: sampleCount(for: quality),
                _padding: 0
            )])
            uniformsNeedUpdate = false
        }

        super.update()
    }

    private func sampleCount(for quality: Int32) -> Int32 {
        switch max(1, min(quality, 3)) {
        case 1:
            return 8
        case 2:
            return 12
        default:
            return 16
        }
    }
}
