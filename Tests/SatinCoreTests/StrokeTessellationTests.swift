#if SWIFT_PACKAGE
import SatinCore
#else
import Satin
#endif

import simd
import XCTest

/// `appendStrokeGeometryData` called through the C API, where style values are plain integers.
final class StrokeTessellationTests: XCTestCase {
    func testAnUnknownCapStyleDrawsRoundAndStaysInsideItsStorage() {
        // Any cap style but 0 (butt) or 1 (square) draws round, so it must be sized as round.
        let points: [simd_float3] = [[0, 0, 0], [1, 0, 0], [2, 0, 0]]
        var roundCaps = tessellate(points, capStyle: 2)
        var unknownCaps = tessellate(points, capStyle: 3)
        defer {
            freeStrokeGeometryData(&roundCaps)
            freeStrokeGeometryData(&unknownCaps)
        }
        XCTAssertEqual(unknownCaps.vertexCount, roundCaps.vertexCount)
        XCTAssertEqual(unknownCaps.indexCount, roundCaps.indexCount)
        XCTAssertLessThanOrEqual(unknownCaps.vertexCount, unknownCaps.vertexCapacity)
        XCTAssertLessThanOrEqual(unknownCaps.indexCount, unknownCaps.indexCapacity)
    }

    func testReusedDataMatchesFreshData() {
        // Working storage kept between updates must not leak a longer stroke into a shorter one.
        let long: [simd_float3] = (0 ..< 40).map { simd_float3(Float($0), sin(Float($0)), 0) }
        let short: [simd_float3] = [[0, 0, 0], [1, 1, 0], [2, 0, 0]]
        var reused = tessellate(long, capStyle: 2)
        defer { freeStrokeGeometryData(&reused) }
        tessellate(short, capStyle: 2, into: &reused)
        var fresh = tessellate(short, capStyle: 2)
        defer { freeStrokeGeometryData(&fresh) }

        XCTAssertEqual(reused.vertexCount, fresh.vertexCount)
        XCTAssertEqual(reused.indexCount, fresh.indexCount)
        for vertexIndex in 0 ..< Int(fresh.vertexCount) {
            XCTAssertEqual(reused.vertexData[vertexIndex].position, fresh.vertexData[vertexIndex].position)
            XCTAssertEqual(reused.vertexData[vertexIndex].uv, fresh.vertexData[vertexIndex].uv)
        }
    }

    func testRoundCapsKeepVAcrossTheWidth() {
        // A line along x has its width along y, so every vertex's v follows its y, on the same side throughout.
        var data = tessellate([[0, 0, 0], [1, 0, 0], [2, 0, 0]], capStyle: 2)
        defer { freeStrokeGeometryData(&data) }
        var leftIsPositiveY: Bool?
        for vertexIndex in 0 ..< Int(data.vertexCount) {
            let vertex = data.vertexData[vertexIndex]
            XCTAssertEqual(abs(vertex.uv.y - 0.5) * 2, abs(vertex.position.y) / 0.1, accuracy: 1e-4)
            guard abs(vertex.position.y) > 1e-4 else { continue }
            let isPositiveLeft = (vertex.uv.y > 0.5) == (vertex.position.y > 0)
            XCTAssertEqual(isPositiveLeft, leftIsPositiveY ?? isPositiveLeft)
            leftIsPositiveY = isPositiveLeft
        }
    }

    func testURunsFromTipToTipAcrossCaps() {
        // A line from x = 0 to x = 2, width 0.2: round and square caps reach 0.1 past each end, and butt caps none.
        for (capStyle, reach) in [(Int32(2), Float(0.1)), (1, 0.1), (0, 0)] {
            var data = tessellate([[0, 0, 0], [1, 0, 0], [2, 0, 0]], capStyle: capStyle)
            defer { freeStrokeGeometryData(&data) }
            for vertexIndex in 0 ..< Int(data.vertexCount) {
                let vertex = data.vertexData[vertexIndex]
                XCTAssertEqual(vertex.uv.x, (vertex.position.x + reach) / (2 + 2 * reach), accuracy: 1e-4, "cap style \(capStyle)")
            }
        }
    }

    func testARoundJoinsRimStaysOnItsEdge() {
        let corner = simd_float3(1, 0, 0)
        var data = tessellate([[0, 0, 0], corner, [1, 1, 0]], capStyle: 0)
        defer { freeStrokeGeometryData(&data) }
        let rim = (0 ..< Int(data.vertexCount)).map { data.vertexData[$0] }.filter { abs(simd_distance($0.position, corner) - 0.1) < 1e-4 }
        XCTAssertGreaterThan(rim.count, 2)
        XCTAssertTrue(rim.allSatisfy { $0.uv.y == rim[0].uv.y })
        XCTAssertTrue(rim[0].uv.y == 0 || rim[0].uv.y == 1)
    }

    func testARoundJoinTooTightForItsWidthKeepsItsRimsOnTheirEdges() {
        // The last segment is shorter than the width, so the joint has a center hub and two rims.
        let corner = simd_float3(1, 0, 0)
        var data = tessellate([[0, 0, 0], corner, [1, 0.05, 0]], capStyle: 0)
        defer { freeStrokeGeometryData(&data) }
        let rim = (0 ..< Int(data.vertexCount)).map { data.vertexData[$0] }.filter { abs(simd_distance($0.position, corner) - 0.1) < 1e-4 }
        XCTAssertGreaterThan(rim.count, 2)
        XCTAssertTrue(rim.allSatisfy { $0.uv.y == 0 || $0.uv.y == 1 })
    }

