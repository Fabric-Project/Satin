//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 6/11/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Forge
import Satin

class TextureComputeRenderer: BaseRenderer {
    class BasicTextureComputeSystem: TextureComputeSystem {}

    lazy var textureCompute: BasicTextureComputeSystem = {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = 512
        textureDescriptor.height = 512
        textureDescriptor.depth = 1
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.resourceOptions = .storageModePrivate
        textureDescriptor.sampleCount = 1
        textureDescriptor.textureType = .type2D
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        return BasicTextureComputeSystem(
            device: device,
            pipelinesURL: pipelinesURL,
            textureDescriptors: [textureDescriptor],
            live: true
        )
    }()

    var material = BasicTextureMaterial(texture: nil)
    lazy var mesh = Mesh(geometry: BoxGeometry(), material: material)

    lazy var scene = Object(label: "Scene", [mesh])
    lazy var context = Context(device, sampleCount, colorPixelFormat, depthPixelFormat, stencilPixelFormat)

    lazy var camera = PerspectiveCamera(position: [0.0, 0.0, 9.0], near: 0.001, far: 100.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: mtkView)
    lazy var renderer = Satin.Renderer(context: context)

    override func setupMtkView(_ metalKitView: MTKView) {
        metalKitView.sampleCount = 1
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.preferredFramesPerSecond = 60
    }

    lazy var startTime: CFAbsoluteTime = getTime()

    override func setup() {
        material.texture = textureCompute.dstTexture
    }

    deinit {
        cameraController.disable()
    }
    
    override func update() {
        material.texture = textureCompute.dstTexture
        cameraController.update()
        textureCompute.set("Time", Float(getTime() - startTime))
        camera.update()
        scene.update()
    }

    override func draw(_ view: MTKView, _ commandBuffer: MTLCommandBuffer) {
        textureCompute.update(commandBuffer)
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(_ size: (width: Float, height: Float)) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }

    func getTime() -> CFAbsoluteTime {
        return CFAbsoluteTimeGetCurrent()
    }
}
