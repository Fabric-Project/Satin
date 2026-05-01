import Metal
import Satin
import XCTest

final class GeometryCoverageTests: XCTestCase {
    func testGeometryFixturesMatchSourceSurfaceArea() {
        XCTAssertEqual(Set(makeGeometryFixtures().keys), expectedGeometryNames)
    }

    func testArcGeometry() throws { try assertGeometryFixture("ArcGeometry") }
    func testBoxGeometry() throws { try assertGeometryFixture("BoxGeometry") }
    func testCapsuleGeometry() throws { try assertGeometryFixture("CapsuleGeometry") }
    func testCircleGeometry() throws { try assertGeometryFixture("CircleGeometry") }
    func testConeGeometry() throws { try assertGeometryFixture("ConeGeometry") }
    func testCylinderGeometry() throws { try assertGeometryFixture("CylinderGeometry") }
    func testExtrudedRoundedRectGeometry() throws { try assertGeometryFixture("ExtrudedRoundedRectGeometry") }
    func testExtrudedTextGeometry() throws { try assertGeometryFixture("ExtrudedTextGeometry") }
    func testIcoSphereGeometry() throws { try assertGeometryFixture("IcoSphereGeometry") }
    func testLineGeometry() throws { try assertGeometryFixture("LineGeometry") }
    func testOctaSphereGeometry() throws { try assertGeometryFixture("OctaSphereGeometry") }
    func testParametricGeometry() throws { try assertGeometryFixture("ParametricGeometry") }
    func testPlaneGeometry() throws { try assertGeometryFixture("PlaneGeometry") }
    func testPointGeometry() throws { try assertGeometryFixture("PointGeometry") }
    func testQuadGeometry() throws { try assertGeometryFixture("QuadGeometry") }
    func testRoundedBoxGeometry() throws { try assertGeometryFixture("RoundedBoxGeometry") }
    func testRoundedRectGeometry() throws { try assertGeometryFixture("RoundedRectGeometry") }
    func testSatinGeometry() throws { try assertGeometryFixture("SatinGeometry") }
    func testSkyboxGeometry() throws { try assertGeometryFixture("SkyboxGeometry") }
    func testSphereGeometry() throws { try assertGeometryFixture("SphereGeometry") }
    func testSquircleGeometry() throws { try assertGeometryFixture("SquircleGeometry") }
    func testTesselatedTextGeometry() throws { try assertGeometryFixture("TesselatedTextGeometry") }
    func testTessellationGeometry() throws { try assertGeometryFixture("TessellationGeometry") }
    func testTextGeometry() throws { try assertGeometryFixture("TextGeometry") }
    func testTorusGeometry() throws { try assertGeometryFixture("TorusGeometry") }
    func testTriangleGeometry() throws { try assertGeometryFixture("TriangleGeometry") }
    func testTubeGeometry() throws { try assertGeometryFixture("TubeGeometry") }
    func testUVDiskGeometry() throws { try assertGeometryFixture("UVDiskGeometry") }
}

private let expectedGeometryNames: Set<String> = [
    "ArcGeometry",
    "BoxGeometry",
    "CapsuleGeometry",
    "CircleGeometry",
    "ConeGeometry",
    "CylinderGeometry",
    "ExtrudedRoundedRectGeometry",
    "ExtrudedTextGeometry",
    "IcoSphereGeometry",
    "LineGeometry",
    "OctaSphereGeometry",
    "ParametricGeometry",
    "PlaneGeometry",
    "PointGeometry",
    "QuadGeometry",
    "RoundedBoxGeometry",
    "RoundedRectGeometry",
    "SatinGeometry",
    "SkyboxGeometry",
    "SphereGeometry",
    "SquircleGeometry",
    "TesselatedTextGeometry",
    "TessellationGeometry",
    "TextGeometry",
    "TorusGeometry",
    "TriangleGeometry",
    "TubeGeometry",
    "UVDiskGeometry",
]

private enum GeometryFixtureKind {
    case visual(VisualGeometryFixture)
    case nonvisual(() throws -> Void)
}

private struct VisualGeometryFixture {
    let referenceName: String
    let size: SIMD2<Int>
    let minimumChangedPixelRatio: Double
    let minimumMeanNormalizedDifference: Double
    let threshold: Double
    let buildScene: (MTLDevice, Camera) -> Object
}

