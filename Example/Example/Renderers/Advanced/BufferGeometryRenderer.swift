//
//  BufferGeometryRenderer.swift
//  Example
//
//  Created by Reza Ali on 7/13/23.
//  Copyright © 2023 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

private final class RoundedBoxBufferGeometry: SatinGeometry {
    var size: Float {
        didSet {
            if oldValue != size {
                _updateData = true
            }
        }
    }

    let radius: Float
    let resolution: Int

    init(context: Context, size: Float = 1.0, radius: Float = 0.25, resolution: Int = 3) {
        self.size = size
        self.radius = radius
        self.resolution = resolution
        super.init(context: context)
    }

    override func generateGeometryData() -> GeometryData {
        generateRoundedBoxGeometryData(size, size, size, radius, Int32(resolution))
    }
}

final class BufferGeometryMesh: Mesh {
    init(context: Context, label: String = "Buffer Geometry Mesh", geometry: Geometry, material: Material) {
        super.init(context: context, label: label, geometry: geometry, material: material)
    }

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}

final class BufferGeometryRenderer: BaseRenderer {
    private lazy var interleavedGeometry = RoundedBoxBufferGeometry(context: defaultContext)
    lazy var geometry: Geometry = interleaved ? interleavedGeometry : Geometry(context: defaultContext)
    lazy var mesh = BufferGeometryMesh(context: defaultContext, geometry: geometry, material: NormalColorMaterial(context: defaultContext, true))

    lazy var intersectionMesh: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, geometry: IcoSphereGeometry(context: defaultContext, radius: 0.1, resolution: 2), material: BasicColorMaterial(context: defaultContext, color: [0.0, 1.0, 0.0, 1.0], blending: .disabled))
        mesh.label = "Intersection Mesh"
        mesh.renderPass = 1
        mesh.visible = false
        return mesh
    }()

    lazy var scene = Object(context: defaultContext, label: "Scene", [mesh, intersectionMesh])

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0, 0, -5], near: 0.01, far: 100.0, fov: 30)
    lazy var renderer = Renderer(context: defaultContext)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)

    let interleaved = true

    override func setup() {
        if !interleaved {
            setupBufferGeometry()
        }

        camera.lookAt(target: .zero)

#if os(visionOS)
        renderer.setClearColor(.zero)
        metalView.backgroundColor = .clear
#endif
    }

    var theta: Float = 0.0

    override func update() {
        if interleaved {
            interleavedGeometry.size = 1.0 + 0.25 * sin(theta)
        }
        cameraController.update()

        theta += 0.1
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }

    // MARK: Geometry Generation

    func setupBufferGeometry() {
        geometry.addAttribute(
            Float4BufferAttribute(
                defaultValue: .zero,
                data: [
                    [-1.0, -1.0, 0.0, 1.0],
                    [1.0, -1.0, 0.0, 1.0],
                    [1.0, 1.0, 0.0, 1.0],
                    [-1.0, 1.0, 0.0, 1.0]
                ]
            ),
            for: .Position
        )

//        geometry.setAttribute(
//            Float3BufferAttribute(
//                index: .Position,
//                data: [
//                    [-1.0, -1.0, 0.0],
//                    [1.0, -1.0, 0.0],
//                    [1.0, 1.0, 0.0],
//                    [-1.0, 1.0, 0.0]
//                ]
//            )
//        )

        geometry.addAttribute(
            Float3BufferAttribute(
                defaultValue: .zero,
                data: [
                    [0.0, 0.0, 1.0],
                    [0.0, 0.0, 1.0],
                    [0.0, 0.0, 1.0],
                    [0.0, 0.0, 1.0]
                ]
            ),
            for: .Normal
        )

        geometry.addAttribute(
            Float2BufferAttribute(
                defaultValue: .zero,
                data: [
                    [0.0, 0.0],
                    [1.0, 0.0],
                    [1.0, 1.0],
                    [0.0, 1.0]
                ]
            ),
            for: .Texcoord
        )

        geometry.addAttribute(
            Float4BufferAttribute(
                defaultValue: .zero,
                data: [
                    [0.0, 0.0, 0.0, 1.0],
                    [0.0, 1.0, 0.0, 1.0],
                    [0.0, 0.0, 1.0, 1.0],
                    [1.0, 0.0, 0.0, 1.0]
                ]
            ),
            for: .Color
        )

        var elements = [0, 1, 2, 2, 3, 0]
        geometry.setElements(ElementBuffer(type: .uint32, data: &elements, count: 6, source: elements))
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
            //            print(result.object.label)
            //            print(result.position)
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
