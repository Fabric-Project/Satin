//
//  ViewFrustum.swift
//  Satin
//

import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// The side planes of one view's clip volume in world space, for skipping renderables whose world
/// bounds lie wholly outside it.
///
/// Conservative: only the four side planes are tested. Together they bound the volume in front of
/// a perspective view (a point behind the eye fails one of them) and the sides of an orthographic
/// one. Near and far are left out, so a reversed, infinite or unusual depth range can never cull
/// anything the view draws; a box is culled only when it is wholly outside one side plane.
struct ViewFrustum {
    // Each plane is (normal, distance): a point p is inside when dot(normal, p) + distance >= 0.
    private let left: simd_float4
    private let right: simd_float4
    private let bottom: simd_float4
    private let top: simd_float4

    init(viewProjectionMatrix: simd_float4x4) {
        let transposed = viewProjectionMatrix.transpose
        let rowX = transposed.columns.0
        let rowY = transposed.columns.1
        let rowW = transposed.columns.3
        // Clip space keeps -w <= x <= w and -w <= y <= w.
        left = rowW + rowX
        right = rowW - rowX
        bottom = rowW + rowY
        top = rowW - rowY
    }

    /// Whether any part of `bounds` may be inside the view. Bounds that are empty, infinite or not
    /// finite can't be judged, so they always may.
    func mayContain(_ bounds: Bounds) -> Bool {
        guard Self.isJudgeable(bounds) else { return true }
        return Self.isInside(bounds, plane: left)
            && Self.isInside(bounds, plane: right)
            && Self.isInside(bounds, plane: bottom)
            && Self.isInside(bounds, plane: top)
    }

    /// Whether `bounds` and `region` may overlap. Bounds that can't be judged always may.
    static func mayIntersect(_ bounds: Bounds, _ region: Bounds) -> Bool {
        guard isJudgeable(bounds), isJudgeable(region) else { return true }
        return all(bounds.min .<= region.max) && all(region.min .<= bounds.max)
    }

    /// Whether the corner of `bounds` furthest along the plane's normal is on its inner side.
    private static func isInside(_ bounds: Bounds, plane: simd_float4) -> Bool {
        let normal = simd_make_float3(plane)
        let furthest = bounds.min.replacing(with: bounds.max, where: normal .>= simd_float3.zero)
        return simd_dot(normal, furthest) + plane.w >= 0
    }

    private static func isJudgeable(_ bounds: Bounds) -> Bool {
        all(bounds.min .<= bounds.max)
            && bounds.min.x.isFinite && bounds.min.y.isFinite && bounds.min.z.isFinite
            && bounds.max.x.isFinite && bounds.max.y.isFinite && bounds.max.z.isFinite
    }
}
