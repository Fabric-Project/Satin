//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 6/27/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import Satin

final class OctasphereRenderer: BaseRenderer {
    lazy var mesh = Mesh(geometry: OctaSphereGeometry(radius: 1, resolution: 3), material: BasicDiffuseMaterial(hardness: 0.75))
    lazy var scene = Object(label: "Scene", [mesh])
    let camera = PerspectiveCamera(position: simd_make_float3(0.0, 0.0, 5.0), near: 0.01, far: 100.0, fov: 30)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    deinit {
        cameraController.disable()
    }

    override func setup() {
        #if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
        #endif
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
    }

    override func resize(size: (width: Float, height: Float), scaleFactor _: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let pt = normalizePoint(metalView.convert(event.locationInWindow, from: nil), metalView.frame.size)
        let results = raycast(camera: camera, coordinate: pt, object: scene)
        for result in results {
            print(result.object.label)
            print(result.position)
        }
    }

    #elseif os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let first = touches.first {
            let point = first.location(in: metalView)
            let size = metalView.frame.size
            let pt = normalizePoint(point, size)
            let results = raycast(camera: camera, coordinate: pt, object: scene)
            for result in results {
                print(result.object.label)
                print(result.position)
            }
        }
    }
    #endif

    func normalizePoint(_ point: CGPoint, _ size: CGSize) -> simd_float2 {
        #if os(macOS)
        return 2.0 * simd_make_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1.0
        #else
        return 2.0 * simd_make_float2(Float(point.x / size.width), 1.0 - Float(point.y / size.height)) - 1.0
        #endif
    }
}