private func assertGeometryFixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
    guard let fixture = makeGeometryFixtures()[name] else {
        XCTFail("Missing geometry fixture for \(name)", file: file, line: line)
        return
    }

    switch fixture {
    case let .visual(config):
        let image = try VisualTestHarness.render(size: config.size) { renderer, camera in
            let scene = config.buildScene(renderer.context.device, camera)
            return (scene: scene, camera: camera)
        }

        VisualTestHarness.assertContainsVisibleContent(
            image,
            minimumChangedPixelRatio: config.minimumChangedPixelRatio,
            minimumMeanNormalizedDifference: config.minimumMeanNormalizedDifference,
            file: file,
            line: line
        )

        try VisualTestHarness.assertVisualMatch(
            image,
            reference: .bundle(name: config.referenceName),
            threshold: config.threshold,
            file: file,
            line: line
        )

    case let .nonvisual(assertion):
        try assertion()
    }
}

private func makeGeometryFixtures() -> [String: GeometryFixtureKind] {
    let fontAtlas = VisualFixtureSupport.makeFontAtlas()

    return [
        "ArcGeometry": makeFlatGeometryFixture(
            referenceName: "geometry-arc",
            geometry: { ArcGeometry(radius: (inner: 0.35, outer: 0.8), angle: (start: 0.0, end: .pi * 1.55), res: (angular: 32, radial: 6)) },
            scale: [1.15, 1.15, 1.0]
        ),
        "BoxGeometry": makeLitGeometryFixture(
            referenceName: "geometry-box",
            geometry: { BoxGeometry(width: 0.9, height: 0.8, depth: 0.7, widthResolution: 2, heightResolution: 2, depthResolution: 2) },
            orientation: simd_quatf(angle: .pi * 0.2, axis: simd_normalize(simd_float3(0.3, 1.0, 0.1)))
        ),
        "CapsuleGeometry": makeLitGeometryFixture(
            referenceName: "geometry-capsule",
            geometry: { CapsuleGeometry(radius: 0.28, height: 0.85, angularResolution: 32, radialResolution: 16, verticalResolution: 4) },
            orientation: simd_quatf(angle: .pi * 0.12, axis: simd_normalize(simd_float3(1.0, 0.0, 0.2)))
        ),
        "CircleGeometry": makeFlatGeometryFixture(
            referenceName: "geometry-circle",
            geometry: { CircleGeometry(radius: 0.8, angularResolution: 32, radialResolution: 6) },
            scale: [1.1, 1.1, 1.0]
        ),
        "ConeGeometry": makeLitGeometryFixture(
            referenceName: "geometry-cone",
            geometry: { ConeGeometry(radius: 0.45, height: 0.95, angularResolution: 32, radialResolution: 3, verticalResolution: 3) }
        ),
        "CylinderGeometry": makeLitGeometryFixture(
            referenceName: "geometry-cylinder",
            geometry: { CylinderGeometry(radius: 0.38, height: 0.9, angularResolution: 32, radialResolution: 3, verticalResolution: 3) },
            orientation: simd_quatf(angle: .pi * 0.1, axis: simd_normalize(simd_float3(0.4, 1.0, 0.0)))
        ),
        "ExtrudedRoundedRectGeometry": makeLitGeometryFixture(
            referenceName: "geometry-extruded-rounded-rect",
            geometry: { ExtrudedRoundedRectGeometry(width: 0.95, height: 0.7, depth: 0.22, radius: 0.14, angularResolution: 32, radialResolution: 6, depthResolution: 3) },
            orientation: simd_quatf(angle: .pi * 0.16, axis: simd_normalize(simd_float3(1.0, 0.3, 0.1)))
        ),
        "ExtrudedTextGeometry": makeLitGeometryFixture(
            referenceName: "geometry-extruded-text",
            geometry: { ExtrudedTextGeometry(text: "S", fontName: "Helvetica", fontSize: 1.0, distance: 0.22) },
            scale: [1.2, 1.2, 1.2],
            orientation: simd_quatf(angle: .pi * 0.08, axis: simd_normalize(simd_float3(0.2, 1.0, 0.1))),
            cameraPosition: [0.0, 0.0, 3.2]
        ),
        "IcoSphereGeometry": makeLitGeometryFixture(
            referenceName: "geometry-icosphere",
            geometry: { IcoSphereGeometry(radius: 0.62, resolution: 2) }
        ),
        "LineGeometry": makeLineGeometryFixture(),
        "OctaSphereGeometry": makeLitGeometryFixture(
            referenceName: "geometry-octasphere",
            geometry: { OctaSphereGeometry(radius: 0.62, resolution: 3) }
        ),
        "ParametricGeometry": makeLitGeometryFixture(
            referenceName: "geometry-parametric",
            geometry: {
                ParametricGeometry(rangeU: 0.0 ... 1.0, rangeV: 0.0 ... 1.0, resolution: simd_int2(24, 18)) { u, v in
                    simd_float3(
                        (u - 0.5) * 1.35,
                        (v - 0.5) * 1.15,
                        sin(u * .pi * 2.0) * cos(v * .pi * 2.0) * 0.2
                    )
                }
            },
            orientation: simd_quatf(angle: -.pi * 0.1, axis: simd_normalize(simd_float3(1.0, 0.2, 0.0)))
        ),
        "PlaneGeometry": makeLitGeometryFixture(
            referenceName: "geometry-plane",
            geometry: { PlaneGeometry(width: 1.25, height: 0.9, widthResolution: 3, heightResolution: 2) },
            orientation: simd_quatf(angle: -.pi * 0.22, axis: simd_normalize(simd_float3(1.0, 0.0, 0.0))),
            cameraPosition: [0.0, 0.7, 4.2],
            lookAt: [0.0, -0.1, 0.0]
        ),
        "PointGeometry": makePointGeometryFixture(),
        "QuadGeometry": makeFlatGeometryFixture(
            referenceName: "geometry-quad",
            geometry: { QuadGeometry(size: 1.35) }
        ),
        "RoundedBoxGeometry": makeLitGeometryFixture(
            referenceName: "geometry-rounded-box",
            geometry: { RoundedBoxGeometry(size: simd_float3(0.82, 0.72, 0.65), radius: 0.14, resolution: 3) },
            orientation: simd_quatf(angle: .pi * 0.18, axis: simd_normalize(simd_float3(0.25, 1.0, 0.18)))
        ),
        "RoundedRectGeometry": makeFlatGeometryFixture(
            referenceName: "geometry-rounded-rect",
            geometry: { RoundedRectGeometry(width: 0.95, height: 0.72, radius: 0.15, angularResolution: 32, radialResolution: 6) },
            scale: [1.1, 1.1, 1.0]
        ),
        "SatinGeometry": .nonvisual {
            let geometry = SatinGeometry()
            XCTAssertEqual(geometry.vertexCount, 0, "Base SatinGeometry should remain empty until subclassed")
            XCTAssertNil(geometry.elementBuffer)
        },
        "SkyboxGeometry": makeSkyboxGeometryFixture(),
        "SphereGeometry": makeLitGeometryFixture(
            referenceName: "geometry-sphere",
            geometry: { SphereGeometry(radius: 0.62, angularResolution: 32, verticalResolution: 18) }
        ),
        "SquircleGeometry": makeFlatGeometryFixture(
            referenceName: "geometry-squircle",
            geometry: { SquircleGeometry(size: 1.35, radius: 0.34, angularResolution: 32, radialResolution: 8) },
            scale: [1.35, 1.35, 1.0],
            minimumChangedPixelRatio: 0.05
        ),
        "TesselatedTextGeometry": makeTesselatedTextGeometryFixture(),
        "TessellationGeometry": .nonvisual {
            let geometry = TessellationGeometry(baseGeometry: QuadGeometry(size: 1.0))
            XCTAssertEqual(geometry.patchCount, 2)
            XCTAssertEqual(geometry.controlPointsPerPatch, 3)
            XCTAssertNotNil(geometry.tessellationDescriptor)
            XCTAssertEqual(geometry.controlPointIndexType, .uint32)
        },
        "TextGeometry": makeTextGeometryFixture(fontAtlas: fontAtlas),
        "TorusGeometry": makeLitGeometryFixture(
            referenceName: "geometry-torus",
            geometry: { TorusGeometry(minorRadius: 0.16, majorRadius: 0.38, minorResolution: 20, majorResolution: 32) },
            orientation: simd_quatf(angle: .pi * 0.3, axis: simd_normalize(simd_float3(1.0, 0.3, 0.0)))
        ),
        "TriangleGeometry": makeFlatGeometryFixture(
            referenceName: "geometry-triangle",
            geometry: { TriangleGeometry(size: 1.35) }
        ),
        "TubeGeometry": makeLitGeometryFixture(
            referenceName: "geometry-tube",
            geometry: { TubeGeometry(radius: 0.42, height: 0.92, startAngle: 0.0, endAngle: .pi * 1.55, angularResolution: 32, verticalResolution: 4) },
            orientation: simd_quatf(angle: .pi * 0.1, axis: simd_normalize(simd_float3(0.9, 0.2, 0.0)))
        ),
        "UVDiskGeometry": makeFlatGeometryFixture(
            referenceName: "geometry-uv-disk",
            geometry: { UVDiskGeometry(innerRadius: 0.35, outerRadius: 0.85) },
            scale: [1.1, 1.1, 1.0]
        ),
    ]
}

