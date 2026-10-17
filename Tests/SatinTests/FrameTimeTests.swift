@testable import Satin
import Metal
import XCTest

/// `FrameTime.first` and `next` step a driver without a clock of its own, deriving each frame's
/// delta and number from the one before. `Renderer` builds frames from the host timestamps its
/// render loop passes in: time counts from the first frame, deltas follow the timestamps, and
/// setting up starts over.
final class FrameTimeTests: XCTestCase {
    // MARK: - FrameTime

    func testFirstIsFrameZeroAtItsTime() {
        let start = FrameTime.first(hostMediaTime: 100)
        XCTAssertEqual(start.frameNumber, 0)
        XCTAssertEqual(start.time, 0)
        XCTAssertEqual(start.deltaTime, 0)
        XCTAssertEqual(start.hostMediaTime, 100)

        let lateStart = FrameTime.first(time: 5, displayTime: 5, hostMediaTime: 100)
        XCTAssertEqual(lateStart.time, 5, "an offline render can start later than 0")
        XCTAssertEqual(lateStart.deltaTime, 0)
    }

    func testNextCountsAndMeasuresFromThePreviousFrame() {
        let second = FrameTime.first(hostMediaTime: 100).next(time: 0.25, hostMediaTime: 100.25)
        let third = second.next(time: 0.75, displayTime: 0.8, hostMediaTime: 100.75)

        XCTAssertEqual(second.frameNumber, 1)
        XCTAssertEqual(second.deltaTime, 0.25, accuracy: 1e-9)
        XCTAssertEqual(third.frameNumber, 2)
        XCTAssertEqual(third.deltaTime, 0.5, accuracy: 1e-9)
        XCTAssertEqual(third.displayTime, 0.8)
        XCTAssertEqual(third.hostMediaTime, 100.75)
    }

    // MARK: - Renderer

    private func makeRenderer() throws -> Renderer {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Renderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
    }

    func testFirstFrameIsFrameZeroAtTimeZero() throws {
        let renderer = try makeRenderer()
        XCTAssertEqual(renderer.frameTime, .zero, "no frame before the first advance")

        let frame = renderer.advanceFrameTime(hostTime: 100, presentationHostTime: nil)

        XCTAssertEqual(frame.frameNumber, 0)
        XCTAssertEqual(frame.time, 0)
        XCTAssertEqual(frame.deltaTime, 0)
        XCTAssertEqual(frame.hostMediaTime, 100)
        XCTAssertEqual(renderer.frameTime, frame)
    }

    func testTimeAndDeltaFollowHostTimestamps() throws {
        let renderer = try makeRenderer()
        _ = renderer.advanceFrameTime(hostTime: 100, presentationHostTime: nil)
        let second = renderer.advanceFrameTime(hostTime: 100.25, presentationHostTime: nil)
        let third = renderer.advanceFrameTime(hostTime: 100.75, presentationHostTime: nil)

        XCTAssertEqual(second.frameNumber, 1)
        XCTAssertEqual(second.time, 0.25, accuracy: 1e-9)
        XCTAssertEqual(second.deltaTime, 0.25, accuracy: 1e-9)
        XCTAssertEqual(third.frameNumber, 2)
        XCTAssertEqual(third.time, 0.75, accuracy: 1e-9)
        XCTAssertEqual(third.deltaTime, 0.5, accuracy: 1e-9)
    }

    func testDisplayTimeSharesTheTimelineAndIsNilWhenUnknown() throws {
        let renderer = try makeRenderer()
        let undisplayed = renderer.advanceFrameTime(hostTime: 100, presentationHostTime: nil)
        let displayed = renderer.advanceFrameTime(hostTime: 100.5, presentationHostTime: 100.75)

        XCTAssertNil(undisplayed.displayTime)
        let displayTime = try XCTUnwrap(displayed.displayTime)
        XCTAssertEqual(displayTime, 0.75, accuracy: 1e-9, "counts from the first frame's host time, like time")
    }

    func testSettingUpStartsFrameTimeOver() throws {
        let renderer = try makeRenderer()
        _ = renderer.advanceFrameTime(hostTime: 100, presentationHostTime: nil)
        _ = renderer.advanceFrameTime(hostTime: 101, presentationHostTime: nil)

        renderer.isSetup = true
        XCTAssertEqual(renderer.frameTime, .zero)

        let frame = renderer.advanceFrameTime(hostTime: 500, presentationHostTime: nil)
        XCTAssertEqual(frame.frameNumber, 0)
        XCTAssertEqual(frame.time, 0)
        XCTAssertEqual(frame.deltaTime, 0)
    }
}
