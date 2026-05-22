//
//  SlugTextRenderer.swift
//
//
//  Created by OpenAI on 4/25/26.
//

import Metal
import MetalKit
import Satin
import Combine

final class SlugTextRenderer: BaseRenderer {
    lazy var scene = Object(context: defaultContext, label: "Scene")

    lazy var camera = PerspectiveCamera(
        context: defaultContext,
        position: [0, 0, 10],
        near: 0.1,
        far: 100.0,
        fov: 60
    )
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)
    lazy var parameters = ParameterGroup("Text", [fontParam])
    lazy var fontParam = StringParameter("Font", "Helvetica", availableFontFamilyNames, .dropdown)

    lazy var textMesh: SlugTextMesh = {
        let mesh = SlugTextMesh(
            context: defaultContext,
            text: "Frame 0",
            fontName: fontParam.value,
            color: .one
        )
        mesh.material?.depthWriteEnabled = false
        return mesh
    }()

    private var frame: Int = 0
    private var cancellable: AnyCancellable?

    override var paramKeys: [String] {
        ["Text"]
    }

    override var params: [String: ParameterGroup?] {
        ["Text": parameters]
    }

    override func setup() {
        scene.add(textMesh)

        cancellable = fontParam.valuePublisher.sink { [weak self] fontName in
            guard let self else { return }
            self.textMesh.font = SlugFontAtlas(context: self.defaultContext, fontName: fontName)
        }

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
        super.setup()
    }

    override func update() {
        textMesh.text = "Satin 2.0\nframe: \(frame)"
        frame += 1
        cameraController.update()
    }
    
//    override func update() {
//        frame += 1
//        textMesh.text = "SLUG \(Int(frame) % 360)"
//        cameraController.update()
//    }

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
