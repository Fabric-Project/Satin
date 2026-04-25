//
//  DiskRenderer.swift
//  Example
//
//  Created by Reza Ali on 10/15/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Combine
import Metal
import MetalKit
import Satin

final class DiskRenderer: BaseRenderer {
    final class DiskMaterial: SourceMaterial {}

    lazy var renderer = Renderer(context: defaultContext)
    lazy var camera = PerspectiveCamera(position: [0, 0, 5], near: 0.1, far: 100.0, fov: 60)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)

    lazy var scene: Object = {
        let geometry = UVDiskGeometry()
        let material = DiskMaterial(pipelinesURL: pipelinesURL, live: true)

        let scene = Object(label: "Scene")
        let count = 1000
        let mesh = InstancedMesh(geometry: geometry, material: material, count: count)
        let object = Object()
        for i in 0 ..< count {
            let scale = Float.random(in: 0.1 ... 0.5)
            let magnitude: Float = 10.0

            object.scale = simd_float3(repeating: scale)
            object.position = [Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude)]

            mesh.setMatrixAt(index: i, matrix: object.localMatrix)
        }
        scene.add(mesh)
        return scene
    }()

    override var sampleCount: Int {
#if targetEnvironment(simulator)
        1
#else
        4
#endif
    }

    override func setup() {
        camera.lookAt(target: .zero)

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
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
