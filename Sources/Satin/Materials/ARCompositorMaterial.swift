//
//  File.swift
//
//
//  Created by Reza Ali on 1/24/24.
//

import Metal

public final class ARCompositorMaterial: ARPostMaterial {
    public var backgroundTextureTransform: simd_float4x4 {
        get {
            get("Background Texture Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4
        }
        set {
            set("Background Texture Transform", newValue)
        }
    }

    public var matteTextureTransform: simd_float4x4 {
        get {
            get("Matte Texture Transform", as: Float4x4Parameter.self)?.value ?? matrix_identity_float4x4
        }
        set {
            set("Matte Texture Transform", newValue)
        }
    }

    public var depthTexture: MTLTexture? {
        didSet {
            set(depthTexture, index: FragmentTextureIndex.Custom2)
        }
    }

    public var backgroundTexture: MTLTexture? {
        didSet {
            set(backgroundTexture, index: FragmentTextureIndex.Custom3)
        }
    }

    public var alphaTexture: MTLTexture? {
        didSet {
            set(alphaTexture, index: FragmentTextureIndex.Custom4)
        }
    }

    public var dilatedDepthTexture: MTLTexture? {
        didSet {
            set(dilatedDepthTexture, index: FragmentTextureIndex.Custom5)
        }
    }

    public required init(context: Context) {
        super.init(context: context)
        configureTextureTransforms()
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        configureTextureTransforms()
    }

    override init(context: Context, contentTexture: MTLTexture? = nil, cameraGrainTexture: MTLTexture? = nil) {
        super.init(context: context, contentTexture: contentTexture, cameraGrainTexture: cameraGrainTexture)
        configureTextureTransforms()
    }

    private func configureTextureTransforms() {
        if get("Background Texture Transform") == nil {
            set("Background Texture Transform", matrix_identity_float4x4)
        }
        if get("Matte Texture Transform") == nil {
            set("Matte Texture Transform", matrix_identity_float4x4)
        }
    }
}
