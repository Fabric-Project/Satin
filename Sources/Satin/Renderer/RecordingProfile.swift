//
//  RecordingProfile.swift
//  Satin
//

import Darwin
import Foundation

/// Development profiling: where Satin's producer (main) and encode-queue time goes, per frame.
///
/// Exclusive time per recording category: time spent inside a nested category counts only for that
/// category, never for the one around it, so the categories add up to the producer's drawing time.
/// Enabled by launching with `SATIN_RECORDING_PROFILE=1`; otherwise every marker is one branch.
/// Prints average milliseconds and calls per frame every `reportInterval` frames.
///
/// Producer markers assume one producer thread. Worker replay is timed separately, under a lock.
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
        /// Writing per-view vertex uniforms.
        case vertexUniforms
        /// Runs, route entries and render-order sorting.
        case bookkeeping
        /// The rest of a scene draw: lights, pass planning, descriptors, sealing and scheduling.
        case scenePlanning
        /// The rest of an effect draw: compute recording, child and quad preparation.
        case effects
        /// Packet replay into Metal encoders on the producer (no `renderQueue`).
        case producerReplay
        /// Waiting for a queued-submission permit.
        case admissionWait

        var label: String {
            switch self {
                case .updateAndTraversal: "update & traversal"
                case .colourCulling: "colour culling"
                case .shadowCulling: "shadow culling"
                case .hooks: "draw(in:) hooks"
                case .vertexUniforms: "vertex uniforms"
                case .bookkeeping: "bookkeeping"
                case .scenePlanning: "scene planning (rest)"
                case .effects: "effects (rest)"
                case .producerReplay: "replay on producer"
                case .admissionWait: "admission wait"
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
    private nonisolated(unsafe) static var queuedSubmissions = 0

    private static let workerLock = UnfairLock()
    private nonisolated(unsafe) static var workerReplay: UInt64 = 0
    private nonisolated(unsafe) static var workerSubmissions = 0

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

    static func noteQueuedSubmission() {
        guard isEnabled else { return }
        queuedSubmissions += 1
    }

    /// Worker-side replay of one queued submission.
    static func addWorkerReplay(_ duration: UInt64) {
        guard isEnabled else { return }
        workerLock.sync {
            workerReplay &+= duration
            workerSubmissions += 1
        }
    }

    private static func milliseconds(_ ticks: UInt64) -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
    }

    private static func report() {
        let frameCount = Double(frames - 1)
        let (replay, replayed) = workerLock.sync { (workerReplay, workerSubmissions) }
        var lines = ["Satin recording profile: \(frames - 1) frames, \(queuedSubmissions) queued submissions"]
        var producerTotal = 0.0
        for category in Category.allCases {
            let perFrame = milliseconds(totals[category.rawValue]) / frameCount
            producerTotal += perFrame
            lines.append(String(format: "  %-24@ %7.3f ms/frame  %8.1f calls/frame", category.label as NSString,
                                perFrame, Double(calls[category.rawValue]) / frameCount))
        }
        lines.append(String(format: "  %-24@ %7.3f ms/frame", "producer total" as NSString, producerTotal))
        lines.append(String(format: "  %-24@ %7.3f ms/frame  %8.1f submissions/frame", "worker replay" as NSString,
                            milliseconds(replay) / frameCount, Double(replayed) / frameCount))
        print(lines.joined(separator: "\n"))

        for index in totals.indices {
            totals[index] = 0
            calls[index] = 0
        }
        frames = 1
        queuedSubmissions = 0
        workerLock.sync {
            workerReplay = 0
            workerSubmissions = 0
        }
    }
}
