//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 6/27/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Combine
import Metal
import MetalKit
import Satin

final class Renderer3D: BaseRenderer {
    let mesh = Mesh(
        label: "Sphere",
        geometry: IcoSphereGeometry(radius: 0.5, resolution: 0),
        material: BasicDiffuseMaterial(hardness: 0.7)
    )

    let intersectionMesh = Mesh(
        label: "Intersection Mesh",
        geometry: IcoSphereGeometry(radius: 0.05, resolution: 2),
        material: BasicColorMaterial(color: [0.0, 1.0, 0.0, 1.0], blending: .disabled),
        visible: false,
        renderPass: 1
    )

    lazy var startTime = getTime()
    lazy var scene = Object(label: "Scene", [mesh])
    lazy var renderer = Renderer(context: defaultContext)
    lazy var camera = PerspectiveCamera(position: [0, 0, 5], near: 0.1, far: 100.0, fov: 30)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)

    override var sampleCount: Int { 1 }

    override func setup() {
        mesh.add(intersectionMesh)

        camera.lookAt(target: .zero)

        #if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
        #endif
    }

    deinit {
        cameraController.disable()
    }

    override func update() {
        cameraController.update()
        mesh.orientation = simd_quatf(angle: Float(getTime() - startTime), axis: simd_normalize(simd_float3.one))
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
        intersect(camera: camera, coordinate: normalizePoint(metalView.convert(event.locationInWindow, from: nil), metalView.frame.size))
    }

    #elseif os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let first = touches.first {
            intersect(camera: camera, coordinate: normalizePoint(first.location(in: metalView), metalView.frame.size))
        }
    }
    #endif

    func intersect(camera: Camera, coordinate: simd_float2) {
        let results = raycast(camera: camera, coordinate: coordinate, object: scene)
        if let result = results.first {
            intersectionMesh.worldPosition = result.position
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
