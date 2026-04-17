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
    lazy var scene = Object(context: defaultContext)
    lazy var camera = PerspectiveCamera(context: defaultContext, position: simd_make_float3(0.0, 0.0, 40.0), near: 0.001, far: 1000.0)
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

        lazy var geo = TesselatedTextGeometry(context: defaultContext, text: input, fontName: "SFProRounded-Heavy", fontSize: 8)

        lazy var mat = BasicColorMaterial(context: defaultContext, color: [1.0, 1.0, 1.0, 0.125], blending: .additive)
        mat.depthWriteEnabled = false
        lazy var mesh = Mesh(context: defaultContext, geometry: geo, material: mat)
        scene.add(mesh)

//        fatalError("generate point mesh")
//        let pGeo = Geometry(context: defaultContext)
//        pGeo.vertexData = geo.vertexData
//        pGeo.primitiveType = .point
//        let pmat = BasicPointMaterial(context: defaultContext, [1, 1, 1, 0.5], 6, .alpha)
//        pmat.depthWriteEnabled = false
//        let pmesh = Mesh(geometry: pGeo, material: pmat)
//        scene.add(pmesh)

        lazy var fmat = BasicColorMaterial(context: defaultContext, color: [1, 1, 1, 0.025], blending: .additive)
        fmat.depthWriteEnabled = false
        lazy var fmesh = Mesh(context: defaultContext, geometry: geo, material: fmat)
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
