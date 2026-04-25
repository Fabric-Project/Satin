//
//  ProjectedShadowRenderer.swift
//  Example
//
//  Created by Reza Ali on 1/25/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import Satin

final class ProjectedShadowRenderer: BaseRenderer {
    // MARK: - 3D Scene

    lazy var scene = Object(context: defaultContext, label: "Scene", [shadowPlaneMesh, mesh])
    lazy var mesh: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, geometry: TorusGeometry(context: defaultContext, minorRadius: 0.1, majorRadius: 0.5), material: NormalColorMaterial(context: defaultContext, true))
        mesh.label = "Box"
        mesh.position = .init(0, 2.0, 0)
        return mesh
    }()

    lazy var shadowMaterial = BasicTextureMaterial(context: defaultContext, texture: nil, flipped: true)
    lazy var shadowRenderer = MeshShadowRenderer(device: device, mesh: mesh, size: (512, 512))
    lazy var shadowPlaneMesh = Mesh(context: defaultContext, geometry: PlaneGeometry(context: defaultContext, size: 4, orientation: .zx), material: shadowMaterial)

    lazy var camera: PerspectiveCamera = {
        lazy var camera = PerspectiveCamera(context: defaultContext, position: [4.0, 6.0, 4.0], near: 0.01, far: 1000.0)
        camera.lookAt(target: .zero)
        return camera
    }()

    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    var angle: Float = 0

    override func setup() {
        renderer.setClearColor(.one)
        cameraController.target.position.y += 1
    }

    override func update() {
        cameraController.update()

        mesh.orientation = simd_quatf(angle: angle, axis: simd_normalize([sin(angle), cos(angle), 0.25]))
        angle += 0.015
        mesh.position.y = 2.0 + sin(angle)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        shadowRenderer.draw(commandBuffer: commandBuffer)

        shadowMaterial.texture = shadowRenderer.texture
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
