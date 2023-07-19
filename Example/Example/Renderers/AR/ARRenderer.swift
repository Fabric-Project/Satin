//
//  Renderer.swift
//  AR
//
//  Created by Reza Ali on 9/26/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

#if os(iOS)
import ARKit
import Metal
import MetalKit

import Forge
import Satin
import SatinCore

class ARRenderer: BaseRenderer, ARSessionDelegate {
    var session = ARSession()

    let boxGeometry = BoxGeometry(width: 0.1, height: 0.1, depth: 0.1)
    let boxMaterial = UvColorMaterial()
    var meshAnchorMap: [UUID: Mesh] = [:]
    
    var scene = Object("Scene")

    lazy var context = Context(device, sampleCount, colorPixelFormat, .depth32Float)
    lazy var camera = ARPerspectiveCamera(session: session, mtkView: mtkView, near: 0.01, far: 100.0)
    lazy var renderer = Satin.Renderer(context: context)

    var backgroundRenderer: ARBackgroundRenderer!

    override func setupMtkView(_ metalKitView: MTKView) {
        metalKitView.sampleCount = 1
        metalKitView.depthStencilPixelFormat = .invalid
        metalKitView.preferredFramesPerSecond = 60
    }

    override init() {
        super.init()
        session.delegate = self
        session.run(ARWorldTrackingConfiguration())
    }

    override func setup() {
        renderer.colorLoadAction = .load

        boxGeometry.context = context
        boxMaterial.context = context

        backgroundRenderer = ARBackgroundRenderer(
            context: Context(device, 1, colorPixelFormat),
            session: session
        )
    }

    override func draw(_ view: MTKView, _ commandBuffer: MTLCommandBuffer) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        backgroundRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(_ size: (width: Float, height: Float)) {
        renderer.resize(size)
        backgroundRenderer.resize(size)
    }

    override func cleanup() {
        session.pause()
    }

    override func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
        if let currentFrame = session.currentFrame {
            let anchor = ARAnchor(transform: simd_mul(currentFrame.camera.transform, translationMatrixf(0.0, 0.0, -0.25)))
            session.add(anchor: anchor)
            let mesh = Mesh(geometry: boxGeometry, material: boxMaterial)
            mesh.worldMatrix = anchor.transform
            meshAnchorMap[anchor.identifier] = mesh
            scene.add(mesh)
        }
    }

    func session(_: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let mesh = meshAnchorMap[anchor.identifier] {
                mesh.worldMatrix = anchor.transform
            }
        }
    }
}

#endif
