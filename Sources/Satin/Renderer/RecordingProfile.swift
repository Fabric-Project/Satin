//
//  RecordingProfile.swift
//  Satin
//

import Darwin
import Foundation

/// Development profiling: where Satin's drawing time goes, per frame.
///
/// Exclusive time per recording category: time spent inside a nested category counts only for that
/// category, never for the one around it, so the categories add up to the drawing time.
/// Enabled by launching with `SATIN_RECORDING_PROFILE=1`; otherwise every marker is one branch.
/// Prints average milliseconds and calls per frame every `reportInterval` frames.
///
/// Markers assume one drawing thread.
/// Absolute numbers swing with CPU clock state between runs: compare proportions within one run, or
/// toggle the mode being compared mid-run.
enum RecordingProfile {
    enum Category: Int, CaseIterable {
        /// `update` / `onUpdate`, traversal, `encode(in:)` GPU preparation and motion samples.
        case updateAndTraversal
        /// Testing renderables against colour views.
        case colourCulling
        /// Testing shadow casters against shadow passes.
        case shadowCulling
        /// Renderable, material and geometry `draw(in:)` bodies, including their packet appends.
        case hooks
        /// Reserving per-view vertex uniforms; they're written when the submission encodes, inside
        /// replay.
        case vertexUniforms
        /// Runs, route entries and render-order sorting.
        case bookkeeping
        /// The rest of a scene draw: lights, pass planning, descriptors and sealing.
        case scenePlanning
        /// The rest of an effect draw: compute recording, child and quad preparation.
        case effects
        /// Packet replay into Metal encoders.
        case replay

        var label: String {
            switch self {
                case .updateAndTraversal: "update & traversal"
                case .colourCulling: "colour culling"
                case .shadowCulling: "shadow culling"
                case .hooks: "draw(in:) hooks"
                case .vertexUniforms: "vertex uniforms (reserve)"
                case .bookkeeping: "bookkeeping"
                case .scenePlanning: "scene planning (rest)"
                case .effects: "effects (rest)"
                case .replay: "replay"
            }
        }
    }

    static let isEnabled = ProcessInfo.processInfo.environment["SATIN_RECORDING_PROFILE"] != nil
    static let reportInterval = 120

    private nonisolated(unsafe) static var stack: ContiguousArray<Category> = {
        var stack = ContiguousArray<Category>()
        stack.reserveCapacity(16)
        return stack
    }()
    private nonisolated(unsafe) static var segmentStart: UInt64 = 0
    private nonisolated(unsafe) static var totals = [UInt64](repeating: 0, count: Category.allCases.count)
    private nonisolated(unsafe) static var calls = [Int](repeating: 0, count: Category.allCases.count)
    private nonisolated(unsafe) static var lastFrameNumber: Int?
    private nonisolated(unsafe) static var frames = 0

    @inline(__always)
    static func begin(_ category: Category) {
        guard isEnabled else { return }
        let now = mach_absolute_time()
        if let top = stack.last { totals[top.rawValue] &+= now &- segmentStart }
        stack.append(category)
        calls[category.rawValue] += 1
        segmentStart = now
    }

    @inline(__always)
    static func end() {
        guard isEnabled, let top = stack.last else { return }
        let now = mach_absolute_time()
        totals[top.rawValue] &+= now &- segmentStart
        stack.removeLast()
        segmentStart = now
    }

    /// Called by each draw with its frame: counts distinct frames and reports every interval.
    static func noteFrame(_ frameNumber: Int) {
        guard isEnabled, stack.isEmpty, lastFrameNumber != frameNumber else { return }
        lastFrameNumber = frameNumber
        frames += 1
        if frames > reportInterval { report() }
    }

    private static func milliseconds(_ ticks: UInt64) -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
    }

    private static func report() {
        let frameCount = Double(frames - 1)
        var lines = ["Satin recording profile: \(frames - 1) frames"]
        var total = 0.0
        for category in Category.allCases {
            let perFrame = milliseconds(totals[category.rawValue]) / frameCount
            total += perFrame
            lines.append(String(format: "  %-24@ %7.3f ms/frame  %8.1f calls/frame", category.label as NSString,
                                perFrame, Double(calls[category.rawValue]) / frameCount))
        }
        lines.append(String(format: "  %-24@ %7.3f ms/frame", "total" as NSString, total))
        print(lines.joined(separator: "\n"))

        for index in totals.indices {
            totals[index] = 0
            calls[index] = 0
        }
        frames = 1
    }
}
