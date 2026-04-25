//
//  Renderer.swift
//  Example Shared
//
//  Created by Reza Ali on 8/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
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

    var geo: TesselatedTextGeometry?

    lazy var fontParam: StringParameter = {
        let families = (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []).sorted()
        return StringParameter("Font", "Helvetica", families, .dropdown)
    }()

    private var cancellable: AnyCancellable?

    override func setup() {
        setupText()

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    func setupText() {
        let input = "SATIN\nPRO"

        let geometry = TesselatedTextGeometry(context: defaultContext, text: input, fontName: fontParam.value, fontSize: 8)
        geo = geometry

        lazy var mat = BasicColorMaterial(context: defaultContext, color: [1.0, 1.0, 1.0, 0.125], blending: .additive)
        mat.depthWriteEnabled = false
        lazy var mesh = Mesh(context: defaultContext, geometry: geometry, material: mat)
        scene.add(mesh)

        lazy var fmat = BasicColorMaterial(context: defaultContext, color: [1, 1, 1, 0.025], blending: .additive)
        fmat.depthWriteEnabled = false
        lazy var fmesh = Mesh(context: defaultContext, geometry: geometry, material: fmat)
        fmesh.triangleFillMode = .lines
        scene.add(fmesh)

        cancellable = fontParam.valuePublisher.sink { [weak self] fontName in
            self?.geo?.fontName = fontName
        }
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
