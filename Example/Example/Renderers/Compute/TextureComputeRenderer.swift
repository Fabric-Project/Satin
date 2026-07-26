//
//  RenderEncoder.swift
//  Example
//
//  Created by Reza Ali on 6/11/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Combine
import Metal
import MetalKit
import Satin

class TextureComputeRenderer: BaseRenderer {
    final class ReactionDiffusionComputeSystem: TextureComputeSystem {}
    final class DisplacementMaterial: SourceMaterial {}

    lazy var textureCompute: ReactionDiffusionComputeSystem = {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = 512
        textureDescriptor.height = 512
        textureDescriptor.depth = 1
        textureDescriptor.pixelFormat = .rgba32Float
        textureDescriptor.resourceOptions = .storageModePrivate
        textureDescriptor.sampleCount = 1
        textureDescriptor.textureType = .type2D
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.allowGPUOptimizedContents = true

        return ReactionDiffusionComputeSystem(
            device: device,
            pipelinesURL: pipelinesURL,
            textureDescriptors: [textureDescriptor],
            feedback: true,
            live: true
        )
    }()

    lazy var material = DisplacementMaterial(context: defaultContext, pipelinesURL: pipelinesURL, live: true)
    lazy var mesh = Mesh(context: defaultContext, geometry: PlaneGeometry(context: defaultContext, size: 2.0, resolution: 512, orientation: .xy), material: material)

    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])
    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 0.0, 4.0], near: 0.001, far: 100.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    override var paramKeys: [String] {
        return [
            "Reaction Diffusion",
            "Displacement Material"
        ]
    }

    override var params: [String: ParameterGroup?] {
        return [
            "Reaction Diffusion": textureCompute.parameters,
            "Displacement Material": material.parameters
        ]
    }

    var subscriptions = Set<AnyCancellable>()

    override func setup() throws {
        textureCompute.parameters.parameterUpdatedPublisher.sink { [weak self] _ in
            self?.textureCompute.reset()
        }.store(in: &subscriptions)

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
        try super.setup()
    }

    override func update() throws {
        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        textureCompute.update(commandBuffer, iterations: 30)
        material.set(textureCompute.dstTexture, index: VertexTextureIndex.Custom0)

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
}
