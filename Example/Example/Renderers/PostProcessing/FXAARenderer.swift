//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 10/2/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

final class FXAARenderer: BaseRenderer {
    final class FxaaMaterial: SourceMaterial {}

    // MARK: Render to Texture

    var renderTexture: MTLTexture!
    var updateRenderTexture = true

    lazy var fxaaMaterial = FxaaMaterial(pipelinesURL: pipelinesURL)
    lazy var fxaaProcessor = PostProcessor(label: "FXAA Post Processor", context: Context(device: device, sampleCount: sampleCount, colorPixelFormat: colorPixelFormat), material: fxaaMaterial)

    lazy var mesh: Mesh = {
        let mesh = Mesh(
            geometry:
            ExtrudedTextGeometry(
                text: "FXAA",
                fontName: "Helvetica",
                fontSize: 1,
                distance: 0.5,
                pivot: [0, 0]
            ),
            material: BasicDiffuseMaterial(hardness: 1.0)
        )
        return mesh
    }()

    var camera = PerspectiveCamera(position: [0, 0, 9], near: 0.001, far: 100.0)

    lazy var scene = Object(label: "Scene", [mesh])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    deinit {
        cameraController.disable()
    }

    override func update() {
        if updateRenderTexture {
            renderTexture = createTexture("Render Texture", colorPixelFormat)
            updateRenderTexture = false
        }

        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            renderTarget: renderTexture
        )

        fxaaMaterial.set(renderTexture, index: FragmentTextureIndex.Custom0)

        fxaaProcessor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
        fxaaProcessor.resize(size: size, scaleFactor: scaleFactor)
        updateRenderTexture = true
        fxaaMaterial.set("Inverse Resolution", 1.0 / simd_make_float2(size.width, size.height))
    }

    func createTexture(_ label: String, _ pixelFormat: MTLPixelFormat) -> MTLTexture? {
        if metalView.drawableSize.width > 0, metalView.drawableSize.height > 0 {
            let descriptor = MTLTextureDescriptor()
            descriptor.pixelFormat = pixelFormat
            descriptor.width = Int(metalView.drawableSize.width)
            descriptor.height = Int(metalView.drawableSize.height)
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
