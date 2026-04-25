//
//  InstancedMeshRenderer.swift
//  Example
//
//  Created by Reza Ali on 10/19/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import ModelIO

import Satin

final class InstancedMeshRenderer: BaseRenderer {
    override var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }

    // MARK: - Satin

    private let camera = PerspectiveCamera(position: [10.0, 10.0, 10.0], near: 0.001, far: 100.0)
    private let scene = Object(label: "Scene")
    private let container = Object(label: "Container")

    private lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    private var instancedMesh: InstancedMesh?
    private lazy var renderer = Renderer(context: defaultContext)

    // MARK: - Properties

    lazy var startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    let dim = 7

    override func setup() {
        camera.lookAt(target: .zero)
        setupScene()

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    deinit {
        cameraController.disable()
    }

    func setupScene() {
        let url = modelsURL.appendingPathComponent("Suzanne/Suzanne.obj")
        guard let model = loadAsset(url: url), let mesh = getMeshes(model, true, true).first else { return }

        let instancedMesh = InstancedMesh(
            label: "Spot",
            geometry: mesh.geometry,
            material: BasicDiffuseMaterial(hardness: 0.0),
            count: dim * dim * dim
        )

        container.add(instancedMesh)
        self.instancedMesh = instancedMesh

        scene.add(container)
        updateInstances(getTime())
    }

    func updateInstances(_ time: Float) {
        guard let instancedMesh = instancedMesh else { return }

        let halfDim: Int = dim / 2
        let object = Object()
        object.scale = .init(repeating: 0.5)
        var index = 0
        for z in -halfDim ... halfDim {
            for y in -halfDim ... halfDim {
                for x in -halfDim ... halfDim {
                    object.position = simd_make_float3(Float(x), Float(y), Float(z))
                    let axis = simd_normalize(object.position)
                    object.orientation = .init(angle: 2.0 * time + simd_length(object.position), axis: axis)

                    instancedMesh.setMatrixAt(index: index, matrix: object.localMatrix)
                    index += 1
                }
            }
        }
    }

    func getTime() -> Float {
        return Float(CFAbsoluteTimeGetCurrent() - startTime)
    }

    override func update() {
        cameraController.update()
        updateInstances(getTime())
        container.position = [2.0 * sin(getTime()), 0.0, 0.0]
        container.scale = .init(repeating: 1.0 + abs(cos(getTime())))
        container.orientation = .init(angle: cos(getTime()) * .pi, axis: simd_normalize(.one))

        camera.update()
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
        cameraController.resize(size)
        renderer.resize(size)
    }
}
