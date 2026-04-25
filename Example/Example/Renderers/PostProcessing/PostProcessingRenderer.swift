//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 7/12/21.
//  Copyright © 2021 Hi-Rez. All rights reserved.
//

import Metal
import Satin
import simd

final class PostProcessingRenderer: BaseRenderer {
    var size = simd_int2(repeating: 0)
    final class PostMaterial: SourceMaterial {}

    var renderTexture: MTLTexture?
    let material = BasicDiffuseMaterial(hardness: 0.7)
    let geometry = IcoSphereGeometry(radius: 1.0, resolution: 0)

    lazy var scene: Object = {
        let scene = Object(label: "Scene")
        for _ in 0 ... 50 {
            let mesh = Mesh(geometry: geometry, material: material)
            let scale = Float.random(in: 0.1 ... 0.75)
            let magnitude = (1.0 - scale) * 5.0

            mesh.scale = simd_float3(repeating: scale)
            mesh.position = [Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude), Float.random(in: -magnitude ... magnitude)]

            mesh.orientation = simd_quatf(angle: Float.random(in: -Float.pi ... Float.pi), axis: simd_normalize(mesh.position))
            scene.add(mesh)
        }
        return scene
    }()

    lazy var postMaterial = PostMaterial(pipelinesURL: pipelinesURL)
    lazy var postProcessor: PostProcessor = {
        let processor = PostProcessor(
            label: "Post Processor",
            context: Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat),
            material: postMaterial
        )
        processor.mesh.preDraw = { [weak self] renderEncoder in
            guard let self = self else { return }
            renderEncoder.setFragmentTexture(self.renderTexture, index: FragmentTextureIndex.Custom0.rawValue)
        }
        return processor
    }()

    let camera = PerspectiveCamera(position: [0.0, 0.0, 10.0], near: 0.001, far: 100.0, fov: 30.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    deinit {
        cameraController.disable()
    }

    override func update() {
        if size.x != Int(metalView.drawableSize.width) || size.y != Int(metalView.drawableSize.height) {
            renderTexture = createTexture("Render Texture", Int(metalView.drawableSize.width), Int(metalView.drawableSize.height), colorPixelFormat, device)
            size = simd_make_int2(Int32(Int(metalView.drawableSize.width)), Int32(metalView.drawableSize.height))
        }

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
        postMaterial.set(renderTexture, index: FragmentTextureIndex.Custom0)
        postProcessor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
        postProcessor.resize(size: size, scaleFactor: scaleFactor)
    }

    func createTexture(_ label: String, _ width: Int, _ height: Int, _ pixelFormat: MTLPixelFormat, _ device: MTLDevice) -> MTLTexture? {
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
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        return texture
    }
}
