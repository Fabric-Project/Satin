//
//  StandardMaterial.swift
//  Satin
//
//  Created by Reza Ali on 11/5/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import ModelIO
import simd

open class StandardMaterial: Material {
    override open var lightingModel: LightingModel { .surface }
    override open var supportedOutputs: RendererOutputs { [.color, .albedo, .normals, .pbr, .velocity, .emissive] }
    override var supportsAlphaOrderIndependentTransparency: Bool { true }
    public var baseColor: simd_float4 {
        get {
            get("Base Color", as: Float4Parameter.self)!.value
        }
        set {
            set("Base Color", newValue)
        }
    }

    public var emissiveColor: simd_float4 {
        get {
            get("Emissive Color", as: Float4Parameter.self)!.value
        }
        set {
            set("Emissive Color", newValue)
        }
    }

    public var specular: Float {
        get {
            get("Specular", as: FloatParameter.self)!.value
        }
        set {
            set("Specular", newValue)
        }
    }

    public var metallic: Float {
        get {
            get("Metallic", as: FloatParameter.self)!.value
        }
        set {
            set("Metallic", newValue)
        }
    }

    public var roughness: Float {
        get {
            get("Roughness", as: FloatParameter.self)!.value
        }
        set {
            set("Roughness", newValue)
        }
    }

    public var occlusion: Float {
        get {
            get("Occlusion", as: FloatParameter.self)!.value
        }
        set {
            set("Occlusion", newValue)
        }
    }

    public var environmentIntensity: Float {
        get {
            get("Environment Intensity", as: FloatParameter.self)!.value
        }
        set {
            set("Environment Intensity", newValue)
        }
    }

    public var gammaCorrection: Float {
        get {
            get("Gamma Correction", as: FloatParameter.self)!.value
        }
        set {
            set("Gamma Correction", newValue)
        }
    }

