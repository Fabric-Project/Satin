//
//  TextMaterial.swift
//
//
//  Created by Reza Ali on 12/30/23.
//

import Foundation
import Metal
import simd

public final class TextMaterial: Material {
    public var fontTexture: MTLTexture? {
        didSet {
            set(fontTexture, index: FragmentTextureIndex.Custom0)
        }
    }

    public var color: simd_float4 {
        get {
            get("Color", as: Float4Parameter.self)!.value
        }
        set {
            set("Color", newValue)
        }
    }

    public var textureTransform: simd_float4x4 {
        get {
            get("Texture Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4
        }
        set {
            set("Texture Transform", newValue)
        }
    }

    public init(context: Context, color: simd_float4 = .one, fontTexture: MTLTexture?) {
        super.init(context: context)

        self.blending = .alpha
        self.fontTexture = fontTexture

        set("Color", color)
        set("Texture Transform", matrix_identity_float4x4)
        set(fontTexture, index: FragmentTextureIndex.Custom0)
    }

    public required init(context: Context) {
        super.init(context: context)

        blending = .alpha
        set("Color", simd_float4.one)
        set("Texture Transform", matrix_identity_float4x4)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        if get("Texture Transform") == nil {
            set("Texture Transform", matrix_identity_float4x4)
        }
    }
}
