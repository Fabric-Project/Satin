import Metal
import Satin
import simd
import XCTest

/// `PolylineGeometry`: SatinCore tessellates a ribbon straight into memory the geometry owns,
/// and each update hands that memory to buffers made once.
final class PolylineGeometryTests: XCTestCase {
    /// A zigzag with sharp turns, so joins take every path: straight, miter, miter falling back
    /// to bevel, bevel, and round fans.
    private let zigzag: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [2, 1, 0], [2.1, -1, 0], [3, 0, 0], [4, 0, 0]]

    func testEveryJoinAndCapIndexesOnlyItsOwnVertices() throws {
        let geometry = try makeGeometry()
        for joinStyle in [PolylineJoinStyle.miter, .bevel, .round] {
            for capStyle in [PolylineCapStyle.butt, .square, .round] {
                for closed in [false, true] {
                    geometry.update(points: zigzag, closed: closed, width: 0.2, joinStyle: joinStyle, capStyle: capStyle,
                                    miterLimit: 2, up: [0, 0, 1], roundResolution: 8)
                    let label = "\(joinStyle) \(capStyle) closed: \(closed)"
                    XCTAssertGreaterThan(geometry.vertexCount, 0, label)
                    XCTAssertGreaterThan(geometry.indexCount, 0, label)
                    let indices = try XCTUnwrap(geometry.elementBuffer?.data).bindMemory(to: UInt32.self, capacity: geometry.indexCount)
                    for index in 0 ..< geometry.indexCount {
                        XCTAssertLessThan(Int(indices[index]), geometry.vertexCount, label)
                    }
                    let bounds = geometry.bounds
                    XCTAssertTrue(bounds.min.x.isFinite && bounds.max.x.isFinite, label)
                    XCTAssertLessThanOrEqual(bounds.min.x, 0, label)
                    XCTAssertGreaterThanOrEqual(bounds.max.x, 4, label)
                }
            }
        }
    }

    func testFewerThanTwoPointsDrawNothing() throws {
        let geometry = try makeGeometry()
        geometry.update(points: zigzag, closed: false, width: 0.2, joinStyle: .round, capStyle: .round, miterLimit: 2, up: [0, 0, 1], roundResolution: 8)
        for points: ContiguousArray<simd_float3> in [[], [[1, 1, 1]], [[1, 1, 1], [1, 1, 1]]] {
            geometry.update(points: points, closed: false, width: 0.2, joinStyle: .round, capStyle: .round, miterLimit: 2, up: [0, 0, 1], roundResolution: 8)
            XCTAssertEqual(geometry.vertexCount, 0)
            XCTAssertEqual(geometry.indexCount, 0)
        }
    }

    private func makeGeometry() throws -> PolylineGeometry {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return PolylineGeometry(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
    }
}
