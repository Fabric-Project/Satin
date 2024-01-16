//
//  PhysicalMaterial.swift
//  Satin
//
//  Created by Reza Ali on 01/6/23.
//  Copyright © 2023 Reza Ali. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import ModelIO
import simd

open class PhysicalMaterial: StandardMaterial {
    public var subsurface: Float {
        get {
            (get("Subsurface") as? FloatParameter)!.value
        }
        set {
            set("Subsurface", newValue)
        }
    }

    public var anisotropic: Float {
        get {
            (get("Anisotropic") as? FloatParameter)!.value
        }
        set {
            set("Anisotropic", newValue)
        }
    }

    public var anisotropicAngle: Float {
        get {
            (get("Anisotropic Angle") as? FloatParameter)!.value
        }
        set {
            set("Anisotropic Angle", newValue)
        }
    }

    public var specularTint: Float {
        get {
            (get("Specular Tint") as? FloatParameter)!.value
        }
        set {
            set("Specular Tint", newValue)
        }
    }

    public var clearcoat: Float {
        get {
            (get("Clearcoat") as? FloatParameter)!.value
        }
        set {
            set("Clearcoat", newValue)
        }
    }

    public var clearcoatRoughness: Float {
        get {
            (get("Clearcoat Roughness") as? FloatParameter)!.value
        }
        set {
            set("Clearcoat Roughness", newValue)
        }
    }

    public var sheen: Float {
        get {
            (get("Sheen") as? FloatParameter)!.value
        }
        set {
            set("Sheen", newValue)
        }
    }

    public var sheenTint: Float {
        get {
            (get("Sheen Tint") as? FloatParameter)!.value
        }
        set {
            set("Sheen Tint", newValue)
        }
    }

    public var transmission: Float {
        get {
            (get("Transmission") as? FloatParameter)!.value
        }
        set {
            set("Transmission", newValue)
        }
    }

    public var thickness: Float {
        get {
            (get("Thickness") as? FloatParameter)!.value
        }
        set {
            set("Thickness", newValue)
        }
    }

    public var ior: Float {
        get {
            (get("Ior") as? FloatParameter)!.value
        }
        set {
            set("Ior", newValue)
        }
    }

