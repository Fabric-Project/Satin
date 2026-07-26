//
//  RenderEncoder.swift
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
        lazy var material = SpriteMaterial(context: defaultContext, pipelinesURL: pipelinesURL)
        material.blending = .additive
        material.depthWriteEnabled = false
        return material
    }()

    lazy var mesh: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, geometry: PointGeometry(context: defaultContext), material: spriteMaterial)
        mesh.instanceCount = particleSystem.count
        mesh.preDraw = { [unowned self] (renderEncoder: MTLRenderCommandEncoder) in
            if let buffer = self.particleSystem.getBuffer("Particle") {
                renderEncoder.setVertexBuffer(buffer, offset: 0, index: VertexBufferIndex.Custom0.rawValue)
            }
        }
        return mesh
    }()

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 0.0, 100.0], near: 0.001, far: 1000.0)

    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    var startTime: CFAbsoluteTime = 0.0

    // MARK: Render to Texture

    var renderTexture: MTLTexture!
    var _updateRenderTexture = true

    lazy var postContext = Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat)
    lazy var chromaMaterial = ChromaMaterial(context: postContext, pipelinesURL: pipelinesURL)

    lazy var chromaticProcessor = PostProcessEncoder(label: "Chroma Processor", context: postContext, material: chromaMaterial)

    override var depthPixelFormat: MTLPixelFormat {
        .invalid
    }

    override func setup() throws {
        startTime = CFAbsoluteTimeGetCurrent()
    }

    override func update() throws {
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

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        updateRenderTexture(
            width: Int(metalView.drawableSize.width),
            height: Int(metalView.drawableSize.height)
        )

        particleSystem.update(commandBuffer)

        try renderer.draw(
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
