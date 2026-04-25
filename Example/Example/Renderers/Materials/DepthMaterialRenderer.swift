//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 6/24/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Satin

final class DepthMaterialRenderer: BaseRenderer {
    lazy var depthMaterial: DepthMaterial = {
        let material = DepthMaterial()
        // Options to play with
        // By default the DepthMaterial uses the near and far from the camera's projection matrix (near & far)
        // By setting the Near and Far parameters below you can override this behavior
        // Setting the Near and Far parameters to negative values will revert to using the camera's projection matrix (near & far)
//        material.set("Invert", false)
//        material.set("Color", false)
        material.set("Near", 8.0)
        material.set("Far", 20.0)
        return material
    }()

    lazy var container: Mesh = {
        let mesh = Mesh(label: "Container", geometry: BoxGeometry(size: 10), material: depthMaterial)
        mesh.geometry.windingOrder = .clockwise
        return mesh
    }()

    lazy var torus: Mesh = {
        let mesh = Mesh(label: "Torus", geometry: TorusGeometry(minorRadius: 0.5, majorRadius: 2.0, minorResolution: 30, majorResolution: 90), material: depthMaterial)
        mesh.position = [2, -2, -2]
        mesh.orientation = simd_quatf(angle: Float.pi * 0.25, axis: normalize([1, 1, 1]))
        return mesh
    }()

    lazy var cylinder: Mesh = {
        let mesh = Mesh(label: "Cylinder", geometry: CylinderGeometry(radius: 0.5, height: 2.0), material: depthMaterial)
        mesh.position = [-2, 2, 2]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, 1, 1]))
        return mesh
    }()

    lazy var capsule: Mesh = {
        let mesh = Mesh(label: "Capsule", geometry: CapsuleGeometry(radius: 0.5, height: 2.0), material: depthMaterial)
        mesh.position = [2, -2, 2]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, 0.5, 1]))
        return mesh
    }()

    lazy var box: Mesh = {
        let mesh = Mesh(label: "Box", geometry: BoxGeometry(), material: depthMaterial)
        mesh.position = [2.5, 3.0, -3]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([1.0, -0.25, 0.25]))
        let rod = Mesh(geometry: CylinderGeometry(radius: 0.1, height: 6.0, angularResolution: 24), material: depthMaterial)
        rod.label = "Rod"
        mesh.add(rod)
        return mesh
    }()

    lazy var longBox: Mesh = {
        let mesh = Mesh(label: "Long Box", geometry: BoxGeometry(width: 0.5, height: 2.0, depth: 4.0), material: depthMaterial)
        mesh.position = [-2, -3, 0]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, -0.5, 0.25]))
        return mesh
    }()

    lazy var cone: Mesh = {
        let mesh = Mesh(label: "Cone", geometry: ConeGeometry(radius: 1.0, height: 2.0, angularResolution: 30), material: depthMaterial)
        mesh.position = [-3, 0, -2]
        mesh.orientation = simd_quatf(angle: Float.pi * 0.25, axis: normalize([1.0, 0.5, 0.25]))
        return mesh
    }()

    lazy var sphere = Mesh(label: "Sphere", geometry: IcoSphereGeometry(radius: 1.5, resolution: 0), material: depthMaterial)

    lazy var scene: Object = {
        let obj = Object(label: "Scene", [
            container,
            box,
            sphere,
            torus,
            cylinder,
            capsule,
            longBox,
            cone,
        ])
        return obj
    }()

    lazy var camera = PerspectiveCamera(position: [0.0, 0.0, 13.0], near: 0.001, far: 20.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = Renderer(context: defaultContext, clearColor: [0.137254902, 0.09411764706, 0.1058823529, 1.0])

    override func setup() {
//        // Setup things here
//        let mat = UvColorMaterial()
//        let boundingBoxes = Object("Bounding Boxes")
//        scene.apply { object in
//            let mesh = Mesh(geometry: BoxGeometry(bounds: object.worldBounds), material: mat)
//            mesh.label = object.label + " Bounds"
//            mesh.triangleFillMode = .lines
//            boundingBoxes.add(mesh)
//        }
//        scene.add(boundingBoxes)

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
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let m = event.locationInWindow
        let pt = normalizePoint(m, metalView.frame.size)
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
