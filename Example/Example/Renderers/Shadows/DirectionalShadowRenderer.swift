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

    lazy var baseMesh = Mesh(context: defaultContext, 
        geometry: BoxGeometry(context: defaultContext, width: 1.25, height: 0.125, depth: 1.25, resolution: 5),
        material: StandardMaterial(context: defaultContext, baseColor: [1.0, 1.0, 1.0, 1.0], metallic: 0.75, roughness: 0.25)
    )

    lazy var torusMesh = Mesh(context: defaultContext, 
        geometry: TorusGeometry(context: defaultContext, minorRadius: 0.1, majorRadius: 0.5),
        material: StandardMaterial(context: defaultContext, baseColor: [1, 1, 1, 1], metallic: 1.0, roughness: 0.25, specular: 1.0)
    )

    lazy var sphereMesh = Mesh(context: defaultContext, 
        geometry: IcoSphereGeometry(context: defaultContext, radius: 0.25, resolution: 3),
        material: StandardMaterial(context: defaultContext, baseColor: .one, metallic: 0.8, roughness: 0.5, specular: 1.0)
    )

    lazy var floorMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, size: 8.0, orientation: .zx),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.72, 0.74, 0.78, 1.0],
            metallic: 0.0,
            roughness: 0.95
        )
    )

    lazy var light0 = DirectionalLight(context: defaultContext, color: [1.0, 1.0, 1.0], intensity: 1.0)
    lazy var light1 = DirectionalLight(context: defaultContext, color: [1.0, 1.0, 1.0], intensity: 1.0)

    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [light0, light1, floorMesh, baseMesh, sphereMesh, torusMesh])
    lazy var camera = PerspectiveCamera(context: defaultContext, position: .init(repeating: 5.0), near: 0.01, far: 500.0, fov: 30)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
            scene.environmentIntensity = 0.5
        }
    }

    override func setup() {
        loadHdri()
        renderer.clearColor = .init(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)

        light0.position.y = 5.0
        light0.castShadow = true
        lightHelperMesh0.label = "Light Helper 0"
        light0.add(lightHelperMesh0)
        if let shadowCamera = light0.shadow.camera as? OrthographicCamera {
            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
        }
        light0.shadow.resolution = (2048, 2048)
        light0.shadow.bias = 0.0005
        light0.shadow.strength = 1
        light0.shadow.radius = 2

        light1.position.y = 5.0
        light1.castShadow = true
        lightHelperMesh1.label = "Light Helper 1"
        light1.add(lightHelperMesh1)
        if let shadowCamera = light1.shadow.camera as? OrthographicCamera {
            shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
        }
        light1.shadow.resolution = (2048, 2048)
        light1.shadow.bias = 0.0005
        light1.shadow.strength = 1
        light1.shadow.radius = 2

        // Setup things here
        camera.lookAt(target: .zero)
        floorMesh.position.y = -1.0

        torusMesh.label = "Main"
        torusMesh.castShadow = true
        torusMesh.receiveShadow = true

        sphereMesh.label = "Sphere"
        sphereMesh.castShadow = true
        sphereMesh.receiveShadow = true

        baseMesh.label = "Base"
        baseMesh.position.y = -0.75
        baseMesh.castShadow = true
        baseMesh.receiveShadow = true

        floorMesh.label = "Floor"
        floorMesh.receiveShadow = true
    }

    lazy var startTime = getTime()

    override func update() {
        cameraController.update()

        let time = getTime() - startTime
        var theta = Float(time)
        let radius: Float = 5.0

        torusMesh.orientation = simd_quatf(angle: theta, axis: Satin.worldUpDirection)
        torusMesh.orientation *= simd_quatf(angle: theta, axis: Satin.worldRightDirection)

        light0.position = simd_make_float3(radius * sin(theta), 5.0, radius * cos(theta))
        light0.lookAt(target: .zero, up: Satin.worldUpDirection)

        theta += .pi * 0.5
        light1.position = simd_make_float3(radius * sin(theta), 5.0, radius * cos(theta))
        light1.lookAt(target: .zero, up: Satin.worldUpDirection)
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
