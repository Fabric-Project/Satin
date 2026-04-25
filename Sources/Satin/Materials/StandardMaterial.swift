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

    private var maps: [PBRTextureType: MTLTexture?] = [:] {
        didSet {
            if oldValue.keys != maps.keys, let shader = shader as? PBRShader {
                shader.maps = maps
            }
        }
    }

    private var samplers: [PBRTextureType: MTLSamplerDescriptor?] = [:] {
        didSet {
            if oldValue.keys != samplers.keys, let shader = shader as? PBRShader {
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
        if let texture = texture {
            maps[type] = texture
            setTextureMultiplierUniformToOne(type: type)
            if samplers[type] == nil {
                let sampler = MTLSamplerDescriptor()
                sampler.minFilter = .linear
                sampler.magFilter = .linear
                sampler.mipFilter = .linear
                setSampler(sampler, type: type)
            }
        } else {
            samplers.removeValue(forKey: type)
            maps.removeValue(forKey: type)
        }
    }

    public func setSampler(_ sampler: MTLSamplerDescriptor?, type: PBRTextureType) {
        if let sampler = sampler {
            samplers[type] = sampler
        } else {
            samplers.removeValue(forKey: type)
        }
    }

    public func setTexcoordTransform(_ transform: simd_float3x3, type: PBRTextureType) {
        set(type.texcoordName.titleCase, transform)
    }

    public func setTexcoordTransform(offset: simd_float2, scale: simd_float2, rotation: Float, type: PBRTextureType) {
        let ct = cos(rotation)
        let st = sin(rotation)

        let rotateTransform = simd_float3x3(
            simd_make_float3(ct, st, 0.0),
            simd_make_float3(-st, ct, 0.0),
            simd_make_float3(0.0, 0.0, 0.0)
        )

        let offsetTransform = simd_float3x3(
            simd_make_float3(1.0, 0.0, 0.0),
            simd_make_float3(0.0, 1.0, 0.0),
            simd_make_float3(offset.x, offset.y, 0.0)
        )

        let scaleTransform = simd_float3x3(
            simd_make_float3(scale.x, 0.0, 0.0),
            simd_make_float3(0.0, scale.y, 0.0),
            simd_make_float3(0.0, 0.0, 0.0)
        )

        let transform = rotateTransform * scaleTransform * offsetTransform
        set(type.texcoordName.titleCase, transform)
    }

    public init(baseColor: simd_float4 = .one,
                metallic: Float = 0.0,
                roughness: Float = 0.2,
                specular: Float = 0.5,
                occlusion: Float = 1.0,
                emissiveColor: simd_float4 = .zero,
                maps: [PBRTextureType: MTLTexture?] = [:])
    {
        super.init()
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.specular = specular
        self.occlusion = occlusion
        self.emissiveColor = emissiveColor
        self.maps = maps
        lighting = true
        blending = .disabled
        initalize()
    }

    func initalize() {
        initalizeTexcoordParameters()
    }

    func initalizeTexcoordParameters() {
        for type in PBRTextureType.allTexcoordCases {
            set(type.texcoordName.titleCase, matrix_identity_float3x3)
        }
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        lighting = true
        blending = .disabled
    }

    public required init() {
        super.init()
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
        pbrShader.maps = maps.filter { $0.value != nil }
        pbrShader.samplers = samplers.filter { $0.value != nil }
        pbrShader.tonemapping = tonemapping
    }

    override open func createShader() -> Shader {
        StandardShader(label: label, pipelineURL: getPipelinesMaterialsURL(label)!.appendingPathComponent("Shaders.metal"))
    }

    override open func bind(renderContext: Context, renderEncoderState: RenderEncoderState, shadow: Bool) {
        super.bind(renderContext: renderContext, renderEncoderState: renderEncoderState, shadow: shadow)
        if !shadow {
            for (type, texture) in maps {
                renderEncoderState.setFragmentPBRTexture(texture, type: type)
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
