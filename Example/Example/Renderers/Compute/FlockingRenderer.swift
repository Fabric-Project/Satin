//
//  FlockingRenderer.swift
//  Example
//
//  Created by Reza Ali on 8/17/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Combine
import Metal
import Satin
import SwiftUICore

final class FlockingRenderer: BaseRenderer {
    final class FlockingComputeSystem: BufferComputeSystem {}
    final class InstanceMaterial: SourceMaterial {}
    final class SpriteMaterial: SourceMaterial {}

    lazy var startTime = CFAbsoluteTimeGetCurrent()

    // MARK: - Controls

    var cancellables = Set<AnyCancellable>()
    #if os(macOS)
    @Bindable var particleCountParam = IntParameter("Particle Count", 16384, .inputfield)
    #else
    @Bindable var particleCountParam = IntParameter("Particle Count", 4096, .inputfield)
    #endif

    var resetParam = BoolParameter("Reset", false)
    var pauseParam = BoolParameter("Pause", false)

//    lazy var params = ParameterGroup("Controls", [pauseParam, resetParam, particleCountParam])

    lazy var scene = Object(label: "Scene", [sprite])
    let camera = OrthographicCamera()
    lazy var renderer = Renderer(context: defaultContext)
    lazy var particleSystem = FlockingComputeSystem(device: device, pipelinesURL: pipelinesURL, count: particleCountParam.value, feedback: true, live: true)

    lazy var spriteMaterial: SpriteMaterial = {
        let material = SpriteMaterial(pipelinesURL: pipelinesURL)
        material.depthWriteEnabled = false
        return material
    }()

    lazy var sprite: Mesh = {
        let mesh = Mesh(geometry: PointGeometry(), material: spriteMaterial)
        mesh.label = "Sprite"
        mesh.cullMode = .none
        mesh.instanceCount = particleCountParam.value
        mesh.preDraw = { [unowned self] (renderEncoder: MTLRenderCommandEncoder) in
            if let buffer = self.particleSystem.getBuffer("Flocking") {
                renderEncoder.setVertexBuffer(
                    buffer,
                    offset: 0,
                    index: VertexBufferIndex.Custom0.rawValue
                )
            }
            if let uniforms = self.particleSystem.uniforms {
                renderEncoder.setVertexBuffer(
                    uniforms.buffer,
                    offset: uniforms.offset,
                    index: VertexBufferIndex.Custom1.rawValue
                )
            }
        }
        return mesh
    }()

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    override func setup() {
        setupObservers()

        #if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
        #endif
    }

    func setupObservers() {
        particleCountParam.valuePublisher.sink { [weak self] value in
            guard let self = self else { return }
            self.particleSystem.count = value
            self.sprite.instanceCount = value
        }.store(in: &cancellables)

        resetParam.valuePublisher.sink { [weak self] value in
            guard let self = self, value == true else { return }
            self.particleSystem.reset()
            self.resetParam.value = false
        }.store(in: &cancellables)
    }

    override func update() {
        let time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        particleSystem.set("Time", time)
        spriteMaterial.set("Time", time)
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        if !pauseParam.value {
            particleSystem.update(commandBuffer)
        }

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        let hw = size.width
        let hh = size.height
        camera.update(left: -hw, right: hw, bottom: -hh, top: hh, near: -100.0, far: 100.0)

        renderer.resize(size)
        let res: simd_float3 = [size.width, size.height, size.width / size.height]
        spriteMaterial.set("Resolution", res)
        particleSystem.set("Resolution", res)
    }
}
