@testable import Satin
import Metal
import simd
import XCTest

/// Routes: each submesh draws in exactly the routes its material's blending, lighting model and
/// alpha-OIT support select, the same routes its mesh is recorded in, and an encoder without OIT
/// never records the OIT route.
final class RouteTests: XCTestCase {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!

    // RenderEncoder.RenderRoute raw values.
    private let opaqueRoute = 0
    private let surfaceOpaqueRoute = 1
    private let unlitOpaqueRoute = 2
    private let alphaTransparentRoute = 3
    private let classicTransparentRoute = 4

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func makeContext(alphaOit: Bool) throws -> Context {
        if alphaOit, !device.supportsFamily(.apple4) { throw XCTSkip("image-block OIT needs Apple4") }
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float, alphaOitEnabled: alphaOit)
    }

    /// A box drawn as one submesh per material, each over all of the box's indices.
    private func makeMesh(context: Context, materials: [Material]) throws -> Mesh {
        let geometry = BoxGeometry(context: context)
        geometry.update()
        let boxElements = try XCTUnwrap(geometry.elementBuffer)
        let mesh = Mesh(context: context, geometry: geometry, material: nil)
        for material in materials {
            // The box's own indices; the box keeps them alive.
            let elements = ElementBuffer(type: boxElements.type, data: boxElements.data, count: boxElements.count, source: geometry)
            mesh.addSubmesh(Submesh(context: context, elementBuffer: elements, material: material))
        }
        mesh.update()
        return mesh
    }

    /// The recorded packets per route, by route raw value.
    private func recordedPacketCounts(_ encoder: RenderEncoder, mesh: Mesh) throws -> [Int] {
        let camera = PerspectiveCamera(context: encoder.context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let submission = encoder.makeSubmissionBuilder(frame: .zero, cameras: [camera], viewports: [MTLViewport(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
        try submission.record(scene: Object(context: encoder.context, label: "Routed", [mesh]))

        var counts = [Int](repeating: 0, count: 5)
        for run in submission.recorder.storage.runs where run.isRecorded {
            counts[run.routeIndex] += run.packets.count
        }
        return counts
    }

    private func material(_ material: Material, blending: Blending) -> Material {
        material.blending = blending
        return material
    }

    func testAnOitAlphaSubmeshDrawsOnlyInTheOitRoute() throws {
        let context = try makeContext(alphaOit: true)
        let mesh = try makeMesh(context: context, materials: [
            material(BasicColorMaterial(context: context), blending: .alpha),
            material(BasicColorMaterial(context: context), blending: .additive),
        ])

        let counts = try recordedPacketCounts(RenderEncoder(context: context), mesh: mesh)

        XCTAssertEqual(counts[alphaTransparentRoute], 1, "the alpha submesh, once")
        XCTAssertEqual(counts[classicTransparentRoute], 1, "the additive submesh only: the alpha one isn't drawn twice")
    }

    func testAnAlphaSubmeshWithoutOitSupportDrawsClassic() throws {
        let context = try makeContext(alphaOit: true)
        let mesh = try makeMesh(context: context, materials: [
            // A plain Material: no OIT variant.
            material(UVColorMaterial(context: context), blending: .alpha),
        ])

        let counts = try recordedPacketCounts(RenderEncoder(context: context), mesh: mesh)

        XCTAssertEqual(counts[alphaTransparentRoute], 0, "its shader has no OIT variant")
        XCTAssertEqual(counts[classicTransparentRoute], 1)
    }

    func testAnEncoderWithoutOitDrawsEveryTransparentSubmeshClassic() throws {
        let context = try makeContext(alphaOit: false)
        let mesh = try makeMesh(context: context, materials: [
            material(BasicColorMaterial(context: context), blending: .alpha),
            material(BasicColorMaterial(context: context), blending: .additive),
        ])

        let counts = try recordedPacketCounts(RenderEncoder(context: context), mesh: mesh)

        XCTAssertEqual(counts[alphaTransparentRoute], 0, "the OIT route isn't recorded without OIT")
        XCTAssertEqual(counts[classicTransparentRoute], 2)
    }

    func testOpaqueSubmeshesDrawInExactlyTheirLayeredRoutes() throws {
        let context = try makeContext(alphaOit: false)
        let mesh = try makeMesh(context: context, materials: [
            StandardMaterial(context: context),
            BasicColorMaterial(context: context),
        ])
        let encoder = RenderEncoder(context: context)
        encoder.renderingMode = .forwardPlus

        let counts = try recordedPacketCounts(encoder, mesh: mesh)

        XCTAssertEqual(counts[surfaceOpaqueRoute], 1, "the surface-lit submesh")
        XCTAssertEqual(counts[unlitOpaqueRoute], 1, "the unlit submesh")
        XCTAssertEqual(counts[opaqueRoute], 0, "the forward bucket isn't recorded in a layered mode")
        XCTAssertEqual(counts[alphaTransparentRoute] + counts[classicTransparentRoute], 0)
    }
}
