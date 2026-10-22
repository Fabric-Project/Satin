#if os(macOS)

import AppKit
import Metal
import QuartzCore
@testable import Satin
import XCTest

/// A renderer that owns a `renderQueue` keeps drawing and presenting while the main thread is busy:
/// its view's display link ticks on a thread of its own and the renderer runs each frame on its queue. Without
/// one, frames come from main and stop while it's blocked, which is what makes the test mean
/// something. Window tests skip when the screen is locked or the display asleep.
final class RenderQueueDeliveryTests: XCTestCase {
    // MARK: - Display link thread

    func testDisplayLinkThreadRunsWorkInTheOrderPosted() {
        let displayLinkThread = DisplayLinkThread(name: "Test Display Link")
        defer { displayLinkThread.stop() }
        let lock = UnfairLock()
        var order: [Int] = []
        var ranOnThread = true
        let done = expectation(description: "all work ran")
        for index in 0 ..< 100 {
            displayLinkThread.perform {
                let isCurrent = displayLinkThread.isCurrent
                lock.sync {
                    order.append(index)
                    ranOnThread = ranOnThread && isCurrent
                }
                if index == 99 { done.fulfill() }
            }
        }
        wait(for: [done], timeout: 5)
        lock.sync {
            XCTAssertEqual(order, Array(0 ..< 100))
            XCTAssertTrue(ranOnThread)
        }
    }

    func testDisplayLinkThreadStopsAfterPostedWork() {
        let displayLinkThread = DisplayLinkThread(name: "Test Display Link")
        let ran = expectation(description: "posted work ran")
        displayLinkThread.perform { ran.fulfill() }
        displayLinkThread.stop()
        wait(for: [ran], timeout: 5)
        let deadline = Date().addingTimeInterval(5)
        while !displayLinkThread.thread.isFinished, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(displayLinkThread.thread.isFinished)
    }

    // MARK: - Main thread blocked (T1)

    func testFramesKeepPresentingOnTheQueueWhileMainIsBlocked() throws {
        let renderQueue = DispatchQueue(label: "Test Render Queue", qos: .userInteractive)
        let frames = try framesWhileMainIsBlocked(renderQueue: renderQueue)
        XCTAssertTrue(frames.drewOnQueue, "every frame should run on the renderer's queue")
        // 500 ms at 60–120 Hz is 30–60 display opportunities; ask for a third of the slowest.
        XCTAssertGreaterThanOrEqual(frames.submitted, 10, "frames submitted while main was blocked")
        XCTAssertGreaterThanOrEqual(frames.presented, 10, "frames presented while main was blocked")
    }

    func testWithoutARenderQueueFramesStopWhileMainIsBlocked() throws {
        let frames = try framesWhileMainIsBlocked(renderQueue: nil)
        XCTAssertLessThanOrEqual(frames.submitted, 1, "main delivers frames, so none start while it's blocked")
    }

    /// Detaching stops the display link on its own thread; the view then changes its delegate on
    /// main. A tick still running on the old thread must never see that write (run under TSan).
    func testDetachingAndRehostingWhileFramesRunKeepsTicksOnTheirOwnState() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderQueue = DispatchQueue(label: "Test Render Queue", qos: .userInteractive)
        let renderer = FrameRecordingRenderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                                                               depthPixelFormat: .invalid, stencilPixelFormat: .invalid),
                                              renderQueue: renderQueue)
        let controller = MetalViewController(renderer: renderer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 256, height: 256), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 256, height: 256))
        window.orderFrontRegardless()
        defer {
            controller.cleanup()
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        let warmUp = Date().addingTimeInterval(5)
        while renderer.presentedCount() < 5, Date() < warmUp {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        try XCTSkipIf(renderer.presentedCount() < 5, "no frames: the display is asleep or the screen is locked")

        let metalView = controller.metalView
        for _ in 0 ..< 20 {
            metalView.removeFromSuperview()
            metalView.delegate = nil
            metalView.delegate = renderer
            window.contentView = metalView
            window.setContentSize(NSSize(width: 256, height: 256))
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let presentedBefore = renderer.presentedCount()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertGreaterThan(renderer.presentedCount(), presentedBefore, "frames keep coming after re-hosting")
    }

    /// Shows a window drawing with `renderQueue`, waits for frames, blocks main for 500 ms, and
    /// counts the frames submitted and presented during the block.
    private func framesWhileMainIsBlocked(renderQueue: DispatchQueue?) throws -> (submitted: Int, presented: Int, drewOnQueue: Bool) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderQueue?.setSpecific(key: FrameRecordingRenderer.queueKey, value: true)
        let renderer = FrameRecordingRenderer(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                                                               depthPixelFormat: .invalid, stencilPixelFormat: .invalid),
                                              renderQueue: renderQueue)
        let controller = MetalViewController(renderer: renderer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 256, height: 256), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        // The controller's view starts at zero size, and the window takes its size from it.
        window.setContentSize(NSSize(width: 256, height: 256))
        window.orderFrontRegardless()
        defer {
            controller.cleanup()
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        let warmUp = Date().addingTimeInterval(5)
        while renderer.presentedCount() < 5, Date() < warmUp {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        try XCTSkipIf(renderer.presentedCount() < 5, "no frames: the display is asleep or the screen is locked")

        let blockStart = CACurrentMediaTime()
        Thread.sleep(forTimeInterval: 0.5)
        let blockEnd = CACurrentMediaTime()

        // Presented handlers arrive after presentation; give the last ones time to land.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return renderer.frames(from: blockStart, to: blockEnd)
    }
}

/// Clears each frame and records, under a lock, when it was submitted and presented.
private final class FrameRecordingRenderer: ViewRenderer {
    static let queueKey = DispatchSpecificKey<Bool>()

    private let lock = UnfairLock()
    private var submissionTimes: [CFTimeInterval] = []
    private var presentationTimes: [CFTimeInterval] = []
    private var drewOnQueue = true

    override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) throws {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.depthAttachment.texture = nil
        renderPassDescriptor.stencilAttachment.texture = nil
        commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)?.endEncoding()
        let now = CACurrentMediaTime()
        let isOnQueue = renderQueue == nil || DispatchQueue.getSpecific(key: Self.queueKey) == true
        lock.sync {
            submissionTimes.append(now)
            drewOnQueue = drewOnQueue && isOnQueue
        }
    }

    override func postDraw(drawable: CAMetalDrawable, commandBuffer: MTLCommandBuffer) {
        drawable.addPresentedHandler { presented in
            guard presented.presentedTime > 0 else { return }
            self.lock.sync { self.presentationTimes.append(presented.presentedTime) }
        }
        super.postDraw(drawable: drawable, commandBuffer: commandBuffer)
    }

    func presentedCount() -> Int {
        lock.sync { presentationTimes.count }
    }

    func frames(from start: CFTimeInterval, to end: CFTimeInterval) -> (submitted: Int, presented: Int, drewOnQueue: Bool) {
        lock.sync {
            (submissionTimes.filter { $0 > start && $0 < end }.count,
             presentationTimes.filter { $0 > start && $0 < end }.count,
             drewOnQueue)
        }
    }
}

#endif
