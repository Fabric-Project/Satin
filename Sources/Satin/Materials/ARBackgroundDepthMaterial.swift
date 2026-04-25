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

    public required init() {
        super.init()
        configure()
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        configure()
    }

    private func configure() {
        depthWriteEnabled = true
        blending = .alpha
    }
}

#endif
