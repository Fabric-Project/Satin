//
//  RenderEncoder.swift
//  2D-macOS
//
//  Created by Reza Ali on 4/22/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit
import Satin

final class Renderer2D: BaseRenderer {
    lazy var mesh = Mesh(context: defaultContext, label: "Quad", geometry: QuadGeometry(context: defaultContext, size: 500), material: UVColorMaterial(context: defaultContext))

    lazy var camera = OrthographicCamera(context: defaultContext)
    lazy var cameraController = OrthographicCameraController(camera: camera, view: metalView)
    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh, intersectionMesh])
    lazy var renderer = RenderEncoder(context: defaultContext)

    lazy var intersectionMesh: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, geometry: CircleGeometry(context: defaultContext, radius: 10), material: BasicColorMaterial(context: defaultContext, color: [0.0, 1.0, 0.0, 1.0], blending: .disabled))
        mesh.label = "Intersection Mesh"
        mesh.renderLayer = .overlay
        mesh.visible = false
        return mesh
    }()

    override func setup() throws {
        camera.near = 0.0
        camera.far = 40.96
        camera.position = [0, 0, 10.0]
//        camera.lookAt(target: .zero)
        #if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
        #endif
    }

    override func update() throws {
        cameraController.update()
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor _: Float) {
        cameraController.resize(size)
        renderer.resize(size)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let pt = normalizePoint(metalView.convert(event.locationInWindow, from: nil), metalView.frame.size)
        intersect(coordinate: pt)
    }

    #elseif os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let first = touches.first {
            let point = first.location(in: metalView)
            let size = metalView.frame.size
            let pt = normalizePoint(point, size)
            intersect(coordinate: pt)
        }
    }
    #endif

    func intersect(coordinate: simd_float2) {
        let results = raycast(camera: camera, coordinate: coordinate, object: scene)
        if let result = results.first {
            intersectionMesh.position = result.position
            intersectionMesh.visible = true
        }
    }

    func normalizePoint(_ point: CGPoint, _ size: CGSize) -> simd_float2 {
        #if os(macOS)
        return 2.0 * simd_make_float2(Float(point.x / size.width), Float(point.y / size.height)) - 1.0
        #else
        return 2.0 * simd_make_float2(Float(point.x / size.width), 1.0 - Float(point.y / size.height)) - 1.0
        #endif
    }
}
