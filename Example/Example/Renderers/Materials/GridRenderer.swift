//
//  GridRenderer.swift
//  Example
//
//  Created by Reza Ali on 9/3/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Metal
import Satin

final class GridRenderer: BaseRenderer {
    final class GridMaterial: SourceMaterial {}

    var camera = PerspectiveCamera(position: [0.0, 0.0, 6.0], near: 0.001, far: 200.0, fov: 45.0)
    lazy var scene = Object(label: "Scene", [skybox])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)
    lazy var gridMaterial = GridMaterial(pipelinesURL: pipelinesURL, live: true)

    lazy var skybox: Mesh = {
        let mesh = Mesh(geometry: SkyboxGeometry(), material: gridMaterial)
        mesh.label = "Skybox"
        mesh.scale = [50, 50, 50]
        return mesh
    }()

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
