//
//  SlugTextMaterial.swift
//
//
//  Created by OpenAI on 4/25/26.
//

import Foundation
import Metal
import simd

public final class SlugTextMaterial: Material {
    public var curveTexture: MTLTexture? {
        didSet {
            set(curveTexture, index: FragmentTextureIndex.Custom0)
        }
    }

    public var bandTexture: MTLTexture? {
        didSet {
            set(bandTexture, index: FragmentTextureIndex.Custom1)
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

    public init(
        context: Context,
        color: simd_float4 = .one,
        curveTexture: MTLTexture?,
        bandTexture: MTLTexture?
    ) {
        super.init(context: context)

        blending = .alpha
        depthWriteEnabled = false

        self.curveTexture = curveTexture
        self.bandTexture = bandTexture

        set("Color", color)
        set(curveTexture, index: FragmentTextureIndex.Custom0)
        set(bandTexture, index: FragmentTextureIndex.Custom1)
    }

    public required init(context: Context) {
        super.init(context: context)

        blending = .alpha
        depthWriteEnabled = false
        set("Color", simd_float4.one)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        if get("Color") == nil {
            set("Color", simd_float4.one)
        }
        blending = .alpha
        depthWriteEnabled = false
    }
}
