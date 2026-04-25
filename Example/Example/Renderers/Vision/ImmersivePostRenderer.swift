//
//  ImmersivePostRenderer.swift
//  Example
//
//  Created by Reza Ali on 6/25/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

#if os(visionOS)

import ARKit
import CompositorServices
import Metal
import Satin

final class ImmersivePostRenderer: ImmersiveBaseRenderer {
    final class GridMaterial: SourceMaterial {}

    lazy var background = Mesh(
        label: "Background",
        geometry: SkyboxGeometry(size: 200),
        material: GridMaterial(pipelinesURL: pipelinesURL, live: true)
    )

    let mesh = Mesh(
        label: "Blob",
        geometry: IcoSphereGeometry(radius: 0.5, resolution: 0),
        material: BasicDiffuseMaterial()
    )

    let floor = Mesh(
        label: "Floor",
        geometry: PlaneGeometry(size: 3.0, orientation: .zx, centered: true),
        material: UVColorMaterial(),
        visible: false
    )

    final class PostMaterial: SourceMaterial {}

    lazy var postMaterial = PostMaterial(pipelinesURL: pipelinesURL)

    lazy var startTime = getTime()
    lazy var scene = Object(label: "Scene", [background, floor, mesh])

    var renderTexture: MTLTexture?

    lazy var renderer = Renderer(
        context: defaultContext,
        depthStoreAction: sampleCount > 1 ? .multisampleResolve : .store
    )

    lazy var postProcessor = PostProcessor(
        context: Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: colorPixelFormat,
            vertexAmplificationCount: layerRenderer.configuration.layout == .layered ? 2 : 1
        ),
        material: postMaterial
    )

#if targetEnvironment(simulator)
    override var sampleCount: Int { 1 } // sample count > 1 doenst resolve properly in the simulator
    override var layerLayout: LayerRenderer.Layout { .dedicated }
    override var isFoveationEnabled: Bool { false }
#else
    override var sampleCount: Int { 1 }
    override var layerLayout: LayerRenderer.Layout { .layered }
    override var isFoveationEnabled: Bool { true }
#endif

#if !targetEnvironment(simulator)
    let planeDetectionProvider = PlaneDetectionProvider(alignments: [.horizontal])
    override var arSessionDataProviders: [any DataProvider] {
        var providers = super.arSessionDataProviders
        providers.append(planeDetectionProvider)
        return providers
    }
#endif

    override func setup() {
        mesh.position = [0, 1, -3]

#if !targetEnvironment(simulator)
        Task {
            for await update in planeDetectionProvider.anchorUpdates {
                if update.anchor.classification == .floor {
                    floor.visible = true
                    floor.worldMatrix = update.anchor.originFromAnchorTransform
                }
            }
        }
#endif
    }

    override func update() {
        let theta = Float(getTime() - startTime)
        mesh.orientation = simd_quatf(angle: theta * 0.75, axis: simd_normalize(simd_make_float3(sin(theta), cos(theta), 1.0)))
    }

    // Layered
    override func draw(
        frame: LayerRenderer.Frame,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        cameras: [PerspectiveCamera],
        viewports: [MTLViewport],
        viewMappings: [MTLVertexAmplificationViewMapping]
    ) {
        guard let refTexture = renderPassDescriptor.colorAttachments[0].texture else { return }

        if renderTexture == nil || renderTexture?.width != refTexture.width || renderTexture?.height != refTexture.height {
            renderTexture = duplicateTexture(ref: refTexture, sampleCount: 1)
        }

        guard let renderTexture else { return }

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            cameras: cameras,
            viewports: viewports,
            viewMappings: viewMappings,
            renderTarget: renderTexture
        )

        postMaterial.set(renderTexture, index: FragmentTextureIndex.Custom0)

        let postRenderPassDescriptor = MTLRenderPassDescriptor()

        if sampleCount > 1 {
            postRenderPassDescriptor.colorAttachments[0].texture = renderPassDescriptor.colorAttachments[0].texture
            postRenderPassDescriptor.colorAttachments[0].resolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture
        }
        else {
            postRenderPassDescriptor.colorAttachments[0].texture = refTexture
        }

        postRenderPassDescriptor.renderTargetArrayLength = viewports.count
        postRenderPassDescriptor.renderTargetWidth = refTexture.width
        postRenderPassDescriptor.renderTargetHeight = refTexture.height

        postProcessor.draw(
            renderPassDescriptor: postRenderPassDescriptor,
            commandBuffer: commandBuffer,
            viewports: viewports,
            viewMappings: viewMappings
        )
    }

    // Dedicated
    override func drawView(view: Int, frame: LayerRenderer.Frame, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, camera: PerspectiveCamera, viewport: MTLViewport) {
        guard let refTexture = renderPassDescriptor.colorAttachments[0].texture,
              let refResolveTexture = renderPassDescriptor.colorAttachments[0].resolveTexture else { return }

        if renderTexture == nil || renderTexture?.width != refTexture.width || renderTexture?.height != refTexture.height {
            renderTexture = duplicateTexture(ref: refTexture, sampleCount: 1)
        }

        guard let renderTexture else { return }

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            viewport: viewport,
            renderTarget: renderTexture
        )

        let postRenderPassDescriptor = MTLRenderPassDescriptor()

        if sampleCount > 1 {
            postRenderPassDescriptor.colorAttachments[0].texture = refResolveTexture
        }
        else {
            postRenderPassDescriptor.colorAttachments[0].texture = refTexture
        }

        postRenderPassDescriptor.renderTargetArrayLength = 1
        postRenderPassDescriptor.renderTargetWidth = refTexture.width
        postRenderPassDescriptor.renderTargetHeight = refTexture.height

        postMaterial.set(renderTexture, index: FragmentTextureIndex.Custom0)
        postProcessor.resize(size: (Float(refTexture.width), Float(refTexture.height)), scaleFactor: 1)

        postProcessor.draw(
            renderPassDescriptor: postRenderPassDescriptor,
            commandBuffer: commandBuffer
        )
    }

    func duplicateTexture(ref: MTLTexture, sampleCount: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor()
        desc.textureType = defaultContext.vertexAmplificationCount > 1 ? .type2DArray : .type2D
        desc.pixelFormat = ref.pixelFormat
        desc.width = ref.width
        desc.height = ref.height
        desc.depth = ref.depth
        desc.sampleCount = sampleCount
        desc.usage = [.renderTarget, .shaderRead]
        desc.arrayLength = ref.arrayLength
        let texture = device.makeTexture(descriptor: desc)
        texture?.label = "Render Texture"
        return texture
    }
}

#endif