    public var pointSize: Float {
        get { get("Point Size", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Point Size", newValue) }
    }

    /// The texture for each map, indexed by `PBRTextureType.index`.
    private var maps = [MTLTexture?](repeating: nil, count: PBRTextureType.count) {
        didSet {
            if pbrSlotPresenceDiffers(oldValue, maps), let shader = shader as? PBRShader {
                shader.maps = maps
            }
        }
    }

    /// The sampler for each map, indexed by `PBRTextureType.index`.
    private var samplers = [MTLSamplerDescriptor?](repeating: nil, count: PBRTextureType.count) {
        didSet {
            if pbrSlotPresenceDiffers(oldValue, samplers), let shader = shader as? PBRShader {
                shader.samplers = samplers
            }
        }
    }

    public var tonemapping: Tonemapping = .aces {
        didSet {
            if oldValue != tonemapping, let shader = shader as? PBRShader {
                shader.tonemapping = tonemapping
            }
        }
    }

    public func setTexture(_ texture: MTLTexture?, type: PBRTextureType) {
        let index = type.index
        if let texture = texture {
            // Setting the texture a map already holds changes nothing; the renderer re-applies the
            // environment maps every frame.
            if maps[index] === texture { return }
            maps[index] = texture
            setTextureMultiplierUniformToOne(type: type)
            if samplers[index] == nil {
                let sampler = MTLSamplerDescriptor()
                sampler.minFilter = .linear
                sampler.magFilter = .linear
                sampler.mipFilter = .linear
                sampler.rAddressMode = .repeat
                sampler.sAddressMode = .repeat
                sampler.tAddressMode = .repeat
                setSampler(sampler, type: type)
            }
        } else {
            samplers[index] = nil
            maps[index] = nil
        }
    }

    public func setSampler(_ sampler: MTLSamplerDescriptor?, type: PBRTextureType) {
        samplers[type.index] = sampler
    }

    public func setTextureTransform(_ transform: simd_float4x4, type: PBRTextureType) {
        set(type.texcoordParameterName, transform)
    }

    public func setTexcoordTransform(_ transform: simd_float4x4, type: PBRTextureType) {
        setTextureTransform(transform, type: type)
    }

    public func setTexcoordTransform(_ transform: simd_float3x3, type: PBRTextureType) {
        setTextureTransform(simd_float4x4(textureTransform: transform), type: type)
    }

    public func setTexcoordTransform(offset: simd_float2, scale: simd_float2, rotation: Float, type: PBRTextureType) {
        setTextureTransform(.textureTransform(offset: offset, scale: scale, rotation: rotation), type: type)
    }

    public init(context: Context, baseColor: simd_float4 = .one,
                metallic: Float = 0.0,
                roughness: Float = 0.2,
                specular: Float = 0.5,
                occlusion: Float = 1.0,
                emissiveColor: simd_float4 = .zero,
                maps: [PBRTextureType: MTLTexture?] = [:])
    {
        super.init(context: context)
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.specular = specular
        self.occlusion = occlusion
        self.emissiveColor = emissiveColor
        var slots = [MTLTexture?](repeating: nil, count: PBRTextureType.count)
        for (type, texture) in maps {
            slots[type.index] = texture
        }
        self.maps = slots
        lighting = true
        blending = .disabled
        initalize()
    }

    func initalize() {
        initalizeTexcoordParameters()
    }

    func initalizeTexcoordParameters() {
        for type in PBRTextureType.allTexcoordCases {
            if get(type.texcoordParameterName) == nil {
                set(type.texcoordParameterName, matrix_identity_float4x4)
            }
        }
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        lighting = true
        blending = .disabled
        initalize()
    }

    public required init(context: Context) {
        super.init(context: context)
        self.baseColor = .one
        self.metallic = 0.0
        self.roughness = 0.2
        self.specular = 0.5
        self.occlusion = 1.0
        self.emissiveColor = .zero
        lighting = true
        blending = .disabled
        initalize()
    }

    override open func setupShaderRenderingConfiguration(_ shader: Shader) {
        super.setupShaderRenderingConfiguration(shader)
        guard let pbrShader = shader as? PBRShader else { return }
        pbrShader.maps = maps
        pbrShader.samplers = samplers
        pbrShader.tonemapping = tonemapping
    }

    override open func createShader() -> Shader {
        StandardShader(context: context, label: label, pipelineURL: getPipelinesMaterialsURL(label)!.appendingPathComponent("Shaders.metal"))
    }

    override open func draw(in context: MaterialDrawContext) {
        super.draw(in: context)
        if !context.isShadowPass {
            for (index, texture) in maps.enumerated() where texture != nil {
                context.setFragmentPBRTexture(texture, type: PBRTextureType.orderedCases[index])
            }
        }
    }

    /// This function is called when a valid PBR texture is set.
    /// This allows users to scale the texture values by the uniform values.
    /// When this function is called, the value is set to one to ensure
    /// the texture values value aren't scaled to zero by the uniform
    func setTextureMultiplierUniformToOne(type: PBRTextureType) {
        switch type {
            case .baseColor:
                baseColor = .one
            case .subsurface:
                break
            case .metallic:
                metallic = 1.0
            case .roughness:
                roughness = 1.0
            case .normal:
                break
            case .emissive:
                emissiveColor = .one
            case .specular:
                specular = 1.0
            case .specularTint:
                break
            case .sheen:
                break
            case .sheenTint:
                break
            case .clearcoat:
                break
            case .clearcoatRoughness:
                break
            case .clearcoatGloss:
                break
            case .anisotropic:
                break
            case .anisotropicAngle:
                break
            case .bump:
                break
            case .displacement:
                break
            case .alpha:
                baseColor.w = 1.0
            case .ior:
                break
            case .transmission:
                break
            case .occlusion:
                occlusion = 1.0
            case .reflection:
                break
            case .irradiance:
                break
            case .brdf:
                break
        }
    }
}
