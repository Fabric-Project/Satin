//
//  ShadowRenderer.swift
//
//
//  Created by Reza Ali on 3/2/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import Satin

final class DirectionalShadowRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    lazy var lightHelperGeo = BoxGeometry(context: defaultContext, width: 0.1, height: 0.1, depth: 0.5)
    lazy var lightHelperMat = BasicDiffuseMaterial(context: defaultContext, hardness: 0.7)

    lazy var lightHelperMesh0 = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat)
    lazy var lightHelperMesh1 = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat)

    lazy var shadowScene = StandardShadowSceneContent(context: defaultContext)

    lazy var light0 = DirectionalLight(context: defaultContext, color: [1.0, 1.0, 1.0], intensity: 1.0)
    lazy var light1 = DirectionalLight(context: defaultContext, color: [1.0, 1.0, 1.0], intensity: 1.0)

    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [light0, light1] + shadowScene.objects)
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [8.0, 4.8, 8.2], near: 0.01, far: 500.0, fov: 34.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
            scene.environmentIntensity = 0.1
        }
    }

    override func setup() throws {
        loadHdri()
        renderer.clearColor = .init(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)

        light0.position.y = 5.0
        light0.castShadow = true
        lightHelperMesh0.label = "Light Helper 0"
        light0.add(lightHelperMesh0)
//        if let shadowCamera = light0.shadow.camera as? OrthographicCamera {
//            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
//        }
        light0.shadow.resolution = (1024, 1024)
        light0.shadow.bias = 0.0001
        light0.shadow.strength = 1
        light0.shadow.radius = 2

        light1.position.y = 5.0
        light1.castShadow = true
        lightHelperMesh1.label = "Light Helper 1"
        light1.add(lightHelperMesh1)
//        if let shadowCamera = light1.shadow.camera as? OrthographicCamera {
//            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
//        }
        light1.shadow.resolution = (1024, 1024)
        light1.shadow.bias = 0.0001
        light1.shadow.strength = 1
        light1.shadow.radius = 2

        shadowScene.setup()
        camera.lookAt(target: shadowScene.sceneTarget)
    }

    lazy var startTime = getTime()

    override func update() throws {
        cameraController.update()

        let time = getTime() - startTime
        var theta = Float(time)
        let radius: Float = 5.0

        shadowScene.update(time: theta)

        light0.position = simd_make_float3(radius * sin(theta), 5.0, radius * cos(theta))
        light0.lookAt(target: shadowScene.sceneTarget, up: Satin.worldUpDirection)

        theta += .pi * 0.5
        light1.position = simd_make_float3(radius * sin(theta), 5.0, radius * cos(theta))
        light1.lookAt(target: shadowScene.sceneTarget, up: Satin.worldUpDirection)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try renderer.draw(
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

    #if os(macOS)
    override func keyDown(with event: NSEvent) -> Bool {
        if !super.keyDown(with: event) {
            if event.characters == " " {
                print("Toggling Lighting & Shadows")
                
                light0.castShadow.toggle()
                light1.castShadow.toggle()
                
                return true
            }
            return false
        }
        return false
    }
    #endif
}