    func testADotsUVsLieFlatAcrossIt() {
        var data = tessellate([[0, 0, 0]], capStyle: 2)
        defer { freeStrokeGeometryData(&data) }
        XCTAssertGreaterThan(data.vertexCount, 2)
        XCTAssertEqual(data.vertexData[0].uv, simd_float2(0.5, 0.5))
        for vertexIndex in 1 ..< Int(data.vertexCount) {
            let vertex = data.vertexData[vertexIndex]
            XCTAssertEqual(abs(vertex.uv.x - 0.5) * 2, abs(vertex.position.x) / 0.1, accuracy: 1e-4)
            XCTAssertEqual(abs(vertex.uv.y - 0.5) * 2, abs(vertex.position.y) / 0.1, accuracy: 1e-4)
        }
    }

    /// Whether every triangle faces +z, as it does when nothing has folded over.
    private func everyTriangleFacesUp(_ data: StrokeGeometryData) -> Bool {
        (0 ..< Int(data.indexCount)).allSatisfy { triangleIndex in
            let triangle = data.indexData[triangleIndex]
            let a = data.vertexData[Int(triangle.i0)].position
            let b = data.vertexData[Int(triangle.i1)].position
            let c = data.vertexData[Int(triangle.i2)].position
            return simd_cross(b - a, c - a).z >= -1e-6
        }
    }

    private func arc(radius: Float, count: Int) -> [simd_float3] {
        (0 ... count).map { step in
            let angle = Float.pi * Float(step) / Float(count)
            return simd_float3(radius * cos(angle), radius * sin(angle), 0)
        }
    }

    func testABendTighterThanTheHalfWidthDoesNotFold() {
        // Half width 0.1, radius 0.05: the inner edge would run backwards on every segment.
        var data = tessellate(arc(radius: 0.05, count: 32), capStyle: 2)
        defer { freeStrokeGeometryData(&data) }
        XCTAssertTrue(everyTriangleFacesUp(data))
    }

    func testAGentleBendKeepsItsInnerCorners() {
        // Radius 1 against half width 0.1: no segment runs backwards, so nothing merges.
        var data = tessellate(arc(radius: 1, count: 32), capStyle: 2)
        defer { freeStrokeGeometryData(&data) }
        XCTAssertTrue(everyTriangleFacesUp(data))
        XCTAssertTrue((0 ..< Int(data.vertexCount)).allSatisfy { data.vertexData[$0].custom0.y != 0 })
    }

    func testAMergedInnerCornerHasNoWidthToRebuild() {
        var data = tessellate(arc(radius: 0.05, count: 32), capStyle: 2)
        defer { freeStrokeGeometryData(&data) }
        let merged = (0 ..< Int(data.vertexCount)).map { data.vertexData[$0] }.filter { $0.custom0.y == 0 }
        XCTAssertFalse(merged.isEmpty)
        XCTAssertTrue(merged.allSatisfy { $0.position == $0.custom1 })
    }

    func testGrowingWhileAppendingKeepsTheStrokesAlreadyAppended() {
        // Round caps on a long second stroke force the storage past the first stroke's capacity.
        let short: [simd_float3] = [[0, 0, 0], [1, 1, 0]]
        let long: [simd_float3] = (0 ..< 200).map { simd_float3(Float($0), sin(Float($0)), 0) }
        var first = tessellate(short, capStyle: 2)
        var second = tessellate(long, capStyle: 2)
        var appended = tessellate(short, capStyle: 2)
        defer {
            freeStrokeGeometryData(&first)
            freeStrokeGeometryData(&second)
            freeStrokeGeometryData(&appended)
        }
        append(long, capStyle: 2, to: &appended)

        XCTAssertEqual(appended.vertexCount, first.vertexCount + second.vertexCount)
        XCTAssertEqual(appended.indexCount, first.indexCount + second.indexCount)
        XCTAssertLessThanOrEqual(appended.vertexCount, appended.vertexCapacity)
        XCTAssertLessThanOrEqual(appended.indexCount, appended.indexCapacity)
        for vertexIndex in 0 ..< Int(first.vertexCount) {
            XCTAssertEqual(appended.vertexData[vertexIndex].position, first.vertexData[vertexIndex].position)
        }
        for vertexIndex in 0 ..< Int(second.vertexCount) {
            XCTAssertEqual(appended.vertexData[Int(first.vertexCount) + vertexIndex].position, second.vertexData[vertexIndex].position)
        }
        let offset = UInt32(first.vertexCount)
        for triangleIndex in 0 ..< Int(second.indexCount) {
            XCTAssertEqual(appended.indexData[Int(first.indexCount) + triangleIndex].i0, second.indexData[triangleIndex].i0 + offset)
        }
    }

    private func tessellate(_ points: [simd_float3], capStyle: Int32) -> StrokeGeometryData {
        var data = createStrokeGeometryData()
        tessellate(points, capStyle: capStyle, into: &data)
        return data
    }

    private func tessellate(_ points: [simd_float3], capStyle: Int32, into data: inout StrokeGeometryData) {
        resetStrokeGeometryData(&data)
        append(points, capStyle: capStyle, to: &data)
    }

    private func append(_ points: [simd_float3], capStyle: Int32, to data: inout StrokeGeometryData) {
        points.withUnsafeBufferPointer { pointsBuffer in
            appendStrokeGeometryData(&data, pointsBuffer.baseAddress, Int32(pointsBuffer.count), false, 0.2,
                                     2, capStyle, 4, [0, 0, 1], 8, nil, 0, nil, 0)
        }
    }
}
