//
//  Renderer.swift
//  Cubemap
//
//  Created by Reza Ali on 6/7/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//
//  Cube Map Texture (quarry_01) from: https://hdrihaven.com/hdri/
//

import Metal
import MetalKit

import Satin

final class CubemapRenderer: BaseRenderer {
    final class CustomMaterial: SourceMaterial {}

    var camera = PerspectiveCamera(position: [0.0, 0.0, 6.0], near: 0.001, far: 200.0, fov: 45.0)

    lazy var scene = Object(label: "Scene", [skybox, mesh])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    lazy var mesh: Mesh = {
        let twoPi = Float.pi * 2.0
        let geometry = ParametricGeometry(rangeU: 0.0...twoPi, rangeV: 0.0...twoPi, resolution: [400, 32], generator: { u, v in
            let R: Float = 0.75
            let r: Float = 0.25
            let c: Float = 0.125
            let q: Float = 2.0
            let p: Float = 6.0
            return torusKnotGenerator(u, v, R, r, c, q, p)
        })

        let mesh = Mesh(geometry: geometry, material: customMaterial)
        mesh.cullMode = .none
        mesh.label = "Knot"
        mesh.preDraw = { [unowned self] (renderEncoder: MTLRenderCommandEncoder) in
            renderEncoder.setFragmentTexture(self.cubeTexture, index: FragmentTextureIndex.Custom0.rawValue)
        }
        return mesh
    }()

    lazy var customMaterial = CustomMaterial(pipelineURL: pipelinesURL.appendingPathComponent("Shaders.metal"))

    lazy var skybox: Mesh = {
        let mesh = Mesh(label: "Skybox", geometry: SkyboxGeometry(), material: SkyboxMaterial())
        mesh.scale = [50, 50, 50]
        return mesh
    }()

    var cubeTexture: MTLTexture!

    override func setup() {
        let url = texturesURL.appendingPathComponent("Cubemap")
        cubeTexture = loadCubemap(
            device,
            [
                url.appendingPathComponent("px.png"),
                url.appendingPathComponent("nx.png"),
                url.appendingPathComponent("py.png"),
                url.appendingPathComponent("ny.png"),
                url.appendingPathComponent("pz.png"),
                url.appendingPathComponent("nz.png"),
            ],
            false // <- generates mipmaps
        )

        if let texture = cubeTexture, let material = skybox.material as? SkyboxMaterial {
            material.texture = texture
        }
    }

    deinit {
        cameraController.disable()
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

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
