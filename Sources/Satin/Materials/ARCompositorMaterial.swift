//
//  File.swift
//
//
//  Created by Reza Ali on 1/24/24.
//

import Metal

public final class ARCompositorMaterial: ARPostMaterial {
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
}
