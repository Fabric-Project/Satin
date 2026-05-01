import Metal
import Satin
import XCTest

final class VisualRendererTests: XCTestCase {
    func testComputeNoiseTextureMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(192, 192)) { renderer, camera in
            let device = renderer.context.device
            let commandQueue = device.makeCommandQueue()!
            let commandBuffer = commandQueue.makeCommandBuffer()!

            let generator = RandomNoiseGenerator(device: device, size: (64, 64), range: 0.0 ... 1.0, seed: 42)
            let noiseTexture = generator.encode(commandBuffer: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            let quad = Mesh(
                label: "Noise Quad",
                geometry: QuadGeometry(size: 2.0),
                material: BasicTextureMaterial(texture: noiseTexture)
            )

            camera.position = [0, 0, 3]
            camera.lookAt(target: .zero)

            return (scene: Object(label: "Scene", [quad]), camera: camera)
        }

        VisualTestHarness.assertContainsVisibleContent(image, minimumChangedPixelRatio: 0.85, minimumMeanNormalizedDifference: 0.1)
        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "compute-noise"),
            threshold: 0.003
        )
    }

    func testMaterialGridMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(192, 192)) { renderer, camera in
            let device = renderer.context.device

            let root = Object(label: "Scene")
            let group = Object(label: "Material Group")

            let checkerTexture = makeCheckerTexture(device: device, width: 32, height: 32)

            let materials: [Material] = [
                BasicColorMaterial(color: simd_float4(0.9, 0.2, 0.15, 1.0), blending: .disabled),
                UVColorMaterial(),
                NormalColorMaterial(),
                BasicTextureMaterial(texture: checkerTexture)
            ]

            let positions: [simd_float3] = [
                [-0.9, 0.9, 0.0],
                [0.9, 0.9, 0.0],
                [-0.9, -0.9, 0.0],
                [0.9, -0.9, 0.0]
            ]

            for (index, material) in materials.enumerated() {
                let mesh = Mesh(
                    label: "Material Mesh \(index)",
                    geometry: RoundedRectGeometry(width: 0.75, height: 0.75, radius: 0.14, angularResolution: 32, radialResolution: 16),
                    material: material
                )
                mesh.position = positions[index]
                group.add(mesh)
            }

            root.add(group)

            camera.position = [0, 0, 4]
            camera.lookAt(target: .zero)

            return (scene: root, camera: camera)
        }

        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "material-grid"),
            threshold: 0.003
        )
    }

    func testGeometryGalleryMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(224, 192)) { _, camera in
            let scene = Object(label: "Scene")

            let light = DirectionalLight(color: simd_float3(repeating: 1.0), intensity: 1.9)
            light.position = [2.2, 2.8, 3.2]
            light.lookAt(target: .zero)

            let material = BasicDiffuseMaterial(color: simd_float4(0.92, 0.78, 0.28, 1.0), blending: .disabled, hardness: 0.65)

            let torus = Mesh(geometry: TorusGeometry(minorRadius: 0.14, majorRadius: 0.34), material: material.clone())
            torus.position = [-1.2, 0.55, 0.0]
            torus.orientation = simd_quatf(angle: .pi * 0.35, axis: simd_normalize(simd_float3(1.0, 0.2, 0.0)))

            let capsule = Mesh(geometry: CapsuleGeometry(radius: 0.2, height: 0.75), material: material.clone())
            capsule.position = [0.0, 0.55, 0.0]
            capsule.orientation = simd_quatf(angle: .pi * 0.1, axis: simd_normalize(simd_float3(0.1, 1.0, 0.3)))

            let cone = Mesh(geometry: ConeGeometry(radius: 0.32, height: 0.72, radialResolution: 32, verticalResolution: 1), material: material.clone())
            cone.position = [1.2, 0.55, 0.0]

            let roundedBox = Mesh(geometry: RoundedBoxGeometry(size: simd_float3(repeating: 0.58), radius: 0.12, resolution: 2), material: material.clone())
            roundedBox.position = [-0.6, -0.72, 0.0]
            roundedBox.orientation = simd_quatf(angle: .pi * 0.22, axis: simd_normalize(simd_float3(0.3, 1.0, 0.2)))

            let octa = Mesh(geometry: OctaSphereGeometry(radius: 0.35, resolution: 3), material: material.clone())
            octa.position = [0.75, -0.72, 0.0]

            scene.add(light)
            scene.add(torus)
            scene.add(capsule)
            scene.add(cone)
            scene.add(roundedBox)
            scene.add(octa)

            camera.position = [0, 0, 4.8]
            camera.lookAt(target: .zero)

            return (scene: scene, camera: camera)
        }

        VisualTestHarness.assertContainsVisibleContent(image, minimumChangedPixelRatio: 0.12, minimumMeanNormalizedDifference: 0.02)
        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "geometry-gallery"),
            threshold: 0.008
        )
    }

    func testSceneHierarchyTransformsMatchReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(192, 192)) { _, camera in
            let scene = Object(label: "Scene")

            let parent = Object(label: "Parent")
            parent.position = [-0.25, 0.0, 0.0]
            parent.orientation = simd_quatf(angle: .pi * 0.16, axis: simd_normalize(simd_float3(0.2, 1.0, 0.0)))

            let child = Object(label: "Child")
            child.position = [0.9, 0.0, 0.0]
            child.scale = [0.8, 1.2, 0.8]
            child.orientation = simd_quatf(angle: -.pi * 0.32, axis: simd_normalize(simd_float3(0.0, 0.0, 1.0)))

            let grandchild = Mesh(
                label: "Grandchild Mesh",
                geometry: BoxGeometry(size: 0.7),
                material: BasicColorMaterial(color: simd_float4(0.95, 0.82, 0.2, 1.0), blending: .disabled)
            )
            grandchild.position = [0.85, 0.0, 0.0]
            grandchild.scale = [0.7, 1.3, 0.6]

            let anchorMesh = Mesh(
                label: "Anchor Mesh",
                geometry: IcoSphereGeometry(radius: 0.35, resolution: 2),
                material: BasicColorMaterial(color: simd_float4(0.15, 0.7, 0.95, 1.0), blending: .disabled)
            )
            anchorMesh.position = [-0.5, -0.55, 0.0]

            child.add(grandchild)
            parent.add(child)
            scene.add(parent)
            scene.add(anchorMesh)

            camera.position = [0, 0, 5.5]
            camera.lookAt(target: [0.15, 0.0, 0.0])

            return (scene: scene, camera: camera)
        }

        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "scene-hierarchy"),
            threshold: 0.005
        )
    }

    func testDirectionalShadowMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(224, 192)) { _, camera in
            let scene = Object(label: "Scene")

            let light = DirectionalLight(color: simd_float3(repeating: 1.0), intensity: 1.2)
            light.position = [2.8, 3.5, 2.8]
            light.lookAt(target: .zero, up: Satin.worldUpDirection)
            light.castShadow = true
            light.shadow.resolution = (width: 1024, height: 1024)
            light.shadow.bias = 0.0005
            light.shadow.strength = 0.6
            light.shadow.radius = 1.25
            if let shadowCamera = light.shadow.camera as? OrthographicCamera {
                shadowCamera.update(left: -3.0, right: 3.0, bottom: -3.0, top: 3.0)
            }

            let floor = Mesh(
                label: "Floor",
                geometry: PlaneGeometry(size: 6.0, orientation: .zx),
                material: BasicDiffuseMaterial(color: simd_float4(0.24, 0.24, 0.28, 1.0), blending: .disabled, hardness: 0.2)
            )
            floor.position.y = -0.9
            floor.receiveShadow = true

            let sphere = Mesh(
                label: "Sphere",
                geometry: IcoSphereGeometry(radius: 0.45, resolution: 2),
                material: BasicDiffuseMaterial(color: simd_float4(0.95, 0.72, 0.25, 1.0), blending: .disabled, hardness: 0.55)
            )
            sphere.position = [-0.55, -0.15, 0.0]
            sphere.castShadow = true
            sphere.receiveShadow = true

            let torus = Mesh(
                label: "Torus",
                geometry: TorusGeometry(minorRadius: 0.12, majorRadius: 0.36),
                material: BasicDiffuseMaterial(color: simd_float4(0.25, 0.8, 0.6, 1.0), blending: .disabled, hardness: 0.8)
            )
            torus.position = [0.75, -0.18, 0.0]
            torus.orientation = simd_quatf(angle: .pi * 0.25, axis: simd_normalize(simd_float3(1.0, 0.4, 0.0)))
            torus.castShadow = true
            torus.receiveShadow = true

            scene.add(light)
            scene.add(floor)
            scene.add(sphere)
            scene.add(torus)

            camera.position = [0, 0.45, 4.6]
            camera.lookAt(target: [0.15, -0.25, 0.0])

            return (scene: scene, camera: camera)
        }

        VisualTestHarness.assertContainsVisibleContent(image, minimumChangedPixelRatio: 0.10, minimumMeanNormalizedDifference: 0.02)
        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "directional-shadow"),
            threshold: 0.01
        )
    }

    func testLightingRigMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(192, 192)) { _, camera in
            let scene = Object(label: "Scene")

            let directional = DirectionalLight(color: simd_float3(1.0, 0.96, 0.9), intensity: 1.4)
            directional.position = [1.5, 2.2, 2.8]
            directional.lookAt(target: .zero)

            let point = PointLight(color: simd_float3(0.15, 0.55, 1.0), intensity: 2.2, radius: 8.0)
            point.position = [-1.8, 1.2, 1.8]

            let spot = SpotLight(color: simd_float3(1.0, 0.3, 0.2), intensity: 3.8, radius: 10.0, angleInner: 22.0, angleOuter: 34.0)
            spot.position = [0.0, 2.5, 2.8]
            spot.lookAt(target: [0.0, -0.2, 0.0])

            let left = Mesh(
                label: "Left Sphere",
                geometry: IcoSphereGeometry(radius: 0.5, resolution: 2),
                material: BasicDiffuseMaterial(color: simd_float4(0.92, 0.55, 0.18, 1.0), blending: .disabled, hardness: 0.35)
            )
            left.position = [-0.95, 0.0, 0.0]

            let center = Mesh(
                label: "Center Sphere",
                geometry: IcoSphereGeometry(radius: 0.5, resolution: 2),
                material: BasicDiffuseMaterial(color: simd_float4(0.82, 0.84, 0.88, 1.0), blending: .disabled, hardness: 0.8)
            )
            center.position = [0.0, 0.0, 0.0]

            let right = Mesh(
                label: "Right Sphere",
                geometry: IcoSphereGeometry(radius: 0.5, resolution: 2),
                material: BasicDiffuseMaterial(color: simd_float4(0.18, 0.85, 0.55, 1.0), blending: .disabled, hardness: 0.55)
            )
            right.position = [0.95, 0.0, 0.0]

            let ground = Mesh(
                label: "Ground",
                geometry: PlaneGeometry(size: 4.0),
                material: BasicDiffuseMaterial(color: simd_float4(0.16, 0.18, 0.22, 1.0), blending: .disabled, hardness: 0.25)
            )
            ground.position = [0.0, -0.75, 0.0]
            ground.orientation = simd_quatf(angle: -.pi * 0.5, axis: simd_float3(1.0, 0.0, 0.0))

            scene.add(directional)
            scene.add(point)
            scene.add(spot)
            scene.add(left)
            scene.add(center)
            scene.add(right)
            scene.add(ground)

            camera.position = [0, 0.35, 4.9]
            camera.lookAt(target: [0.0, -0.1, 0.0])

            return (scene: scene, camera: camera)
        }

        VisualTestHarness.assertContainsVisibleContent(image, minimumChangedPixelRatio: 0.12, minimumMeanNormalizedDifference: 0.02)
        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "lighting-rig"),
            threshold: 0.01
        )
    }

    // TODO: Ideally have good small ref HDRI 
