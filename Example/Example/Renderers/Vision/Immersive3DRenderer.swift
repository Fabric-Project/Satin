//
//  ImmersiveRenderer3D.swift
//  Example
//
//  Created by Reza Ali on 1/23/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

#if os(visionOS)

import ARKit
import CompositorServices
import Metal
import Satin

final class Immersive3DRenderer: ImmersiveBaseRenderer {
    final class GridMaterial: SourceMaterial {}

    let mesh = Mesh(
        label: "Blob",
        geometry: IcoSphereGeometry(radius: 0.5, resolution: 0),
        material: NormalColorMaterial(true)
    )

    lazy var background = Mesh(
        label: "Background",
        geometry: SkyboxGeometry(size: 200),
        material: GridMaterial(pipelinesURL: pipelinesURL, live: true)
    )

    let floor = Mesh(
        label: "Floor",
        geometry: PlaneGeometry(size: 3.0, orientation: .zx, centered: true),
        material: UVColorMaterial(),
        visible: false
    )

    lazy var startTime = getTime()
    lazy var scene = Object(label: "Scene", [
//        background,
        mesh,
        floor
    ])

    lazy var renderer = Renderer(context: defaultContext, clearColor: .zero)

#if targetEnvironment(simulator)
    override var layerLayout: LayerRenderer.Layout { .dedicated }
#else
    override var layerLayout: LayerRenderer.Layout { .layered }
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

    override func draw(
        frame: LayerRenderer.Frame,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        cameras: [PerspectiveCamera],
        viewports: [MTLViewport],
        viewMappings: [MTLVertexAmplificationViewMapping]
    ) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            cameras: cameras,
            viewports: viewports,
            viewMappings: viewMappings
        )
    }

    override func drawView(view: Int, frame: LayerRenderer.Frame, renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer, camera: PerspectiveCamera, viewport: MTLViewport) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            viewport: viewport
        )
    }
}

#endif
