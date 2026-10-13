//
//  AssetAnimation.swift
//  Satin
//

/// Everything in a loaded asset that moves over time: its skeletons and its animated objects.
/// `setTime` sets them all to one time; set each element's time yourself to run them on
/// separate clocks.
public final class AssetAnimation: TimeDriven {
    public let skeletons: [Skeleton]
    /// Nil when no object's transform is animated.
    public let objectAnimation: ObjectAnimation?
    /// The asset's own time range when it states one; otherwise the span of every element's keys.
    public let timeRange: ClosedRange<Double>?

    public init(skeletons: [Skeleton], objectAnimation: ObjectAnimation?, timeRange: ClosedRange<Double>? = nil) {
        self.skeletons = skeletons
        self.objectAnimation = objectAnimation
        let elementRanges = (skeletons.map(\.timeRange) + [objectAnimation?.timeRange]).compactMap { $0 }
        if let timeRange {
            self.timeRange = timeRange
        } else if let start = elementRanges.map(\.lowerBound).min(), let end = elementRanges.map(\.upperBound).max() {
            self.timeRange = start ... end
        } else {
            self.timeRange = nil
        }
    }

    /// Each element, in the order `setTime` sets them: objects first, then skeletons.
    public var elements: [any TimeDriven] {
        (objectAnimation.map { [$0] } ?? []) + skeletons
    }

    public func setTime(_ time: Double) {
        objectAnimation?.setTime(time)
        for skeleton in skeletons {
            skeleton.setTime(time)
        }
    }
}
