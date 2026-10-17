@testable import Satin
import XCTest

/// `Tween` progresses on the times it is updated with, not a clock of its own: it anchors on the
/// first update after starting or resuming, waits out its delay, and restarts a loop at the time
/// it completes.
final class TweenTests: XCTestCase {
    private let accuracy = 1e-9

    func testProgressFollowsUpdateTimesFromTheFirstUpdate() {
        let tween = Tween(duration: 2).start()

        XCTAssertFalse(tween.update(time: 10), "anchors at its first update")
        XCTAssertEqual(tween.progress, 0, accuracy: accuracy)

        XCTAssertFalse(tween.update(time: 11))
        XCTAssertEqual(tween.progress, 0.5, accuracy: accuracy)

        XCTAssertTrue(tween.update(time: 12))
        XCTAssertTrue(tween.complete)
    }

    func testDelayHoldsTweeningUntilItPasses() {
        var tweenValues: [Double] = []
        var tweenStartCount = 0
        let tween = Tween(duration: 2)
            .onTweenStart { tweenStartCount += 1 }
            .onTween { tweenValues.append($0) }
            .delay(1)
            .start()

        _ = tween.update(time: 10)
        XCTAssertEqual(tween.progress, -0.5, accuracy: accuracy)
        XCTAssertTrue(tweenValues.isEmpty)
        XCTAssertEqual(tweenStartCount, 0)

        _ = tween.update(time: 11)
        XCTAssertEqual(tween.progress, 0, accuracy: accuracy)
        XCTAssertEqual(tweenValues, [0])
        XCTAssertEqual(tweenStartCount, 1)
    }

    func testPauseHoldsProgressAndPlayResumesFromIt() {
        let tween = Tween(duration: 2).start()
        _ = tween.update(time: 10)
        _ = tween.update(time: 11)

        tween.pause()
        _ = tween.update(time: 20)
        XCTAssertEqual(tween.progress, 0.5, accuracy: accuracy, "paused at the last update's progress")

        _ = tween.play()
        _ = tween.update(time: 30)
        XCTAssertEqual(tween.progress, 0.5, accuracy: accuracy, "resumes on the first update after play")

        _ = tween.update(time: 30.5)
        XCTAssertEqual(tween.progress, 0.75, accuracy: accuracy)
    }

    func testLoopRestartsAtTheTimeItCompletes() {
        let tween = Tween(duration: 2).loop().start()
        _ = tween.update(time: 0)

        XCTAssertFalse(tween.update(time: 2), "a looping tween restarts instead of completing")

        _ = tween.update(time: 3)
        XCTAssertEqual(tween.progress, 0.5, accuracy: accuracy)

        tween.remove()
    }
}
