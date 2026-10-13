//
//  ObjectAnimation.swift
//  Satin
//

import simd

/// Moves objects by keyed transforms: `animation`'s target `i` is `objects[i]`'s local
/// transform. A channel the animation does not key keeps the object's transform from when the
/// animation was made.
public final class ObjectAnimation: TimeDriven {
    public let objects: [Object]
    public let animation: TransformAnimation

    private let initialDecompositions: [simd_float4x4.Decomposition]

    public init(objects: [Object], animation: TransformAnimation) {
        self.objects = objects
        self.animation = animation
        initialDecompositions = objects.map(\.localMatrix.decomposed)
    }

    public var timeRange: ClosedRange<Double>? { animation.timeRange }

    public func setTime(_ time: Double) {
        let sample = animation.sample(at: time)
        for (objectIndex, object) in objects.enumerated() {
            object.localMatrix = animation.transform(of: objectIndex, in: sample, fallback: initialDecompositions[objectIndex])
        }
    }
}
