//
//  PolylineSimplify.swift
//  Satin
//

import simd

/// Ramer-Douglas-Peucker: drops the points whose removal moves the line by no more than
/// `tolerance`, measured to the kept segment around them, so the first and last points and
/// the overall shape stay. A closed polyline is split at the point farthest from its first,
/// so neither side of the loop flattens. Returns `points` unchanged for a tolerance of 0
/// or less, or two points or fewer.
public func simplifyPolyline(_ points: ContiguousArray<simd_float3>, tolerance: Float,
                             closed: Bool = false) -> ContiguousArray<simd_float3> {
    guard tolerance > 0, points.count > 2 else { return points }
    let toleranceSquared = tolerance * tolerance
    var keep = [Bool](repeating: false, count: points.count)

    if closed {
        var splitIndex = 0
        var farthestDistanceSquared: Float = -1
        for pointIndex in points.indices {
            let distanceSquared = simd_distance_squared(points[pointIndex], points[0])
            if distanceSquared > farthestDistanceSquared {
                farthestDistanceSquared = distanceSquared
                splitIndex = pointIndex
            }
        }
        // The second half runs past the last point back to the first: index `count` is point 0.
        markDouglasPeuckerPoints(points, from: 0, to: splitIndex, toleranceSquared: toleranceSquared, keep: &keep)
        markDouglasPeuckerPoints(points, from: splitIndex, to: points.count, toleranceSquared: toleranceSquared, keep: &keep)
    } else {
        markDouglasPeuckerPoints(points, from: 0, to: points.count - 1, toleranceSquared: toleranceSquared, keep: &keep)
    }

    var simplified = ContiguousArray<simd_float3>()
    simplified.reserveCapacity(points.count)
    for pointIndex in points.indices where keep[pointIndex] {
        simplified.append(points[pointIndex])
    }
    return simplified
}

/// Marks the points between `first` and `last` (indices wrap past the end) that stay, working
/// through an explicit stack of ranges so a long polyline cannot overflow the call stack.
private func markDouglasPeuckerPoints(_ points: ContiguousArray<simd_float3>, from first: Int, to last: Int,
                                      toleranceSquared: Float, keep: inout [Bool]) {
    let count = points.count
    var ranges: [(first: Int, last: Int)] = [(first, last)]
    while let range = ranges.popLast() {
        keep[range.first % count] = true
        keep[range.last % count] = true
        guard range.last - range.first > 1 else { continue }

        let segmentStart = points[range.first % count]
        let segmentEnd = points[range.last % count]
        var farthestIndex = range.first
        var farthestDistanceSquared: Float = 0
        for pointIndex in (range.first + 1) ..< range.last {
            let distanceSquared = distanceSquaredToSegment(points[pointIndex % count], segmentStart, segmentEnd)
            if distanceSquared > farthestDistanceSquared {
                farthestDistanceSquared = distanceSquared
                farthestIndex = pointIndex
            }
        }
        if farthestDistanceSquared > toleranceSquared {
            ranges.append((range.first, farthestIndex))
            ranges.append((farthestIndex, range.last))
        }
    }
}

/// To the segment, not its infinite line, so a path that doubles back keeps its turn.
private func distanceSquaredToSegment(_ point: simd_float3, _ segmentStart: simd_float3, _ segmentEnd: simd_float3) -> Float {
    let segment = segmentEnd - segmentStart
    let lengthSquared = simd_length_squared(segment)
    let fraction = lengthSquared > 0 ? simd_clamp(simd_dot(point - segmentStart, segment) / lengthSquared, 0, 1) : 0
    return simd_distance_squared(point, segmentStart + fraction * segment)
}
