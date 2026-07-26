//
//  TessellationRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/2/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

final class TessellationRenderer: BaseRenderer {
    final class Tessellated: TessellationProcessor<MTLTriangleTessellationFactorsHalf> {}
    final class TessellatedMaterial: SourceMaterial {}

    lazy var tessellator = Tessellated(
        device: device,
        pipelineURL: pipelinesURL.appendingPathComponent("Tessellated/Compute.metal"),
        live: true,
        geometry: tessGeometry
    )

    lazy var tessGeometry = TessellationGeometry(
        baseGeometry: IcoSphereGeometry(context: defaultContext, radius: 1, resolution: 1)
    )

    lazy var tessMaterial = TessellatedMaterial(context: defaultContext, pipelinesURL: pipelinesURL)
    lazy var tessMesh = TessellationMesh(
        context: defaultContext,
        label: "Tessellated Fill",
        geometry: tessGeometry,
        material: tessMaterial,
        tessellator: tessellator,
        tessellate: false
    )

    lazy var tessWireMesh = TessellationMesh(
        context: defaultContext,
        label: "Tessellated Wire",
        geometry: tessGeometry,
        material: TessellatedMaterial(context: defaultContext, pipelinesURL: pipelinesURL),
        tessellator: tessellator,
        tessellate: false
    )

    lazy var scene = Object(context: defaultContext, label: "Scene", [tessMesh, tessWireMesh])

    lazy var camera = PerspectiveCamera(context: defaultContext, position: .init(repeating: 4.0), near: 0.01, far: 50.0, fov: 30)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)

    override func setup() throws {
        camera.lookAt(target: .zero)

        tessMesh.material?.depthBias = DepthBias(bias: -1, slope: -1, clamp: -1)

        tessWireMesh.triangleFillMode = MTLTriangleFillMode.lines
        tessWireMesh.material?.blending = Blending.additive

        tessWireMesh.material?.depthBias = DepthBias(bias: 1, slope: 1, clamp: 1)
        tessWireMesh.material?.set("Color", [1.0, 1.0, 1.0, 0.33])
    }

    lazy var startTime = getTime()
    override func update() throws {
        let currentTime = getTime() - startTime
        let osc = Float(sin(currentTime)) * 0.5

        tessWireMesh.material?.set("Amplitude", osc)
        tessMesh.material?.set("Amplitude", osc)

        let oscEdge = Float(sin(currentTime * 0.5))
        let oscInsider = Float(cos(currentTime * 1.25))

        tessellator.set("Edge Tessellation Factor", abs(oscEdge) * 16.0)
        tessellator.set("Inside Tessellation Factor", abs(oscInsider) * 16.0)

        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        tessellator.update(commandBuffer)
        try renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}
