@testable import Satin
import Metal
import simd
import XCTest

final class PoseBoundsInvalidationTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func makeGeometry(palette: JointPalette) -> Geometry {
        let geometry = QuadGeometry(context: context, size: 1)
        let count = geometry.vertexCount
        geometry.addAttribute(UShort4BufferAttribute(defaultValue: .zero, data: Array(repeating: simd_ushort4.zero, count: count)), for: .JointIndices)
        geometry.addAttribute(Float4BufferAttribute(defaultValue: .zero, data: Array(repeating: simd_float4(1, 0, 0, 0), count: count)), for: .JointWeights)
        geometry.jointPalette = palette
        return geometry
    }

    private func makeMesh(palette: JointPalette) -> Mesh {
        let mesh = Mesh(context: context, geometry: makeGeometry(palette: palette), material: BasicColorMaterial(context: context))
        mesh.update()
        return mesh
    }

    func testAnUpdateCallbackMovesACachedOffscreenPoseIntoView() throws {
        let palette = JointPalette(jointCount: 1)
        palette.update(matrices: [simd_float4x4(translation: [100, 0, 0])])
        let mesh = makeMesh(palette: palette)
        XCTAssertEqual(mesh.worldBounds.min.x, 99.5, accuracy: 0.001)
        mesh.onUpdate = { palette.update(matrices: [matrix_identity_float4x4]) }

        mesh.update()

        XCTAssertEqual(mesh.worldBounds.min.x, -0.5, accuracy: 0.001)
        let encoder = RenderEncoder(context: context)
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100)
        let commandBuffer = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let submission = encoder.makeSubmission(frame: .zero, commandBuffer: commandBuffer, cameras: [camera], viewports: [MTLViewport(originX: 0, originY: 0, width: 16, height: 16, znear: 0, zfar: 1)])
        try submission.record(scene: mesh)
        XCTAssertGreaterThan(submission.recorder.storage.packetCount, 0)
    }

    func testAPoseChangeInvalidatesCachedAncestorBoundsWithoutAnotherUpdate() {
        let palette = JointPalette(jointCount: 1)
        let mesh = makeMesh(palette: palette)
        let parent = Object(context: context, label: "Parent", [mesh])
        XCTAssertEqual(parent.worldBounds.max.x, 0.5, accuracy: 0.001)
        _ = mesh.localBounds

        palette.update(matrices: [simd_float4x4(translation: [3, 0, 0])])

        XCTAssertEqual(parent.worldBounds.max.x, 3.5, accuracy: 0.001)
        XCTAssertEqual(mesh.localBounds.max.x, 3.5, accuracy: 0.001)
    }

    func testReplacingAndRemovingThePaletteInvalidatesBoundsImmediately() {
        let first = JointPalette(jointCount: 1)
        first.update(matrices: [simd_float4x4(translation: [3, 0, 0])])
        let mesh = makeMesh(palette: first)
        XCTAssertEqual(mesh.worldBounds.max.x, 3.5, accuracy: 0.001)
        let replacement = JointPalette(jointCount: 1)
        replacement.update(matrices: [simd_float4x4(translation: [7, 0, 0])])

        mesh.geometry.jointPalette = replacement
        XCTAssertEqual(mesh.worldBounds.max.x, 7.5, accuracy: 0.001)
        replacement.update(matrices: [matrix_identity_float4x4])
        XCTAssertEqual(mesh.worldBounds.max.x, 0.5, accuracy: 0.001)

        mesh.geometry.jointPalette = nil
        XCTAssertEqual(mesh.worldBounds.max.x, 0.5, accuracy: 0.001)
    }

    func testASharedPaletteInvalidatesEveryMeshAndCanOutliveThem() {
        let palette = JointPalette(jointCount: 1)
        let survivor = makeMesh(palette: palette)
        autoreleasepool {
            let temporary = makeMesh(palette: palette)
            _ = temporary.worldBounds
            _ = survivor.worldBounds
            palette.update(matrices: [simd_float4x4(translation: [2, 0, 0])])
            XCTAssertEqual(temporary.worldBounds.max.x, 2.5, accuracy: 0.001)
            XCTAssertEqual(survivor.worldBounds.max.x, 2.5, accuracy: 0.001)
        }
        palette.update(matrices: [simd_float4x4(translation: [4, 0, 0])])
        XCTAssertEqual(survivor.worldBounds.max.x, 4.5, accuracy: 0.001)
    }

    func testPosedViewsWithoutTheirOwnPaletteFollowTheSourceBounds() {
        let palette = JointPalette(jointCount: 1)
        let source = makeGeometry(palette: palette)
        let view = PosedGeometry(source: PosedGeometry(source: source))
        let mesh = Mesh(context: context, geometry: view, material: BasicColorMaterial(context: context))
        mesh.update()
        let parent = Object(context: context, label: "Parent", [mesh])
        XCTAssertEqual(parent.worldBounds.max.x, 0.5, accuracy: 0.001)

        palette.update(matrices: [simd_float4x4(translation: [3, 0, 0])])

        XCTAssertEqual(parent.worldBounds.max.x, 3.5, accuracy: 0.001)
        XCTAssertEqual(view.bounds.max.x, 3.5, accuracy: 0.001)
    }
}
