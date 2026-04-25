//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 6/25/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import Satin

final class BufferComputeRenderer: BaseRenderer {
    final class ParticleComputeSystem: BufferComputeSystem {}
    final class SpriteMaterial: SourceMaterial {}
    final class ChromaMaterial: SourceMaterial {}

    lazy var particleSystem = ParticleComputeSystem(device: device, pipelinesURL: pipelinesURL, count: 8192, live: true)

    lazy var spriteMaterial: SpriteMaterial = {
        let material = SpriteMaterial(pipelinesURL: pipelinesURL)
        material.blending = .additive
        material.depthWriteEnabled = false
        return material
    }()

    lazy var mesh: Mesh = {
        let mesh = Mesh(geometry: PointGeometry(), material: spriteMaterial)
        mesh.instanceCount = particleSystem.count
        mesh.preDraw = { [unowned self] (renderEncoder: MTLRenderCommandEncoder) in
            if let buffer = self.particleSystem.getBuffer("Particle") {
                renderEncoder.setVertexBuffer(buffer, offset: 0, index: VertexBufferIndex.Custom0.rawValue)
            }
        }
        return mesh
    }()

    let camera = PerspectiveCamera(position: [0.0, 0.0, 100.0], near: 0.001, far: 1000.0)

    lazy var scene = Object(label: "Scene", [mesh])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    var startTime: CFAbsoluteTime = 0.0

    // MARK: Render to Texture

    var renderTexture: MTLTexture!
    var _updateRenderTexture = true

    lazy var chromaMaterial = ChromaMaterial(pipelinesURL: pipelinesURL)

    lazy var chromaticProcessor = PostProcessor(label: "Chroma Processor", context: Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat), material: chromaMaterial)

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    override func setup() {
        startTime = CFAbsoluteTimeGetCurrent()
    }

    deinit {
        cameraController.disable()
    }

    override func update() {
        var time = Float(CFAbsoluteTimeGetCurrent() - startTime)
        chromaMaterial.set("Time", time)

        time *= 0.25
        let radius: Float = 10.0 * sin(time * 0.5) * cos(time)
        camera.position = simd_make_float3(radius * sin(time), radius * cos(time), 100.0)
        cameraController.update()
    }

    func updateRenderTexture(width: Int, height: Int) {
        guard _updateRenderTexture else { return }

        renderTexture = createTexture(
            label: "Render Texture",
            pixelFormat: colorPixelFormat,
            width: width,
            height: height
        )

        _updateRenderTexture = false
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        updateRenderTexture(
            width: Int(metalView.drawableSize.width),
            height: Int(metalView.drawableSize.height)
        )

        particleSystem.update(commandBuffer)

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            renderTarget: renderTexture
        )

        chromaMaterial.set(renderTexture, index: FragmentTextureIndex.Custom0)

        chromaticProcessor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
        chromaticProcessor.resize(size: size, scaleFactor: scaleFactor)
        _updateRenderTexture = true
    }

    func createTexture(label: String, pixelFormat: MTLPixelFormat, width: Int, height: Int) -> MTLTexture? {
        if width > 0, height > 0 {
            let descriptor = MTLTextureDescriptor()
            descriptor.pixelFormat = pixelFormat
            descriptor.width = width
            descriptor.height = height
            descriptor.sampleCount = 1
            descriptor.textureType = .type2D
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            descriptor.resourceOptions = .storageModePrivate
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            texture.label = label
            return texture
        }
        return nil
    }
}
