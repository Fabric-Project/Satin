import Satin
import Metal
import simd
import XCTest

/// Uses the public module surface, as a camera implemented by an application does.
private final class AdjustableProjectionCamera: Camera {
    var horizontalScale: Float = 1 {
        didSet {
            if horizontalScale != oldValue { projectionInputsDidChange() }
        }
    }

    override func computeProjectionMatrix() -> simd_float4x4 {
        var projection = matrix_identity_float4x4
        projection.columns.0.x = horizontalScale
        return projection
    }
}

final class CameraProjectionInvalidationTests: XCTestCase {
    private func makeCamera() throws -> AdjustableProjectionCamera {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
        return AdjustableProjectionCamera(context: context)
    }

    func testExternalSubclassInputInvalidatesProjectionAndViewProjection() throws {
        let camera = try makeCamera()
        camera.position = [2, 0, 0]
        let originalProjection = camera.projectionMatrix
        let originalViewProjection = camera.viewProjectionMatrix

        camera.horizontalScale = 3

        XCTAssertEqual(originalProjection.columns.0.x, 1)
        XCTAssertEqual(originalViewProjection.columns.0.x, 1)
        XCTAssertEqual(camera.projectionMatrix.columns.0.x, 3)
        XCTAssertEqual(camera.viewProjectionMatrix.columns.0.x, 3)
        XCTAssertEqual(camera.viewProjectionMatrix.columns.3.x, -6)
    }

    func testExternalSubclassInputReplacesAnAssignedProjection() throws {
        let camera = try makeCamera()
        var assignedProjection = matrix_identity_float4x4
        assignedProjection.columns.0.x = 7
        camera.projectionMatrix = assignedProjection
        XCTAssertEqual(camera.viewProjectionMatrix.columns.0.x, 7)

        camera.horizontalScale = 4

        XCTAssertEqual(camera.projectionMatrix.columns.0.x, 4)
        XCTAssertEqual(camera.viewProjectionMatrix.columns.0.x, 4)
    }
}
