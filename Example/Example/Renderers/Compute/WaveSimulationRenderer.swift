//
//  WaveSimulationRenderer.swift
//  Example
//
//  Created by Reza Ali on 8/10/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Combine
import Foundation
import Metal
import MetalKit
import Satin

final class WaveSimulationRenderer: BaseRenderer {
    final class WaveComputeSystem: TextureComputeSystem {}
    final class DisplacementMaterial: SourceMaterial {}

    lazy var computer: WaveComputeSystem = .init(
        device: device,
        pipelinesURL: pipelinesURL,
        textureDescriptors: getTextureDescriptors(),
        feedback: true,
        live: true
    )

    lazy var material = DisplacementMaterial(pipelinesURL: pipelinesURL, live: true)
    lazy var mesh = Mesh(geometry: PlaneGeometry(size: 2.0, resolution: 512, orientation: .xy), material: material)

    lazy var scene = Object(label: "Scene", [mesh])

    let camera = PerspectiveCamera(position: [0.0, 0.0, 4.0], near: 0.001, far: 100.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    var appParams = ParameterGroup("App", [
        BoolParameter("Reset", false, .button),
        IntParameter("Iterations", 2, 0, 100, .inputfield)
    ])

    override var paramKeys: [String] {
        return [
            "App",
            "Wave Compute",
            "Displacement Material"
        ]
    }

    override var params: [String: ParameterGroup?] {
        return [
            "App": appParams,
            "Wave Compute": computer.parameters,
            "Displacement Material": material.parameters
        ]
    }

    var subscriptions = Set<AnyCancellable>()

    override func setup() {
        computer.parameters.parameterUpdatedPublisher.sink { [weak self] param in
            if param.controlType != .none {
                self?.computer.reset()
            }
        }.store(in: &subscriptions)

        appParams.get("Reset", as: BoolParameter.self)?.valuePublisher.sink { [weak self] reset in
            if reset {
                self?.computer.reset()
            }
        }.store(in: &subscriptions)

        mesh.cullMode = .none

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
        super.setup()
    }

    deinit {
        cameraController.disable()
    }

    lazy var startTime = getTime()

    override func update() {
        computer.set("Time", Float(getTime() - startTime))
        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        computer.update(commandBuffer, iterations: appParams.get("Iterations", as: IntParameter.self)?.value ?? 1)
        material.set(computer.dstTexture, index: VertexTextureIndex.Custom0)
        material.set(computer.dstTexture, index: FragmentTextureIndex.Custom0)

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
        computer.textureDescriptors = getTextureDescriptors()
    }

    func getTextureDescriptors() -> [MTLTextureDescriptor] {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = 1024
        textureDescriptor.height = 1024
        textureDescriptor.depth = 1
        textureDescriptor.pixelFormat = .rgba32Float
        textureDescriptor.resourceOptions = .storageModePrivate
        textureDescriptor.sampleCount = 1
        textureDescriptor.textureType = .type2D
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.allowGPUOptimizedContents = true
        return [textureDescriptor]
    }
}
