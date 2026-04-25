//
//  Renderer.swift
//  Example Shared
//
//  Created by Reza Ali on 8/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import CoreGraphics
import CoreText

import Metal
import MetalKit

import Satin

final class TextRenderer: BaseRenderer {
    let scene = Object()
    let camera = PerspectiveCamera(position: simd_make_float3(0.0, 0.0, 40.0), near: 0.001, far: 1000.0)
    lazy var cameraController: PerspectiveCameraController = .init(camera: camera, view: metalView)
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
        let input = "SATIN\nPRO"

        /*
         Times
         AvenirNext-UltraLight
         Helvetica
         SFMono-HeavyItalic
         SFProRounded-Thin
         SFProRounded-Heavy
         */

        let geo = TesselatedTextGeometry(text: input, fontName: "SFProRounded-Heavy", fontSize: 8)

        let mat = BasicColorMaterial(color: [1.0, 1.0, 1.0, 0.125], blending: .additive)
        mat.depthWriteEnabled = false
        let mesh = Mesh(geometry: geo, material: mat)
        scene.add(mesh)

//        fatalError("generate point mesh")
//        let pGeo = Geometry()
//        pGeo.vertexData = geo.vertexData
//        pGeo.primitiveType = .point
//        let pmat = BasicPointMaterial([1, 1, 1, 0.5], 6, .alpha)
//        pmat.depthWriteEnabled = false
//        let pmesh = Mesh(geometry: pGeo, material: pmat)
//        scene.add(pmesh)

        let fmat = BasicColorMaterial(color: [1, 1, 1, 0.025], blending: .additive)
        fmat.depthWriteEnabled = false
        let fmesh = Mesh(geometry: geo, material: fmat)
        fmesh.triangleFillMode = .lines
        scene.add(fmesh)
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
