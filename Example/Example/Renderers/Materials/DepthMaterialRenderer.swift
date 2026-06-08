//
//  RenderEncoder.swift
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
        lazy var material = DepthMaterial(context: defaultContext)
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
        lazy var mesh = Mesh(context: defaultContext, label: "Container", geometry: BoxGeometry(context: defaultContext, size: 10), material: depthMaterial)
        mesh.geometry.windingOrder = .clockwise
        return mesh
    }()

    lazy var torus: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, label: "Torus", geometry: TorusGeometry(context: defaultContext, minorRadius: 0.5, majorRadius: 2.0, minorResolution: 30, majorResolution: 90), material: depthMaterial)
        mesh.position = [2, -2, -2]
        mesh.orientation = simd_quatf(angle: Float.pi * 0.25, axis: normalize([1, 1, 1]))
        return mesh
    }()

    lazy var cylinder: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, label: "Cylinder", geometry: CylinderGeometry(context: defaultContext, radius: 0.5, height: 2.0), material: depthMaterial)
        mesh.position = [-2, 2, 2]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, 1, 1]))
        return mesh
    }()

    lazy var capsule: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, label: "Capsule", geometry: CapsuleGeometry(context: defaultContext, radius: 0.5, height: 2.0), material: depthMaterial)
        mesh.position = [2, -2, 2]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, 0.5, 1]))
        return mesh
    }()

    lazy var box: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, label: "Box", geometry: BoxGeometry(context: defaultContext), material: depthMaterial)
        mesh.position = [2.5, 3.0, -3]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([1.0, -0.25, 0.25]))
        lazy var rod = Mesh(context: defaultContext, geometry: CylinderGeometry(context: defaultContext, radius: 0.1, height: 6.0, angularResolution: 24), material: depthMaterial)
        rod.label = "Rod"
        mesh.add(rod)
        return mesh
    }()

    lazy var longBox: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, label: "Long Box", geometry: BoxGeometry(context: defaultContext, width: 0.5, height: 2.0, depth: 4.0), material: depthMaterial)
        mesh.position = [-2, -3, 0]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, -0.5, 0.25]))
        return mesh
    }()

    lazy var cone: Mesh = {
        lazy var mesh = Mesh(context: defaultContext, label: "Cone", geometry: ConeGeometry(context: defaultContext, radius: 1.0, height: 2.0, angularResolution: 30), material: depthMaterial)
        mesh.position = [-3, 0, -2]
        mesh.orientation = simd_quatf(angle: Float.pi * 0.25, axis: normalize([1.0, 0.5, 0.25]))
        return mesh
    }()

    lazy var sphere = Mesh(context: defaultContext, label: "Sphere", geometry: IcoSphereGeometry(context: defaultContext, radius: 1.5, resolution: 0), material: depthMaterial)

    lazy var scene: Object = {
        lazy var obj = Object(context: defaultContext, label: "Scene", [
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

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 0.0, 13.0], near: 0.001, far: 20.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext, clearColor: [0.137254902, 0.09411764706, 0.1058823529, 1.0])

    override func setup() {
//        // Setup things here
//        let mat = UvColorMaterial()
//        let boundingBoxes = Object("Bounding Boxes")
//        scene.apply { object in
//            let mesh = Mesh(geometry: BoxGeometry(context: defaultContext, bounds: object.worldBounds), material: mat)
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
