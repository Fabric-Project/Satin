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

    lazy var floorMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, size: 11.0, orientation: .zx),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.72, 0.74, 0.78, 1.0],
            metallic: 0.0,
            roughness: 0.96
        )
    )

    lazy var backdropMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: 11.0, height: 6.5, orientation: .xy),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.63, 0.66, 0.71, 1.0],
            metallic: 0.0,
            roughness: 0.98
        )
    )

    lazy var baseMesh = Mesh(
        context: defaultContext,
        geometry: BoxGeometry(context: defaultContext, width: 1.65, height: 0.25, depth: 1.65, resolution: 4),
        material: StandardMaterial(context: defaultContext, baseColor: [0.87, 0.89, 0.94, 1.0], metallic: 0.15, roughness: 0.82)
    )

    lazy var torusMesh = Mesh(
        context: defaultContext,
        geometry: TorusGeometry(context: defaultContext, minorRadius: 0.12, majorRadius: 0.65),
        material: StandardMaterial(context: defaultContext, baseColor: [0.98, 0.98, 1.0, 1.0], metallic: 1.0, roughness: 0.2, specular: 1.0)
    )

    lazy var sphereMesh = Mesh(
        context: defaultContext,
        geometry: IcoSphereGeometry(context: defaultContext, radius: 0.55, resolution: 4),
        material: StandardMaterial(context: defaultContext, baseColor: [0.96, 0.95, 0.98, 1.0], metallic: 0.82, roughness: 0.18, specular: 1.0)
    )

    lazy var boxMesh = Mesh(
        context: defaultContext,
        geometry: BoxGeometry(context: defaultContext, width: 1.1, height: 1.6, depth: 1.1, resolution: 3),
        material: StandardMaterial(context: defaultContext, baseColor: [0.89, 0.92, 0.98, 1.0], metallic: 0.45, roughness: 0.28, specular: 0.9)
    )

    lazy var coneMesh = Mesh(
        context: defaultContext,
        geometry: ConeGeometry(context: defaultContext, radius: 0.6, height: 1.7, angularResolution: 72, radialResolution: 1, verticalResolution: 8),
        material: StandardMaterial(context: defaultContext, baseColor: [0.93, 0.9, 0.86, 1.0], metallic: 0.2, roughness: 0.48, specular: 0.75)
    )

    lazy var cylinderMesh = Mesh(
        context: defaultContext,
        geometry: CylinderGeometry(context: defaultContext, radius: 0.38, height: 1.45, angularResolution: 72, radialResolution: 1, verticalResolution: 5),
        material: StandardMaterial(context: defaultContext, baseColor: [0.82, 0.86, 0.92, 1.0], metallic: 0.55, roughness: 0.32, specular: 0.9)
    )

    lazy var light0 = PointLight(context: defaultContext, color: [1.0, 0.45, 0.25], intensity: 170.0, radius: 16.0)
    lazy var light1 = PointLight(context: defaultContext, color: [0.2, 0.78, 1.0], intensity: 150.0, radius: 16.0)

    lazy var scene = IBLScene(
        context: defaultContext,
        label: "Scene",
        [light0, light1, floorMesh, backdropMesh, baseMesh, torusMesh, sphereMesh, boxMesh, coneMesh, cylinderMesh]
    )

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [8.0, 4.6, 8.0], near: 0.01, far: 500.0, fov: 34.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    lazy var startTime = getTime()

    func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
            scene.environmentIntensity = 0.08
        }
    }

    override func setup() {
        loadHdri()
        renderer.clearColor = .init(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)

        setupLights()

        camera.lookAt(target: [0.0, -0.15, 0.0])

        floorMesh.label = "Floor"
        floorMesh.position.y = -1.0
        floorMesh.receiveShadow = true

        backdropMesh.label = "Backdrop"
        backdropMesh.position = [0.0, 2.1, -5.0]
        backdropMesh.receiveShadow = true

        baseMesh.label = "Base"
        baseMesh.position = [0.0, -0.875, 0.0]
        baseMesh.castShadow = true
        baseMesh.receiveShadow = true

        torusMesh.label = "Main"
        torusMesh.position = [0.0, 0.1, 0.0]
        torusMesh.castShadow = true
        torusMesh.receiveShadow = true

        sphereMesh.label = "Sphere"
        sphereMesh.position = [1.95, -0.45, 1.25]
        sphereMesh.castShadow = true
        sphereMesh.receiveShadow = true

        boxMesh.label = "Box"
        boxMesh.position = [-1.9, -0.2, -1.2]
        boxMesh.castShadow = true
        boxMesh.receiveShadow = true

        coneMesh.label = "Cone"
        coneMesh.position = [1.55, -0.15, -1.85]
        coneMesh.castShadow = true
        coneMesh.receiveShadow = true

        cylinderMesh.label = "Cylinder"
        cylinderMesh.position = [-2.25, -0.275, 1.55]
        cylinderMesh.castShadow = true
        cylinderMesh.receiveShadow = true
    }

    func setupLights() {
        light0.label = "Warm Point Light"
        light0.position = [3.25, 2.15, 0.0]
        light0.castShadow = true
        light0.shadow.resolution = (1024, 1024)
        light0.shadow.bias = 0.0005
        light0.shadow.normalBias = 0.05
        light0.shadow.radius = 1.5
        light0.shadow.strength = 0.95
        lightHelperMesh0.label = "Light Helper 0"
        light0.add(lightHelperMesh0)

        light1.label = "Cool Point Light"
        light1.position = [-2.45, 2.55, 0.0]
        light1.castShadow = true
        light1.shadow.resolution = (1024, 1024)
        light1.shadow.bias = 0.0005
        light1.shadow.normalBias = 0.05
        light1.shadow.radius = 1.5
        light1.shadow.strength = 0.95
        lightHelperMesh1.label = "Light Helper 1"
        light1.add(lightHelperMesh1)
    }

    override func update() {
        cameraController.update()

        let time = Float(getTime() - startTime)
        let theta = time * 0.8

        torusMesh.orientation = simd_quatf(angle: theta, axis: Satin.worldUpDirection)
        torusMesh.orientation *= simd_quatf(angle: theta * 0.35, axis: Satin.worldRightDirection)

        boxMesh.orientation = simd_quatf(angle: theta * 0.2, axis: simd_normalize([0.0, 1.0, 0.2]))
        coneMesh.orientation = simd_quatf(angle: -theta * 0.45, axis: Satin.worldUpDirection)
        cylinderMesh.orientation = simd_quatf(angle: theta * 0.28, axis: Satin.worldUpDirection)

        light0.position = simd_make_float3(
            cos(theta) * 3.25,
            2.15 + sin(theta * 1.35) * 0.24,
            sin(theta) * 3.25
        )

        let theta1 = -.pi + theta * 0.9
        light1.position = simd_make_float3(
            cos(theta1) * 2.45,
            2.55 + sin(theta * 1.1 + 1.2) * 0.2,
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
