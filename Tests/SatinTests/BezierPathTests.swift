import Satin
import simd
import XCTest

final class BezierPathTests: XCTestCase {
    func testLinesSampleToTheirEndPoints() {
        var path = BezierPath(start: [0, 0, 0])
        path.addLine(to: [1, 0, 0])
        path.addLine(to: [1, 1, 0])
        XCTAssertEqual(path.sampledPoints(), [[0, 0, 0], [1, 0, 0], [1, 1, 0]])
    }

    func testAQuadraticSamplesLikeItsCubic() {
        var quadratic = BezierPath(start: [0, 0, 0])
        quadratic.addQuadratic(control: [1, 2, 0], to: [2, 0, 0])
        var cubic = BezierPath(start: [0, 0, 0])
        cubic.addCubic(control1: simd_float3(2.0 / 3.0, 4.0 / 3.0, 0), control2: simd_float3(4.0 / 3.0, 4.0 / 3.0, 0), to: [2, 0, 0])

        let quadraticPoints = quadratic.sampledPoints()
        let cubicPoints = cubic.sampledPoints()
        XCTAssertEqual(quadraticPoints.count, cubicPoints.count)
        for (quadraticPoint, cubicPoint) in zip(quadraticPoints, cubicPoints) {
            XCTAssertLessThan(simd_distance(quadraticPoint, cubicPoint), 1e-5)
        }
    }

    func testAClosedPathDoesNotRepeatItsStart() {
        var path = BezierPath(start: [0, 0, 0], isClosed: true)
        path.addLine(to: [1, 0, 0])
        path.addLine(to: [1, 1, 0])
        path.addLine(to: [0, 0, 0])
        XCTAssertEqual(path.sampledPoints(), [[0, 0, 0], [1, 0, 0], [1, 1, 0]])
    }

    func testACollapsedHandleStillCurves() {
        // control1 sits on the start: the curve leaves toward control2, and its midpoint is (0.125, 0.5).
        var path = BezierPath(start: [0, 0, 0])
        path.addCubic(control1: [0, 0, 0], control2: [0, 1, 0], to: [1, 1, 0])
        let points = path.sampledPoints()
        XCTAssertGreaterThan(points.count, 2)
        XCTAssertTrue(points.contains { simd_distance($0, [0.125, 0.5, 0]) < 1e-5 }, "The first split lands on the midpoint")
    }

    func testATinyCurveSamplesLikeTheSameCurveAtFullSize() {
        // A handle counts as collapsed relative to the curve's size, not in absolute units.
        func arch(scale: Float) -> BezierPath {
            var path = BezierPath(start: [0, 0, 0])
            path.addCubic(control1: [0, scale, 0], control2: [scale, scale, 0], to: [scale, 0, 0])
            return path
        }
        XCTAssertEqual(arch(scale: 1e-7).sampledPoints().count, arch(scale: 1).sampledPoints().count)
    }

    func testACurveThatIsAPointSamplesToThatPoint() {
        var path = BezierPath(start: [1, 2, 3])
        path.addCubic(control1: [1, 2, 3], control2: [1, 2, 3], to: [1, 2, 3])
        XCTAssertEqual(path.sampledPoints(), [[1, 2, 3]])
    }

    func testATighterAngleLimitSamplesMorePoints() {
        var path = BezierPath(start: [0, 0, 0])
        path.addCubic(control1: [1, 2, 0], control2: [2, -2, 0], to: [3, 0, 0])
        let coarse = path.sampledPoints(angleLimit: .pi / 8)
        let fine = path.sampledPoints(angleLimit: .pi / 64)
        XCTAssertGreaterThan(fine.count, coarse.count)
        XCTAssertEqual(coarse.first, [0, 0, 0])
        XCTAssertEqual(coarse.last, [3, 0, 0])
    }
}
