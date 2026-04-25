//
//  ARBackgroundMaterial.swift
//
//
//  Created by Reza Ali on 1/23/24.
//

#if os(iOS)

import ARKit
import Metal

public final class ARBackgroundMaterial: Material {
    public var color: simd_float4 {
        set {
            (get("Color") as! Float4Parameter).value = newValue
        }
        get {
            (get("Color") as! Float4Parameter).value
        }
    }

    public var srgb: Bool {
        set {
            (get("Srgb") as! BoolParameter).value = newValue
        }
        get {
            (get("Srgb") as! BoolParameter).value
        }
    }

    public var capturedImageTextureY: CVMetalTexture? {
        didSet {
            if let textureY = capturedImageTextureY {
                set(CVMetalTextureGetTexture(textureY), index: FragmentTextureIndex.Custom0)
            }
            else {
                set(nil, index: FragmentTextureIndex.Custom0)
            }
        }
    }

    public var capturedImageTextureCbCr: CVMetalTexture? {
        didSet {
            if let textureCbCr = capturedImageTextureCbCr {
                set(CVMetalTextureGetTexture(textureCbCr), index: FragmentTextureIndex.Custom1)
            }
            else {
                set(nil, index: FragmentTextureIndex.Custom1)
            }
        }
    }

    public init(color: simd_float4 = simd_float4(repeating: 1.0), srgb: Bool = false) {
        super.init()
        set("Color", color)
        set("Srgb", srgb)
        configure()
    }

    public required init() {
        super.init()
        set("Color", simd_float4.one)
        set("Srgb", false)
        configure()
    }

    func configure() {
        depthWriteEnabled = false
        depthCompareFunction = .always
        blending = .alpha
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

#endif
