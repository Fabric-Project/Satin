//
//  TimeDriven.swift
//  Satin
//

/// Something posed by a time in seconds: a skeleton, a set of animated objects. Each can be
/// driven on its own clock, or all of an asset's together through `AssetAnimation`.
///
/// Set the time at most once per frame: each change makes the outgoing pose last frame's, for
/// velocity.
public protocol TimeDriven: AnyObject {
    /// The seconds the animation spans; nil when nothing is keyed.
    var timeRange: ClosedRange<Double>? { get }
    func setTime(_ time: Double)
}
