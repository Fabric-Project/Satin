//
//  JumpFloodOutlineRenderer.swift
//  Example
//
//  Created by Reza Ali on 6/29/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import Satin

final class JumpFloodOutlineRenderer: BaseRenderer {
    final class FloodMaterial: SourceMaterial {}
    final class PostMaterial: SourceMaterial {}

    lazy var mesh = Mesh(geometry: RoundedBoxGeometry(size: 1.0, radius: 0.25, resolution: 4), material: BasicDiffuseMaterial(hardness: 0))

    final class JumpFloodComputeSystem: TextureComputeSystem {
        var spacing: Int = 8
        var initTexture: MTLTexture?

        override func bindUniforms(_ computeEncoder: MTLComputeCommandEncoder) {
            super.bindUniforms(computeEncoder)
            computeEncoder.setBytes(&spacing, length: MemoryLayout<Int>.size, index: ComputeBufferIndex.Custom0.rawValue)
        }

        override func bind(computeEncoder: MTLComputeCommandEncoder, iteration: Int) -> Int {
            _ = super.bind(computeEncoder: computeEncoder, iteration: iteration)
            if let initTexture { computeEncoder.setTexture(initTexture, index: 0) }
            return index
        }
    }

    final class JumpFloodInitComputeSystem: TextureComputeSystem {}

    lazy var startTime = getTime()
    lazy var scene = Object(label: "Scene", [mesh])

    lazy var quad = Mesh(geometry: QuadGeometry(), material: PostMaterial(pipelinesURL: pipelinesURL, live: true))

    override var sampleCount: Int { 1 }
    override var colorPixelFormat: MTLPixelFormat { .rgba16Float }

    var renderTexture: MTLTexture?
    lazy var renderer = Renderer(context: defaultContext, clearColor: .zero)

    let camera = PerspectiveCamera(position: [0, 0, 5], near: 0.01, far: 100.0, fov: 30)
    lazy var cameraController = OrbitPerspectiveCameraController(camera: camera, view: metalView)

    let orthoCamera = OrthographicCamera()

    lazy var jumpFlood = JumpFloodComputeSystem(
        device: device,
        pipelinesURL: pipelinesURL,
        textureDescriptors: getTextureDescriptors(),
        feedback: true,
        live: true
    )

    lazy var jumpFloodInit = JumpFloodInitComputeSystem(
        device: device,
        pipelinesURL: pipelinesURL,
        textureDescriptors: getTextureDescriptors(),
        feedback: false,
        live: true
    )

    var tween: Tween?

    override func setup() {
        camera.lookAt(target: .zero)

        quad.material?.blending = .alpha
        camera.lookAt(target: .zero)

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif

//        tween = Tweener
//            .tweenScale(duration: 2.0, object: mesh, from: .one, to: .init(repeating: 2.0))
//            .easing(.inOutBack)
//            .pingPong()
//            .loop()
//            .start()
    }

    deinit {
        cameraController.disable()
        tween?.remove()
    }

    override func update() {
        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard let renderTexture else { return }

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            renderTarget: renderTexture
        )

        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.label = "Selection Processor Compute Encoder"

            jumpFloodInit.set(renderTexture, index: ComputeTextureIndex.Custom1)
            jumpFloodInit.update(computeEncoder)

            jumpFlood.resetIndex()

            jumpFlood.set(renderTexture, index: ComputeTextureIndex.Custom2)

            jumpFlood.initTexture = jumpFloodInit.dstTexture
            var spacing: Float = 32

            while spacing >= 1 {
                jumpFlood.spacing = Int(spacing)
                jumpFlood.update(computeEncoder)

                jumpFlood.initTexture = nil
                spacing /= 2
            }

            computeEncoder.endEncoding()
        }

        quad.material?.set(renderTexture, index: FragmentTextureIndex.Custom0)
        quad.material?.set(jumpFlood.dstTexture, index: FragmentTextureIndex.Custom1)

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: quad,
            camera: orthoCamera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)

        let descriptors = getTextureDescriptors()
        jumpFloodInit.textureDescriptors = descriptors
        jumpFlood.textureDescriptors = descriptors

        renderTexture = createTexture(
            device: device,
            label: "Render Texture",
            width: Int(size.width),
            height: Int(size.height),
            pixelFormat: defaultContext.colorPixelFormat
        )
    }

    func getTextureDescriptors() -> [MTLTextureDescriptor] {
        let textureDescriptor = MTLTextureDescriptor()

        textureDescriptor.pixelFormat = .rgba16Float

        textureDescriptor.width = Int(metalView.drawableSize.width)
        textureDescriptor.height = Int(metalView.drawableSize.height)

        return [textureDescriptor]
    }

    func createTexture(device: MTLDevice, label: String, width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.sampleCount = 1
        descriptor.textureType = .type2D
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate
        descriptor.allowGPUOptimizedContents = true

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }
}
