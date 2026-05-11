//
//  MultipleContextRenderer.swift
//  Example
//
//  Created by Reza Ali on 8/4/24.
//  Copyright © 2024 Hi-Rez. All rights reserved.
//

import Foundation

import Metal
import MetalKit
import Satin

final class MultipleContextRenderer: BaseRenderer {
    lazy var mesh: Mesh = {
        let material = BasicDiffuseMaterial(context: defaultContext, hardness: 0.7)
        material.ambient = 0.15
        return Mesh(context: defaultContext, geometry: IcoSphereGeometry(context: defaultContext, radius: 0.5, resolution: 0), material: material)
    }()
    lazy var noDepthContext = Context(
        device: device,
        sampleCount: 1,
        colorPixelFormat: colorPixelFormat
    )
    lazy var meshNoDepth: Mesh = {
        let material = BasicDiffuseMaterial(context: defaultContext, hardness: 0.7)
        material.ambient = 0.15
        return Mesh(context: noDepthContext, geometry: IcoSphereGeometry(context: defaultContext, radius: 0.5, resolution: 0), material: material)
    }()

    lazy var startTime = getTime()
    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh])
    lazy var sceneNoDepth = Object(context: defaultContext, label: "Scene No Depth", [meshNoDepth])

    override var sampleCount: Int {
#if targetEnvironment(simulator)
        return 1
#else
        return 1
#endif
    }

    lazy var renderer = Renderer(context: defaultContext)
    lazy var rendererNoDepth = Renderer(
        context: noDepthContext
    )

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [5, 5, 5], near: 0.01, far: 100.0, fov: 30)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)

    var tween: Tween?

    override func setup() {
        camera.lookAt(target: .zero)

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
        //
        //        tween = Tweener
        //            .tweenScale(duration: 2.0, object: mesh, from: .one, to: .init(repeating: 2.0))
        //            .easing(.inOutBack)
        //            .pingPong()
        //            .loop()
        //            .start()
    }

    deinit {
        tween?.remove()
    }

    override func update() {
        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        rendererNoDepth.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: sceneNoDepth,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
        rendererNoDepth.resize(size)
    }
}
