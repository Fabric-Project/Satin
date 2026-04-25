//
//  Renderer.swift
//  VertexAttributes
//
//  Created by Reza Ali on 4/18/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

final class VertexAttributesRenderer: BaseRenderer {
    var intersectionMesh: Mesh = {
        let mesh = Mesh(geometry: IcoSphereGeometry(radius: 0.01, resolution: 2), material: BasicColorMaterial(color: [0.0, 1.0, 0.0, 1.0], blending: .disabled))
        mesh.label = "Intersection Mesh"
        mesh.visible = false
        return mesh
    }()

    final class CustomMaterial: SourceMaterial {}

    override var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }

    let camera = PerspectiveCamera(position: [0.0, 0.0, 4.0], near: 0.001, far: 100.0)
    lazy var scene = Object(label: "Scene", [intersectionMesh])
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext)

    override func setup() {
        let url = modelsURL.appendingPathComponent("Suzanne").appendingPathComponent("Suzanne.obj")
        guard let model = loadAsset(url: url), let mesh = getMeshes(model, true, true).first else { return }

        mesh.material = CustomMaterial(pipelinesURL: pipelinesURL)
        scene.add(mesh)

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
        let aspect = size.width / size.height
        camera.aspect = aspect
        renderer.resize(size)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let pt = normalizePoint(metalView.convert(event.locationInWindow, from: nil), metalView.frame.size)
        let results = raycast(camera: camera, coordinate: pt, object: scene)
        for result in results {
            print(result.object.label)
            print(result.position)
            intersectionMesh.position = result.position
            intersectionMesh.visible = true
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
