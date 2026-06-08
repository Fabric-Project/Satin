import Metal
import Satin
import XCTest

final class MaterialCoverageTests: XCTestCase {
    func testARCompositorMaterial() throws {
        let image = try renderMaterial(size: [176, 176]) { context, device, camera in
            camera.position = [0.0, 0.0, 3.0]
            camera.lookAt(target: .zero)

            let content = VisualFixtureSupport.makeCheckerTexture(device: device, width: 64, height: 64)
            let grain = VisualFixtureSupport.makeAlphaTexture(device: device, width: 64, height: 64)
            let depth = VisualFixtureSupport.makeSolidTexture(device: device)
            let background = VisualFixtureSupport.makeCheckerTexture(device: device, width: 32, height: 32)
            let alpha = VisualFixtureSupport.makeAlphaTexture(device: device, width: 32, height: 32)
            let dilated = VisualFixtureSupport.makeSolidTexture(device: device)
            VisualFixtureSupport.retain([content, grain, depth, background, alpha, dilated], for: "ARCompositorMaterial")

            let material = ARCompositorMaterial(context: context)
            material.contentTexture = content
            material.cameraGrainTexture = grain
            material.depthTexture = depth
            material.backgroundTexture = background
            material.alphaTexture = alpha
            material.dilatedDepthTexture = dilated

            let mesh = Mesh(context: context, label: "ARCompositor", geometry: QuadGeometry(context: context, size: 2.0), material: material)
            return makeMaterialScene(context: context, mesh, lit: false)
        }

        try assertMaterialImage(image, reference: "material-ar-compositor", threshold: 0.008, minimumChangedPixelRatio: 0.9, minimumMeanNormalizedDifference: 0.02)
    }

    func testARMatteMaterial() throws {
        let image = try renderMaterial(size: [176, 176]) { context, device, camera in
            camera.position = [0.0, 0.0, 3.0]
            camera.lookAt(target: .zero)

            let background = Mesh(
                context: context,
                label: "Background",
                geometry: QuadGeometry(context: context, size: 2.2),
                material: BasicColorMaterial(context: context, color: simd_float4(0.14, 0.16, 0.2, 1.0), blending: .disabled)
            )
            background.position.z = -0.1

            let material = ARMatteMaterial(context: context)
            material.alphaTexture = VisualFixtureSupport.makeAlphaTexture(device: device, width: 64, height: 64)
            material.dilatedDepthTexture = VisualFixtureSupport.makeCheckerTexture(device: device, width: 64, height: 64)

            let mesh = Mesh(context: context, label: "ARMatte", geometry: QuadGeometry(context: context, size: 2.0), material: material)
            return makeMaterialScene(context: context, background, extras: [mesh], lit: false)
        }

        try assertMaterialImage(image, reference: "material-ar-matte", threshold: 0.008, minimumChangedPixelRatio: 0.9, minimumMeanNormalizedDifference: 0.02)
    }

    func testARPostMaterial() throws {
        let image = try renderMaterial(size: [176, 176]) { context, device, camera in
            camera.position = [0.0, 0.0, 3.0]
            camera.lookAt(target: .zero)

            let content = VisualFixtureSupport.makeCheckerTexture(device: device, width: 64, height: 64)
            let grain = VisualFixtureSupport.makeAlphaTexture(device: device, width: 64, height: 64)
            VisualFixtureSupport.retain([content, grain], for: "ARPostMaterial")

            let material = ARPostMaterial(context: context)
            material.contentTexture = content
            material.cameraGrainTexture = grain

            let mesh = Mesh(context: context, label: "ARPost", geometry: QuadGeometry(context: context, size: 2.0), material: material)
            return makeMaterialScene(context: context, mesh, lit: false)
        }

        try assertMaterialImage(image, reference: "material-ar-post", threshold: 0.008, minimumChangedPixelRatio: 0.9, minimumMeanNormalizedDifference: 0.02)
    }

    func testBasicColorMaterial() throws {
        try assertSphereMaterial(
            reference: "material-basic-color",
            material: { context, _ in BasicColorMaterial(context: context, color: simd_float4(0.92, 0.24, 0.18, 1.0), blending: .disabled) }
        )
    }

