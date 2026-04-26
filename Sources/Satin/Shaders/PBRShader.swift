//
//  PBRShader.swift
//  Satin
//
//  Created by Reza Ali on 12/9/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import Metal

open class PBRShader: SourceShader {
    open var maps = [MTLTexture?](repeating: nil, count: PBRTextureType.allCases.count) {
        didSet {
            let activeSetChanged = zip(oldValue, maps).contains { ($0 == nil) != ($1 == nil) }
            if activeSetChanged {
                definesNeedsUpdate = true
            }
        }
    }

    open var samplers: [PBRTextureType: MTLSamplerDescriptor?] = [:] {
        didSet {
            if oldValue.keys != samplers.keys {
                constantsNeedsUpdate = true
            }
        }
    }

    open var tonemapping: Tonemapping = .aces {
        didSet {
            if oldValue != tonemapping {
                definesNeedsUpdate = true
            }
        }
    }

    override open func getConstants() -> [String] {
        var results = super.getConstants()
        for pbrTexType in PBRTextureType.allCases {
            if let sampler = samplers[pbrTexType], let descriptor = sampler {
                results.append(descriptor.shaderInjection(index: pbrTexType))
            }
        }
        return results
    }

    override open func getDefines() -> [ShaderDefine] {
        var results = super.getDefines()

        if maps.contains(where: { $0 != nil }) { results.append(ShaderDefine(key: "HAS_MAPS", value: NSString(string: "true"))) }

        for type in PBRTextureType.allCases where maps[type.index] != nil {
            results.append(ShaderDefine(key: type.shaderDefine, value: NSString(string: "true")))
        }

        results.append(ShaderDefine(key: tonemapping.shaderDefine, value: NSString(string: "true")))
        return results
    }
}
