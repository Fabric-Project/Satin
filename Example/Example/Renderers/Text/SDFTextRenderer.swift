//
//  TextRenderer.swift
//  Example
//
//  Created by Reza Ali on 6/27/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import Satin

final class SDFTextRenderer: BaseRenderer {
    lazy var fontTexture: MTLTexture? = {
        let loader = MTKTextureLoader(device: device)
        do {
            let options: [MTKTextureLoader.Option: Any] = [
                MTKTextureLoader.Option.SRGB: false,
                MTKTextureLoader.Option.generateMipmaps: false
            ]
            return try loader.newTexture(URL: sharedAssetsURL.appendingPathComponent("Fonts/SFProRounded/SFProRoundedBold64.png"), options: options)
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }()

    var scene = Object(label: "Scene")

    lazy var camera = PerspectiveCamera(position: [0, 0, 5], near: 0.1, far: 100.0, fov: 60)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    lazy var textMesh: TextMesh = {
        let fontAtlas = try! FontAtlas.load(url: sharedAssetsURL.appendingPathComponent("Fonts/SFProRounded/SFProRoundedBold64.json"))
        return TextMesh(geometry: TextGeometry(text: "Hello World", font: fontAtlas), material: TextMaterial(color: .one, fontTexture: fontTexture))
    }()

    override func setup() {
        textMesh.material?.depthWriteEnabled = false
        textMesh.scale = .init(repeating: 1.0 / 128.0)
        textMesh.position.y = 4.75 / 128.0
        scene.add(textMesh)

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    deinit {
        cameraController.disable()
    }

    var frame: Float = 0
    override func update() {
        textMesh.text = "\(frame)"
        frame -= 1
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
