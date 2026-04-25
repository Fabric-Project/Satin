//
//  RayMarchingRenderer.swift
//  Example
//
//  Created by Reza Ali on 6/26/21.
//  Copyright © 2021 Hi-Rez. All rights reserved.
//

import Metal
import Satin

final class RayMarchingRenderer: BaseRenderer {
    final class RayMarchedMaterial: SourceMaterial {
        init(pipelinesURL: URL) {
            super.init(pipelinesURL: pipelinesURL, live: true)
            blending = .disabled
        }

        required init() {
            fatalError("init() has not been implemented")
        }

        required init(from decoder: Decoder) throws {
            try super.init(from: decoder)
        }
    }

    let mesh = Mesh(geometry: BoxGeometry(size: 2.0), material: BasicDiffuseMaterial(hardness: 0.7))
    let camera = PerspectiveCamera(position: [10.0, 10.0, 10.0], near: 0.1, far: 100.0, fov: 45)

    lazy var rayMarchedMaterial = RayMarchedMaterial(pipelinesURL: pipelinesURL)
    lazy var rayMarchedMesh = Mesh(geometry: QuadGeometry(), material: rayMarchedMaterial)
    lazy var scene = Object(label: "Scene", [mesh, rayMarchedMesh])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    override func setup() {
        camera.lookAt(target: .zero)
    }

    deinit {
        cameraController.disable()
    }

    override func update() {
        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
