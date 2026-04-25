//
//  Renderer.swift
//  AR
//
//  Created by Reza Ali on 9/26/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Combine
import Metal

import Satin

final class ARRenderer: BaseRenderer {
    var session: ARSession { sessionPublisher.session }
    private let sessionPublisher = ARSessionPublisher(session: ARSession())
    private var anchorsSubscription: AnyCancellable?

    private let boxGeometry = BoxGeometry(width: 0.1, height: 0.1, depth: 0.1)
    private let boxMaterial = UVColorMaterial()
    private var meshAnchorMap: [UUID: Mesh] = [:]

    private var scene = Object(label: "Scene")

    private lazy var context = Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat, depthPixelFormat: .depth32Float)
    private lazy var camera = ARPerspectiveCamera(session: session, metalView: metalView, near: 0.01, far: 100.0)
    private lazy var renderer = Renderer(context: context)

    private var backgroundRenderer: ARBackgroundRenderer!

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    override init() {
        super.init()

        session.run(ARWorldTrackingConfiguration())
    }

    override func setup() {
        metalView.preferredFramesPerSecond = 60

        renderer.colorLoadAction = .load

        boxGeometry.context = context
        boxMaterial.context = context

        backgroundRenderer = ARBackgroundRenderer(
            context: Context(device: device, sampleCount: 1, colorPixelFormat: colorPixelFormat),
            session: session
        )

        anchorsSubscription = sessionPublisher.updatedAnchorsPublisher.sink { [weak self] anchors in
            guard let self else { return }
            for anchor in anchors {
                if let mesh = self.meshAnchorMap[anchor.identifier] {
                    mesh.worldMatrix = anchor.transform
                }
            }
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
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

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
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
}

#endif
