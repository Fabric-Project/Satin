//
//  SpotShadowRenderer.swift
//  Example
//
//  Created by OpenAI on 4/20/26.
//

import Metal
import MetalKit
import Satin

final class SpotShadowRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    lazy var lightHelperGeo = IcoSphereGeometry(context: defaultContext, radius: 0.14, resolution: 1)
    lazy var lightHelperMat0 = BasicColorMaterial(context: defaultContext, color: [1.0, 0.72, 0.42, 1.0], blending: .disabled)
    lazy var lightHelperMat1 = BasicColorMaterial(context: defaultContext, color: [0.38, 0.72, 1.0, 1.0], blending: .disabled)
    lazy var lightHelperMesh0 = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat0)
    lazy var lightHelperMesh1 = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat1)
    lazy var shadowScene = StandardShadowSceneContent(context: defaultContext)

    lazy var light0 = SpotLight(
        context: defaultContext,
        color: [1.0, 0.76, 0.48],
        intensity: 260.0,
        radius: 12.5,
        angleInner: 15.0,
        angleOuter: 24.0
    )

    lazy var light1 = SpotLight(
        context: defaultContext,
        color: [0.35, 0.74, 1.0],
        intensity: 235.0,
        radius: 12.5,
        angleInner: 16.0,
        angleOuter: 25.0
    )

    lazy var scene = IBLScene(
        context: defaultContext,
        label: "Scene",
        [light0, light1] + shadowScene.objects
    )

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [8.0, 4.8, 8.2], near: 0.01, far: 500.0, fov: 34.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    lazy var textureLoader = MTKTextureLoader(device: device)

    lazy var startTime = getTime()

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

        setupLights()

        shadowScene.setup()
        camera.lookAt(target: shadowScene.sceneTarget)
    }

    func setupLights() {
        light0.label = "Warm Spot Light"
        light0.position = [3.3, 2.0, 1.4]
        light0.castShadow = true
        light0.shadow.resolution = (1024, 1024)
        light0.shadow.bias = 0.0001
        light0.shadow.radius = 1.25
        light0.shadow.strength = 0.96
        light0.add(lightHelperMesh0)
        light0.lookAt(target: shadowScene.sceneTarget, up: Satin.worldUpDirection)

        var url = texturesURL.appendingPathComponent("light_02.png")
        do {
            light0.projectionTexture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: true,
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically,
            ])
        }
        catch {
            print(error.localizedDescription)
        }
        
        light1.label = "Cool Spot Light"
        light1.position = [-2.9, 2.0, -1.5]
        light1.castShadow = true
        light1.shadow.resolution = (1024, 1024)
        light1.shadow.bias = 0.0001
        light1.shadow.radius = 1.25
        light1.shadow.strength = 0.96
        light1.add(lightHelperMesh1)
        light1.lookAt(target: shadowScene.sceneTarget, up: Satin.worldUpDirection)
        
        url = texturesURL.appendingPathComponent("window_04.png")
        do {
            light1.projectionTexture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: true,
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically,
            ])
            
            light1.projectionMode = .color
        }
        catch {
            print(error.localizedDescription)
        }
    }

    override func update() throws {
        cameraController.update()

        let time = Float(getTime() - startTime)
        let theta = time * 0.72

        shadowScene.update(time: theta)

        let target0 = simd_make_float3(
            sin(theta * 0.42) * 0.6,
            shadowScene.sceneTarget.y + 0.2 + sin(theta * 0.8) * 0.08,
            cos(theta * 0.36) * 0.45
        )

        light0.position = simd_make_float3(
            cos(theta) * 3.7,
            1.5 + sin(theta * 1.18) * 0.22,
            sin(theta) * 3.1
        )
        light0.lookAt(target: target0, up: Satin.worldUpDirection)

        let theta1 = theta * 0.88 + .pi * 0.92
        let target1 = simd_make_float3(
            cos(theta * 0.37 + 1.1) * 0.55,
            shadowScene.sceneTarget.y + 0.2 + sin(theta * 0.73 + 0.5) * 0.07,
            sin(theta * 0.43 + 0.3) * 0.5
        )

        light1.position = simd_make_float3(
            cos(theta1) * 3.25,
            1.5 + sin(theta * 1.03 + 0.9) * 0.24,
            sin(theta1) * 3.55
        )
        light1.lookAt(target: target1, up: Satin.worldUpDirection)
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
