//
//  PBRConstants.swift
//
//
//  Created by Reza Ali on 3/17/23.
//

import Foundation

public enum PBRTextureType: String, CaseIterable, Codable {
    case baseColor
    case subsurface
    case metallic
    case roughness
    case normal
    case emissive
    case specular
    case specularTint
    case sheen
    case sheenTint
    case clearcoat
    case clearcoatRoughness
    case clearcoatGloss
    case anisotropic
    case anisotropicAngle
    case bump
    case displacement
    case alpha
    case ior
    case transmission
    case occlusion
    case reflection
    case irradiance
    case brdf

    public var index: Int {
        switch self {
            case .baseColor:
                return 0
            case .subsurface:
                return 1
            case .metallic:
                return 2
            case .roughness:
                return 3
            case .normal:
                return 4
            case .emissive:
                return 5
            case .specular:
                return 6
            case .specularTint:
                return 7
            case .sheen:
                return 8
            case .sheenTint:
                return 9
            case .clearcoat:
                return 10
            case .clearcoatRoughness:
                return 11
            case .clearcoatGloss:
                return 12
            case .anisotropic:
                return 13
            case .anisotropicAngle:
                return 14
            case .bump:
                return 15
            case .displacement:
                return 16
            case .alpha:
                return 17
            case .ior:
                return 18
            case .transmission:
                return 19
            case .occlusion:
                return 20
            case .reflection:
                return 21
            case .irradiance:
                return 22
            case .brdf:
                return 23
        }
    }

    public var shaderDefine: String {
        description.titleCase.uppercased().replacingOccurrences(of: " ", with: "_") + "_MAP"
    }

    public var textureType: String {
        switch self {
            case .irradiance, .reflection:
                return "texturecube"
            default:
                return "texture2d"
        }
    }

    public var description: String {
        self.rawValue
    }

    public var samplerName: String {
        description + "Sampler"
    }

    public var textureName: String {
        description + "Map"
    }

    public var texcoordName: String {
        switch self {
            case .clearcoatGloss:
                return PBRTextureType.clearcoatRoughness.texcoordName
            default:
                return description + "TexcoordTransform"
        }
    }

    public var textureIndex: String {
        "PBRTexture" + Substring(description.prefix(1).uppercased()) + Substring(description.dropFirst())
    }

    public static var allTexcoordCases: [PBRTextureType] {
        [
            .baseColor,
            .subsurface,
            .metallic,
            .roughness,
            .normal,
            .emissive,
            .specular,
            .specularTint,
            .sheen,
            .sheenTint,
            .clearcoat,
            .clearcoatRoughness,
            .anisotropic,
            .anisotropicAngle,
            .bump,
            .displacement,
            .alpha,
            .ior,
            .transmission,
            .occlusion,
            .reflection,
            .irradiance
        ]
    }
}