    func testBasicDiffuseMaterial() throws {
        try assertSphereMaterial(
            reference: "material-basic-diffuse",
            lit: true,
            material: { context, _ in BasicDiffuseMaterial(context: context, color: simd_float4(0.92, 0.72, 0.24, 1.0), blending: .disabled, hardness: 0.72) }
        )
    }

    func testBasicPointMaterial() throws {
        let image = try renderMaterial(size: [176, 176]) { context, _, camera in
            camera.position = [0.0, 0.0, 3.2]
            camera.lookAt(target: .zero)

            let mesh = Mesh(
                context: context,
                label: "Points",
                geometry: PointGeometry(context: context, data: [
                    [-0.75, 0.7, 0.0],
                    [-0.3, 0.25, 0.0],
                    [0.1, 0.0, 0.0],
                    [0.55, -0.35, 0.0],
                    [0.8, -0.7, 0.0],
                ]),
                material: BasicPointMaterial(context: context, color: simd_float4(1.0, 0.85, 0.25, 1.0), size: 22.0, blending: .disabled)
            )

            return makeMaterialScene(context: context, mesh, lit: false)
        }

        try assertMaterialImage(image, reference: "material-basic-point", threshold: 0.012, minimumChangedPixelRatio: 0.02, minimumMeanNormalizedDifference: 0.004)
    }

    func testBasicTextureMaterial() throws {
        try assertSphereMaterial(
            reference: "material-basic-texture",
            lit: true,
            material: { context, device in BasicTextureMaterial(context: context, texture: VisualFixtureSupport.makeCheckerTexture(device: device)) }
        )
    }

    func testDepthMaterial() throws {
        let image = try renderMaterial(size: [176, 176]) { context, _, camera in
            camera.position = [0.0, 0.0, 5.0]
            camera.lookAt(target: .zero)

            let scene = Object(context: context, label: "Scene")

            let front = Mesh(
                context: context,
                label: "Front",
                geometry: SphereGeometry(context: context, radius: 0.55, angularResolution: 28, verticalResolution: 16),
                material: DepthMaterial(context: context, color: true, invert: false)
            )
            front.position = [-0.55, 0.0, 0.35]

            let back = Mesh(
                context: context,
                label: "Back",
                geometry: SphereGeometry(context: context, radius: 0.55, angularResolution: 28, verticalResolution: 16),
                material: DepthMaterial(context: context, color: true, invert: false)
            )
            back.position = [0.55, 0.0, -0.35]

            scene.add(front)
            scene.add(back)
            return scene
        }

        try assertMaterialImage(image, reference: "material-depth", threshold: 0.008, minimumChangedPixelRatio: 0.08, minimumMeanNormalizedDifference: 0.01)
    }

    func testMatCapMaterial() throws {
        try assertSphereMaterial(
            reference: "material-matcap",
            material: { context, device in MatCapMaterial(context: context, texture: VisualFixtureSupport.makeCheckerTexture(device: device)) }
        )
    }

    func testNormalColorMaterial() throws {
        try assertSphereMaterial(reference: "material-normal-color", material: { context, _ in NormalColorMaterial(context: context) })
    }

