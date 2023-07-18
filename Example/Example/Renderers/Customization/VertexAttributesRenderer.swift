//
//  Renderer.swift
//  VertexAttributes
//
//  Created by Reza Ali on 4/18/22.
//  Copyright © 2022 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Forge
import Satin

class VertexAttributesRenderer: BaseRenderer {
    var intersectionMesh: Mesh = {
        let mesh = Mesh(geometry: IcoSphereGeometry(radius: 0.01, resolution: 2), material: BasicColorMaterial([0.0, 1.0, 0.0, 1.0], .disabled))
        mesh.label = "Intersection Mesh"
        mesh.visible = false
        return mesh
    }()

    class CustomMaterial: SourceMaterial {}

    override var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }

    var camera = PerspectiveCamera(position: [0.0, 0.0, 4.0], near: 0.001, far: 100.0)
    lazy var scene = Object("Scene", [intersectionMesh])
    lazy var context = Context(device, sampleCount, colorPixelFormat, depthPixelFormat, stencilPixelFormat)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: mtkView)
    lazy var renderer = Satin.Renderer(context: context)

    override func setupMtkView(_ metalKitView: MTKView) {
        metalKitView.sampleCount = 1
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.preferredFramesPerSecond = 60
        metalKitView.colorPixelFormat = .bgra8Unorm
    }

    var loadedMesh: LoadedMesh!

    override func setup() {
        loadedMesh = LoadedMesh(
            url: modelsURL.appendingPathComponent("Suzanne").appendingPathComponent("Suzanne.obj"),
            material: CustomMaterial(pipelinesURL: pipelinesURL)
        )
        scene.add(loadedMesh)
    }

    deinit {
        cameraController.disable()
    }

    override func update() {
        cameraController.update()
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
        let aspect = size.width / size.height
        camera.aspect = aspect
        renderer.resize(size)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let pt = normalizePoint(mtkView.convert(event.locationInWindow, from: nil), mtkView.frame.size)
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
            let point = first.location(in: mtkView)
            let size = mtkView.frame.size
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
