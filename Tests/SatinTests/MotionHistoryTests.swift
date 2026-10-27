@testable import Satin
import Metal
import simd
import XCTest

/// Motion is per occurrence: a renderable's kth occurrence in a frame pairs with its kth occurrence
/// in the frame before, every pass of an occurrence shares one sample, ordinals with no history start
/// still, and a camera's previous view-projection advances once per frame.
final class MotionHistoryTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func makeMesh() -> Mesh {
        Mesh(context: context, geometry: BoxGeometry(context: context), material: nil)
    }

    private func translation(_ x: Float) -> simd_float4x4 {
        simd_float4x4(translation: [x, 0, 0])
    }

    private let frame0 = FrameTime.zero
    private var frame1: FrameTime { frame0.next(time: 1.0 / 60.0) }
    private var frame2: FrameTime { frame1.next(time: 2.0 / 60.0) }

    func testAnOccurrencePairsWithTheSameOrdinalLastFrame() {
        let mesh = makeMesh()
        mesh.position = [1, 0, 0]
        mesh.beginOccurrence(frame: frame0)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, mesh.occurrence.modelMatrix, "a first frame has no motion")

        mesh.position = [2, 0, 0]
        mesh.beginOccurrence(frame: frame1)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, translation(1))
        XCTAssertEqual(mesh.occurrence.modelMatrix, translation(2))
    }

    func testEveryPassOfAnOccurrenceReadsOneSample() {
        let mesh = makeMesh()
        mesh.position = [1, 0, 0]
        mesh.beginOccurrence(frame: frame0)
        mesh.position = [2, 0, 0]
        mesh.beginOccurrence(frame: frame1)

        // Shadow, face and colour passes read the occurrence without advancing it.
        let shadowPass = mesh.occurrence
        let colorPass = mesh.occurrence
        XCTAssertEqual(shadowPass.previousModelMatrix, translation(1))
        XCTAssertEqual(colorPass.previousModelMatrix, translation(1), "a second pass doesn't erase the motion")
    }

    func testNOccurrencesInAFrameKeepNHistories() {
        let mesh = makeMesh()
        for x: Float in [1, 10] {
            mesh.position = [x, 0, 0]
            mesh.beginOccurrence(frame: frame0)
        }

        mesh.position = [2, 0, 0]
        mesh.beginOccurrence(frame: frame1)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, translation(1))
        mesh.position = [11, 0, 0]
        mesh.beginOccurrence(frame: frame1)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, translation(10), "the second occurrence pairs with last frame's second")
    }

    func testAnExtraOrdinalStartsStill() {
        let mesh = makeMesh()
        mesh.position = [1, 0, 0]
        mesh.beginOccurrence(frame: frame0)

        mesh.beginOccurrence(frame: frame1)
        mesh.position = [5, 0, 0]
        mesh.beginOccurrence(frame: frame1)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, mesh.occurrence.modelMatrix, "no occurrence last frame to pair with")
    }

    func testFewerOccurrencesDropTheStaleSamples() {
        let mesh = makeMesh()
        for x: Float in [1, 10] {
            mesh.position = [x, 0, 0]
            mesh.beginOccurrence(frame: frame0)
        }
        mesh.position = [2, 0, 0]
        mesh.beginOccurrence(frame: frame1)

        // Frame 2's second occurrence has no frame-1 second occurrence: it starts still rather than
        // pairing with frame 0's.
        mesh.beginOccurrence(frame: frame2)
        mesh.position = [12, 0, 0]
        mesh.beginOccurrence(frame: frame2)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, mesh.occurrence.modelMatrix)
    }

    func testASkippedFrameStartsStill() {
        let mesh = makeMesh()
        mesh.position = [1, 0, 0]
        mesh.beginOccurrence(frame: frame0)

        mesh.position = [3, 0, 0]
        mesh.beginOccurrence(frame: frame2)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, translation(3), "not drawn in frame 1: no motion to report")
    }

    func testResetMotionStartsTheNextOccurrencesStill() {
        let mesh = makeMesh()
        mesh.position = [1, 0, 0]
        mesh.beginOccurrence(frame: frame0)

        mesh.resetMotion()
        mesh.position = [2, 0, 0]
        mesh.beginOccurrence(frame: frame1)
        XCTAssertEqual(mesh.occurrence.previousModelMatrix, translation(2))
    }

    func testACamerasPreviousViewProjectionAdvancesOncePerFrame() {
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let first = camera.viewProjectionMatrix
        _ = camera.previousViewProjectionMatrix(frame: frame0)

        camera.position = [1, 0, 5]
        XCTAssertEqual(camera.previousViewProjectionMatrix(frame: frame1), first)
        XCTAssertEqual(camera.previousViewProjectionMatrix(frame: frame1), first, "every pass in a frame reads the same previous value")
    }

    func testCameraCutResetsMotionEvenWithinTheCurrentFrame() {
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        _ = camera.previousViewProjectionMatrix(frame: frame0)
        camera.position = [100, 0, 5]
        _ = camera.previousViewProjectionMatrix(frame: frame1)
        camera.resetMotion()
        let cut = camera.viewProjectionMatrix
        XCTAssertEqual(camera.previousViewProjectionMatrix(frame: frame1), cut)
        camera.position = [101, 0, 5]
        XCTAssertEqual(camera.previousViewProjectionMatrix(frame: frame1), cut)
        XCTAssertEqual(camera.previousViewProjectionMatrix(frame: frame2), cut)
    }

    func testDroppingAnOccurrencePreservesSurvivingOrdinals() {
        let mesh = makeMesh()
        for x: Float in [1, 10, 100] {
            mesh.position = [x, 0, 0]
            mesh.beginOccurrence(frame: frame0)
        }
        for (current, previous): (Float, Float) in [(2, 1), (11, 10)] {
            mesh.position = [current, 0, 0]
            mesh.beginOccurrence(frame: frame1)
            XCTAssertEqual(mesh.occurrence.previousModelMatrix, translation(previous))
        }
    }

    func testGroupedHistoryRejectsChangedCountsAndSkippedFrames() {
        var history = MotionHistory<Int>()
        history.beginOccurrence(frameNumber: 0, sampleCount: 2)
        XCTAssertEqual(history.record(1), 1)
        XCTAssertEqual(history.record(2), 2)
        history.beginOccurrence(frameNumber: 1, sampleCount: 1)
        XCTAssertEqual(history.record(10), 10)
        history.beginOccurrence(frameNumber: 2, sampleCount: 1)
        XCTAssertEqual(history.record(11), 10)
        history.beginOccurrence(frameNumber: 4, sampleCount: 1)
        XCTAssertEqual(history.record(12), 12)
    }
}