    func testPhysicalMaterial() throws {
        let image = try renderMaterial(size: [224, 176]) { context, _, camera in
            camera.position = [0.0, 0.3, 6.4]
            camera.lookAt(target: [0.0, -0.05, 0.0])

            let left = Mesh(
                context: context,
                label: "Clearcoat",
                geometry: SphereGeometry(context: context, radius: 0.58, angularResolution: 36, verticalResolution: 18),
                material: PhysicalMaterial(
                    context: context,
                    baseColor: simd_float4(0.9, 0.24, 0.16, 1.0),
                    metallic: 0.0,
                    roughness: 0.42,
                    specular: 0.65,
                    clearcoat: 1.0,
                    clearcoatRoughness: 0.08
                )
            )
            left.position = [-1.3, 0.0, 0.0]

            let center = Mesh(
                context: context,
                label: "Anisotropic",
                geometry: SphereGeometry(context: context, radius: 0.58, angularResolution: 36, verticalResolution: 18),
                material: PhysicalMaterial(
                    context: context,
                    baseColor: simd_float4(0.94, 0.92, 0.9, 1.0),
                    metallic: 1.0,
                    roughness: 0.22,
                    specular: 1.0,
                    anisotropic: 0.85,
                    anisotropicAngle: 0.7
                )
            )
            center.position = [0.0, 0.0, 0.0]

            let right = Mesh(
                context: context,
                label: "Sheen",
                geometry: SphereGeometry(context: context, radius: 0.58, angularResolution: 36, verticalResolution: 18),
                material: PhysicalMaterial(
                    context: context,
                    baseColor: simd_float4(0.2, 0.42, 0.95, 1.0),
                    metallic: 0.0,
                    roughness: 0.65,
                    specular: 0.5,
                    sheen: 0.9,
                    sheenTint: 0.8
                )
            )
            right.position = [1.3, 0.0, 0.0]

            return makeMaterialScene(context: context, left, extras: [center, right], lit: true, includeGround: true)
        }

        try assertMaterialImage(image, reference: "material-physical", threshold: 0.01, minimumChangedPixelRatio: 0.14, minimumMeanNormalizedDifference: 0.01)
        assertPBRSpheresVisible(image)
    }

    // Shadw Material removed from 2.0 
//    func testShadowMaterial() throws {
//        let image = try renderMaterial(size: [224, 176]) { context, _, camera in
//            camera.position = [0.0, 0.55, 4.8]
//            camera.lookAt(target: [0.0, -0.25, 0.0])
//
//            let scene = Object(context: context, label: "Scene")
//
//            let light = DirectionalLight(context: context, color: simd_float3(1.0, 0.98, 0.95), intensity: 1.6)
//            light.position = [2.2, 3.0, 2.6]
//            light.lookAt(target: .zero)
//            light.castShadow = true
//            light.shadow.resolution = (width: 1024, height: 1024)
//            light.shadow.bias = 0.0005
//            light.shadow.strength = 0.7
//            if let shadowCamera = light.shadow.camera as? OrthographicCamera {
//                shadowCamera.update(left: -3.0, right: 3.0, bottom: -3.0, top: 3.0)
//            }
//
//            let caster = Mesh(
//                context: context,
//                label: "Caster",
//                geometry: SphereGeometry(context: context, radius: 0.52, angularResolution: 36, verticalResolution: 18),
//                material: BasicDiffuseMaterial(context: context, color: simd_float4(0.92, 0.74, 0.24, 1.0), blending: .disabled, hardness: 0.7)
//            )
//            caster.position = [0.0, -0.1, 0.0]
//            caster.castShadow = true
//            caster.receiveShadow = true
//
//            let receiver = Mesh(
//                context: context,
//                label: "Receiver",
//                geometry: PlaneGeometry(context: context, size: 5.0, orientation: .zx),
//                material: BasicDiffuseMaterial(context: context, color: simd_float4(0.0, 0.0, 0.0, 0.38), blending: .alpha, hardness: 0.0)
//            )
//            receiver.position.y = -0.9
//            receiver.receiveShadow = true
//
//            let base = Mesh(
//                context: context,
//                label: "Base",
//                geometry: PlaneGeometry(context: context, size: 5.0, orientation: .zx),
//                material: BasicColorMaterial(context: context, color: simd_float4(0.82, 0.84, 0.88, 1.0), blending: .disabled)
//            )
//            base.position.y = -0.9
//
//            scene.add(light)
//            scene.add(base)
//            scene.add(caster)
//            scene.add(receiver)
//            return scene
//        }
//
//        try assertMaterialImage(image, reference: "material-shadow", threshold: 0.01, minimumChangedPixelRatio: 0.12, minimumMeanNormalizedDifference: 0.015)
//    }

