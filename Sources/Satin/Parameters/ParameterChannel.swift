//
//  ParameterChannel.swift
//  Satin
//

import Foundation

/// A parameter that a `ParameterChannel` moves values for. The flags are the channel's, read and
/// written only under its lock.
protocol ParameterChannelMember: AnyObject {
    var isQueuedForApply: Bool { get set }
    var isQueuedForPublish: Bool { get set }
    func attach(to channel: ParameterChannel?)
    /// On the owner: applies the values the UI submitted, if `channel` is still the member's.
    func applySubmittedValues(from channel: ParameterChannel)
    /// On the main thread: copies what the owner last set into the main-thread mirror, if
    /// `channel` is still the member's.
    func publishToMain(from channel: ParameterChannel)
}

/// Moves a parameter group's values between the main thread and the queue that owns the group.
///
/// UI writes are kept per parameter until one block on `renderQueue` applies them all; values the
/// owner sets are kept until one block on the main thread copies them into the mirrors. A burst of
/// writes in either direction costs one block per group, however many values it carries. The
/// lists swap with the drain's own, so nothing allocates once both have grown.
final class ParameterChannel {
    let renderQueue: DispatchQueue
    let lock = UnfairLock()

    private var toApply = ContiguousArray<any ParameterChannelMember>()
    private var applying = ContiguousArray<any ParameterChannelMember>()
    private var isApplyScheduled = false

    private var toPublish = ContiguousArray<any ParameterChannelMember>()
    private var publishing = ContiguousArray<any ParameterChannelMember>()
    private var isPublishScheduled = false

    init(renderQueue: DispatchQueue) {
        self.renderQueue = renderQueue
    }

    /// From the UI, after `member` stored a submitted value: applies it on the owner soon.
    func scheduleApply(_ member: any ParameterChannelMember) {
        let schedules = lock.sync {
            if !member.isQueuedForApply {
                member.isQueuedForApply = true
                toApply.append(member)
            }
            guard !isApplyScheduled else { return false }
            isApplyScheduled = true
            return true
        }
        if schedules { renderQueue.async { self.applySubmitted() } }
    }

    /// From the owner, after `member` stored a value it set: publishes it on main soon.
    func schedulePublish(_ member: any ParameterChannelMember) {
        let schedules = lock.sync {
            if !member.isQueuedForPublish {
                member.isQueuedForPublish = true
                toPublish.append(member)
            }
            guard !isPublishScheduled else { return false }
            isPublishScheduled = true
            return true
        }
        if schedules { DispatchQueue.main.async { self.publishChanges() } }
    }

    private func applySubmitted() {
        lock.sync {
            swap(&toApply, &applying)
            isApplyScheduled = false
            for member in applying { member.isQueuedForApply = false }
        }
        for member in applying { member.applySubmittedValues(from: self) }
        applying.removeAll(keepingCapacity: true)
    }

    private func publishChanges() {
        lock.sync {
            swap(&toPublish, &publishing)
            isPublishScheduled = false
            for member in publishing { member.isQueuedForPublish = false }
        }
        for member in publishing { member.publishToMain(from: self) }
        publishing.removeAll(keepingCapacity: true)
    }
}
