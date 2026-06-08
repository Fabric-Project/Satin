//
//  PointShadowRenderer.swift
//  Example
//
//  Created by OpenAI on 4/20/26.
//

import Metal
import MetalKit
import Satin

final class PointShadowRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    lazy var lightHelperGeo = IcoSphereGeometry(context: defaultContext, radius: 0.14, resolution: 1)
    lazy var lightHelperMat0 = BasicColorMaterial(context: defaultContext, color: [1.0, 0.45, 0.25, 1.0], blending: .disabled)
    lazy var lightHelperMat1 = BasicColorMaterial(context: defaultContext, color: [0.2, 0.78, 1.0, 1.0], blending: .disabled)
    lazy var lightHelperMesh0 = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat0)
    lazy var lightHelperMesh1 = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat1)
    lazy var shadowScene = StandardShadowSceneContent(context: defaultContext)

    lazy var light0 = PointLight(context: defaultContext, color: [1.0, 0.45, 0.25], intensity: 50.0, radius: 16.0)
    lazy var light1 = PointLight(context: defaultContext, color: [0.2, 0.78, 1.0], intensity: 50.0, radius: 16.0)

    lazy var scene = IBLScene(
        context: defaultContext,
        label: "Scene",
        [light0, light1] + shadowScene.objects
    )

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [8.0, 4.8, 8.2], near: 0.01, far: 500.0, fov: 34.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    lazy var startTime = getTime()

    func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
            scene.environmentIntensity = 0.1
        }
    }

    override func setup() {
        loadHdri()
        renderer.clearColor = .init(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)

        setupLights()

        shadowScene.setup()
        camera.lookAt(target: shadowScene.sceneTarget)
    }

    func setupLights() {
        light0.label = "Warm Point Light"
        light0.position = [3.25, 1.5, 0.0]
        light0.castShadow = true
        light0.shadow.resolution = (1024, 1024)
        light0.shadow.bias = 0.0001
//        light0.shadow.normalBias = 0.05
        light0.shadow.radius = 1.5
        light0.shadow.strength = 0.95
        lightHelperMesh0.label = "Light Helper 0"
        light0.add(lightHelperMesh0)

        light1.label = "Cool Point Light"
        light1.position = [-2.45, 1.5, 0.0]
        light1.castShadow = true
        light1.shadow.resolution = (1024, 1024)
        light1.shadow.bias = 0.0001
//        light1.shadow.normalBias = 0.05
        light1.shadow.radius = 1.5
        light1.shadow.strength = 0.95
        lightHelperMesh1.label = "Light Helper 1"
        light1.add(lightHelperMesh1)
    }

    override func update() {
        cameraController.update()

        let time = Float(getTime() - startTime)
        let theta = time * 0.8

        shadowScene.update(time: theta)

        light0.position = simd_make_float3(
            cos(theta) * 3.25,
            1.5 + sin(theta * 1.35) * 0.24,
            sin(theta) * 3.25
        )

        let theta1 = -.pi + theta * 0.9
        light1.position = simd_make_float3(
            cos(theta1) * 2.45,
            1.5 + sin(theta * 1.1 + 1.2) * 0.2,
            sin(theta1) * 2.45
        )
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

    #if os(macOS)
    override func keyDown(with event: NSEvent) -> Bool {
        if !super.keyDown(with: event) {
            if event.characters == " " {
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
