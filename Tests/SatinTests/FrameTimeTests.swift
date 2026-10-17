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

    /// Runs one frame as the render loop does: makes it from the timestamps, then updates with it.
    private func advance(_ renderer: Renderer, hostTime: TimeInterval, presentationHostTime: TimeInterval? = nil) throws -> FrameTime {
        let frame = renderer.nextFrameTime(hostTime: hostTime, presentationHostTime: presentationHostTime)
        try renderer.update(frame: frame)
        return frame
    }

    func testUpdateStoresAFrameDrivenByHand() throws {
        let renderer = try makeRenderer()
        let frame = FrameTime.first(time: 3, hostMediaTime: 0).next(time: 3.5, hostMediaTime: 0)

        try renderer.update(frame: frame)

        XCTAssertEqual(renderer.frameTime, frame)
    }

    func testFirstFrameIsFrameZeroAtTimeZero() throws {
        let renderer = try makeRenderer()
        XCTAssertEqual(renderer.frameTime, .zero, "no frame before the first advance")

        let frame = try advance(renderer, hostTime: 100)

        XCTAssertEqual(frame.frameNumber, 0)
        XCTAssertEqual(frame.time, 0)
        XCTAssertEqual(frame.deltaTime, 0)
        XCTAssertEqual(frame.hostMediaTime, 100)
        XCTAssertEqual(renderer.frameTime, frame)
    }

    func testTimeAndDeltaFollowHostTimestamps() throws {
        let renderer = try makeRenderer()
        _ = try advance(renderer, hostTime: 100)
        let second = try advance(renderer, hostTime: 100.25)
        let third = try advance(renderer, hostTime: 100.75)

        XCTAssertEqual(second.frameNumber, 1)
        XCTAssertEqual(second.time, 0.25, accuracy: 1e-9)
        XCTAssertEqual(second.deltaTime, 0.25, accuracy: 1e-9)
        XCTAssertEqual(third.frameNumber, 2)
        XCTAssertEqual(third.time, 0.75, accuracy: 1e-9)
        XCTAssertEqual(third.deltaTime, 0.5, accuracy: 1e-9)
    }

    func testDisplayTimeSharesTheTimelineAndIsNilWhenUnknown() throws {
        let renderer = try makeRenderer()
        let undisplayed = try advance(renderer, hostTime: 100)
        let displayed = try advance(renderer, hostTime: 100.5, presentationHostTime: 100.75)

        XCTAssertNil(undisplayed.displayTime)
        let displayTime = try XCTUnwrap(displayed.displayTime)
        XCTAssertEqual(displayTime, 0.75, accuracy: 1e-9, "counts from the first frame's host time, like time")
    }

    func testSettingUpStartsFrameTimeOver() throws {
        let renderer = try makeRenderer()
        _ = try advance(renderer, hostTime: 100)
        _ = try advance(renderer, hostTime: 101)

        renderer.isSetup = true
        XCTAssertEqual(renderer.frameTime, .zero)

        let frame = try advance(renderer, hostTime: 500)
        XCTAssertEqual(frame.frameNumber, 0)
        XCTAssertEqual(frame.time, 0)
        XCTAssertEqual(frame.deltaTime, 0)
    }
}
