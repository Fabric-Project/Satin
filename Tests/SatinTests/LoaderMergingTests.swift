@testable import Satin
import Metal
import MetalKit
import simd
import XCTest

/// Merging static meshes at load: meshes join only when nothing about how they draw differs (one
/// material, one cull mode, one vertex layout, one world transform, opaque, static, no children),
/// so the merged model renders the same pixels with fewer draws. Off unless asked for.
///
/// `loader_merging.usda` holds the cases; see its header.
final class LoaderMergingTests: XCTestCase {
    private var context: Context!
    private var textureLoader: MTKTextureLoader!
    private var url: URL!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        // The loader makes materials only when it can load their textures.
        textureLoader = MTKTextureLoader(device: device)
        url = try XCTUnwrap(Bundle.module.url(forResource: "loader_merging", withExtension: "usda"))
    }

    /// One cell merges across the whole model, as the cases in the fixture expect.
    private func loadMeshes(merging: Bool, cells: Int = 1) throws -> [Mesh] {
        let model = try XCTUnwrap(loadAsset(url: url, context: context, textureLoader: textureLoader, mergeStaticMeshes: merging, mergeCells: cells))
        return model.getChildren().compactMap { $0 as? Mesh }
    }

    private func mesh(_ name: String, in meshes: [Mesh]) throws -> Mesh {
        try XCTUnwrap(meshes.first { $0.label == name }, "no mesh named \(name); loaded \(meshes.map(\.label).sorted())")
    }

    func testWithoutMergingEveryMeshLoads() throws {
        XCTAssertEqual(try loadMeshes(merging: false).map(\.label).sorted(), ["P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"])
    }

    func testMergingJoinsOnlyMeshesThatDrawAlike() throws {
        let separate = try loadMeshes(merging: false)
        let merged = try loadMeshes(merging: true)

        XCTAssertEqual(merged.map(\.label).sorted(), ["P", "S", "T", "U", "V", "W", "X", "Y"],
                       "Q, R and Z join P; everything that differs in how it draws stays")

        let joined = try ["P", "Q", "R", "Z"].map { try mesh($0, in: separate) }
        let p = try mesh("P", in: merged)
        XCTAssertEqual(p.geometry.vertexCount, joined.reduce(0) { $0 + $1.geometry.vertexCount })
        XCTAssertEqual(p.geometry.indexCount, joined.reduce(0) { $0 + $1.geometry.indexCount })
        // Each load makes its own materials: compare within the merged load, with S, also Red.
        XCTAssertTrue(p.material === (try mesh("S", in: merged)).material, "the merged mesh draws with the material they shared")
        XCTAssertEqual(p.cullMode, joined[0].cullMode)
        XCTAssertEqual(p.worldMatrix, joined[0].worldMatrix)
    }

    func testMergingStaysWithinEachCellOfTheGrid() throws {
        // The candidates span x -3 ... 1.8, the longest side: three cells of 1.6. P and Q share the
        // first cell; R's centre is in the second and Z's in the third, so they stay apart.
        let merged = try loadMeshes(merging: true, cells: 3)
        XCTAssertEqual(merged.map(\.label).sorted(), ["P", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"])

        let separate = try loadMeshes(merging: false)
        let p = try mesh("P", in: merged)
        XCTAssertEqual(p.geometry.vertexCount, try mesh("P", in: separate).geometry.vertexCount + mesh("Q", in: separate).geometry.vertexCount)
    }

    func testMergingIsDeterministic() throws {
        let first = try loadMeshes(merging: true)
        let second = try loadMeshes(merging: true)

        XCTAssertEqual(first.map(\.label), second.map(\.label), "the same meshes, in the same order")
        XCTAssertEqual(first.map(\.geometry.vertexCount), second.map(\.geometry.vertexCount))
    }

    func testAMergedModelRendersTheSamePixels() throws {
        func render(merging: Bool) throws -> RGBAImage {
            try VisualTestHarness.render(size: [160, 96]) { renderer, camera in
                let context = renderer.context
                let model = loadAsset(url: self.url, context: context, textureLoader: MTKTextureLoader(device: context.device), mergeStaticMeshes: merging, mergeCells: 1)
                    ?? Object(context: context, label: "Missing")
                let light = DirectionalLight(context: context, color: [1, 1, 1], intensity: 2)
                light.position = [1, 2, 4]
                light.lookAt(target: .zero, up: Satin.worldUpDirection)
                camera.position = [0, 0, 9]
                return (scene: Object(context: context, label: "Scene", [model, light]), camera: camera)
            }
        }

        let separate = try render(merging: false)
        let merged = try render(merging: true)

        VisualTestHarness.assertContainsVisibleContent(separate)
        XCTAssertEqual(separate.pixels, merged.pixels)
    }
}
