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

    public init(color: simd_float4 = .one, fontTexture: MTLTexture?) {
        super.init()

        self.blending = .alpha
        self.fontTexture = fontTexture

        set("Color", color)
        set(fontTexture, index: FragmentTextureIndex.Custom0)
    }

    public required init() {
        super.init()

        blending = .alpha
        set("Color", simd_float4.one)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
