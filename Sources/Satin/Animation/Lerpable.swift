//
//  Lerpable.swift
//  Satin
//

import simd

/// A value that interpolates between two others: `t` 0 gives `from`, 1 gives `to`. `t` is not
/// clamped, so an easing that overshoots (back, elastic) extrapolates. Shape `t` with `Easing`
/// first to ease the motion.
public protocol Lerpable {
    static func lerp(_ from: Self, _ to: Self, _ t: Float) -> Self
}

extension Float: Lerpable {
    public static func lerp(_ from: Float, _ to: Float, _ t: Float) -> Float {
        simd_mix(from, to, t)
    }
}

extension Double: Lerpable {
    public static func lerp(_ from: Double, _ to: Double, _ t: Float) -> Double {
        simd_mix(from, to, Double(t))
    }
}

extension simd_float2: Lerpable {
    public static func lerp(_ from: simd_float2, _ to: simd_float2, _ t: Float) -> simd_float2 {
        simd_mix(from, to, simd_float2(repeating: t))
    }
}

extension simd_float3: Lerpable {
    public static func lerp(_ from: simd_float3, _ to: simd_float3, _ t: Float) -> simd_float3 {
        simd_mix(from, to, simd_float3(repeating: t))
    }
}

extension simd_float4: Lerpable {
    public static func lerp(_ from: simd_float4, _ to: simd_float4, _ t: Float) -> simd_float4 {
        simd_mix(from, to, simd_float4(repeating: t))
    }
}

extension simd_quatf: Lerpable {
    /// Spherical, along the shorter arc.
    public static func lerp(_ from: simd_quatf, _ to: simd_quatf, _ t: Float) -> simd_quatf {
        simd_slerp(from, to, t)
    }
}

extension simd_float4x4: Lerpable {
    /// As translation, rotation and scale (`TransformComponents`): translation and scale mix and
    /// rotation slerps, so the matrices in between stay rigid instead of skewing, and a mirrored
    /// pair stays mirrored. Shear and projection are not kept; `simd_mix` the columns for those.
    public static func lerp(_ from: simd_float4x4, _ to: simd_float4x4, _ t: Float) -> simd_float4x4 {
        let start = TransformComponents(matrix: from)
        let end = TransformComponents(matrix: to)
        return TransformComponents(
            translation: .lerp(start.translation, end.translation, t),
            rotation: .lerp(start.rotation, end.rotation, t),
            scale: .lerp(start.scale, end.scale, t)
        ).matrix
    }
}
