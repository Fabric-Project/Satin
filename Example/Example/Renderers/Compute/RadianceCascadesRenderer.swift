//
//  RadianceCascadesRenderer.swift
//  Example
//
//  Created by Reza Ali on 12/8/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import Satin

final class RadianceCascadesRenderer: BaseRenderer {
    final class PostMaterial: SourceMaterial {}

    final class RadianceCascadesProcessor: TextureComputeProcessor {}
    // create radiance cascade textures (array)
    // create a merged radiance texture (1/2 size of the main scene texture)
    // use a texture processor to calculate the radiance for each cascade
    // use a texture processor to merge the radience from each level
    // visualize the result on screen using the main scene texture + radiance texture

    var radianceCascadeTexture: MTLTexture?
    var updateRadianceCascadeTextures = true
    lazy var radianceCascadesProcessor = RadianceCascadesProcessor(
        device: device,
        pipelinesURL: pipelinesURL,
        live: true
    )

    lazy var mesh = Mesh(
        label: "Quad",
        geometry: QuadGeometry(),
        material: PostMaterial(pipelinesURL: pipelinesURL, live: true)
    )

    var camera = OrthographicCamera()
    lazy var cameraController = OrthographicCameraController(camera: camera, view: metalView, defaultZoom: 0.00125)
    lazy var scene = Object(label: "Scene", [mesh])
    lazy var renderer = Renderer(context: defaultContext)

    override func setup() {
#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    override func update() {
        cameraController.update()
        if updateRadianceCascadeTextures {
            radianceCascadeTexture = createRadianceCascadeTextures()
            mesh.material?.set(radianceCascadeTexture, index: FragmentTextureIndex.Custom0)
            radianceCascadesProcessor.set(radianceCascadeTexture, index: ComputeTextureIndex.Custom0)
            mesh.instanceCount = radianceCascadeTexture?.arrayLength ?? 1
            updateRadianceCascadeTextures = false
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        radianceCascadesProcessor.update(commandBuffer)

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        cameraController.resize(size)
        renderer.resize(size)
        updateRadianceCascadeTextures = true
    }

    func createRadianceCascadeTextures() -> MTLTexture? {
        let size = CGSize(width: 1024, height: 1024)
        let width = Float(size.width)
        let height = Float(size.height)
        guard width > 0, height > 0 else { return nil }

        let resolution = simd_make_float2(width, height)
        let diagonal = simd_length(resolution)
        let cascades = Int(ceil(log(diagonal)/log(4.0)))

        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = Int(width)/2
        descriptor.height = Int(height)/2
        descriptor.sampleCount = 1
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = cascades
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        descriptor.resourceOptions = .storageModePrivate
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Radiance Cascades Texture"
        return texture
    }
}
