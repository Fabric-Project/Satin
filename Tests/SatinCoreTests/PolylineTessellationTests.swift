#if SWIFT_PACKAGE
import SatinCore
#endif

import Satin
import simd
import XCTest

final class PolylineTessellationTests: XCTestCase {
    func testRoundJoinAtReversalProducesFinitePositions() throws {
        let points: [simd_float3] = [[0, 0, 0], [1, 0, 0], [0, 0, 0]]
        var geometryData = points.withUnsafeBufferPointer { pointsBuffer in
            generatePolylineGeometryData(
                pointsBuffer.baseAddress,
                Int32(pointsBuffer.count),
                false,
                0.2,
                PolylineJoinStyle.round.rawValue,
                PolylineCapStyle.butt.rawValue,
                4,
                [0, 0, 1],
                8,
                nil,
                0,
                nil,
                0
            )
        }
        defer { freePolylineGeometryData(&geometryData) }

        XCTAssertGreaterThan(geometryData.vertexCount, 0)
        XCTAssertGreaterThan(geometryData.indexCount, 0)
        let vertices = try XCTUnwrap(geometryData.vertexData)
        for vertexIndex in 0 ..< Int(geometryData.vertexCount) {
            let position = vertices[vertexIndex].position
            XCTAssertTrue(
                position.x.isFinite && position.y.isFinite && position.z.isFinite,
                "Vertex \(vertexIndex) has a nonfinite position at the 180-degree round join: \(position)"
            )
        }
    }
}
