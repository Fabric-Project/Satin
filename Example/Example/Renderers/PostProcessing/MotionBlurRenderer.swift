//
//  MotionBlurRenderer.swift
//  Example
//
//  Created by Reza Ali on 4/20/25.
//  Copyright © 2025 Hi-Rez. All rights reserved.
//
#if os(macOS)
import AppKit
#endif

import Metal
import Satin
import simd

final class MotionBlurRenderer: BaseRenderer {
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }
    override var colorPixelFormat: MTLPixelFormat { .rgba16Float }
    override var depthPixelFormat: MTLPixelFormat { .depth32Float }

    // MARK: - Inspector

    override var paramKeys: [String] { ["Motion Blur"] }
    override var params: [String: ParameterGroup?] { ["Motion Blur": renderer.motionBlurMaterial.parameters] }

    private var savedStrength: Float = 0.02

    // MARK: - Camera

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0, 14, 30], near: 0.1, far: 300.0, fov: 45.0)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)

    // MARK: - Renderer

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
        r.motionBlurMaterial.strength = 0.02
        r.motionBlurMaterial.samples = 24
        r.motionBlurMaterial.jitter = 0.0
        return r
    }()

    lazy var compositorMaterial = BasicTextureMaterial(context: defaultContext)
    lazy var compositor = PostProcessor(
        label: "Compositor",
        context: defaultContext,
        material: compositorMaterial,
        depthLoadAction: .dontCare,
        depthStoreAction: .dontCare
    )

    // MARK: - Scene

    lazy var skybox = Mesh(
        context: defaultContext,
        label: "Skybox",
        geometry: SkyboxGeometry(context: defaultContext, size: 250),
        material: SkyboxMaterial(context: defaultContext)
    )

    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [skybox])

    struct OrbitalGroup {
        let pivot: Object
        let angularSpeed: Float
    }

    var orbitalGroups: [OrbitalGroup] = []

    private let ringParams: [(radius: Float, speed: Float, count: Int, color: simd_float4, scale: Float, metallic: Float, roughness: Float)] = [
        (radius:  3.0, speed:  3.6, count:  6, color: [0.95, 0.25, 0.25, 1], scale: 0.55, metallic: 0.9, roughness: 0.15),
        (radius:  6.0, speed:  2.0, count:  9, color: [0.95, 0.65, 0.10, 1], scale: 0.65, metallic: 0.0, roughness: 0.40),
        (radius: 10.0, speed:  1.1, count: 12, color: [0.15, 0.80, 0.40, 1], scale: 0.80, metallic: 0.6, roughness: 0.25),
        (radius: 15.0, speed:  0.55, count: 15, color: [0.15, 0.50, 0.95, 1], scale: 0.95, metallic: 0.0, roughness: 0.60),
        (radius: 21.0, speed:  0.25, count: 18, color: [0.70, 0.20, 0.95, 1], scale: 1.10, metallic: 0.85, roughness: 0.10),
    ]

    private var time: Float = 0.0
    private var lastTime: CFAbsoluteTime = 0

    // MARK: - Lifecycle

    override func setup() {
        camera.lookAt(target: [0, 2, 0])
        loadEnvironment()
        buildScene()
        scene.environmentIntensity = 0.5

        super.setup()
    }

    override func update() {
        cameraController.update()
        let now = getTime()
        let dt = lastTime > 0 ? Float(now - lastTime) : Float(1.0 / 60.0)
        lastTime = now
        time += dt
        for group in orbitalGroups {
            group.pivot.orientation = simd_quatf(angle: group.angularSpeed * time, axis: [0, 1, 0])
        }
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        renderer.draw(
            renderPassDescriptor: MTLRenderPassDescriptor(),
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )

        if let motionBlurTexture = renderer.motionBlurTexture {
            compositorMaterial.texture = motionBlurTexture
            compositor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        } else if let colorTexture = renderer.colorTexture {
            compositorMaterial.texture = colorTexture
            compositor.draw(renderPassDescriptor: renderPassDescriptor, commandBuffer: commandBuffer)
        }
    }

    override func resize(size: (width: Float, height: Float), scaleFactor: Float) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
        compositor.resize(size: size, scaleFactor: scaleFactor)
    }

#if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let mat = renderer.motionBlurMaterial
        if mat.strength > 0 {
            savedStrength = mat.strength
            mat.strength = 0
        } else {
            mat.strength = savedStrength
        }
    }
#endif

    // MARK: - Environment

    private func loadEnvironment() {
        let url = texturesURL.appendingPathComponent("brown_photostudio_02_2k.hdr")
        if let hdr = loadHDR(device: device, url: url) {
            scene.setEnvironment(texture: hdr)
        }
    }

    // MARK: - Scene Construction

    private func buildScene() {
        let floor = Mesh(
            context: defaultContext,
            label: "Floor",
            geometry: PlaneGeometry(context: defaultContext, size: 80, resolution: 1),
            material: StandardMaterial(context: defaultContext, baseColor: [0.08, 0.08, 0.10, 1], metallic: 0.0, roughness: 0.85)
        )
        floor.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        scene.add(floor)

        let geometries: [(Context) -> Geometry] = [
            { IcoSphereGeometry(context: $0, radius: 1.0, resolution: 3) },
            { RoundedBoxGeometry(context: $0, size: 1.8, radius: 0.3, resolution: 3) },
            { CapsuleGeometry(context: $0, radius: 0.7, height: 2.0) },
        ]

        for (ringIndex, params) in ringParams.enumerated() {
            let pivot = Object(context: defaultContext, label: "Ring \(ringIndex)")
            let geom = geometries[ringIndex % geometries.count](defaultContext)
            let mat = StandardMaterial(
                context: defaultContext,
                baseColor: params.color,
                metallic: params.metallic,
                roughness: params.roughness
            )

            for i in 0 ..< params.count {
                let angle = Float(i) / Float(params.count) * 2.0 * .pi
                let mesh = Mesh(context: defaultContext, label: "Orb \(ringIndex)-\(i)", geometry: geom, material: mat)
                mesh.position = [cos(angle) * params.radius, params.scale * 0.5, sin(angle) * params.radius]
                mesh.scale = simd_float3(repeating: params.scale)
                mesh.orientation = simd_quatf(angle: angle, axis: simd_normalize([0.4, 1.0, 0.3]))
                pivot.add(mesh)
            }

            orbitalGroups.append(OrbitalGroup(pivot: pivot, angularSpeed: params.speed))
            scene.add(pivot)
        }

        let center = Mesh(
            context: defaultContext,
            label: "Center",
            geometry: IcoSphereGeometry(context: defaultContext, radius: 1.5, resolution: 4),
            material: StandardMaterial(context: defaultContext, baseColor: [1, 1, 1, 1], metallic: 1.0, roughness: 0.05)
        )
        center.position.y = 1.5
        scene.add(center)
    }
}
