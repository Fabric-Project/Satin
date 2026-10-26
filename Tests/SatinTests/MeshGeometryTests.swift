@testable import Satin
import Metal
import simd
import XCTest

/// A mesh always has a geometry, a decoded one included, and a mesh whose submeshes carry the
/// materials answers questions about its own missing material without trapping.
final class MeshGeometryTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    func testADecodedMeshHasAnEmptyGeometryOfItsContext() throws {
        let data = try JSONEncoder().encode(Mesh(context: context, geometry: BoxGeometry(context: context), material: nil))
        let decoder = JSONDecoder()
        decoder.userInfo[.satinContext] = context
        let decoded = try decoder.decode(Mesh.self, from: data)

        XCTAssertEqual(decoded.geometry.vertexCount, 0)
        XCTAssertTrue(decoded.geometry.context == context)
    }

    func testAMeshWithoutAMaterialOfItsOwnCountsAsOpaque() {
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: nil)
        XCTAssertTrue(mesh.opaque)
    }

    // MARK: - Double-sided transparency

    /// The packets a double-sided, uncullled mesh of `submeshMaterials` records in the colour pass.
    private func recordDoubleSided(submeshMaterials: [Material]) throws -> (cullModes: [MTLCullMode], storage: PacketStorage) {
        let device = context.device
        let storage = PacketStoragePool().lease()
        let recorder = PacketRecorder(storage: storage, lease: FrameArena(device: device).lease(frame: .zero))
        let geometry = BoxGeometry(context: context)
        geometry.update()
        let elements = try XCTUnwrap(geometry.elementBuffer)
        let mesh = Mesh(context: context, geometry: geometry, material: nil)
        for material in submeshMaterials {
            mesh.addSubmesh(Submesh(context: context, elementBuffer: elements, material: material))
        }
        mesh.doubleSided = true
        mesh.cullMode = .none
        mesh.update()
        mesh.beginOccurrence(frame: .zero)
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let packets = try recorder.record(mesh, renderContext: context, pass: .color, materialPass: .all,
                                      views: [RenderView(camera: camera, viewport: simd_float4(0, 0, 64, 64))])
        return (packets.map { storage.packets[$0].cullMode }, storage)
    }

    private func material(blending: Blending) -> Material {
        let material = BasicColorMaterial(context: context)
        material.blending = blending
        return material
    }

    func testATransparentSubmeshDrawsItsBackFacesThenItsFrontFaces() throws {
        XCTAssertEqual(try recordDoubleSided(submeshMaterials: [material(blending: .alpha)]).cullModes, [.front, .back])
    }

    func testOpaqueSubmeshesDrawOnceUncullled() throws {
        XCTAssertEqual(try recordDoubleSided(submeshMaterials: [material(blending: .disabled)]).cullModes, [.none])
    }

    func testAPassMixingOpaqueAndTransparentSubmeshesOrdersTheTransparentOnes() throws {
        let cullModes = try recordDoubleSided(submeshMaterials: [material(blending: .disabled), material(blending: .alpha)]).cullModes
        XCTAssertEqual(cullModes, [.front, .front, .back, .back], "every submesh's back faces, then every front face")
    }

    func testAStructBufferHoldsItsBufferFromTheStart() {
        let buffer = StructBuffer<Float>(device: context.device, count: 4)
        XCTAssertGreaterThanOrEqual(buffer.buffer.length, 256 * Satin.maxBuffersInFlight)
    }
}