private func makeFlatGeometryFixture(
    referenceName: String,
    geometry: @escaping () -> Geometry,
    scale: simd_float3 = .one,
    orientation: simd_quatf = simd_quatf(angle: 0.0, axis: simd_float3(0.0, 1.0, 0.0)),
    cameraPosition: simd_float3 = [0.0, 0.0, 4.0],
    lookAt: simd_float3 = .zero,
    minimumChangedPixelRatio: Double = 0.08,
    minimumMeanNormalizedDifference: Double = 0.015
) -> GeometryFixtureKind {
    .visual(
        VisualGeometryFixture(
            referenceName: referenceName,
            size: [160, 160],
            minimumChangedPixelRatio: minimumChangedPixelRatio,
            minimumMeanNormalizedDifference: minimumMeanNormalizedDifference,
            threshold: 0.006,
            buildScene: { _, camera in
                camera.position = cameraPosition
                camera.lookAt(target: lookAt)

                let mesh = Mesh(
                    label: referenceName,
                    geometry: geometry(),
                    material: BasicColorMaterial(color: simd_float4(0.92, 0.78, 0.24, 1.0), blending: .disabled)
                )
                mesh.scale = scale
                mesh.orientation = orientation

                return makeScene(with: mesh)
            }
        )
    )
}

