import Metal
import Satin
import XCTest

final class GeometryCoverageTests: XCTestCase {
    func testArcGeometry() throws {
        try assertFlatGeometry(
            reference: "geometry-arc",
            geometry: { context in ArcGeometry(context: context, radius: (inner: 0.35, outer: 0.8), angle: (start: 0.0, end: .pi * 1.55), res: (angular: 32, radial: 6)) },
            scale: [1.15, 1.15, 1.0]
        )
    }

    func testBoxGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-box",
            geometry: { context in BoxGeometry(context: context, width: 0.9, height: 0.8, depth: 0.7, widthResolution: 2, heightResolution: 2, depthResolution: 2) },
            orientation: simd_quatf(angle: .pi * 0.2, axis: simd_normalize(simd_float3(0.3, 1.0, 0.1)))
        )
    }

    func testCapsuleGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-capsule",
            geometry: { context in CapsuleGeometry(context: context, radius: 0.28, height: 0.85, angularResolution: 32, radialResolution: 16, verticalResolution: 4) },
            orientation: simd_quatf(angle: .pi * 0.12, axis: simd_normalize(simd_float3(1.0, 0.0, 0.2)))
        )
    }

    func testCircleGeometry() throws {
        try assertFlatGeometry(
            reference: "geometry-circle",
            geometry: { context in CircleGeometry(context: context, radius: 0.8, angularResolution: 32, radialResolution: 6) },
            scale: [1.1, 1.1, 1.0]
        )
    }

    func testConeGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-cone",
            geometry: { context in ConeGeometry(context: context, radius: 0.45, height: 0.95, angularResolution: 32, radialResolution: 3, verticalResolution: 3) }
        )
    }

    func testCylinderGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-cylinder",
            geometry: { context in CylinderGeometry(context: context, radius: 0.38, height: 0.9, angularResolution: 32, radialResolution: 3, verticalResolution: 3) },
            orientation: simd_quatf(angle: .pi * 0.1, axis: simd_normalize(simd_float3(0.4, 1.0, 0.0)))
        )
    }

    func testExtrudedRoundedRectGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-extruded-rounded-rect",
            geometry: { context in ExtrudedRoundedRectGeometry(context: context, width: 0.95, height: 0.7, depth: 0.22, radius: 0.14, angularResolution: 32, radialResolution: 6, depthResolution: 3) },
            orientation: simd_quatf(angle: .pi * 0.16, axis: simd_normalize(simd_float3(1.0, 0.3, 0.1)))
        )
    }

    func testExtrudedTextGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-extruded-text",
            geometry: { context in ExtrudedTextGeometry(context: context, text: "S", fontName: "Helvetica", fontSize: 1.0, distance: 0.22) },
            scale: [1.2, 1.2, 1.2],
            orientation: simd_quatf(angle: .pi * 0.08, axis: simd_normalize(simd_float3(0.2, 1.0, 0.1))),
            cameraPosition: [0.0, 0.0, 3.2]
        )
    }

    func testIcoSphereGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-icosphere",
            geometry: { context in IcoSphereGeometry(context: context, radius: 0.62, resolution: 2) }
        )
    }

    func testLineGeometry() throws {
        let image = try renderGeometry(size: [160, 160]) { context, _, camera in
            camera.position = [0.0, 0.0, 3.0]
            camera.lookAt(target: .zero)

            let material = BasicColorMaterial(context: context, color: simd_float4(0.2, 0.85, 1.0, 1.0), blending: .disabled)
            let scene = Object(context: context, label: "Scene")

            let line0 = Mesh(context: context, label: "Line 0", geometry: LineGeometry(context: context), material: material.clone())
            line0.scale = [0.72, 0.06, 1.0]
            line0.position = [-0.55, 0.45, 0.0]
            line0.orientation = simd_quatf(angle: .pi * 0.22, axis: simd_float3(0.0, 0.0, 1.0))

            let line1 = Mesh(context: context, label: "Line 1", geometry: LineGeometry(context: context), material: material.clone())
            line1.scale = [0.92, 0.08, 1.0]
            line1.position = [0.15, -0.05, 0.0]
            line1.orientation = simd_quatf(angle: -.pi * 0.12, axis: simd_float3(0.0, 0.0, 1.0))

            let line2 = Mesh(context: context, label: "Line 2", geometry: LineGeometry(context: context), material: material.clone())
            line2.scale = [0.56, 0.05, 1.0]
            line2.position = [0.62, -0.52, 0.0]
            line2.orientation = simd_quatf(angle: .pi * 0.34, axis: simd_float3(0.0, 0.0, 1.0))

            scene.add(line0)
            scene.add(line1)
            scene.add(line2)
            return scene
        }

        assertGeometryImage(image, reference: "geometry-line", threshold: 0.01, minimumChangedPixelRatio: 0.02, minimumMeanNormalizedDifference: 0.004)
    }

    func testOctaSphereGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-octasphere",
            geometry: { context in OctaSphereGeometry(context: context, radius: 0.62, resolution: 3) }
        )
    }

    func testParametricGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-parametric",
            geometry: { context in
                ParametricGeometry(context: context, rangeU: 0.0 ... 1.0, rangeV: 0.0 ... 1.0, resolution: simd_int2(24, 18)) { u, v in
                    simd_float3(
                        (u - 0.5) * 1.35,
                        (v - 0.5) * 1.15,
                        sin(u * .pi * 2.0) * cos(v * .pi * 2.0) * 0.2
                    )
                }
            },
            orientation: simd_quatf(angle: -.pi * 0.1, axis: simd_normalize(simd_float3(1.0, 0.2, 0.0)))
        )
    }

    func testPlaneGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-plane",
            geometry: { context in PlaneGeometry(context: context, width: 1.25, height: 0.9, widthResolution: 3, heightResolution: 2) },
            orientation: simd_quatf(angle: -.pi * 0.22, axis: simd_normalize(simd_float3(1.0, 0.0, 0.0))),
            cameraPosition: [0.0, 0.7, 4.2],
            lookAt: [0.0, -0.1, 0.0]
        )
    }

    func testPointGeometry() throws {
        let image = try renderGeometry(size: [160, 160]) { context, _, camera in
            camera.position = [0.0, 0.0, 3.5]
            camera.lookAt(target: .zero)

            let points: [simd_float3] = [
                [-0.85, 0.65, 0.0],
                [-0.25, 0.25, 0.1],
                [0.25, -0.15, 0.0],
                [0.75, -0.6, -0.1],
                [0.55, 0.7, 0.0],
            ]

            let mesh = Mesh(
                context: context,
                label: "Points",
                geometry: PointGeometry(context: context, data: points),
                material: BasicPointMaterial(context: context, color: simd_float4(1.0, 0.85, 0.2, 1.0), size: 18.0, blending: .disabled)
            )
            return makeScene(context: context, mesh)
        }

        assertGeometryImage(image, reference: "geometry-point", threshold: 0.012, minimumChangedPixelRatio: 0.01, minimumMeanNormalizedDifference: 0.003)
    }

    func testQuadGeometry() throws {
        try assertFlatGeometry(reference: "geometry-quad", geometry: { context in QuadGeometry(context: context, size: 1.35) })
    }

    func testRoundedBoxGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-rounded-box",
            geometry: { context in RoundedBoxGeometry(context: context, size: simd_float3(0.82, 0.72, 0.65), radius: 0.14, resolution: 3) },
            orientation: simd_quatf(angle: .pi * 0.18, axis: simd_normalize(simd_float3(0.25, 1.0, 0.18)))
        )
    }

    func testRoundedRectGeometry() throws {
        try assertFlatGeometry(
            reference: "geometry-rounded-rect",
            geometry: { context in RoundedRectGeometry(context: context, width: 0.95, height: 0.72, radius: 0.15, angularResolution: 32, radialResolution: 6) },
            scale: [1.1, 1.1, 1.0]
        )
    }

    func testSatinGeometry() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let geometry = SatinGeometry(context: VisualTestHarness.makeContext(device: device))
        XCTAssertEqual(geometry.vertexCount, 0)
        XCTAssertNil(geometry.elementBuffer)
    }

    func testSkyboxGeometry() throws {
        let image = try renderGeometry(size: [176, 176]) { context, device, camera in
            camera.position = .zero
            camera.lookAt(target: [0.0, 0.0, -1.0])

            let mesh = Mesh(
                context: context,
                label: "Skybox",
                geometry: SkyboxGeometry(context: context, size: 40.0),
                material: SkyboxMaterial(context: context, texture: VisualFixtureSupport.makeCubeTexture(device: device, size: 16))
            )
            return makeScene(context: context, mesh)
        }

        assertGeometryImage(image, reference: "geometry-skybox", threshold: 0.008, minimumChangedPixelRatio: 0.95, minimumMeanNormalizedDifference: 0.08)
    }

    func testSphereGeometry() throws {
        try assertLitGeometry(reference: "geometry-sphere", geometry: { context in SphereGeometry(context: context, radius: 0.62, angularResolution: 32, verticalResolution: 18) })
    }

    func testSquircleGeometry() throws {
        try assertFlatGeometry(
            reference: "geometry-squircle",
            geometry: { context in SquircleGeometry(context: context, size: 1.35, radius: 0.34, angularResolution: 32, radialResolution: 8) },
            scale: [1.35, 1.35, 1.0],
            minimumChangedPixelRatio: 0.05
        )
    }

    func testTesselatedTextGeometry() throws {
        let image = try renderGeometry(size: [176, 176]) { context, _, camera in
            camera.position = [0.0, 0.0, 2.6]
            camera.lookAt(target: .zero)

            let mesh = Mesh(
                context: context,
                label: "TesselatedText",
                geometry: TesselatedTextGeometry(context: context, text: "S", fontName: "Helvetica", fontSize: 1.0, pivot: simd_float2(0.5, 0.5)),
                material: BasicDiffuseMaterial(context: context, color: simd_float4(0.95, 0.82, 0.3, 1.0), blending: .disabled, hardness: 0.75)
            )
            mesh.scale = [1.2, 1.2, 1.2]
            mesh.cullMode = .none

            let light = DirectionalLight(context: context, color: simd_float3(1.0, 0.97, 0.92), intensity: 1.9)
            light.position = [1.9, 2.4, 3.1]
            light.lookAt(target: .zero)

            return makeScene(context: context, mesh, extras: [light])
        }

        assertGeometryImage(image, reference: "geometry-tesselated-text", threshold: 0.008, minimumChangedPixelRatio: 0.03, minimumMeanNormalizedDifference: 0.004)
    }

    func testTessellationGeometry() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let context = VisualTestHarness.makeContext(device: device)
        let geometry = TessellationGeometry(baseGeometry: QuadGeometry(context: context, size: 1.0))
        XCTAssertEqual(geometry.patchCount, 2)
        XCTAssertEqual(geometry.controlPointsPerPatch, 3)
        XCTAssertNotNil(geometry.tessellationDescriptor)
        XCTAssertEqual(geometry.controlPointIndexType, MTLTessellationControlPointIndexType.uint32)
    }

    func testTextGeometry() throws {
        let fontAtlas = VisualFixtureSupport.makeFontAtlas()
        let image = try renderGeometry(size: [176, 144]) { context, _, camera in
            camera.position = [0.0, 0.0, 35.0]
            camera.lookAt(target: .zero)

            let mesh = Mesh(
                context: context,
                label: "Text",
                geometry: TextGeometry(context: context, text: "S", font: fontAtlas),
                material: BasicColorMaterial(context: context, color: simd_float4(0.96, 0.84, 0.3, 1.0), blending: .disabled)
            )
            mesh.scale = [0.2, 0.2, 0.2]

            return makeScene(context: context, mesh)
        }

        assertGeometryImage(image, reference: "geometry-text", threshold: 0.006, minimumChangedPixelRatio: 0.02, minimumMeanNormalizedDifference: 0.004)
    }

    func testTorusGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-torus",
            geometry: { context in TorusGeometry(context: context, minorRadius: 0.16, majorRadius: 0.38, minorResolution: 20, majorResolution: 32) },
            orientation: simd_quatf(angle: .pi * 0.3, axis: simd_normalize(simd_float3(1.0, 0.3, 0.0)))
        )
    }

    func testTriangleGeometry() throws {
        try assertFlatGeometry(reference: "geometry-triangle", geometry: { context in TriangleGeometry(context: context, size: 1.35) })
    }

    func testTubeGeometry() throws {
        try assertLitGeometry(
            reference: "geometry-tube",
            geometry: { context in TubeGeometry(context: context, radius: 0.42, height: 0.92, startAngle: 0.0, endAngle: .pi * 1.55, angularResolution: 32, verticalResolution: 4) },
            orientation: simd_quatf(angle: .pi * 0.1, axis: simd_normalize(simd_float3(0.9, 0.2, 0.0)))
        )
    }

    func testUVDiskGeometry() throws {
        try assertFlatGeometry(
            reference: "geometry-uv-disk",
            geometry: { context in UVDiskGeometry(context: context, innerRadius: 0.35, outerRadius: 0.85) },
            scale: [1.1, 1.1, 1.0]
        )
    }
}

