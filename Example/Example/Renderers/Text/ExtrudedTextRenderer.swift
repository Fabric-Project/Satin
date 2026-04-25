//
//  ExtrudedTextRenderer.swift
//  Example Shared
//
//  Created by Reza Ali on 8/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal
import Satin

final class ExtrudedTextRenderer: BaseRenderer {
    var scene = Object()
    var mesh: Mesh!

    lazy var camera = PerspectiveCamera(position: [15.0, 20.0, 40.0], near: 10.0, far: 60.0, fov: 60)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    override func setup() {
        setupText()

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    deinit {
        cameraController.disable()
    }

    func setupText() {
        let input = "stay hungry\nstay foolish"
        let geo = ExtrudedTextGeometry(
            text: input,
            fontName: "Helvetica",
            fontSize: 8,
            distance: 8,
            bounds: CGSize(width: -1, height: -1),
            pivot: simd_make_float2(0, 0),
            textAlignment: .left,
            verticalAlignment: .center
        )

        let mat = DepthMaterial()
        mat.set("Invert", true)
        mesh = Mesh(geometry: geo, material: mat)

        camera.lookAt(target: mesh.worldBounds.center)

        scene.add(mesh)
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
