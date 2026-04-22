//
//  ARMatteMaterial.swift
//
//
//  Created by Reza Ali on 1/24/24.
//

import Metal

public class ARMatteMaterial: Material {
    override open var lightingModel: LightingModel { .unlit }
    public var textureTransform: simd_float4x4 {
        get {
            get("Texture Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4
        }
        set {
            set("Texture Transform", newValue)
        }
    }

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

    public required init(context: Context) {
        super.init(context: context)
        set("Texture Transform", matrix_identity_float4x4)
    }

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        if get("Texture Transform") == nil {
            set("Texture Transform", matrix_identity_float4x4)
        }
    }
}
