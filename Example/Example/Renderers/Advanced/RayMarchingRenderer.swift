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
        init(context: Context, pipelinesURL: URL) {
            super.init(context: context, pipelinesURL: pipelinesURL, live: true)
            blending = .disabled
        }

        required init(context: Context) {
            super.init(context: context)
        }

        required init(from decoder: Decoder) throws {
            try super.init(from: decoder)
        }
    }

    lazy var mesh: Mesh = {
        let material = BasicDiffuseMaterial(context: defaultContext, hardness: 0.7)
        material.ambient = 0.15
        return Mesh(context: defaultContext, geometry: BoxGeometry(context: defaultContext, size: 2.0), material: material)
    }()
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [10.0, 10.0, 10.0], near: 0.1, far: 100.0, fov: 45)

    lazy var rayMarchedMaterial = RayMarchedMaterial(context: defaultContext, pipelinesURL: pipelinesURL)
    lazy var rayMarchedMesh = Mesh(context: defaultContext, geometry: QuadGeometry(context: defaultContext), material: rayMarchedMaterial)
    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh, rayMarchedMesh])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    override func setup() {
        camera.lookAt(target: .zero)
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
