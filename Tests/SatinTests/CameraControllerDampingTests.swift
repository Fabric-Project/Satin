@testable import Satin
import XCTest

/// Camera controller tweens damp and move as a 60 Hz loop would, whatever the frame rate: one 60 Hz
/// frame is the old per-frame step, two 120 Hz frames match it, and a long frame stays bounded.
final class CameraControllerDampingTests: XCTestCase {
    private let damping: Float = 0.9
    private let accuracy: Float = 1e-5

    func testOneFrameAt60HzIsThePerFrameStep() {
        let step = dampedTweenStep(damping: damping, deltaTime: 1.0 / 60.0)
        XCTAssertEqual(step.remaining, damping, accuracy: accuracy)
        XCTAssertEqual(step.travelled, damping, accuracy: accuracy)
    }

    func testTwoFramesAt120HzMatchOneAt60Hz() {
        let first = dampedTweenStep(damping: damping, deltaTime: 1.0 / 120.0)
        let second = dampedTweenStep(damping: damping, deltaTime: 1.0 / 120.0)
        let sixty = dampedTweenStep(damping: damping, deltaTime: 1.0 / 60.0)

        XCTAssertEqual(first.remaining * second.remaining, sixty.remaining, accuracy: accuracy)
        XCTAssertEqual(first.travelled + first.remaining * second.travelled, sixty.travelled, accuracy: accuracy)
    }

    func testLongFrameTravelIsBounded() {
        let step = dampedTweenStep(damping: damping, deltaTime: 2)
        XCTAssertLessThan(step.remaining, 0.001)
        XCTAssertLessThanOrEqual(step.travelled, damping / (1 - damping) + accuracy, "never past where the tween would come to rest")
    }

    func testNoTimeMeansNoMotion() {
        let step = dampedTweenStep(damping: damping, deltaTime: 0)
        XCTAssertEqual(step.remaining, 1)
        XCTAssertEqual(step.travelled, 0, accuracy: accuracy)
    }

    func testUndampedTravelsOneVelocityPerFrame() {
        let step = dampedTweenStep(damping: 1, deltaTime: 0.5)
        XCTAssertEqual(step.remaining, 1)
        XCTAssertEqual(step.travelled, 30, accuracy: accuracy)
    }
}
