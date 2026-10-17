//
//  FrameTime.swift
//  Satin
//

import Foundation
import QuartzCore

/// The one time a frame is rendered at, made once per frame by whatever drives rendering and
/// passed in: nothing that renders a frame reads a clock of its own. Everything rendered in a
/// frame shares it, however many times that frame draws.
///
/// A render loop with a display link builds each frame from the link's timestamps, which are
/// authoritative. A driver without a clock of its own, such as an offline render, starts with
/// `first(...)` and steps with `next(time:...)`, deciding only each frame's `time`.
public struct FrameTime: Hashable, Sendable {
    /// Seconds since the renderer's first frame.
    public let time: TimeInterval

    /// Seconds between this frame's `time` and the previous frame's; 0 on the first frame.
    public let deltaTime: TimeInterval

    /// When this frame is expected on screen, on the same timeline as `time`. Nil when the frame
    /// is not displayed. It leads `time` when the render loop knows its presentation time.
    public let displayTime: TimeInterval?

    /// Wall-clock seconds (`Date.timeIntervalSinceReferenceDate`) when the frame was made, for
    /// consumers that want calendar time. Not for animation: the wall clock can jump.
    public let systemTime: TimeInterval

    /// The host clock (`CACurrentMediaTime`) time this frame targets.
    public let hostMediaTime: TimeInterval

    /// Counts frames from 0, once per frame.
    public let frameNumber: Int

    public init(time: TimeInterval, deltaTime: TimeInterval, displayTime: TimeInterval?, systemTime: TimeInterval, hostMediaTime: TimeInterval, frameNumber: Int) {
        self.time = time
        self.deltaTime = deltaTime
        self.displayTime = displayTime
        self.systemTime = systemTime
        self.hostMediaTime = hostMediaTime
        self.frameNumber = frameNumber
    }
}

public extension FrameTime {
    /// Frame 0 at time 0, with nothing stamped: a placeholder before any frame is made.
    static let zero = FrameTime(time: 0, deltaTime: 0, displayTime: nil, systemTime: 0, hostMediaTime: 0, frameNumber: 0)

    /// Frame 0 at `time` (0 unless the render starts later), for a driver without a clock of its
    /// own. `hostMediaTime` defaults to now.
    static func first(time: TimeInterval = 0, displayTime: TimeInterval? = nil, hostMediaTime: TimeInterval = CACurrentMediaTime()) -> FrameTime {
        FrameTime(
            time: time,
            deltaTime: 0,
            displayTime: displayTime,
            systemTime: Date.timeIntervalSinceReferenceDate,
            hostMediaTime: hostMediaTime,
            frameNumber: 0
        )
    }

    /// The frame after this one, at `time` on this frame's timeline, for a driver without a clock
    /// of its own: `deltaTime` and `frameNumber` follow from this frame. `hostMediaTime` defaults
    /// to now.
    func next(time: TimeInterval, displayTime: TimeInterval? = nil, hostMediaTime: TimeInterval = CACurrentMediaTime()) -> FrameTime {
        FrameTime(
            time: time,
            deltaTime: time - self.time,
            displayTime: displayTime,
            systemTime: Date.timeIntervalSinceReferenceDate,
            hostMediaTime: hostMediaTime,
            frameNumber: frameNumber + 1
        )
    }
}