//    func testSkyboxIBLMatchesReference() throws {
//        let image = try VisualTestHarness.render(size: SIMD2(224, 192)) { renderer, camera in
//            let device = renderer.context.device
//            let cubeTexture = makeTestCubeTexture(device: device, size: 32)
//
//            let commandQueue = device.makeCommandQueue()!
//            let commandBuffer = commandQueue.makeCommandBuffer()!
//            let brdfTexture = BrdfGenerator(device: device, size: 128).encode(commandBuffer: commandBuffer)
//            commandBuffer.commit()
//            commandBuffer.waitUntilCompleted()
//
//            let skybox = Mesh(label: "Skybox", geometry: SkyboxGeometry(size: 40.0), material: SkyboxMaterial())
//            let sphere = Mesh(
//                label: "IBL Sphere",
//                geometry: IcoSphereGeometry(radius: 0.7, resolution: 2),
//                material: StandardMaterial(baseColor: simd_float4(0.92, 0.92, 0.95, 1.0), metallic: 1.0, roughness: 0.18, specular: 1.0)
//            )
//            sphere.position = [0.0, 0.0, 0.0]
//
//            let scene = IBLScene(label: "Scene", [skybox, sphere])
//            scene.environmentIntensity = 1.0
//            scene.cubemapTexture = cubeTexture
//            scene.reflectionTexture = cubeTexture
//            scene.irradianceTexture = cubeTexture
//            scene.brdfTexture = brdfTexture
//
//            camera.position = [0, 0, 4.3]
//            camera.lookAt(target: .zero)
//
//            return (scene: scene, camera: camera)
//        }
//
//        VisualTestHarness.assertContainsVisibleContent(image, minimumChangedPixelRatio: 0.9, minimumMeanNormalizedDifference: 0.08)
//        try VisualTestHarness.assertVisualMatch(
//            image,
//            reference: .bundle(name: "skybox-ibl"),
//            threshold: 0.01
//        )
//    }

    func testInstancingHierarchyMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(192, 192)) { _, camera in
            let scene = Object(label: "Scene")
            let container = Object(label: "Container")
            container.position = [0.2, -0.1, 0.0]
            container.scale = simd_float3(repeating: 1.15)
            container.orientation = simd_quatf(angle: .pi * 0.15, axis: simd_normalize(simd_float3(0.3, 1.0, 0.2)))

            let instanced = InstancedMesh(
                label: "Instanced Spheres",
                geometry: IcoSphereGeometry(radius: 0.18, resolution: 1),
                material: BasicDiffuseMaterial(color: simd_float4(0.92, 0.72, 0.24, 1.0), blending: .disabled, hardness: 0.6),
                count: 16
            )

            var matrices: [simd_float4x4] = []
            for row in 0..<4 {
                for column in 0..<4 {
                    let object = Object()
                    object.position = [
                        Float(column) * 0.48 - 0.72,
                        Float(row) * 0.48 - 0.72,
                        sin(Float(row + column) * 0.7) * 0.18
                    ]
                    object.scale = simd_float3(repeating: 0.9 + Float(row) * 0.06)
                    object.orientation = simd_quatf(
                        angle: Float(row * 4 + column) * 0.3,
                        axis: simd_normalize(simd_float3(0.35, 1.0, 0.4))
                    )
                    matrices.append(object.localMatrix)
                }
            }
            instanced.setInstanceMatrices(matrices)

            let light = DirectionalLight(color: simd_float3(repeating: 1.0), intensity: 1.8)
            light.position = [2.0, 2.0, 3.0]
            light.lookAt(target: .zero)

            container.add(instanced)
            scene.add(light)
            scene.add(container)

            camera.position = [0, 0, 4.8]
            camera.lookAt(target: [0.15, 0.0, 0.0])

            return (scene: scene, camera: camera)
        }

        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "instancing-hierarchy"),
            threshold: 0.008
        )
    }

    func testTessellatedTextGeometryMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(224, 160)) { _, camera in
            let light = DirectionalLight(color: simd_float3(repeating: 1.0), intensity: 1.6)
            light.position = [1.5, 2.0, 2.5]
            light.lookAt(target: .zero)

            let text = Mesh(
                label: "Text",
                geometry: TesselatedTextGeometry(text: "SATIN", fontName: "Helvetica", fontSize: 1.2, pivot: simd_float2(0.5, 0.5)),
                material: BasicDiffuseMaterial(color: simd_float4(0.95, 0.82, 0.3, 1.0), blending: .disabled, hardness: 0.7)
            )
            text.scale = [0.42, 0.42, 0.42]
            text.position = [0.0, -0.1, 0.0]

            camera.position = [0, 0, 4.5]
            camera.lookAt(target: .zero)

            return (scene: Object(label: "Scene", [light, text]), camera: camera)
        }

        VisualTestHarness.assertContainsVisibleContent(image, minimumChangedPixelRatio: 0.02, minimumMeanNormalizedDifference: 0.008)
        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "tessellated-text"),
            threshold: 0.01
        )
    }
    
    func testExtrudedTextGeometryMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(224, 160)) { _, camera in
            let light = DirectionalLight(color: simd_float3(repeating: 1.0), intensity: 1.6)
            light.position = [1.5, 2.0, 2.5]
            light.lookAt(target: .zero)

            let text = Mesh(
                label: "Text",
                geometry: ExtrudedTextGeometry(text: "SATIN", fontName: "Helvetica", fontSize: 1.2, pivot: simd_float2(0.5, 0.5)),
                material: BasicDiffuseMaterial(color: simd_float4(0.95, 0.82, 0.3, 1.0), blending: .disabled, hardness: 0.7)
            )
            text.scale = [0.42, 0.42, 0.42]
            text.orientation = simd_quatf(angle: degToRad(20), axis: simd_float3(1, 1, 0))
            text.position = [0.0, -0.1, 0.0]

            camera.position = [0, 0, 4.5]
            camera.lookAt(target: .zero)

            return (scene: Object(label: "Scene", [light, text]), camera: camera)
        }

        VisualTestHarness.assertContainsVisibleContent(image, minimumChangedPixelRatio: 0.02, minimumMeanNormalizedDifference: 0.008)
        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "extruded-text"),
            threshold: 0.01
        )
    }

    func testUVQuadMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(128, 128)) { _, camera in
            let mesh = Mesh(
                label: "Quad",
                geometry: QuadGeometry(size: 1.6),
                material: UVColorMaterial()
            )

            camera.position = [0, 0, 3]
            camera.lookAt(target: .zero)

            return (scene: Object(label: "Scene", [mesh]), camera: camera)
        }

        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "uv-quad"),
            threshold: 0.001
        )
    }

    func testLitSphereMatchesReference() throws {
        let image = try VisualTestHarness.render(size: SIMD2(128, 128)) { _, camera in
            let material = BasicDiffuseMaterial(color: simd_float4(0.95, 0.4, 0.15, 1.0), blending: .disabled, hardness: 0.75)
            let mesh = Mesh(
                label: "Sphere",
                geometry: IcoSphereGeometry(radius: 0.7, resolution: 2),
                material: material
            )
            mesh.orientation = simd_quatf(angle: .pi * 0.2, axis: simd_normalize(simd_float3(0.3, 1.0, 0.2)))

            let light = DirectionalLight(color: simd_float3(repeating: 1.0), intensity: 2.0)
            light.position = [1.5, 2.0, 3.0]
            light.lookAt(target: .zero)

            camera.position = [0, 0, 4]
            camera.lookAt(target: .zero)

            return (scene: Object(label: "Scene", [light, mesh]), camera: camera)
        }

        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: "lit-sphere"),
            threshold: 0.01
        )
    }
}

