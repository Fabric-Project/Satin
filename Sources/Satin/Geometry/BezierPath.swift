//
//  BezierPath.swift
//  Satin
//

#if SWIFT_PACKAGE
import SatinCore
#endif

import simd

/// One continuous path of straight and curved segments in 3D, open or closed; a 2D path
/// keeps z at 0. Sample it into points for `PolylineGeometry`, optionally thinned with
/// `simplifyPolyline(_:tolerance:closed:)`. A shape of several separate paths is an array.
public struct BezierPath: Equatable {
    public enum Segment: Equatable {
        case line(to: simd_float3)
        case quadratic(control: simd_float3, to: simd_float3)
        case cubic(control1: simd_float3, control2: simd_float3, to: simd_float3)
    }

    public var start: simd_float3
    public var segments: [Segment]
    /// A closed path returns from its last point to `start`, straight if it is not there already.
    public var isClosed: Bool

    public init(start: simd_float3, segments: [Segment] = [], isClosed: Bool = false) {
        self.start = start
        self.segments = segments
        self.isClosed = isClosed
    }

    public mutating func addLine(to point: simd_float3) {
        segments.append(.line(to: point))
    }

    public mutating func addQuadratic(control: simd_float3, to point: simd_float3) {
        segments.append(.quadratic(control: control, to: point))
    }

    public mutating func addCubic(control1: simd_float3, control2: simd_float3, to point: simd_float3) {
        segments.append(.cubic(control1: control1, control2: control2, to: point))
    }

    /// Points along the path: every segment's end point, plus as many points inside each curve
    /// as keep the turn between neighbouring points under `angleLimit` (radians). No point
    /// repeats the one before it, and a closed path does not repeat `start` at its end.
    public func sampledPoints(angleLimit: Float = .pi / 36) -> ContiguousArray<simd_float3> {
        var points: ContiguousArray<simd_float3> = [start]
        var current = start
        for segment in segments {
            switch segment {
            case let .line(to):
                if to != current { points.append(to) }
                current = to
            case let .quadratic(control, to):
                // Raised to the cubic that traces the same curve, for one sampler.
                appendCubic(from: current, control1: current + (control - current) * (2.0 / 3.0),
                            control2: to + (control - to) * (2.0 / 3.0), to: to, angleLimit: angleLimit, into: &points)
                current = to
            case let .cubic(control1, control2, to):
                appendCubic(from: current, control1: control1, control2: control2, to: to, angleLimit: angleLimit, into: &points)
                current = to
            }
        }
        if isClosed, points.count > 1, let last = points.last, simd_distance(last, start) <= 1e-6 {
            points.removeLast()
        }
        return points
    }

    /// SatinCore's adaptive sampling of one cubic, after its first point (already in `points`).
    private func appendCubic(from: simd_float3, control1: simd_float3, control2: simd_float3, to: simd_float3,
                             angleLimit: Float, into points: inout ContiguousArray<simd_float3>) {
        var sampled = getAdaptiveCubicBezierPath3(from, control1, control2, to, angleLimit)
        defer { freePolyline3D(&sampled) }
        // A curve that is a single point samples to its two equal end points: keep neither repeat.
        for point in UnsafeBufferPointer(start: sampled.data, count: Int(sampled.count)).dropFirst() where point != points.last {
            points.append(point)
        }
    }
}