    func testSkyboxMaterial() throws {
        let image = try renderMaterial(size: [176, 176]) { context, device, camera in
            camera.position = .zero
            camera.lookAt(target: [0.0, 0.0, -1.0])

            let mesh = Mesh(
                context: context,
                label: "Skybox",
                geometry: SkyboxGeometry(context: context, size: 40.0),
                material: SkyboxMaterial(context: context, texture: VisualFixtureSupport.makeCubeTexture(device: device, size: 16))
            )
            return makeMaterialScene(context: context, mesh, lit: false)
        }

        try assertMaterialImage(image, reference: "material-skybox", threshold: 0.008, minimumChangedPixelRatio: 0.95, minimumMeanNormalizedDifference: 0.015)
    }

    func testSourceMaterial() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal unavailable")
            return
        }

        let context = VisualTestHarness.makeContext(device: device)
        let material = SourceMaterial(context: context, pipelineURL: getPipelinesMaterialsURL("BasicColor")!.appendingPathComponent("Shaders.metal"))
        material.label = "BasicColor"
        material.blending = Blending.disabled
        material.set("Color", simd_float4(0.26, 0.82, 0.95, 1.0))
        material.update()

        XCTAssertNotNil(material.shader)
        XCTAssertTrue(material.shader is SourceShader)
        XCTAssertNotNil((material.shader as? SourceShader)?.source)
    }

    func testStandardMaterial() throws {
        let image = try renderMaterial(size: [224, 176]) { context, _, camera in
            camera.position = [0.0, 0.3, 6.4]
            camera.lookAt(target: [0.0, -0.05, 0.0])

            let left = Mesh(
                context: context,
                label: "Matte",
                geometry: SphereGeometry(context: context, radius: 0.58, angularResolution: 36, verticalResolution: 18),
                material: StandardMaterial(context: context, baseColor: simd_float4(0.92, 0.36, 0.22, 1.0), metallic: 0.0, roughness: 0.82, specular: 0.4)
            )
            left.position = [-1.3, 0.0, 0.0]

            let center = Mesh(
                context: context,
                label: "Metal",
                geometry: SphereGeometry(context: context, radius: 0.58, angularResolution: 36, verticalResolution: 18),
                material: StandardMaterial(context: context, baseColor: simd_float4(0.94, 0.93, 0.92, 1.0), metallic: 1.0, roughness: 0.18, specular: 1.0)
            )
            center.position = [0.0, 0.0, 0.0]

            let right = Mesh(
                context: context,
                label: "Coated",
                geometry: SphereGeometry(context: context, radius: 0.58, angularResolution: 36, verticalResolution: 18),
                material: StandardMaterial(context: context, baseColor: simd_float4(0.18, 0.55, 0.95, 1.0), metallic: 0.35, roughness: 0.42, specular: 0.9)
            )
            right.position = [1.3, 0.0, 0.0]

            return makeMaterialScene(context: context, left, extras: [center, right], lit: true, includeGround: true)
        }

        try assertMaterialImage(image, reference: "material-standard", threshold: 0.01, minimumChangedPixelRatio: 0.14, minimumMeanNormalizedDifference: 0.01)
        assertPBRSpheresVisible(image)
    }

    func testTextMaterial() throws {
        let image = try renderMaterial(size: [192, 144]) { context, device, camera in
            camera.position = [0.0, 0.0, 35.0]
            camera.lookAt(target: .zero)

            let background = Mesh(
                context: context,
                label: "Background",
                geometry: QuadGeometry(context: context, size: 5.5),
                material: BasicColorMaterial(context: context, color: simd_float4(0.14, 0.16, 0.2, 1.0), blending: .disabled)
            )
            background.position = [0.0, 0.0, -0.2]

            let mesh = Mesh(
                context: context,
                label: "Text",
                geometry: TextGeometry(context: context, text: "S", font: VisualFixtureSupport.makeFontAtlas()),
                material: TextMaterial(context: context, color: simd_float4(1.0, 1.0, 1.0, 1.0), fontTexture: VisualFixtureSupport.makeFontTexture(device: device))
            )
            mesh.scale = [0.2, 0.2, 0.2]
            mesh.cullMode = .none

            return makeMaterialScene(context: context, background, extras: [mesh], lit: false)
        }

        try assertMaterialImage(image, reference: "material-text", threshold: 0.008, minimumChangedPixelRatio: 0.03, minimumMeanNormalizedDifference: 0.004)
    }

    func testUVColorMaterial() throws {
        try assertSphereMaterial(reference: "material-uv-color", material: { context, _ in UVColorMaterial(context: context) })
    }
}

