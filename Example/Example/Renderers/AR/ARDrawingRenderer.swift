//
//  ARDrawingRenderer.swift
//  Example
//
//  Created by Reza Ali on 3/15/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

#if os(iOS)

import ARKit
import Metal
import MetalKit

import Satin

import SwiftUI

final class ARDrawingRenderer: BaseRenderer {
    final class RainbowMaterial: SourceMaterial {}

    // MARK: - AR

    var session = ARSession()

    // MARK: - 3D

    lazy var material = RainbowMaterial(context: defaultContext, pipelinesURL: pipelinesURL)
    lazy var mesh = InstancedMesh(context: defaultContext, geometry: IcoSphereGeometry(context: defaultContext, radius: 0.03, resolution: 3), material: material, count: 20000)
    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])

    lazy var camera = ARPerspectiveCamera(context:defaultContext, session: session, metalView: metalView, near: 0.01, far: 100.0)
    lazy var renderer = {
        lazy var renderer = RenderEncoder(context: defaultContext)
        renderer.label = "Content RenderEncoder"
        renderer.setClearColor(.zero)
        renderer.colorLoadAction = .load
        renderer.depthLoadAction = .load
        return renderer
    }()

    private lazy var startTime: CFAbsoluteTime = getTime()
    private lazy var time: CFAbsoluteTime = getTime()

    // MARK: - Interaction

    var touchDown = false

    // MARK: - Background

    var backgroundRenderer: ARBackgroundDepthEncoder!

    // MARK: - Init

    var clear: Binding<Bool>

    convenience init(clear: Binding<Bool>) {

        self.init(context: .makePlatformDefault())
        self.clear = clear
    }

    override init(context: Context)
    {
        self.clear = .constant(false)
        super.init(context: context)
       
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.smoothedSceneDepth]
        session.run(config)
    }

    // MARK: - Setup

    override func setup() throws {
        metalView.preferredFramesPerSecond = 60

        mesh.drawCount = 0
        backgroundRenderer = ARBackgroundDepthEncoder(
            context: defaultContext,
            session: session,
            sessionPublisher: ARSessionPublisher(session: session),
            metalView: metalView,
            near: camera.near,
            far: camera.far
        )

//        backgroundRenderer = ARBackgroundEncoder(
//            context: defaultContext,
//            session: session
//        )
    }

    // MARK: - Update

    override func update() throws {
        updateDrawing()
        updateMaterial()
    }

    // MARK: - Draw

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        backgroundRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )

        try renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    // MARK: - Cleanup

    override func cleanup() throws {
        session.pause()
    }

    // MARK: - Resize

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        renderer.resize(size)
        backgroundRenderer.resize(size: size, scaleFactor: scaleFactor)
    }

    // MARK: - Interactions

    override func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
        touchDown = true
    }

    override func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
        touchDown = false
    }

    // MARK: - Updates

    private func updateDrawing() {
        if clear.wrappedValue {
            mesh.drawCount = 0
            clear.wrappedValue = false
        } else if touchDown, let currentFrame = session.currentFrame {
            add(simd_mul(currentFrame.camera.transform, translationMatrixf(0, 0, -0.2)))
        }
    }

    private func add(_ transform: simd_float4x4) {
        if let index = mesh.drawCount {
            mesh.drawCount = index + 1
            mesh.setMatrixAt(index: index, matrix: transform)
        }
    }

    private func updateMaterial() {
        time = getTime() - startTime
        material.set("Time", Float(time))
    }
}

#endif
