//
//  MinimalSatin2DRenderer.swift
//  Example
//
//  Created by OpenAI on 4/19/26.
//

#if os(macOS)

import Metal
import Satin

final class MinimalSatin2DRenderer: MetalViewRenderer {
    private lazy var material = BasicColorMaterial(
        context: defaultContext,
        color: simd_float4(0.93, 0.85, 0.30, 1.0),
        blending: .disabled
    )

    private lazy var mesh = Mesh(
        context: defaultContext,
        label: "Quad",
        geometry: QuadGeometry(context: defaultContext, size: 0.8),
        material: material
    )

    private lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])
    private lazy var camera = OrthographicCamera(context: defaultContext)
    private lazy var renderer = Renderer(
        label: "Minimal Satin 2D Renderer",
        context: defaultContext,
        clearColor: simd_float4(0.10, 0.12, 0.16, 1.0)
    )

    override var depthPixelFormat: MTLPixelFormat { .invalid }
    override var stencilPixelFormat: MTLPixelFormat { .invalid }

    override func setup() {
        camera.position = [0, 0, 1]
        camera.near = 0.0
        camera.far = 10.0
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor _: Float) {
        let safeHeight = max(size.height, 1.0)
        let aspect = max(size.width / safeHeight, 0.0001)

        let halfWidth: Float
        let halfHeight: Float

        if aspect >= 1.0 {
            halfWidth = aspect
            halfHeight = 1.0
        } else {
            halfWidth = 1.0
            halfHeight = 1.0 / aspect
        }

        camera.update(
            left: -halfWidth,
            right: halfWidth,
            bottom: -halfHeight,
            top: halfHeight,
            near: 0.0,
            far: 10.0
        )

        renderer.resize(size)
    }
}

#endif