private func makeLitGeometryFixture(
    referenceName: String,
    geometry: @escaping () -> Geometry,
    scale: simd_float3 = .one,
    orientation: simd_quatf = simd_quatf(angle: 0.0, axis: simd_float3(0.0, 1.0, 0.0)),
    cameraPosition: simd_float3 = [0.0, 0.0, 4.35],
    lookAt: simd_float3 = .zero
) -> GeometryFixtureKind {
    .visual(
        VisualGeometryFixture(
            referenceName: referenceName,
            size: [176, 176],
            minimumChangedPixelRatio: 0.08,
            minimumMeanNormalizedDifference: 0.018,
            threshold: 0.008,
            buildScene: { _, camera in
                camera.position = cameraPosition
                camera.lookAt(target: lookAt)

                let mesh = Mesh(
                    label: referenceName,
                    geometry: geometry(),
                    material: BasicDiffuseMaterial(color: simd_float4(0.92, 0.76, 0.25, 1.0), blending: .disabled, hardness: 0.7)
                )
                mesh.scale = scale
                mesh.orientation = orientation

                let light = DirectionalLight(color: simd_float3(1.0, 0.97, 0.92), intensity: 1.9)
                light.position = [1.9, 2.4, 3.1]
                light.lookAt(target: lookAt)

                let fill = PointLight(color: simd_float3(0.25, 0.5, 0.95), intensity: 0.8, radius: 10.0)
                fill.position = [-1.6, 1.0, 2.4]

                return makeScene(with: mesh, extras: [light, fill])
            }
        )
    )
}

private func makeLineGeometryFixture() -> GeometryFixtureKind {
    .visual(
        VisualGeometryFixture(
            referenceName: "geometry-line",
            size: [160, 160],
            minimumChangedPixelRatio: 0.02,
            minimumMeanNormalizedDifference: 0.004,
            threshold: 0.01,
            buildScene: { _, camera in
                camera.position = [0.0, 0.0, 3.0]
                camera.lookAt(target: .zero)

                let material = BasicColorMaterial(color: simd_float4(0.2, 0.85, 1.0, 1.0), blending: .disabled)
                let scene = Object(label: "Scene")

                let line0 = Mesh(label: "Line 0", geometry: LineGeometry(), material: material.clone())
                line0.scale = [0.72, 0.06, 1.0]
                line0.position = [-0.55, 0.45, 0.0]
                line0.orientation = simd_quatf(angle: .pi * 0.22, axis: simd_float3(0.0, 0.0, 1.0))

                let line1 = Mesh(label: "Line 1", geometry: LineGeometry(), material: material.clone())
                line1.scale = [0.92, 0.08, 1.0]
                line1.position = [0.15, -0.05, 0.0]
                line1.orientation = simd_quatf(angle: -.pi * 0.12, axis: simd_float3(0.0, 0.0, 1.0))

                let line2 = Mesh(label: "Line 2", geometry: LineGeometry(), material: material.clone())
                line2.scale = [0.56, 0.05, 1.0]
                line2.position = [0.62, -0.52, 0.0]
                line2.orientation = simd_quatf(angle: .pi * 0.34, axis: simd_float3(0.0, 0.0, 1.0))

                scene.add(line0)
                scene.add(line1)
                scene.add(line2)
                return scene
            }
        )
    )
}

