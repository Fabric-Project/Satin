//
//  TransformAnimation.swift
//  Satin
//

import simd

/// Keyed transforms for a set of targets, named by path: a USD `SkelAnimation`'s joints, or a
/// scene's animated objects. Each target has a translation, rotation and scale per key; each
/// channel keeps its own key times, since files key them independently.
///
/// Sampling is linear for translation and scale and shortest-arc spherical for rotation, and
/// holds the first and last keys outside the keyed range. It allocates nothing: `sample(at:)`
/// finds the keys around a time once, and `transform(of:in:fallback:)` reads any target there.
public struct TransformAnimation {
    /// One channel's keys, stored flat: target `t` at key `k` is `values[k * targetCount + t]`.
    public struct Channel<Value> {
        /// Ascending, in seconds.
        public let keyTimes: [Double]
        public let values: [Value]
        public let targetCount: Int

        /// Keys past the values given are dropped.
        public init(keyTimes: [Double], values: [Value], targetCount: Int) {
            let keyCount = targetCount > 0 ? min(keyTimes.count, values.count / targetCount) : 0
            self.keyTimes = Array(keyTimes.prefix(keyCount))
            self.values = Array(values.prefix(keyCount * targetCount))
            self.targetCount = keyCount > 0 ? targetCount : 0
        }

        public static var empty: Channel { Channel(keyTimes: [], values: [], targetCount: 0) }

        public var isEmpty: Bool { keyTimes.isEmpty }

        /// The keys on either side of `time` and how far `time` lies between them, holding the
        /// first and last keys outside the keyed range; nil without keys.
        public func surroundingKeys(at time: Double) -> Keys? {
            guard let first = keyTimes.first, let last = keyTimes.last else { return nil }
            if time <= first { return Keys(lower: 0, upper: 0, fraction: 0) }
            if time >= last { return Keys(lower: keyTimes.count - 1, upper: keyTimes.count - 1, fraction: 0) }
            // The first key after `time`; binary search, since keys are ascending.
            var low = 0, high = keyTimes.count - 1
            while low < high {
                let middle = (low + high) / 2
                if keyTimes[middle] <= time { low = middle + 1 } else { high = middle }
            }
            let span = keyTimes[low] - keyTimes[low - 1]
            return Keys(lower: low - 1, upper: low, fraction: span > 0 ? Float((time - keyTimes[low - 1]) / span) : 0)
        }

        func lowerValue(of target: Int, at keys: Keys) -> Value { values[keys.lower * targetCount + target] }
        func upperValue(of target: Int, at keys: Keys) -> Value { values[keys.upper * targetCount + target] }
    }

    /// Two neighboring keys of a channel and how far between them a time lies.
    public struct Keys: Equatable {
        public let lower: Int
        public let upper: Int
        public let fraction: Float
    }

    /// Each channel's keys around one time; nil for a channel without keys.
    public struct Sample {
        public let translationKeys: Keys?
        public let rotationKeys: Keys?
        public let scaleKeys: Keys?
    }

    /// What each target is, in the order of each key's values.
    public let paths: [String]
    public let translations: Channel<simd_float3>
    public let rotations: Channel<simd_quatf>
    public let scales: Channel<simd_float3>

    public init(paths: [String], translations: Channel<simd_float3>, rotations: Channel<simd_quatf>, scales: Channel<simd_float3>) {
        self.paths = paths
        self.translations = translations
        self.rotations = rotations
        self.scales = scales
    }

    /// From the earliest key of any channel to the latest; nil when nothing is keyed.
    public var timeRange: ClosedRange<Double>? {
        let keyTimes = [translations.keyTimes, rotations.keyTimes, scales.keyTimes]
        guard let start = keyTimes.compactMap(\.first).min(), let end = keyTimes.compactMap(\.last).max() else { return nil }
        return start ... end
    }

    public func sample(at time: Double) -> Sample {
        Sample(
            translationKeys: translations.surroundingKeys(at: time),
            rotationKeys: rotations.surroundingKeys(at: time),
            scaleKeys: scales.surroundingKeys(at: time)
        )
    }

    /// One target's transform at a sample. A channel without keys, or without this target,
    /// keeps `fallback`'s component.
    public func transform(of target: Int, in sample: Sample, fallback: TransformComponents) -> simd_float4x4 {
        var components = fallback
        if let keys = sample.translationKeys, target < translations.targetCount {
            components.translation = simd_mix(translations.lowerValue(of: target, at: keys), translations.upperValue(of: target, at: keys), simd_float3(repeating: keys.fraction))
        }
        if let keys = sample.rotationKeys, target < rotations.targetCount {
            components.rotation = simd_slerp(rotations.lowerValue(of: target, at: keys), rotations.upperValue(of: target, at: keys), keys.fraction)
        }
        if let keys = sample.scaleKeys, target < scales.targetCount {
            components.scale = simd_mix(scales.lowerValue(of: target, at: keys), scales.upperValue(of: target, at: keys), simd_float3(repeating: keys.fraction))
        }
        return components.matrix
    }
}

/// A transform as translation, rotation and scale, composed scale first, then rotation, then
/// translation, as USD composes a joint's transform.
public struct TransformComponents: Equatable {
    public var translation: simd_float3
    public var rotation: simd_quatf
    public var scale: simd_float3

    public init(translation: simd_float3 = .zero, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: simd_float3 = .one) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    /// Decomposes a matrix without shear; a sheared matrix loses its shear. A mirrored matrix
    /// (negative determinant) keeps its handedness as a negative x scale.
    public init(matrix: simd_float4x4) {
        var xAxis = simd_make_float3(matrix.columns.0)
        let yAxis = simd_make_float3(matrix.columns.1)
        let zAxis = simd_make_float3(matrix.columns.2)
        var scale = simd_float3(simd_length(xAxis), simd_length(yAxis), simd_length(zAxis))
        if simd_dot(simd_cross(xAxis, yAxis), zAxis) < 0 {
            scale.x = -scale.x
            xAxis = -xAxis
        }
        let safeScale = simd_max(simd_abs(scale), simd_float3(repeating: .leastNormalMagnitude))
        self.init(
            translation: simd_make_float3(matrix.columns.3),
            rotation: simd_quatf(simd_float3x3(xAxis / safeScale.x, yAxis / safeScale.y, zAxis / safeScale.z)),
            scale: scale
        )
    }

    public var matrix: simd_float4x4 {
        var matrix = simd_float4x4(simd_normalize(rotation))
        matrix.columns.0 *= scale.x
        matrix.columns.1 *= scale.y
        matrix.columns.2 *= scale.z
        matrix.columns.3 = simd_float4(translation, 1)
        return matrix
    }
}
