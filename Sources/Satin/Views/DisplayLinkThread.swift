//
//  DisplayLinkThread.swift
//  Satin
//

import Foundation
import QuartzCore

/// A thread with its own run loop that a view's display link ticks on when its renderer has a
/// `renderQueue`, so ticks keep coming while the main thread is busy. It only forwards: each tick
/// hands its frame to the renderer's queue. Work posted with `perform(_:)` runs here in order.
final class DisplayLinkThread {
    let thread: Thread
    let runLoop: RunLoop
    private let cfRunLoop: CFRunLoop

    init(name: String = "Satin Display Link") {
        let started = DispatchSemaphore(value: 0)
        let handoff = RunLoopHandoff()
        thread = Thread {
            handoff.runLoop = RunLoop.current
            handoff.cfRunLoop = CFRunLoopGetCurrent()
            // A port keeps the run loop running while no display link or work is scheduled on it.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            started.signal()
            while !Thread.current.isCancelled {
                _ = RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
        started.wait()
        runLoop = handoff.runLoop ?? .main
        cfRunLoop = handoff.cfRunLoop ?? CFRunLoopGetMain()
    }

    deinit {
        stop()
    }

    var isCurrent: Bool { Thread.current === thread }

    /// Runs `work` on this thread after everything posted before it. Never waits for it.
    func perform(_ work: @escaping () -> Void) {
        CFRunLoopPerformBlock(cfRunLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(cfRunLoop)
    }

    /// Ends the thread once the work already posted has run.
    func stop() {
        let thread = thread
        perform {
            thread.cancel()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
}

/// Carries the new thread's run loop back to `DisplayLinkThread.init`, which waits for it.
private final class RunLoopHandoff {
    var runLoop: RunLoop?
    var cfRunLoop: CFRunLoop?
}

/// What a display link ticking on a `DisplayLinkThread` draws with. Each link gets its own, and
/// only that link's thread reads or writes `drawingDelegate`: stopping a link clears it there,
/// after any tick in progress, so the view never shares state with a tick that may still run.
final class DisplayLinkTicker: NSObject {
    let metalLayer: CAMetalLayer
    /// Display link thread only.
    var drawingDelegate: ViewRendererDelegate?

    init(metalLayer: CAMetalLayer, drawingDelegate: ViewRendererDelegate?) {
        self.metalLayer = metalLayer
        self.drawingDelegate = drawingDelegate
    }
}

#if os(macOS)
extension DisplayLinkTicker: CAMetalDisplayLinkDelegate {
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        drawingDelegate?.draw(metalLayer: metalLayer, drawable: update.drawable,
                              hostTime: update.targetTimestamp, presentationHostTime: update.targetPresentationTimestamp)
    }
}
#else
extension DisplayLinkTicker {
    @objc func tick(_ displayLink: CADisplayLink) {
        guard let drawingDelegate, let drawable = metalLayer.nextDrawable() else { return }
        drawingDelegate.draw(metalLayer: metalLayer, drawable: drawable, hostTime: displayLink.timestamp,
                             presentationHostTime: displayLink.targetTimestamp)
    }
}
#endif
