@testable import Satin
import Metal
import MetalKit
import ModelIO
import simd
import XCTest

/// Loading maps an asset's source materials and sidedness onto Satin meshes: meshes bound to one
/// source material share one Satin material, materials that only share a name stay apart, culling
/// follows each mesh's sidedness, and a mirrored mesh keeps its outside faces.
///
/// `loader_sharing.usda` holds the cases; see its header.
final class LoaderTests: XCTestCase {
    private var context: Context!
    private var textureLoader: MTKTextureLoader!
    private var url: URL!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        // The loader makes materials only when it can load their textures.
        textureLoader = MTKTextureLoader(device: device)
        url = try XCTUnwrap(Bundle.module.url(forResource: "loader_sharing", withExtension: "usda"))
    }

    private func loadMeshes() throws -> [Mesh] {
        let model = try XCTUnwrap(loadAsset(url: url, context: context, textureLoader: textureLoader))
        return model.getChildren().compactMap { $0 as? Mesh }
    }

    private func mesh(_ name: String, in meshes: [Mesh]) throws -> Mesh {
        try XCTUnwrap(meshes.first { $0.label == name }, "no mesh named \(name); loaded \(meshes.map(\.label).sorted())")
    }

    // MARK: - Material sharing

    func testMeshesBoundToOneSourceMaterialShareASatinMaterial() throws {
        let meshes = try loadMeshes()
        let a = try mesh("A", in: meshes)
        let c = try mesh("C", in: meshes)
        let d = try mesh("D", in: meshes)
        let f = try mesh("F", in: meshes)

        let m1 = try XCTUnwrap(a.material)
        XCTAssertTrue(d.material === m1, "A and D are both bound to M1")
        XCTAssertFalse(c.material === m1, "C is bound to M2")
        XCTAssertEqual(f.submeshes.count, 2, "F's two material subsets are two submeshes")
        XCTAssertTrue(f.submeshes.first?.material === m1, "F's first subset is bound to M1")
        XCTAssertTrue(f.submeshes.last?.material === c.material, "F's second subset is bound to M2")
    }

    func testDifferentlyNamedButIdenticalMaterialsShare() throws {
        let meshes = try loadMeshes()
        XCTAssertTrue(try mesh("I", in: meshes).material === mesh("C", in: meshes).material,
                      "Twin equals M2 in everything but its name and scope")
    }

    func testSameNamedMaterialsInDifferentScopesStaySeparate() throws {
        let meshes = try loadMeshes()
        let g = try XCTUnwrap(try mesh("G", in: meshes).material as? StandardMaterial)
        let h = try XCTUnwrap(try mesh("H", in: meshes).material as? StandardMaterial)

        XCTAssertFalse(g === h, "two source materials named Same are two materials")
        XCTAssertNotEqual(g.baseColor, h.baseColor, "each keeps its own colour")
    }

    func testCloningLetsOneMeshDifferFromTheMeshesSharingItsMaterial() throws {
        let meshes = try loadMeshes()
        let a = try mesh("A", in: meshes)
        let d = try mesh("D", in: meshes)
        let shared = try XCTUnwrap(d.material as? StandardMaterial)
        XCTAssertTrue(a.material === shared, "A and D share their material before one is cloned")
        let sharedColour = shared.baseColor

        let clone = try XCTUnwrap(a.material?.clone() as? StandardMaterial)
        a.material = clone
        clone.baseColor = [1, 0, 1, 1]

        XCTAssertFalse(a.material === d.material)
        XCTAssertEqual(shared.baseColor, sharedColour, "the meshes still sharing the source material are unchanged")
    }

    // MARK: - Sidedness

    func testCullingFollowsEachMeshsSidedness() throws {
        let meshes = try loadMeshes()
        XCTAssertEqual(try mesh("A", in: meshes).cullMode, .back, "single-sided")
        XCTAssertEqual(try mesh("C", in: meshes).cullMode, .back, "single-sided")
        XCTAssertEqual(try mesh("D", in: meshes).cullMode, .back, "single-sided, mirrored")
        XCTAssertEqual(try mesh("B", in: meshes).cullMode, .none, "double-sided, though it shares A's material")
        XCTAssertEqual(try mesh("E", in: meshes).cullMode, .none, "double-sided, with two submeshes")
        XCTAssertEqual(try mesh("F", in: meshes).cullMode, .back, "single-sided, with two submeshes")
    }

    func testTheCullModeRuleCoversEveryFacing() {
        XCTAssertEqual(cullMode(forFaces: []), .none, "no material says nothing about sides")
        XCTAssertEqual(cullMode(forFaces: [.front]), .back)
        XCTAssertEqual(cullMode(forFaces: [.front, .front]), .back)
        XCTAssertEqual(cullMode(forFaces: [.back]), .front)
        XCTAssertEqual(cullMode(forFaces: [.doubleSided]), .none)
        XCTAssertEqual(cullMode(forFaces: [.front, .doubleSided]), .none, "culling is mesh-wide: one double-sided part keeps both sides")
        XCTAssertEqual(cullMode(forFaces: [.front, .back]), .none, "and so does a mix of front and back")
    }

    // MARK: - Textures

    func testAnImageIsSharedOnlyWhenLoadedWithTheSameOptions() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let texture = try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)))
        let textures = LoadedTextures()
        let mipmapped: [MTKTextureLoader.Option: Any] = [.generateMipmaps: true, .origin: MTKTextureLoader.Origin.flippedVertically]
        let flat: [MTKTextureLoader.Option: Any] = [.generateMipmaps: false, .origin: MTKTextureLoader.Origin.flippedVertically]

        textures.add(texture, source: "asset.usdz[0/image.png]", options: mipmapped)

        XCTAssertTrue(textures.texture(source: "asset.usdz[0/image.png]", options: mipmapped) === texture, "same image, same options")
        XCTAssertNil(textures.texture(source: "asset.usdz[0/image.png]", options: flat), "same image, other options: its own texture")
        XCTAssertNil(textures.texture(source: "asset.usdz[0/other.png]", options: mipmapped), "another image")
    }

    // MARK: - Winding

    func testAMirroredMeshFlipsItsWindingOnceItsTransformIsKnown() throws {
        let meshes = try loadMeshes()
        let a = try mesh("A", in: meshes)
        let d = try mesh("D", in: meshes)

        XCTAssertEqual(a.windingOrder, .counterClockwise, "the asset's triangles are counter-clockwise")
        XCTAssertEqual(d.windingOrder, .clockwise, "mirrored by its parent's scale, so its front faces turn clockwise")
    }

    func testAMirroredDoubleSidedMeshFlipsItsWindingAndCullsNothing() throws {
        let j = try mesh("J", in: loadMeshes())
        XCTAssertEqual(j.cullMode, .none)
        XCTAssertEqual(j.windingOrder, .clockwise)
    }
}
