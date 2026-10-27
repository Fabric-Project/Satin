//
//  PBRShader.swift
//  Satin
//
//  Created by Reza Ali on 12/9/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import Metal

/// Whether two arrays indexed by `PBRTextureType.index` hold values in different slots. Only presence
/// changes a PBR shader's source, not which texture or sampler fills a slot.
func pbrSlotPresenceDiffers<Value>(_ lhs: [Value?], _ rhs: [Value?]) -> Bool {
    for index in lhs.indices where (lhs[index] == nil) != (rhs[index] == nil) {
        return true
    }
    return false
}

open class PBRShader: SourceShader {
    /// The material's texture for each map, indexed by `PBRTextureType.index`. Which maps are
    /// present picks the shader's defines.
    open var maps = [MTLTexture?](repeating: nil, count: PBRTextureType.count) {
        didSet {
            if pbrSlotPresenceDiffers(oldValue, maps) {
                definesNeedsUpdate = true
            }
        }
    }

    /// The material's sampler for each map, indexed by `PBRTextureType.index`, injected as constants.
    open var samplers = [MTLSamplerDescriptor?](repeating: nil, count: PBRTextureType.count) {
        didSet {
            if pbrSlotPresenceDiffers(oldValue, samplers) {
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
        for pbrTexType in PBRTextureType.orderedCases {
            if let descriptor = samplers[pbrTexType.index] {
                results.append(descriptor.shaderInjection(index: pbrTexType))
            }
        }
        return results
    }

    override open func getDefines() -> [ShaderDefine] {
        var results = super.getDefines()

        if maps.contains(where: { $0 != nil }) { results.append(ShaderDefine(key: "HAS_MAPS", value: NSString(string: "true"))) }

        for pbrTexType in PBRTextureType.orderedCases where maps[pbrTexType.index] != nil {
            results.append(ShaderDefine(key: pbrTexType.shaderDefine, value: NSString(string: "true")))
        }

        results.append(ShaderDefine(key: tonemapping.shaderDefine, value: NSString(string: "true")))
        return results
    }
}
