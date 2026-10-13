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

    private let initialComponents: [TransformComponents]

    public init(objects: [Object], animation: TransformAnimation) {
        self.objects = objects
        self.animation = animation
        initialComponents = objects.map { TransformComponents(matrix: $0.localMatrix) }
    }

    public var timeRange: ClosedRange<Double>? { animation.timeRange }

    public func setTime(_ time: Double) {
        let sample = animation.sample(at: time)
        for (objectIndex, object) in objects.enumerated() {
            object.localMatrix = animation.transform(of: objectIndex, in: sample, fallback: initialComponents[objectIndex])
        }
    }
}