private func makeCheckerTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = .shaderRead
    descriptor.storageMode = .shared

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * bytesPerPixel
            let isLight = ((x / 8) + (y / 8)).isMultiple(of: 2)
            let value: UInt8 = isLight ? 235 : 45
            pixels[index + 0] = value
            pixels[index + 1] = isLight ? 160 : 90
            pixels[index + 2] = isLight ? 55 : 210
            pixels[index + 3] = 255
        }
    }

    let texture = device.makeTexture(descriptor: descriptor)!
    texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: pixels,
        bytesPerRow: bytesPerRow
    )
    return texture
}

private func makeTestCubeTexture(device: MTLDevice, size: Int) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: size, mipmapped: false)
    descriptor.usage = .shaderRead
    descriptor.storageMode = .shared

    let texture = device.makeTexture(descriptor: descriptor)!
    let faceColors: [[UInt16]] = [
        [0x3C00, 0x0000, 0x0000, 0x3C00], // +X red
        [0x0000, 0x3C00, 0x0000, 0x3C00], // -X green
        [0x0000, 0x0000, 0x3C00, 0x3C00], // +Y blue
        [0x3C00, 0x3C00, 0x0000, 0x3C00], // -Y yellow
        [0x0000, 0x3C00, 0x3C00, 0x3C00], // +Z cyan
        [0x3C00, 0x0000, 0x3C00, 0x3C00], // -Z magenta
    ]

    let pixelCount = size * size
    let bytesPerPixel = MemoryLayout<UInt16>.size * 4
    let bytesPerRow = size * bytesPerPixel
    let bytesPerImage = pixelCount * bytesPerPixel

    for (slice, color) in faceColors.enumerated() {
        var pixels = [UInt16](repeating: 0, count: pixelCount * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index + 0] = color[0]
            pixels[index + 1] = color[1]
            pixels[index + 2] = color[2]
            pixels[index + 3] = color[3]
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            slice: slice,
            withBytes: pixels,
            bytesPerRow: bytesPerRow,
            bytesPerImage: bytesPerImage
        )
    }

    return texture
}
