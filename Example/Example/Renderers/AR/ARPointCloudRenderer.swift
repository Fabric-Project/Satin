//
//  ARPointCloudRenderer.swift
//  Example
//
//  Created by Reza Ali on 5/8/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Metal
import MetalKit

import Satin
import SwiftUI

final class ARPointCloudRenderer: BaseRenderer {
    final class PointMaterial: SourceMaterial {}
    final class PointComputeSystem: BufferComputeSystem {
        var depthTexture: CVMetalTexture?
        override func bind(_ computeEncoder: MTLComputeCommandEncoder) -> Int {
            if let depthTexture {
                computeEncoder.setTexture(CVMetalTextureGetTexture(depthTexture), index: ComputeTextureIndex.Custom0.rawValue)
            }
            return super.bind(computeEncoder)
        }
    }

    lazy var pointCloud = PointComputeSystem(device: device, pipelineURL: pipelinesURL.appendingPathComponent("Point/Compute.metal"), count: 256 * 192)

    // MARK: - UI

    var updateComputeParam = BoolParameter("Update", true, .toggle)
    lazy var controls = ParameterGroup("Controls", [updateComputeParam])

    override var params: [String: ParameterGroup?] {
        [controls.label: controls]
    }

    override var paramKeys: [String] {
        [controls.label]
    }

    // MARK: - AR

    var session = ARSession()

    // MARK: - 3D

    lazy var mesh = Mesh(geometry: IcoSphereGeometry(radius: 0.001, resolution: 1), material: PointMaterial(pipelinesURL: pipelinesURL))

    lazy var scene = Object(label: "Scene", [mesh])

    lazy var camera = ARPerspectiveCamera(session: session, metalView: metalView, near: 0.01, far: 100.0)
    lazy var renderer = {
        let renderer = Renderer(context: defaultContext)
        renderer.label = "Content Renderer"
        renderer.setClearColor(.zero)
        renderer.colorLoadAction = .load
        renderer.depthLoadAction = .load
        return renderer
    }()

    private lazy var startTime: CFAbsoluteTime = getTime()
    private lazy var time: CFAbsoluteTime = getTime()

    // MARK: - Background

    var backgroundRenderer: ARBackgroundDepthRenderer!

    override init() {
        super.init()

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        session.run(config)
    }

    // MARK: - Setup

    override func setup() {
        metalView.preferredFramesPerSecond = 60

        mesh.instanceCount = 256 * 192
        mesh.material?.onBind = { [weak self] re in
            re.setVertexBuffer(
                self?.pointCloud.getBuffer("Point"),
                offset: 0,
                index: VertexBufferIndex.Custom0.rawValue
            )
        }

        backgroundRenderer = ARBackgroundDepthRenderer(
            context: defaultContext,
            session: session,
            sessionPublisher: ARSessionPublisher(session: session),
            metalView: metalView,
            near: camera.near,
            far: camera.far
        )
    }

    // MARK: - Draw

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        backgroundRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )

        if updateComputeParam.value {
            if let currentFrame = session.currentFrame {
                pointCloud.depthTexture = backgroundRenderer.sceneDepthTexture
                pointCloud.set("Local To World", camera.localToWorld)
                pointCloud.set("Intrinsics Inversed", camera.intrinsics.inverse)
                pointCloud.set("Resolution", simd_make_float2(
                    Float(Int(currentFrame.camera.imageResolution.width)),
                    Float(currentFrame.camera.imageResolution.height)))
            }

            pointCloud.update(commandBuffer)
        }

        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    // MARK: - Resize

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
    }

    // MARK: - Deinit

    override func cleanup() {
        session.pause()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateComputeParam.value.toggle()
    }
}

#endif
