import Metal
import simd

private final class DeferredLightingShader: StandardShader {
    override func getDefines() -> [ShaderDefine] {
        var results = super.getDefines()
        if directShadowCount > 0, directShadowTextureCount > 0 {
            results.append(ShaderDefine(key: "HAS_SHADOWS", value: NSString(string: "true")))
        }
        return results
    }
}

public final class DeferredLightingMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }
    override public var supportedOutputs: RendererOutputs { [.color] }

    public unowned var albedoTexture: MTLTexture? {
        didSet { set(albedoTexture, index: FragmentTextureIndex.Custom0) }
    }

    public unowned var normalTexture: MTLTexture? {
        didSet { set(normalTexture, index: FragmentTextureIndex.Custom1) }
    }

    public unowned var pbrTexture: MTLTexture? {
        didSet { set(pbrTexture, index: FragmentTextureIndex.Custom2) }
    }

    public unowned var emissiveTexture: MTLTexture? {
        didSet { set(emissiveTexture, index: FragmentTextureIndex.Custom3) }
    }

    public unowned var depthTexture: MTLTexture? {
        didSet { set(depthTexture, index: FragmentTextureIndex.Custom4) }
    }

    public var reflectionTexture: MTLTexture? {
        didSet { setEnvironmentTexture(reflectionTexture, type: .reflection) }
    }

    public var irradianceTexture: MTLTexture? {
        didSet { setEnvironmentTexture(irradianceTexture, type: .irradiance) }
    }

    public var brdfTexture: MTLTexture? {
        didSet { setEnvironmentTexture(brdfTexture, type: .brdf) }
    }

    public var environmentIntensity: Float {
        get { get("Environment Intensity", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Environment Intensity", newValue) }
    }

    public var gammaCorrection: Float {
        get { get("Gamma Correction", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Gamma Correction", newValue) }
    }

    public var specular: Float {
        get { get("Specular", as: FloatParameter.self)?.value ?? 0.5 }
        set { set("Specular", newValue) }
    }

    public var inverseProjectionMatrix: simd_float4x4 {
        get { get("Inverse Projection Matrix", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("Inverse Projection Matrix", newValue) }
    }

    public var inverseViewMatrix: simd_float4x4 {
        get { get("Inverse View Matrix", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("Inverse View Matrix", newValue) }
    }

    public var reflectionTexcoordTransform: simd_float4x4 {
        get { get("Reflection Texcoord Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("Reflection Texcoord Transform", newValue) }
    }

    public var irradianceTexcoordTransform: simd_float4x4 {
        get { get("Irradiance Texcoord Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4 }
        set { set("Irradiance Texcoord Transform", newValue) }
    }

    public var worldCameraPosition: simd_float4 {
        get { get("World Camera Position", as: Float4Parameter.self)?.value ?? .zero }
        set { set("World Camera Position", newValue) }
    }

    public var tonemapping: Tonemapping = .aces {
        didSet {
            if oldValue != tonemapping, let shader = shader as? PBRShader {
                shader.tonemapping = tonemapping
            }
        }
    }

    private var maps = [MTLTexture?](repeating: nil, count: PBRTextureType.allCases.count) {
        didSet {
            let activeSetChanged = zip(oldValue, maps).contains { ($0 == nil) != ($1 == nil) }
            if activeSetChanged, let shader = shader as? PBRShader {
                shader.maps = maps
            }
        }
    }

    private var samplers: [PBRTextureType: MTLSamplerDescriptor?] = [:] {
        didSet {
            if oldValue.keys != samplers.keys, let shader = shader as? PBRShader {
                shader.samplers = samplers.filter { $0.value != nil }
            }
        }
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
        lighting = true
        receiveShadow = false
        blending = .disabled
        depthWriteEnabled = false
        depthCompareFunction = .always

        if get("Environment Intensity") == nil { set("Environment Intensity", Float(1.0)) }
        if get("Gamma Correction") == nil { set("Gamma Correction", Float(1.0)) }
        if get("Specular") == nil { set("Specular", Float(0.5)) }
        if get("Inverse Projection Matrix") == nil { set("Inverse Projection Matrix", matrix_identity_float4x4) }
        if get("Inverse View Matrix") == nil { set("Inverse View Matrix", matrix_identity_float4x4) }
        if get("Reflection Texcoord Transform") == nil { set("Reflection Texcoord Transform", matrix_identity_float4x4) }
        if get("Irradiance Texcoord Transform") == nil { set("Irradiance Texcoord Transform", matrix_identity_float4x4) }
        if get("World Camera Position") == nil { set("World Camera Position", simd_float4(0, 0, 0, 1)) }

        set(albedoTexture, index: FragmentTextureIndex.Custom0)
        set(normalTexture, index: FragmentTextureIndex.Custom1)
        set(pbrTexture, index: FragmentTextureIndex.Custom2)
        set(emissiveTexture, index: FragmentTextureIndex.Custom3)
        set(depthTexture, index: FragmentTextureIndex.Custom4)
    }

    public func update(camera: Camera) {
        inverseProjectionMatrix = camera.projectionMatrix.inverse
        inverseViewMatrix = camera.viewMatrix.inverse
        worldCameraPosition = simd_float4(camera.worldPosition, 1.0)
    }

    override public func createShader() -> Shader {
        DeferredLightingShader(
            context: context,
            label: label,
            pipelineURL: getPipelinesMaterialsURL(label)!.appendingPathComponent("Shaders.metal")
        )
    }

    override public func setupShaderRenderingConfiguration(_ shader: Shader) {
        super.setupShaderRenderingConfiguration(shader)
        guard let pbrShader = shader as? PBRShader else { return }
        pbrShader.maps = maps
        pbrShader.samplers = samplers.filter { $0.value != nil }
        pbrShader.tonemapping = tonemapping
    }

    override public func bind(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        super.bind(renderContext: renderContext, renderEncoderState: renderEncoderState, shadow: shadow)
        if !shadow {
            for i in maps.indices {
                if let texture = maps[i] {
                    renderEncoderState.setFragmentPBRTexture(texture, index: i)
                }
            }
        }
    }

    private func setEnvironmentTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        if let texture {
            maps[type.index] = texture
            if samplers[type] == nil {
                let sampler = MTLSamplerDescriptor()
                sampler.minFilter = .linear
                sampler.magFilter = .linear
                sampler.mipFilter = .linear
                samplers[type] = sampler
            }
        } else {
            maps[type.index] = nil
            samplers.removeValue(forKey: type)
        }
    }
}