    public init(
        baseColor: simd_float4 = .one,
        metallic: Float = 1.0,
        roughness: Float = 1.0,
        specular: Float = 0.5,
        emissiveColor: simd_float4 = .zero,
        subsurface: Float = .zero,
        anisotropic: Float = .zero,
        anisotropicAngle: Float = .zero,
        specularTint: Float = .zero,
        clearcoat: Float = .zero,
        clearcoatRoughness: Float = .zero,
        sheen: Float = .zero,
        sheenTint: Float = .zero,
        transmission: Float = .zero,
        occlusion: Float = 1.0,
        thickness: Float = 0.0,
        ior: Float = 1.5,
        maps: [PBRTextureType: MTLTexture?] = [:]
    ) {
        super.init(
            baseColor: baseColor,
            metallic: metallic, 
            roughness: roughness,
            specular: specular,
            occlusion: occlusion,
            emissiveColor: emissiveColor,
            maps: maps
        )

        self.subsurface = subsurface

        self.anisotropic = anisotropic
        self.anisotropicAngle = anisotropicAngle

        self.specularTint = specularTint
        
        self.clearcoat = clearcoat
        self.clearcoatRoughness = clearcoatRoughness
        
        self.sheen = sheen
        self.sheenTint = sheenTint

        self.transmission = transmission
        self.thickness = thickness
        self.ior = ior
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    public required init() {
        super.init()
    }

    override open func createShader() -> Shader {
        PhysicalShader(label: label, pipelineURL: getPipelinesMaterialsURL(label)!.appendingPathComponent("Shaders.metal"))
    }

    override internal func setTextureMultiplierUniformToOne(type: PBRTextureType) {
        switch type {
            case .baseColor:
                baseColor = .one
            case .subsurface:
                subsurface = 1.0
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
                specularTint = 1.0
            case .sheen:
                sheen = 1.0
            case .sheenTint:
                sheenTint = 1.0
            case .clearcoat:
                clearcoat = 1.0
            case .clearcoatRoughness:
                clearcoatRoughness = 1.0
            case .clearcoatGloss:
                clearcoatRoughness = 1.0
            case .anisotropic:
                anisotropic = 1.0
            case .anisotropicAngle:
                anisotropicAngle = 1.0
            case .bump:
                break
            case .displacement:
                break
            case .alpha:
                baseColor.w = 1.0
            case .ior:
                ior = 1.0
            case .transmission:
                transmission = 1.0
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

public extension PhysicalMaterial {
    func setPropertiesFrom(material: MDLMaterial, textureLoader: MTKTextureLoader? = nil) {
        // MARK: - BaseColor

        if let property = material.property(with: .baseColor) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .baseColor)
                }
            } else if property.type == .color, let color = property.color, let rgba = color.components {
                baseColor = simd_make_float4(Float(rgba[0]), Float(rgba[1]), Float(rgba[2]), Float(rgba[3]))
            } else if property.type == .float4 {
                baseColor = property.float4Value
            } else if property.type == .float3 {
                baseColor = simd_make_float4(property.float3Value, 1.0)
            } else if property.type == .float {
                baseColor = simd_make_float4(property.floatValue, property.floatValue, property.floatValue, 1.0)
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Subsurface

        if let property = material.property(with: .subsurface) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .subsurface)
                }
            } else if property.type == .float {
                subsurface = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Metallic

        if let property = material.property(with: .metallic) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .metallic)
                }
            } else if property.type == .float {
                metallic = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Specular

        if let property = material.property(with: .specular) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .specular)
                }
            } else if property.type == .float {
                specular = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - SpecularTint

        if let property = material.property(with: .specularTint) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .specularTint)
                }
            } else if property.type == .float {
                specularTint = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Roughness

        if let property = material.property(with: .roughness) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .roughness)
                }
            } else if property.type == .float {
                roughness = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Anisotropic

        if let property = material.property(with: .anisotropic) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .anisotropic)
                }
            } else if property.type == .float {
                anisotropic = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - AnisotropicRotation

        if let property = material.property(with: .anisotropicRotation) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .anisotropicAngle)
                }
            } else if property.type == .float {
                anisotropicAngle = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Sheen

        if let property = material.property(with: .sheen) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .sheen)
                }
            } else if property.type == .float {
                sheen = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - SheenTint

        if let property = material.property(with: .sheenTint) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .sheenTint)
                }
            } else if property.type == .float {
                sheenTint = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Clearcoat

        if let property = material.property(with: .clearcoat) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .clearcoat)
                }
            } else if property.type == .float {
                clearcoat = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - ClearcoatGloss

        if let property = material.property(with: .clearcoatGloss) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .clearcoatGloss)
                }
            } else if property.type == .float {
                clearcoatRoughness = 1.0 - property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Emission

        if let property = material.property(with: .emission) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .emissive)
                }
            } else if property.type == .color, let color = property.color, let rgba = color.components {
                emissiveColor = simd_make_float4(Float(rgba[0]), Float(rgba[1]), Float(rgba[2]), Float(rgba[3]))
            } else if property.type == .float4 {
                emissiveColor = property.float4Value
            } else if property.type == .float3 {
                emissiveColor = simd_make_float4(property.float3Value, 1.0)
            } else if property.type == .float {
                emissiveColor = simd_make_float4(1.0, 1.0, 1.0, property.floatValue)
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Bump

        if let property = material.property(with: .bump) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: mdlTexture.mipLevelCount > 1 ? true : false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .bump)
                }
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Opacity

        if let property = material.property(with: .opacity) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .alpha)
                }
            } else if property.type == .float {
                baseColor.w = property.floatValue
                if property.floatValue < 1.0 {
                    blending = .alpha
                }
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - InterfaceIndexOfRefraction

        if let property = material.property(with: .interfaceIndexOfRefraction) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .ior)
                }
            } else if property.type == .float {
                ior = property.floatValue
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - ObjectSpaceNormal

        if let property = material.property(with: .objectSpaceNormal) {
            print("loading object space normal")
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .normal)
                }
            } else {
                print("objectSpaceNormal not supported")
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - TangentSpaceNormal

        if let property = material.property(with: .tangentSpaceNormal) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .normal)
                }
            } else if property.type == .color, let color = property.color, let rgba = color.components {
                print(simd_make_float4(Float(rgba[0]), Float(rgba[1]), Float(rgba[2]), Float(rgba[3])))
            } else if property.type == .float4 {
                print(property.float4Value)
            } else if property.type == .float3 {
                print(simd_make_float4(property.float3Value, 1.0))
            } else if property.type == .float {
                print(simd_make_float4(1.0, 1.0, 1.0, property.floatValue))
            } else {
                print("tangentSpaceNormal not supported")
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - Displacement

        if let property = material.property(with: .displacement) {
            if property.type == .texture, let mdlTexture = property.textureSamplerValue?.texture {
                if let textureLoader {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .generateMipmaps: false,
                        .origin: MTKTextureLoader.Origin.flippedVertically,
                    ]
                    loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .displacement)
                }
            } else {
                print("Unsupported MDLMaterial Property: \(property.name)")
            }
        }

        // MARK: - AmbientOcclusion

        if let property = material.property(with: .ambientOcclusion), property.type == .texture,
           let mdlTexture = property.textureSamplerValue?.texture
        {
            if let textureLoader {
                let options: [MTKTextureLoader.Option: Any] = [
                    .generateMipmaps: false,
                    .origin: MTKTextureLoader.Origin.flippedVertically,
                ]
                loadTexture(loader: textureLoader, mdlTexture: mdlTexture, options: options, target: .occlusion)
            }
        }
    }

//    func loadTextureAsync(
//        loader: MTKTextureLoader,
//        mdlTexture: MDLTexture,
//        options: [MTKTextureLoader.Option: Any],
//        target: PBRTextureIndex
//    ) {
//        loader.newTexture(texture: mdlTexture, options: options) { [weak self] texture, error in
//            if let texture = texture {
//                self?.setTexture(texture, type: target)
//            } else if let error = error {
//                print(error.localizedDescription)
//            }
//        }
//    }

    func loadTexture(
        loader: MTKTextureLoader,
        mdlTexture: MDLTexture,
        options: [MTKTextureLoader.Option: Any],
        target: PBRTextureType
    ) {
        do {
            let texture = try loader.newTexture(texture: mdlTexture, options: options)
            setTexture(texture, type: target)
        } catch {
            print(error.localizedDescription)
        }
    }
}
