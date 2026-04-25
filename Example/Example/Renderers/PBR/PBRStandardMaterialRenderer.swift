//
//  StandardMaterialRenderer.swift
//  Satin
//
//  Created by Reza Ali on 11/11/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//
//  Cube Map Texture from: https://hdrihaven.com/hdri/
//

import Metal
import MetalKit

import Satin

import CoreImage
import ModelIO
import UniformTypeIdentifiers

final class PBRStandardMaterialRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }
    override var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }

    override var colorPixelFormat: MTLPixelFormat {
        .rgba16Float
    }

    // MARK: - UI

    override var paramKeys: [String] {
        return ["Material"]
    }

    override var params: [String: ParameterGroup?] {
        return [
            "Material": material.parameters,
        ]
    }

    var model: Object?
    lazy var startTime = getTime()
    lazy var skybox: Mesh = .init(label: "Skybox", geometry: SkyboxGeometry(size: 250), material: SkyboxMaterial())
    lazy var scene = IBLScene(label: "Scene", [skybox])
    lazy var camera = PerspectiveCamera(position: [0.0, 0.0, 4.0], near: 0.01, far: 1000.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    let material = StandardMaterial()

    override func setup() {
        loadHdri()
        setupTextures()
        setupLights()
        setupScene()
        scene.environmentIntensity = 0.375

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
        skybox.visible = false
#endif
    }

    deinit {
        cameraController.disable()
    }

    override func update() {
        model?.orientation = simd_quatf(angle: Float(getTime() - startTime) * 0.5, axis: worldUpDirection)
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

    // MARK: - Lights

    func setupLights() {
        let positions = [
            simd_make_float3(0.0, 0.0, -1.0),
            simd_make_float3(0.0, -1.0, 0.0),
            simd_make_float3(0.0, 1.0, 0.0),
            simd_make_float3(0.0, 0.0, 1.0),
        ]

        let ups = [
            Satin.worldUpDirection,
            Satin.worldRightDirection,
            Satin.worldRightDirection,
            Satin.worldUpDirection,
        ]

        for (index, position) in positions.enumerated() {
            let light = DirectionalLight(color: .one, intensity: 0.5)
            light.position = position
            light.lookAt(target: .zero, up: ups[index])
            scene.add(light)
        }
    }

    // MARK: - Scene

    lazy var textureLoader = MTKTextureLoader(device: device)

    func setupScene() {
        if let model = loadAsset(url: modelsURL.appendingPathComponent("Suzanne").appendingPathComponent("Suzanne.obj")) {
            var mesh: Mesh?
            model.apply { obj in
                if let m = obj as? Mesh {
                    mesh = m
                }
            }
            if let mesh = mesh {
                mesh.material = material
                self.model = mesh
                scene.add(mesh)
            }
        }
    }

    // MARK: - Textures

    func setupTextures() {
        // we do this to make sure we don't recompile the material multiple times
        let cubeDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .r32Float, size: 1, mipmapped: false)
        let cubeTexture = device.makeTexture(descriptor: cubeDesc)
        material.setTexture(cubeTexture, type: .reflection)
        material.setTexture(cubeTexture, type: .irradiance)

        // we do this to make sure we don't recompile the material multiple times
        let tmpDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 1, height: 1, mipmapped: false)
        let tmpTexture = device.makeTexture(descriptor: tmpDesc)
        material.setTexture(tmpTexture, type: .brdf)
        material.setTexture(tmpTexture, type: .baseColor)
        material.setTexture(tmpTexture, type: .occlusion)
        material.setTexture(tmpTexture, type: .metallic)
        material.setTexture(tmpTexture, type: .normal)
        material.setTexture(tmpTexture, type: .roughness)

        let baseURL = modelsURL.appendingPathComponent("Suzanne")
        let maps: [PBRTextureType: URL] = [
            .baseColor: baseURL.appendingPathComponent("albedo.png"),
            .occlusion: baseURL.appendingPathComponent("ao.png"),
            .metallic: baseURL.appendingPathComponent("metallic.png"),
            .normal: baseURL.appendingPathComponent("normal.png"),
            .roughness: baseURL.appendingPathComponent("roughness.png"),
        ]

        let loader = MTKTextureLoader(device: device)
        do {
            for (type, url) in maps {
                let texture = try loader.newTexture(URL: url, options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically,
                ])
                material.setTexture(texture, type: type)
            }
        }
        catch {
            print(error.localizedDescription)
        }
    }

    // MARK: - Environment Textures

    func loadHdri() {
        let url = texturesURL.appendingPathComponent("brown_photostudio_02_2k.hdr")
        if let hdr = loadHDR(device: device, url: url) {
            scene.setEnvironment(texture: hdr)
        }
    }
}