private func assertFlatGeometry(
    reference: String,
    geometry: @escaping (Context) -> Geometry,
    scale: simd_float3 = .one,
    orientation: simd_quatf = simd_quatf(angle: 0.0, axis: simd_float3(0.0, 1.0, 0.0)),
    cameraPosition: simd_float3 = [0.0, 0.0, 4.0],
    lookAt: simd_float3 = .zero,
    minimumChangedPixelRatio: Double = 0.08,
    minimumMeanNormalizedDifference: Double = 0.015,
    threshold: Double = 0.006,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let image = try renderGeometry(size: [160, 160]) { context, _, camera in
        camera.position = cameraPosition
        camera.lookAt(target: lookAt)

        let mesh = Mesh(
            context: context,
            label: reference,
            geometry: geometry(context),
            material: BasicColorMaterial(context: context, color: simd_float4(0.92, 0.78, 0.24, 1.0), blending: .disabled)
        )
        mesh.scale = scale
        mesh.orientation = orientation
        return makeScene(context: context, mesh)
    }

    assertGeometryImage(image, reference: reference, threshold: threshold, minimumChangedPixelRatio: minimumChangedPixelRatio, minimumMeanNormalizedDifference: minimumMeanNormalizedDifference, file: file, line: line)
}

private func assertLitGeometry(
    reference: String,
    geometry: @escaping (Context) -> Geometry,
    scale: simd_float3 = .one,
    orientation: simd_quatf = simd_quatf(angle: 0.0, axis: simd_float3(0.0, 1.0, 0.0)),
    cameraPosition: simd_float3 = [0.0, 0.0, 4.35],
    lookAt: simd_float3 = .zero,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let image = try renderGeometry(size: [176, 176]) { context, _, camera in
        camera.position = cameraPosition
        camera.lookAt(target: lookAt)

        let mesh = Mesh(
            context: context,
            label: reference,
            geometry: geometry(context),
            material: BasicDiffuseMaterial(context: context, color: simd_float4(0.92, 0.76, 0.25, 1.0), blending: .disabled, hardness: 0.7)
        )
        mesh.scale = scale
        mesh.orientation = orientation

        let light = DirectionalLight(context: context, color: simd_float3(1.0, 0.97, 0.92), intensity: 1.9)
        light.position = [1.9, 2.4, 3.1]
        light.lookAt(target: lookAt)

        let fill = PointLight(context: context, color: simd_float3(0.25, 0.5, 0.95), intensity: 0.8, radius: 10.0)
        fill.position = [-1.6, 1.0, 2.4]

        return makeScene(context: context, mesh, extras: [light, fill])
    }

    assertGeometryImage(image, reference: reference, threshold: 0.008, minimumChangedPixelRatio: 0.08, minimumMeanNormalizedDifference: 0.018, file: file, line: line)
}

private func renderGeometry(
    size: SIMD2<Int>,
    buildScene: (Context, MTLDevice, Camera) -> Object
) throws -> RGBAImage {
    try VisualTestHarness.render(size: size) { renderer, camera in
        let scene = buildScene(renderer.context, renderer.context.device, camera)
        return (scene: scene, camera: camera)
    }
}

private func assertGeometryImage(
    _ image: RGBAImage,
    reference: String,
    threshold: Double,
    minimumChangedPixelRatio: Double,
    minimumMeanNormalizedDifference: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    VisualTestHarness.assertContainsVisibleContent(
        image,
        minimumChangedPixelRatio: minimumChangedPixelRatio,
        minimumMeanNormalizedDifference: minimumMeanNormalizedDifference,
        file: file,
        line: line
    )

    try! VisualTestHarness.assertVisualMatch(
        image,
        reference: .bundle(name: reference),
        threshold: threshold,
        file: file,
        line: line
    )
}

private func makeScene(context: Context, _ primary: Object, extras: [Object] = []) -> Object {
    let scene = Object(context: context, label: "Scene")
    extras.forEach { scene.add($0) }
    scene.add(primary)
    return scene
}
