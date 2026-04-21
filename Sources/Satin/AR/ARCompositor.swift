//
//  ARMattePostProcessor.swift
//  Example
//
//  Created by Reza Ali on 4/11/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Foundation
import Metal

public class ARCompositor: ARPostProcessor {
    public var depthTexture: MTLTexture? {
        didSet {
            if let material = mesh.material as? ARCompositorMaterial {
                material.depthTexture = depthTexture
            }
        }
    }

    public var backgroundTexture: MTLTexture? {
        didSet {
            if let material = mesh.material as? ARCompositorMaterial {
                material.backgroundTexture = backgroundTexture
            }
        }
    }

    public var alphaTexture: MTLTexture? {
        didSet {
            if let material = mesh.material as? ARCompositorMaterial {
                material.alphaTexture = alphaTexture
            }
        }
    }

    public var dilatedDepthTexture: MTLTexture? {
        didSet {
            if let material = mesh.material as? ARCompositorMaterial {
                material.dilatedDepthTexture = dilatedDepthTexture
            }
        }
    }

    override public required init(
        label: String,
        context: Context,
        session: ARSession
    ) {
        super.init(label: label, context: context, session: session)

        mesh.material = ARCompositorMaterial(context: context)

        renderer.setClearColor(.zero)

        renderer.colorLoadAction = .clear
        renderer.colorStoreAction = .store

        renderer.depthLoadAction = .clear
        renderer.depthStoreAction = .store
    }
}

#endif
