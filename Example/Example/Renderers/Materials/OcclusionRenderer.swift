//
//  OcclusionRenderer.swift
//  Example
//
//  Created by Reza Ali on 1/13/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Forge
import Satin

class OcclusionRenderer: BaseRenderer {
    var mesh = Mesh(geometry: IcoSphereGeometry(radius: 1.0, resolution: 0), material: BasicDiffuseMaterial(0.7))

    var intersectionMesh: Mesh = {
        let mesh = Mesh(geometry: IcoSphereGeometry(radius: 0.1, resolution: 2), material: BasicColorMaterial([0.0, 1.0, 0.0, 1.0], .disabled))
        mesh.label = "Intersection Mesh"
        mesh.visible = false
        return mesh
    }()

    let occlusionGeometry = BoxGeometry(width: 4.0, height: 1.0, depth: 4.0)

    lazy var occlusionMesh: Mesh = {
        let meshMaterial = BasicColorMaterial(.zero, .disabled)
        let mesh = Mesh(
            geometry: occlusionGeometry,
            material: meshMaterial
        )
        mesh.position.y = -0.5

        let wireframeMaterial = BasicColorMaterial(.init(1.0, 1.0, 1.0, 0.5), .additive)
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
    lazy var context = Context(device, sampleCount, colorPixelFormat, depthPixelFormat, stencilPixelFormat)
    lazy var camera: PerspectiveCamera = {
        let camera = PerspectiveCamera(position: .init(repeating: 8.0), near: 0.01, far: 1000.0, fov: 30)
        camera.lookAt(target: .zero, up: Satin.worldUpDirection)
        return camera
    }()

    lazy var cameraController = PerspectiveCameraController(camera: camera, view: mtkView)
    lazy var renderer = Satin.Renderer(context: context)

    override func setupMtkView(_ metalKitView: MTKView) {
        metalKitView.sampleCount = 1
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.preferredFramesPerSecond = 60
    }

    deinit {
        cameraController.disable()
    }

    override func update() {
        cameraController.update()
        camera.update()
        scene.update()
    }

    override func draw(_ view: MTKView, _ commandBuffer: MTLCommandBuffer) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(_ size: (width: Float, height: Float)) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        intersect(coordinate: normalizePoint(mtkView.convert(event.locationInWindow, from: nil), mtkView.frame.size))
    }

    #elseif os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let first = touches.first {
            intersect(coordinate: normalizePoint(first.location(in: mtkView), mtkView.frame.size))
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