private func makePointGeometryFixture() -> GeometryFixtureKind {
    .visual(
        VisualGeometryFixture(
            referenceName: "geometry-point",
            size: [160, 160],
            minimumChangedPixelRatio: 0.01,
            minimumMeanNormalizedDifference: 0.003,
            threshold: 0.012,
            buildScene: { _, camera in
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
                    label: "Points",
                    geometry: PointGeometry(data: points),
                    material: BasicPointMaterial(color: simd_float4(1.0, 0.85, 0.2, 1.0), size: 18.0, blending: .disabled)
                )

                return makeScene(with: mesh)
            }
        )
    )
}

private func makeTextGeometryFixture(fontAtlas: FontAtlas) -> GeometryFixtureKind {
    .visual(
        VisualGeometryFixture(
            referenceName: "geometry-text",
            size: [176, 144],
            minimumChangedPixelRatio: 0.02,
            minimumMeanNormalizedDifference: 0.004,
            threshold: 0.006,
            buildScene: { _, camera in
                camera.position = [0.0, 0.0, 35.0]
                camera.lookAt(target: .zero)

                let material = BasicColorMaterial(color: simd_float4(0.96, 0.84, 0.3, 1.0), blending: .disabled)

                let mesh = Mesh(
                    label: "Text",
                    geometry: TextGeometry(text: "S", font: fontAtlas),
                    material: material
                )
                mesh.scale = [0.2, 0.2, 0.2]

                return makeScene(with: mesh)
            }
        )
    )
}

private func makeTesselatedTextGeometryFixture() -> GeometryFixtureKind {
    .visual(
        VisualGeometryFixture(
            referenceName: "geometry-tesselated-text",
            size: [176, 176],
            minimumChangedPixelRatio: 0.03,
            minimumMeanNormalizedDifference: 0.004,
            threshold: 0.008,
            buildScene: { _, camera in
                camera.position = [0.0, 0.0, 2.6]
                camera.lookAt(target: .zero)

                let material = BasicDiffuseMaterial(color: simd_float4(0.95, 0.82, 0.3, 1.0), blending: .disabled, hardness: 0.75)

                let mesh = Mesh(
                    label: "TesselatedText",
                    geometry: TesselatedTextGeometry(text: "S", fontName: "Helvetica", fontSize: 1.0, pivot: simd_float2(0.5, 0.5)),
                    material: material
                )
                mesh.scale = [1.2, 1.2, 1.2]

                let light = DirectionalLight(color: simd_float3(1.0, 0.97, 0.92), intensity: 1.9)
                light.position = [1.9, 2.4, 3.1]
                light.lookAt(target: .zero)

                return makeScene(with: mesh, extras: [light])
            }
        )
    )
}

private func makeSkyboxGeometryFixture() -> GeometryFixtureKind {
    .visual(
        VisualGeometryFixture(
            referenceName: "geometry-skybox",
            size: [176, 176],
            minimumChangedPixelRatio: 0.95,
            minimumMeanNormalizedDifference: 0.08,
            threshold: 0.008,
            buildScene: { device, camera in
                camera.position = .zero
                camera.lookAt(target: [0.0, 0.0, -1.0])

                let mesh = Mesh(
                    label: "Skybox",
                    geometry: SkyboxGeometry(size: 40.0),
                    material: SkyboxMaterial(texture: VisualFixtureSupport.makeCubeTexture(device: device, size: 16))
                )

                return makeScene(with: mesh)
            }
        )
    )
}

private func makeScene(with primary: Object, extras: [Object] = []) -> Object {
    let scene = Object(label: "Scene")
    extras.forEach { scene.add($0) }
    scene.add(primary)
    return scene
}
