//
//  RenderEncoder.swift
//  Example Shared
//
//  Created by Reza Ali on 8/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import CoreGraphics

import Metal
import MetalKit

import Satin

final class TextRenderer: BaseRenderer {
    lazy var scene = Object(context: defaultContext)
    lazy var camera = PerspectiveCamera(context: defaultContext, position: simd_make_float3(0.0, 0.0, 40.0), near: 0.001, far: 1000.0)
    lazy var cameraController: PerspectiveCameraController = .init(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    var geo: TesselatedTextGeometry?
    lazy var parameters = ParameterGroup("Text", [fontParam])

    lazy var fontParam: StringParameter = {
        StringParameter("Font", "Helvetica", availableFontFamilyNames, .dropdown)
    }()

    private var cancellable: AnyCancellable?

    override var paramKeys: [String] {
        ["Text"]
    }

    override var params: [String: ParameterGroup?] {
        ["Text": parameters]
    }

    override func setup() {
        setupText()

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
        super.setup()
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

    private var frame: Int = 0
    override func update() {
        geo?.text = "Satin 2.0\nframe: \(frame)"
        frame += 1
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
