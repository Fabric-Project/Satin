//
//  ARMatteMaterial.swift
//
//
//  Created by Reza Ali on 1/24/24.
//

import Metal

public class ARMatteMaterial: Material {
    public var alphaTexture: MTLTexture? {
        didSet {
            alphaTexture?.label = "ARMatteAlpha Texture"
            set(alphaTexture, index: FragmentTextureIndex.Custom0)
        }
    }

    public var dilatedDepthTexture: MTLTexture? {
        didSet {
            dilatedDepthTexture?.label = "ARMatteAlpha dilatedDepthTexture"
            set(dilatedDepthTexture, index: FragmentTextureIndex.Custom1)
        }
    }

    public required init() {
        super.init()
    }

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
