//
//  ExtrudedTextRenderer.swift
//  Example Shared
//
//  Created by Reza Ali on 8/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal
import Combine
import Satin

final class ExtrudedTextRenderer: BaseRenderer {
    lazy var scene = Object(context: defaultContext)
    var mesh: Mesh!
    var geo: ExtrudedTextGeometry?

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [15.0, 20.0, 40.0], near: 10.0, far: 60.0, fov: 60)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)
    lazy var parameters = ParameterGroup("Text", [fontParam])
    lazy var fontParam = StringParameter("Font", "Helvetica", availableFontFamilyNames, .dropdown)

    override var paramKeys: [String] {
        ["Text"]
    }

    override var params: [String: ParameterGroup?] {
        ["Text": parameters]
    }

    private var cancellable: AnyCancellable?

    override func setup() {
        setupText()

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
        super.setup()
    }

    func setupText() {
        let input = "stay hungry\nstay foolish"
        let geometry = ExtrudedTextGeometry(context: defaultContext, 
            text: input,
            fontName: fontParam.value,
            fontSize: 8,
            distance: 8,
            bounds: CGSize(width: -1, height: -1),
            pivot: simd_make_float2(0, 0),
            textAlignment: .left,
            verticalAlignment: .center
        )
        geo = geometry

        lazy var mat = DepthMaterial(context: defaultContext)
        mat.set("Invert", true)
        mesh = Mesh(context: defaultContext, geometry: geometry, material: mat)

        camera.lookAt(target: mesh.worldBounds.center)

        scene.add(mesh)

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
