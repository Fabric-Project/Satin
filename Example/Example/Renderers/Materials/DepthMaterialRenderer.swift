//
//  Renderer.swift
//  Example
//
//  Created by Reza Ali on 6/24/20.
//  Copyright © 2020 Hi-Rez. All rights reserved.
//

import Metal
import MetalKit

import Forge
import Satin

class DepthMaterialRenderer: BaseRenderer {
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
        let mesh = Mesh(geometry: BoxGeometry(size: 10), material: depthMaterial)
        mesh.label = "Container"
        mesh.geometry.windingOrder = .clockwise
        return mesh
    }()

    lazy var torus: Mesh = {
        let mesh = Mesh(geometry: TorusGeometry(minorRadius: 0.5, majorRadius: 2.0, minorResolution: 30, majorResolution: 90), material: depthMaterial)
        mesh.label = "Torus"
        mesh.position = [2, -2, -2]
        mesh.orientation = simd_quatf(angle: Float.pi * 0.25, axis: normalize([1, 1, 1]))
        return mesh
    }()

    lazy var cylinder: Mesh = {
        let mesh = Mesh(geometry: CylinderGeometry(radius: 0.5, height: 2.0), material: depthMaterial)
        mesh.label = "Cylinder"
        mesh.position = [-2, 2, 2]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, 1, 1]))
        return mesh
    }()

    lazy var capsule: Mesh = {
        let mesh = Mesh(geometry: CapsuleGeometry(radius: 0.5, height: 2.0), material: depthMaterial)
        mesh.label = "Capsule"
        mesh.position = [2, -2, 2]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, 0.5, 1]))
        return mesh
    }()

    lazy var box: Mesh = {
        let mesh = Mesh(geometry: BoxGeometry(), material: depthMaterial)
        mesh.label = "Box"
        mesh.position = [2.5, 3.0, -3]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([1.0, -0.25, 0.25]))
        let rod = Mesh(geometry: CylinderGeometry(radius: 0.1, height: 6.0, angularResolution: 24), material: depthMaterial)
        rod.label = "Rod"
        mesh.add(rod)
        return mesh
    }()

    lazy var longBox: Mesh = {
        let mesh = Mesh(geometry: BoxGeometry(width: 0.5, height: 2.0, depth: 4.0), material: depthMaterial)
        mesh.label = "Long Box"
        mesh.position = [-2, -3, 0]
        mesh.orientation = simd_quatf(angle: -Float.pi * 0.25, axis: normalize([0.5, -0.5, 0.25]))
        return mesh
    }()

    lazy var cone: Mesh = {
        let mesh = Mesh(geometry: ConeGeometry(radius: 1.0, height: 2.0, angularResolution: 30), material: depthMaterial)
        mesh.label = "Cone"
        mesh.position = [-3, 0, -2]
        mesh.orientation = simd_quatf(angle: Float.pi * 0.25, axis: normalize([1.0, 0.5, 0.25]))
        return mesh
    }()

    lazy var sphere: Mesh = {
        let mesh = Mesh(geometry: IcoSphereGeometry(radius: 1.5, resolution: 0), material: depthMaterial)
        mesh.label = "Sphere"
        return mesh
    }()

    lazy var scene: Object = {
        let obj = Object("Scene", [
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

    lazy var context = Context(device, sampleCount, colorPixelFormat, depthPixelFormat, stencilPixelFormat)

    lazy var camera = PerspectiveCamera(position: [0.0, 0.0, 13.0], near: 0.001, far: 20.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: mtkView)

    lazy var renderer: Satin.Renderer = {
        let renderer = Satin.Renderer(context: context)
        renderer.clearColor = .init(red: 0.137254902, green: 0.09411764706, blue: 0.1058823529, alpha: 1.0)
        return renderer
    }()

    override func setupMtkView(_ metalKitView: MTKView) {
        metalKitView.sampleCount = 1
        metalKitView.colorPixelFormat = .bgra8Unorm
        metalKitView.depthStencilPixelFormat = .depth32Float
        metalKitView.preferredFramesPerSecond = 60
    }

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
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }

    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let m = event.locationInWindow
        let pt = normalizePoint(m, mtkView.frame.size)
        let results = raycast(camera: camera, coordinate: pt, object: scene)
        for result in results {
            print(result.object.label)
            print(result.position)
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
