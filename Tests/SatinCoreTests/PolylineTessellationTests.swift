#if SWIFT_PACKAGE
import SatinCore
#else
import Satin
#endif

import simd
import XCTest

/// `generatePolylineGeometryData` called through the C API, where style values are plain integers.
final class PolylineTessellationTests: XCTestCase {
    func testAnUnknownCapStyleDrawsRoundAndStaysInsideItsStorage() {
        // Any cap style but 0 (butt) or 1 (square) draws round, so it must be sized as round.
        let points: [simd_float3] = [[0, 0, 0], [1, 0, 0], [2, 0, 0]]
        var roundCaps = tessellate(points, capStyle: 2)
        var unknownCaps = tessellate(points, capStyle: 3)
        defer {
            freePolylineGeometryData(&roundCaps)
            freePolylineGeometryData(&unknownCaps)
        }
        XCTAssertEqual(unknownCaps.vertexCount, roundCaps.vertexCount)
        XCTAssertEqual(unknownCaps.indexCount, roundCaps.indexCount)
        XCTAssertLessThanOrEqual(unknownCaps.vertexCount, unknownCaps.vertexCapacity)
        XCTAssertLessThanOrEqual(unknownCaps.indexCount, unknownCaps.indexCapacity)
    }

    func testReusedDataMatchesFreshData() {
        // Working storage kept between updates must not leak a longer polyline into a shorter one.
        let long: [simd_float3] = (0 ..< 40).map { simd_float3(Float($0), sin(Float($0)), 0) }
        let short: [simd_float3] = [[0, 0, 0], [1, 1, 0], [2, 0, 0]]
        var reused = tessellate(long, capStyle: 2)
        defer { freePolylineGeometryData(&reused) }
        tessellate(short, capStyle: 2, into: &reused)
        var fresh = tessellate(short, capStyle: 2)
        defer { freePolylineGeometryData(&fresh) }

        XCTAssertEqual(reused.vertexCount, fresh.vertexCount)
        XCTAssertEqual(reused.indexCount, fresh.indexCount)
        for vertexIndex in 0 ..< Int(fresh.vertexCount) {
            XCTAssertEqual(reused.vertexData[vertexIndex].position, fresh.vertexData[vertexIndex].position)
            XCTAssertEqual(reused.vertexData[vertexIndex].uv, fresh.vertexData[vertexIndex].uv)
        }
    }

    private func tessellate(_ points: [simd_float3], capStyle: Int32) -> PolylineGeometryData {
        var data = createPolylineGeometryData()
        tessellate(points, capStyle: capStyle, into: &data)
        return data
    }

    private func tessellate(_ points: [simd_float3], capStyle: Int32, into data: inout PolylineGeometryData) {
        points.withUnsafeBufferPointer { pointsBuffer in
            generatePolylineGeometryData(&data, pointsBuffer.baseAddress, Int32(pointsBuffer.count), false, 0.2,
                                         2, capStyle, 4, [0, 0, 1], 8, nil, 0, nil, 0)
        }
    }
}
