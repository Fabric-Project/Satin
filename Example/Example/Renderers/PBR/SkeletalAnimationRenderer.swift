//
//  SkeletalAnimationRenderer.swift
//  Example
//

import Metal
import MetalKit
import Satin

/// Plays a USD skeletal animation: `loadAnimatedAsset` returns the model and its animation,
/// whose `setTime` poses every skinned mesh on the GPU. Staged like the PBR Point Shadows example:
/// a cyclorama and two shadow-casting point lights.
final class SkeletalAnimationRenderer: BaseRenderer {
    override var modelsURL: URL { sharedAssetsURL.appendingPathComponent("Models") }
    override var texturesURL: URL { sharedAssetsURL.appendingPathComponent("Textures") }

    /// The model's largest dimension once scaled, in the PBR Point Shadows example's units.
    let modelSize: Float = 16.0

    lazy var cycloramaMesh = Mesh(
        context: defaultContext,
        geometry: CycloramaGeometry(
            context: defaultContext,
            width: 38.0,
            length: 30.0,
            depth: 27.0,
            radius: 15.0,
            widthResolution: 8,
            lengthResolution: 8,
            depthResolution: 8,
            angularResolution: 28
        ),
        material: StandardMaterial(
            context: defaultContext,
            baseColor: [0.82, 0.84, 0.88, 1.0],
            metallic: 0.0,
            roughness: 0.96
        )
    )

    lazy var skybox = Mesh(context: defaultContext, geometry: SkyboxGeometry(context: defaultContext, size: 200), material: SkyboxMaterial(context: defaultContext))
    lazy var scene = IBLScene(context: defaultContext, label: "Scene", [cycloramaMesh, skybox])

    lazy var camera = PerspectiveCamera(context: defaultContext, position: [0.0, 5.0, 30.0], near: 0.01, far: 1000.0, fov: 45)
    lazy var cameraController = PerspectiveCameraController(camera: camera, view: metalView)
    lazy var renderer = RenderEncoder(context: defaultContext)
    lazy var textureLoader = MTKTextureLoader(device: device)

    var animation: AssetAnimation?
    lazy var startTime = getTime()

    override func setup() throws {
        if let hdr = loadHDR(device: device, url: texturesURL.appendingPathComponent("brown_photostudio_02_2k.hdr")) {
            scene.setEnvironment(texture: hdr)
        }
        scene.environmentIntensity = 0.02
        
//        let loaded = loadAnimatedAsset(url: modelsURL.appendingPathComponent("chameleon_anim_mtl_variant.usdz"), context: defaultContext, textureLoader: textureLoader)
        let loaded = loadAnimatedAsset(url: modelsURL.appendingPathComponent("CC0_カブトムシ__赤_Japanese_Rhinoceros_Beetle_Red.usdz"), context: defaultContext, textureLoader: textureLoader)
        animation = loaded.animation
        for mesh in loaded.root.getChildren().compactMap({ $0 as? Mesh }) {
            mesh.castShadow = true
            mesh.receiveShadow = true
        }

        // Scaled to the stage and centered at the origin; the cyclorama's floor meets its base.
        let bounds = loaded.root.worldBounds
        let scale = modelSize / max(simd_reduce_max(bounds.size), .leastNormalMagnitude)
        loaded.root.scale = .init(repeating: scale)
        loaded.root.position = -bounds.center * scale
        scene.add(loaded.root)

        cycloramaMesh.label = "Cyclorama"
        cycloramaMesh.position = [0.0, -bounds.size.y * scale * 0.5, -16.0]
        cycloramaMesh.receiveShadow = true
        cycloramaMesh.cullMode = .none

        camera.lookAt(target: .zero)
        setupLights()
    }

    /// A warm key light above and in front, and a cool rim light behind and to the side.
    func setupLights() {
        let positions: [simd_float3] = [[5.0, 5.0, 9.0], [-5.0, 5.0, 9.0]]
        let colors: [simd_float3] = [[1.0, 0.86, 0.72], [0.55, 0.75, 1.0]]
        let intensities: [Float] = [100.0, 100.0]

        for index in positions.indices {
            let light = PointLight(context: defaultContext, color: colors[index], intensity: intensities[index], radius: 120)
            light.position = positions[index]
            light.castShadow = true
            light.shadow.resolution = (1024, 1024)
            light.shadow.bias = 0.00005
            light.shadow.normalBias = 0.05
            light.shadow.radius = 1.0
            light.shadow.strength = 0.9
            
            light.lookAt(target: .zero)

            let lightMesh = Mesh(
                context: defaultContext,
                geometry: IcoSphereGeometry(context: defaultContext, radius: 0.25, resolution: 3),
                material: BasicColorMaterial(context: defaultContext, color: simd_make_float4(colors[index], 1.0), blending: .disabled)
            )
            lightMesh.label = "Light Mesh \(index)"
            light.add(lightMesh)
            scene.add(light)
        }
    }

    override func update() throws {
        cameraController.update()
        // Loops the animation; set once per frame, so velocity sees one step.
        guard let animation, let timeRange = animation.timeRange, timeRange.upperBound > timeRange.lowerBound else { return }
        let elapsed = getTime() - startTime
        animation.setTime(timeRange.lowerBound + elapsed.truncatingRemainder(dividingBy: timeRange.upperBound - timeRange.lowerBound))
    }

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        try renderer.draw(
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
}
