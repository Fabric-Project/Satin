//
//  ARBackgroundDepthMaterial.swift
//
//
//  Created by Reza Ali on 1/24/24.
//

#if os(iOS)

import ARKit
import Metal

public class ARBackgroundDepthMaterial: Material {
    override open var lightingModel: LightingModel { .unlit }
    public var textureTransform: simd_float4x4 {
        get {
            get("Texture Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4
        }
        set {
            set("Texture Transform", newValue)
        }
    }

    public var upscaledSceneDepthTexture: MTLTexture? {
        didSet {
            set(upscaledSceneDepthTexture, index: FragmentTextureIndex.Custom0)
        }
    }

    public var sceneDepthTexture: CVMetalTexture? {
        didSet {
            if let sceneDepthTexture {
                set(CVMetalTextureGetTexture(sceneDepthTexture), index: FragmentTextureIndex.Custom0)
            }
        }
    }

    public required init(context: Context) {
        super.init(context: context)
        configure()
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        configure()
    }

    private func configure() {
        depthWriteEnabled = true
        blending = .alpha
        if get("Texture Transform") == nil {
            set("Texture Transform", matrix_identity_float4x4)
        }
    }
}

#endif
