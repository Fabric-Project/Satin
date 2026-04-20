//
//  Renderer.swift
//  Cubemap
//
//  Created by Reza Ali on 6/7/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//
//  Cube Map Texture from: https://hdrihaven.com/hdri/
//

import Metal
import MetalKit
import Satin

final class PBRRenderer: BaseRenderer {
    final class CustomShader: PBRShader {}
    final class CustomMaterial: StandardMaterial {
        var pipelineURL: URL
        init(context: Context, pipelinesURL: URL) {
            pipelineURL = pipelinesURL.appendingPathComponent("Custom").appendingPathComponent("Shaders.metal")
            super.init(context: context, baseColor: .one, metallic: .zero, roughness: .zero)
        }

        required init(context: Context) {
            pipelineURL = URL(fileURLWithPath: "")
            super.init(context: context)
        }

        required init(from _: Decoder) throws {
            fatalError("init(from:) has not been implemented")
        }

        override func createShader() -> Shader {
            return CustomShader(context: context, label: label, pipelineURL: pipelineURL)
        }
    }

    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    lazy var floorMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, size: 32.0, orientation: .zx),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.8, 0.82, 0.86, 1.0],
            metallic: 0.0,
            roughness: 0.95
        )
    )

    lazy var backdropMesh = Mesh(
        context: defaultContext,
        geometry: PlaneGeometry(context: defaultContext, width: 30.0, height: 24.0, orientation: .xy),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.84, 0.86, 0.9, 1.0],
            metallic: 0.0,
            roughness: 0.9
        )
    )
    
    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [floorMesh, backdropMesh, mesh, skybox])
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 6.0, 40.0], near: 0.001, far: 1000.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    lazy var customMaterial: CustomMaterial = {
        lazy var mat = CustomMaterial(context: defaultContext, pipelinesURL: pipelinesURL)
        mat.lighting = true
        mat.set("Base Color", [1.0, 1.0, 1.0, 1.0])
        mat.set("Emissive Color", [0.0, 0.0, 0.0, 0.0])
        return mat
    }()

    lazy var mesh: InstancedMesh = {
        lazy var mesh = InstancedMesh(context: defaultContext, geometry: IcoSphereGeometry(context: defaultContext, radius: 0.875, resolution: 4), material: customMaterial, count: 11 * 11)
        mesh.label = "Spheres"
        lazy var placer = Object(context: defaultContext)
        for y in 0 ..< 11 {
            for x in 0 ..< 11 {
                let index = y * 11 + x
                placer.position = simd_make_float3(2.0 * Float(x) - 10, 2.0 * Float(y) - 10, 0.0)
                mesh.setMatrixAt(index: index, matrix: placer.localMatrix)
            }
        }
        return mesh
    }()

    lazy var skybox = Mesh(context: defaultContext, geometry: SkyboxGeometry(context: defaultContext, size: 50), material: SkyboxMaterial(context: defaultContext))

    override func setup() {
        camera.lookAt(target: .zero)
        mesh.castShadow = true
        mesh.receiveShadow = true

        floorMesh.label = "Floor"
        floorMesh.position.y = -12.5
        floorMesh.receiveShadow = true

        backdropMesh.label = "Backdrop"
        backdropMesh.position.z = -8.0
        backdropMesh.receiveShadow = true

        loadHdri()
        setupLights()
    }

    func setupLights() {
        let dist: Float = 6.0
        let positions = [
            simd_make_float3(dist, dist, dist),
            simd_make_float3(-dist * 0.95, dist * 0.75, dist * 0.85),
            simd_make_float3(dist * 0.35, -dist * 0.9, dist * 0.5),
            simd_make_float3(-dist * 0.5, -dist * 0.35, dist * 1.1),
        ]
        let colors: [simd_float3] = [
            [1.0, 0.94, 0.86],
            [0.78, 0.86, 1.0],
            [1.0, 0.76, 0.62],
            [0.72, 0.8, 1.0],
        ]
        let intensities: [Float] = [325.0, 160.0, 110.0, 85.0]

        let sphereLightGeo: Geometry = mesh.geometry
        for (index, position) in positions.enumerated() {
            lazy var light = PointLight(
                context: defaultContext,
                color: colors[index],
                intensity: intensities[index],
                radius: 120
            )
            light.position = position
//            if index == 0 {
                light.castShadow = true
                light.shadow.resolution = (1024, 1024)
                light.shadow.bias = 0.0005
                light.shadow.normalBias = 0.05
                light.shadow.radius = 1.0
                light.shadow.strength = 0.75
            
//            if let shadowCamera = light.shadow.camera as? OrthographicCamera {
//                shadowCamera.update(left: -2, right: 2, bottom: -2, top: 2)
//            }

//            }

            lazy var lightMesh = Mesh(
                context: defaultContext,
                geometry: sphereLightGeo,
                material: BasicColorMaterial(context: defaultContext, color: simd_make_float4(colors[index], 1.0), blending: .disabled)
            )
            lightMesh.scale = .init(repeating: 0.25)
            lightMesh.label = "Light Mesh \(index)"
            light.add(lightMesh)

            scene.add(light)
            
            scene.environmentIntensity = 0.05
        }
    }

    func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr)
        }
    }

    override func update() {
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

    override func resize(size: (width: Float, height: Float), scaleFactor _: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