private func assertSphereMaterial(
    reference: String,
    lit: Bool = false,
    material: @escaping (Context, MTLDevice) -> Material,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let image = try renderMaterial(size: [176, 176]) { context, device, camera in
        camera.position = [0.0, 0.0, 4.5]
        camera.lookAt(target: .zero)

        let mesh = Mesh(
            context: context,
            label: reference,
            geometry: SphereGeometry(context: context, radius: 0.72, angularResolution: 36, verticalResolution: 18),
            material: material(context, device)
        )

        return makeMaterialScene(context: context, mesh, lit: lit)
    }

    try assertMaterialImage(
        image,
        reference: reference,
        threshold: 0.006,
        minimumChangedPixelRatio: 0.09,
        minimumMeanNormalizedDifference: lit ? 0.02 : 0.012,
        file: file,
        line: line
    )
}

private func renderMaterial(
    size: SIMD2<Int>,
    buildScene: (Context, MTLDevice, Camera) -> Object
) throws -> RGBAImage {
    try VisualTestHarness.render(size: size) { renderer, camera in
        let scene = buildScene(renderer.context, renderer.context.device, camera)
        return (scene: scene, camera: camera)
    }
}

private func assertMaterialImage(
    _ image: RGBAImage,
    reference: String,
    threshold: Double,
    minimumChangedPixelRatio: Double,
    minimumMeanNormalizedDifference: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    VisualTestHarness.assertContainsVisibleContent(
        image,
        minimumChangedPixelRatio: minimumChangedPixelRatio,
        minimumMeanNormalizedDifference: minimumMeanNormalizedDifference,
        file: file,
        line: line
    )

    try VisualTestHarness.assertVisualMatch(
        image,
        reference: .bundle(name: reference),
        threshold: threshold,
        file: file,
        line: line
    )
}

private func assertPBRSpheresVisible(_ image: RGBAImage, file: StaticString = #filePath, line: UInt = #line) {
    for region in [
        ImageRegion(name: "left sphere", normalizedRect: CGRect(x: 0.08, y: 0.22, width: 0.24, height: 0.38)),
        ImageRegion(name: "center sphere", normalizedRect: CGRect(x: 0.38, y: 0.22, width: 0.24, height: 0.38)),
        ImageRegion(name: "right sphere", normalizedRect: CGRect(x: 0.68, y: 0.22, width: 0.24, height: 0.38)),
    ] {
        VisualTestHarness.assertContainsVisibleContent(
            image,
            in: region,
            minimumChangedPixelRatio: 0.08,
            minimumMeanNormalizedDifference: 0.01,
            file: file,
            line: line
        )
    }
}

private func makeMaterialScene(context: Context, _ primary: Object, extras: [Object] = [], lit: Bool, includeGround: Bool = false) -> Object {
    let scene = Object(context: context, label: "Scene")

    if lit {
        let directional = DirectionalLight(context: context, color: simd_float3(1.0, 0.97, 0.92), intensity: 1.7)
        directional.position = [1.8, 2.2, 2.9]
        directional.lookAt(target: simd_float3.zero)

        let point = PointLight(context: context, color: simd_float3(0.2, 0.45, 0.95), intensity: 1.0, radius: 10.0)
        point.position = [-1.5, 1.0, 2.6]

        scene.add(directional)
        scene.add(point)

        if includeGround {
            let ground = Mesh(
                context: context,
                label: "Ground",
                geometry: PlaneGeometry(context: context, size: 6.0),
                material: BasicDiffuseMaterial(context: context, color: simd_float4(0.16, 0.18, 0.22, 1.0), blending: .disabled, hardness: 0.2)
            )
            ground.position = [0.0, -0.82, 0.0]
            ground.orientation = simd_quatf(angle: -.pi * 0.5, axis: simd_float3(1.0, 0.0, 0.0))
            scene.add(ground)
        }
    }

    extras.forEach { scene.add($0) }
    scene.add(primary)
    return scene
}
