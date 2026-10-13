@testable import Satin
import simd
import XCTest

/// `Lerpable`: every conformance meets its ends, quaternions take the short arc, and matrices
/// interpolate as translation, rotation and scale, so the matrices in between stay rigid.
final class LerpableTests: XCTestCase {
    private let accuracy: Float = 1e-5

    // MARK: - Scalars and Vectors

    func testScalarsAndVectorsMeetTheirEndsAndMidpoint() {
        XCTAssertEqual(Float.lerp(2, 6, 0), 2)
        XCTAssertEqual(Float.lerp(2, 6, 0.5), 4)
        XCTAssertEqual(Float.lerp(2, 6, 1), 6)
        XCTAssertEqual(Double.lerp(2, 6, 0.5), 4)
        XCTAssertEqual(simd_float2.lerp([0, 2], [4, 6], 0.5), [2, 4])
        XCTAssertEqual(simd_float3.lerp([0, 2, 4], [4, 6, 8], 0.5), [2, 4, 6])
        XCTAssertEqual(simd_float4.lerp([0, 2, 4, 6], [4, 6, 8, 10], 0.5), [2, 4, 6, 8])
    }

    func testOvershootingEasingsExtrapolate() {
        XCTAssertEqual(Float.lerp(0, 10, 1.25), 12.5, "t is not clamped")
        XCTAssertEqual(Float.lerp(0, 10, -0.25), -2.5)
    }

    // MARK: - Quaternions

    func testQuaternionsTakeTheShortArc() {
        let start = simd_quatf(angle: 0, axis: [0, 0, 1])
        // The same rotation as a quarter turn, written as its negation: the long way round is 270°.
        let end = -simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        let halfway = simd_quatf.lerp(start, end, 0.5)
        let rotated = halfway.act([1, 0, 0])
        XCTAssertEqual(rotated.x, cos(.pi / 4), accuracy: accuracy)
        XCTAssertEqual(rotated.y, sin(.pi / 4), accuracy: accuracy)
    }

    // MARK: - Matrices

    func testMatricesMeetTheirEnds() {
        let start = simd_float4x4(translation: [1, 2, 3], rotation: simd_quatf(angle: 0.3, axis: [0, 1, 0]), scale: [1, 2, 3])
        let end = simd_float4x4(translation: [-1, 0, 5], rotation: simd_quatf(angle: 1.2, axis: [1, 0, 0]), scale: [3, 1, 2])
        assertEqual(simd_float4x4.lerp(start, end, 0), start)
        assertEqual(simd_float4x4.lerp(start, end, 1), end)
    }

    func testMatricesHalfwayBetweenRotationsStayRigid() {
        let start = matrix_identity_float4x4
        let end = simd_float4x4(rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
        let halfway = simd_float4x4.lerp(start, end, 0.5)
        // Mixing the columns would shrink both axes to ~0.707 here.
        assertOrthonormal(halfway)
        XCTAssertEqual(halfway.determinant, 1, accuracy: accuracy)
        let rotated = simd_make_float3(halfway * simd_float4(1, 0, 0, 0))
        XCTAssertEqual(rotated.x, cos(.pi / 4), accuracy: accuracy)
        XCTAssertEqual(rotated.y, sin(.pi / 4), accuracy: accuracy)
    }

    func testMatricesInterpolateTranslationAndScale() {
        let start = simd_float4x4(translation: [0, 0, 0], scale: [1, 1, 1])
        let end = simd_float4x4(translation: [2, 4, 6], scale: [3, 5, 7])
        assertEqual(simd_float4x4.lerp(start, end, 0.5), simd_float4x4(translation: [1, 2, 3], scale: [2, 3, 4]))
    }

    func testMirroredMatricesStayMirrored() {
        let mirror = simd_float4x4(diagonal: [-1, 1, 1, 1])
        let start = mirror
        let end = simd_float4x4(rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])) * mirror
        for t: Float in [0, 0.25, 0.5, 0.75, 1] {
            XCTAssertEqual(simd_float4x4.lerp(start, end, t).determinant, -1, accuracy: accuracy, "t = \(t)")
        }
        assertEqual(simd_float4x4.lerp(start, end, 1), end)
    }

    // MARK: - Decomposition

    func testMirroredMatricesRoundTrip() {
        let matrix = simd_float4x4(translation: [1, 2, 3], rotation: simd_quatf(angle: 0.7, axis: simd_normalize([1, 1, 0])), scale: [-2, 3, 4])
        XCTAssertLessThan(matrix.decomposed.scale.x, 0)
        assertEqual(recomposed(matrix), matrix)
    }

    func testCollapsedAxesKeepAUnitRotationAndRoundTrip() {
        let rotation = simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3]))
        let scales: [simd_float3] = [[0, 2, 3], [2, 0, 3], [2, 3, 0], [0, 0, 3], [0, 2, 0], [2, 0, 0], [0, 0, 0]]
        for scale in scales {
            let matrix = simd_float4x4(translation: [1, 2, 3], rotation: rotation, scale: scale)
            XCTAssertEqual(simd_length(matrix.decomposed.rotation.vector), 1, accuracy: accuracy, "scale \(scale)")
            assertOrthonormal(simd_float4x4(matrix.decomposed.rotation))
            assertEqual(recomposed(matrix), matrix, "scale \(scale)")
        }
    }

    func testCollapsedAxesKeepTheirDirectionsOnTheOtherAxes() {
        let rotation = simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3]))
        let matrix = simd_float4x4(rotation: rotation, scale: [0, 2, 3])
        let rebuilt = simd_float3x3(matrix.decomposed.rotation)
        let original = simd_float3x3(rotation)
        for column in 0 ..< 3 {
            XCTAssertEqual(simd_distance(rebuilt[column], original[column]), 0, accuracy: accuracy, "column \(column)")
        }
    }

    // MARK: - Helpers

    private func assertEqual(_ actual: simd_float4x4, _ expected: simd_float4x4, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        for column in 0 ..< 4 {
            XCTAssertEqual(simd_distance(actual[column], expected[column]), 0, accuracy: 1e-4, "column \(column) \(message)", file: file, line: line)
        }
    }

    private func assertOrthonormal(_ matrix: simd_float4x4, file: StaticString = #filePath, line: UInt = #line) {
        let axes = (0 ..< 3).map { simd_make_float3(matrix[$0]) }
        for first in 0 ..< 3 {
            XCTAssertEqual(simd_length(axes[first]), 1, accuracy: accuracy, "axis \(first) length", file: file, line: line)
            for second in first + 1 ..< 3 {
                XCTAssertEqual(simd_dot(axes[first], axes[second]), 0, accuracy: accuracy, "axes \(first), \(second) not square", file: file, line: line)
            }
        }
    }
}
