//
//  EnhancedPBRRenderer.swift
//  Satin
//
//  Created by Reza Ali on 1/6/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//
//  Cube Map Texture from: https://hdrihaven.com/hdri/
//

import Foundation
import Metal
import MetalKit
import Satin

final class PBREnhancedRenderer: BaseRenderer, MaterialDelegate {
    // MARK: - 3D Scene

    final class CustomShader: PhysicalShader {}

    final class CustomMaterial: PhysicalMaterial {
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
            let shader = CustomShader(context: context, label: label, pipelineURL: pipelineURL)
//            shader.live = true
            return shader
        }
    }

    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [mesh, skybox])
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 0.0, 40.0], near: 0.001, far: 1000.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    lazy var customMaterial: CustomMaterial = {
        lazy var mat = CustomMaterial(context: defaultContext, pipelinesURL: pipelinesURL)
        mat.delegate = self
        mat.set("Base Color", [1.0, 0.0, 0.0, 1.0])
        mat.set("Emissive Color", [1.0, 1.0, 1.0, 0.0])
        return mat
    }()

    lazy var mesh: InstancedMesh = {
        lazy var mesh = InstancedMesh(context: defaultContext, geometry: IcoSphereGeometry(context: defaultContext, radius: 0.875, resolution: 4), material: customMaterial, count: 11 * 12)
        mesh.label = "Spheres"
        lazy var placer = Object(context: defaultContext)
        for y in 0 ..< 12 {
            for x in 0 ..< 11 {
                let index = y * 11 + x
                placer.position = simd_make_float3(2.0 * Float(x) - 10, 2.0 * Float(y) - 11, 0.0)
                mesh.setMatrixAt(index: index, matrix: placer.localMatrix)
            }
        }
        return mesh
    }()

    lazy var skyboxMaterial = SkyboxMaterial(context: defaultContext)
    lazy var skybox = Mesh(context: defaultContext, geometry: SkyboxGeometry(context: defaultContext, size: 50), material: skyboxMaterial)

    override func setup() {
        setupLights()
        loadHdri()
    }

    deinit {
        cameraController.disable()
    }

    func setupLights() {
        let dist: Float = 12.0
        let positions = [
            simd_make_float3(dist, dist, dist),
            simd_make_float3(-dist, dist, dist),
            simd_make_float3(dist, -dist, dist),
            simd_make_float3(-dist, -dist, dist),
        ]

        let sphereLightGeo: Geometry = mesh.geometry
        lazy var sphereLightMat = BasicColorMaterial(context: defaultContext, color: .one, blending: .disabled)
        for (index, position) in positions.enumerated() {
            lazy var light = PointLight(context: defaultContext, color: .one, intensity: 250, radius: 150.0)
            light.position = position
            lazy var lightMesh = Mesh(context: defaultContext, geometry: sphereLightGeo, material: sphereLightMat)
            lightMesh.scale = .init(repeating: 0.25)
            lightMesh.label = "Light Mesh \(index)"
            light.add(lightMesh)

            scene.add(light)
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

    func updated(material: Satin.Material) {
    }
}
