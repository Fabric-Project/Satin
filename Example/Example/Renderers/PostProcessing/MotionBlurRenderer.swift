//
//  MotionBlurRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/20/25.
//  Copyright © 2025 Hi-Rez. All rights reserved.
//

import Metal
import Satin
import simd

final class MotionBlurRenderer: BaseRenderer {
    // MARK: - Rendering

    override var depthPixelFormat: MTLPixelFormat { .depth32Float }

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0, 12, 28], near: 0.1, far: 200.0, fov: 45.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer: Renderer = {
        let r = Renderer(
            context: defaultContext,
            colorLoadAction: .clear,
            colorStoreAction: .store,
            depthLoadAction: .clear,
            depthStoreAction: .store,
            frameBufferOnly: false
        )
        r.passes = [.motionBlur]
        r.colorTextureStorageMode = .private
        r.depthTextureStorageMode = .private
        r.motionBlurMaterial.strength = 1
        r.motionBlurMaterial.samples = 16
        return r
    }()

    // Final composite — takes motionBlurTexture → screen
    lazy var compositorMaterial = BasicTextureMaterial(context: defaultContext)
    lazy var compositor = PostProcessor(
        label: "Compositor",
        context: defaultContext,
        material: compositorMaterial,
        depthLoadAction: .dontCare,
        depthStoreAction: .dontCare
    )

    // MARK: - Scene

    // Each OrbitalGroup holds objects at one radius, all rotating at one angular speed
    struct OrbitalGroup {
        let pivot: Object
        let angularSpeed: Float  // radians per second
    }

    var orbitalGroups: [OrbitalGroup] = []

    lazy var scene: Object = {
        let scene = Object(context: defaultContext, label: "Scene")

        // Floor plane for reference
        let floor = Mesh(
            context: defaultContext,
            label: "Floor",
            geometry: PlaneGeometry(context: defaultContext, size: 60, resolution: 1),
            material: BasicColorMaterial(context: defaultContext, color: [0.12, 0.12, 0.14, 1.0], blending: .disabled)
        )
        floor.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        scene.add(floor)

        // 5 orbital rings with increasing radii and decreasing angular speed
        let ringParams: [(radius: Float, speed: Float, count: Int, color: simd_float4, scale: Float)] = [
            (radius:  3.0, speed:  3.6, count: 6,  color: [0.95, 0.35, 0.35, 1], scale: 0.55),
            (radius:  6.0, speed:  2.0, count: 9,  color: [0.95, 0.70, 0.25, 1], scale: 0.65),
            (radius: 10.0, speed:  1.1, count: 12, color: [0.30, 0.85, 0.50, 1], scale: 0.80),
            (radius: 15.0, speed:  0.55, count: 15, color: [0.25, 0.60, 0.95, 1], scale: 0.95),
            (radius: 21.0, speed:  0.25, count: 18, color: [0.75, 0.35, 0.95, 1], scale: 1.10),
        ]

        let geometries: [(Context) -> Geometry] = [
            { IcoSphereGeometry(context: $0, radius: 1.0, resolution: 3) },
            { RoundedBoxGeometry(context: $0, size: 1.8, radius: 0.3, resolution: 3) },
            { CapsuleGeometry(context: $0, radius: 0.7, height: 2.0) },
        ]

        for (ringIndex, params) in ringParams.enumerated() {
            let pivot = Object(context: defaultContext, label: "Ring \(ringIndex)")
            let geomFactory = geometries[ringIndex % geometries.count]
            let geom = geomFactory(defaultContext)
            let mat = BasicColorMaterial(context: defaultContext, color: params.color, blending: .disabled)

            for i in 0 ..< params.count {
                let angle = Float(i) / Float(params.count) * 2.0 * .pi
                let mesh = Mesh(context: defaultContext, label: "Orb \(ringIndex)-\(i)", geometry: geom, material: mat)
                mesh.position = [cos(angle) * params.radius, params.scale * 0.5, sin(angle) * params.radius]
                mesh.scale = simd_float3(repeating: params.scale)
                mesh.orientation = simd_quatf(angle: angle, axis: simd_normalize([0.4, 1, 0.3]))
                pivot.add(mesh)
            }

            orbitalGroups.append(OrbitalGroup(pivot: pivot, angularSpeed: params.speed))
            scene.add(pivot)
        }

        // Central spinning shape (fast, stays in place)
        let centerGeom = IcoSphereGeometry(context: defaultContext, radius: 1.5, resolution: 4)
        let centerMat = BasicColorMaterial(context: defaultContext, color: [1.0, 1.0, 1.0, 1.0], blending: .disabled)
        let center = Mesh(context: defaultContext, label: "Center", geometry: centerGeom, material: centerMat)
        center.position.y = 1.5
        scene.add(center)

        return scene
    }()

    // MARK: - Time

    private var time: Float = 0.0

    // MARK: - Lifecycle

    override func setup() {
        camera.lookAt(target: [0, 2, 0])
    }

    override func update() {
        cameraController.update()
        let dt: Float = 1.0 / 60.0
        time += dt

        for group in orbitalGroups {
            group.pivot.orientation = simd_quatf(angle: group.angularSpeed * time, axis: [0, 1, 0])
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        // Render scene (+ velocity prepass + motion blur) to motionBlurTexture
        renderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        // Composite motionBlurTexture → screen
        if let motionBlurTexture = renderer.motionBlurTexture {
            compositorMaterial.texture = motionBlurTexture
            compositor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        } else {
            // Fallback: show unblurred color if motionBlurTexture isn't ready
            if let colorTexture = renderer.colorTexture {
                compositorMaterial.texture = colorTexture
                compositor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
            }
        }
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
        compositor.resize(size: size, scaleFactor: scaleFactor)
    }
}
