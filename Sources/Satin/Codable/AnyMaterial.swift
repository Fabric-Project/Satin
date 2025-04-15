//
//  AnyMaterial.swift
//
//
//  Created by Reza Ali on 11/18/22.
//

import Foundation

public enum MaterialType: String, Codable {
    case base, basiccolor, basicdiffuse, basicpoint, basictexture, depth, matcap, normal, physical, shadow, skybox, standard, uvcolor

    var metaType: Material.Type {
        switch self {
        case .base:
            return Material.self
        case .basiccolor:
            return BasicColorMaterial.self
        case .basicdiffuse:
            return BasicDiffuseMaterial.self
        case .basicpoint:
            return BasicPointMaterial.self
        case .basictexture:
            return BasicTextureMaterial.self
        case .depth:
            return DepthMaterial.self
        case .matcap:
            return MatCapMaterial.self
        case .normal:
            return NormalColorMaterial.self
        case .physical:
            return PhysicalMaterial.self
        case .shadow:
            return ShadowMaterial.self
        case .skybox:
            return SkyboxMaterial.self
        case .standard:
            return StandardMaterial.self
        case .uvcolor:
            return UVColorMaterial.self
        }
    }
}

open class AnyMaterial: Codable {
    public var type: MaterialType
    public var material: Material

    // Important: the ordering below is dependent of inheritance hierarchy

    public init(_ material: Material) {
        self.material = material

        if material is MatCapMaterial {
            type = .matcap
        } else if material is BasicTextureMaterial {
            type = .basictexture
        } else if material is BasicDiffuseMaterial {
            type = .basicdiffuse
        } else if material is BasicColorMaterial {
            type = .basiccolor
        } else if material is BasicPointMaterial {
            type = .basicpoint
        } else if material is DepthMaterial {
            type = .depth
        } else if material is NormalColorMaterial {
            type = .normal
        } else if material is SkyboxMaterial {
            type = .skybox
        } else if material is PhysicalMaterial {
            type = .physical
        } else if material is StandardMaterial {
            type = .standard
        } else if material is UVColorMaterial {
            type = .uvcolor
        } else if material is ShadowMaterial {
            type = .shadow
        } else {
            type = .base
        }
    }

    private enum CodingKeys: CodingKey {
        case type, material
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MaterialType.self, forKey: .type)
        material = try type.metaType.init(from: container.superDecoder(forKey: .material))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try material.encode(to: container.superEncoder(forKey: .material))
    }
}
