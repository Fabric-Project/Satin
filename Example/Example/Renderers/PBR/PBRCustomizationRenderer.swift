//
//  PBRCustomizationRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/4/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//
//  Cube Map Texture from: https://hdrihaven.com/hdri/
//

import Metal
import Satin

final class PBRCustomizationRenderer: BaseRenderer {
    // MARK: - 3D Scene

    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    lazy var material = PhysicalMaterial(context: defaultContext)
    lazy var mesh = Mesh(context: defaultContext, geometry: BoxGeometry(context: defaultContext, size: 4.0), material: material)
    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [skybox, mesh])
    lazy var camera = PerspectiveCamera(context: defaultContext, position: .init(repeating: 10.0), near: 0.001, far: 1000.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    lazy var skyboxMaterial = SkyboxMaterial(context: defaultContext)
    lazy var skybox = Mesh(context: defaultContext, geometry: SkyboxGeometry(context: defaultContext, size: 200), material: skyboxMaterial)

    override func setup() throws {
        camera.lookAt(target: .zero)
        loadHdri()
        try generateNoiseTexture()
    }

    func loadHdri() {
        let filename = "brown_photostudio_02_2k.hdr"
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent(filename)) {
            scene.setEnvironment(texture: hdr, completion: Self.reportEnvironmentLoadingResult)
        }
    }

    override func update(frame: FrameTime) throws {
        try super.update(frame: frame)

        cameraController.update(frame: frame)
        let osc = Float(sin(frame.time)) * 0.5
        let scale = simd_float2(repeating: osc + 1.0)
        let rotation: Float = osc * Float.pi
        let offset = simd_float2(repeating: -0.5)
        material.setTexcoordTransform(offset: offset, scale: scale, rotation: rotation, type: .roughness)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try renderer.draw(
            frame: frameTime,
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

    func generateNoiseTexture() throws {
        let randomNoiseGenerator = RandomNoiseGenerator(device: device, size: (64, 64), range: 0.0 ... 0.5)
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let noiseTexture = try randomNoiseGenerator.encode(commandBuffer: commandBuffer)
            commandBuffer.addCompletedHandler { _ in
                self.material.metallic = 1.0
                self.material.setTexture(noiseTexture, type: .roughness)
                let sampler = MTLSamplerDescriptor()
                sampler.minFilter = .nearest
                sampler.magFilter = .nearest
                sampler.sAddressMode = .repeat
                sampler.tAddressMode = .repeat
                self.material.setSampler(sampler, type: .roughness)
            }
            commandBuffer.commit()
        }
    }
}
