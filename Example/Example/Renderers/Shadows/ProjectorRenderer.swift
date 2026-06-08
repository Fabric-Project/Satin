//
//  ProjectorRenderer.swift
//  Example
//
//  Created by OpenAI on 4/20/26.
//

import Metal
import MetalKit
import Satin

final class ProjectorRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    lazy var lightHelperGeo = IcoSphereGeometry(context: defaultContext, radius: 0.16, resolution: 1)
    lazy var lightHelperMat = BasicColorMaterial(context: defaultContext, color: [1.0, 0.98, 0.9, 1.0], blending: .disabled)
    lazy var lightHelperMesh = Mesh(context: defaultContext, geometry: lightHelperGeo, material: lightHelperMat)
    lazy var shadowScene = StandardShadowSceneContent(context: defaultContext)

    lazy var projectorLight = SpotLight(
        context: defaultContext,
        color: [1.0, 1.0, 1.0],
        intensity: 360.0,
        radius: 14.0,
        angleInner: 15.0,
        angleOuter: 30.0
    )

    lazy var scene = IBLScene(
        context: defaultContext,
        label: "Scene",
        [projectorLight] + shadowScene.objects
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

    func loadProjectorTexture() {
        let url = texturesURL.appendingPathComponent("PM5544_with_non-PAL_signals.png")
        do {
            projectorLight.projectionTexture = try textureLoader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.SRGB: true,
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically,
            ])
        }
        catch {
            print(error.localizedDescription)
        }
    }

    override func setup() {
        loadHdri()
        loadProjectorTexture()
        renderer.clearColor = .init(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)

        setupProjector()

        shadowScene.setup()
        camera.lookAt(target: shadowScene.sceneTarget)
    }

    func setupProjector() {
        projectorLight.label = "Projector"
        projectorLight.position = [0.0, 1.5, 4.75]
        projectorLight.castShadow = true
        projectorLight.projectionMode = .color
        projectorLight.shadow.resolution = (1024, 1024)
        projectorLight.shadow.bias = 0.0001
//        projectorLight.shadow.normalBias = 0.055
        projectorLight.shadow.radius = 1
        projectorLight.shadow.strength = 2
        projectorLight.add(lightHelperMesh)
        projectorLight.lookAt(target: shadowScene.sceneTarget, up: Satin.worldUpDirection)
    }

    override func update() {
        cameraController.update()

        let time = Float(getTime() - startTime)
        let theta = time * 0.48

        shadowScene.update(time: theta)

        projectorLight.position = simd_make_float3(
            sin(theta) * 2.5,
            2.0 + sin(theta * 0.62) * 1.5,
            7.0 + cos(theta * 0.75) * 0.75
        )

        let target = simd_make_float3(
            sin(theta * 0.54) * 0.35,
            -0.14 + sin(theta * 0.38) * 0.05,
            shadowScene.sceneTarget.z + cos(theta * 0.46) * 0.24
        )
        projectorLight.lookAt(target: target, up: Satin.worldUpDirection)
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
                projectorLight.castShadow.toggle()
                return true
            }
            return false
        }
        return false
    }
    #endif
}
