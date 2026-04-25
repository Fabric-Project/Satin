//
//  OcclusionRenderer.swift
//  Example
//
//  Created by Reza Ali on 1/13/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

final class OcclusionRenderer: BaseRenderer {
    let mesh = Mesh(
        label: "Mesh",
        geometry: IcoSphereGeometry(radius: 1.0, resolution: 0),
        material: BasicDiffuseMaterial(hardness: 0.7)
    )
    let intersectionMesh = Mesh(
        label: "Intersection Mesh",
        geometry: IcoSphereGeometry(radius: 0.1, resolution: 2),
        material: BasicColorMaterial(color: [0.0, 1.0, 0.0, 1.0], blending: .disabled),
        visible: false
    )

    let occlusionGeometry = BoxGeometry(width: 4.0, height: 1.0, depth: 4.0)

    lazy var occlusionMesh: Mesh = {
        let meshMaterial = BasicColorMaterial(color: .zero, blending: .disabled)
        let mesh = Mesh(
            geometry: occlusionGeometry,
            material: meshMaterial
        )
        mesh.position.y = -0.5

        let wireframeMaterial = BasicColorMaterial(color: .init(1.0, 1.0, 1.0, 0.5), blending: .additive)
        wireframeMaterial.depthBias = DepthBias(bias: 1.0, slope: 1.0, clamp: 1.0)
        wireframeMaterial.depthWriteEnabled = false

        let meshWireframe = Mesh(
            geometry: occlusionGeometry,
            material: wireframeMaterial
        )

        meshWireframe.triangleFillMode = .lines
        mesh.add(meshWireframe)

        return mesh
    }()

    lazy var scene = Object(label: "Scene", [occlusionMesh, mesh, intersectionMesh])
    lazy var camera: PerspectiveCamera = {
        let camera = PerspectiveCamera(position: .init(repeating: 8.0), near: 0.01, far: 1000.0, fov: 30)
        camera.lookAt(target: .zero, up: Satin.worldUpDirection)
        return camera
    }()

    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    deinit {
        cameraController.disable()
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
        intersect(coordinate: normalizePoint(metalView.convert(event.locationInWindow, from: nil), metalView.frame.size))
    }

    #elseif os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let first = touches.first {
            intersect(coordinate: normalizePoint(first.location(in: metalView), metalView.frame.size))
        }
    }
    #endif

    func intersect(coordinate: simd_float2) {
        let results = raycast(camera: camera, coordinate: coordinate, object: scene)
        if let result = results.first {
            print(result.object.label)
            print(result.position)
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
