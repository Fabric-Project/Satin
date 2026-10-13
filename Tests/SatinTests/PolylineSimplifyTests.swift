import Satin
import simd
import XCTest

final class PolylineSimplifyTests: XCTestCase {
    func testCollinearPointsAreDropped() {
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [2, 0.001, 0], [3, 0, 0]]
        XCTAssertEqual(simplifyPolyline(points, tolerance: 0.01), [[0, 0, 0], [3, 0, 0]])
    }

    func testAHairpinKeepsItsTip() {
        // The path doubles back: its tip lies far from the segment joining its ends.
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [5, 0, 0], [0, 0.05, 0]]
        XCTAssertEqual(simplifyPolyline(points, tolerance: 0.01), points)
    }

    func testAClosedSquareKeepsItsCorners() {
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [0.5, 0, 0], [1, 0, 0], [1, 0.5, 0], [1, 1, 0], [0.5, 1, 0], [0, 1, 0], [0, 0.5, 0]]
        XCTAssertEqual(simplifyPolyline(points, tolerance: 0.01, closed: true), [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]])
    }

    func testNoToleranceKeepsEveryPoint() {
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [2, 0, 0]]
        XCTAssertEqual(simplifyPolyline(points, tolerance: 0), points)
    }
}
