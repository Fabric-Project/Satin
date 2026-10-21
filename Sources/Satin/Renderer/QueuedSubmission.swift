import Darwin
import Dispatch
import Metal

/// Shared scheduling for producer-recorded scenes, effects and compute work.
/// A permit covers this encoder's submission, not an entire frame or its downstream readers.
enum QueuedSubmission {
    final class Admission {
        private let semaphore: DispatchSemaphore

        init(limit: Int) {
            precondition(limit > 0, "Queued submissions require a positive admission limit")
            semaphore = DispatchSemaphore(value: limit)
        }

        fileprivate func acquire() { semaphore.wait() }
        fileprivate func release() { semaphore.signal() }
    }

    /// Called on the sole producer before recording, updates or other preparation side effects.
    static func begin(commandBuffer: MTLCommandBuffer, renderQueue: DispatchQueue, admission: Admission) throws -> MTLCommandBuffer {
        guard commandBuffer.status == .notEnqueued else { throw SubmissionError.commandBufferAlreadyEnqueued }
        dispatchPrecondition(condition: .notOnQueue(renderQueue))
        RecordingProfile.begin(.admissionWait)
        admission.acquire()
        RecordingProfile.end()
        RecordingProfile.noteQueuedSubmission()
        guard let satinBuffer = commandBuffer.commandQueue.makeCommandBuffer() else {
            admission.release()
            throw SubmissionError.commandBufferUnavailable
        }
        return satinBuffer
    }

    /// Reserve GPU order on the producer. Commit order on different CPU queues cannot change it.
    /// This owns the recording exclusively: it cannot be independently encoded or
    /// abandoned by another caller. No encoder/scene state is captured by either closure.
    static func schedule(_ commands: RecordedGPUCommands, satinBuffer: MTLCommandBuffer, renderQueue: DispatchQueue, admission: Admission) {
        satinBuffer.enqueue()
        satinBuffer.addCompletedHandler { _ in admission.release() }
        renderQueue.async {
            // Only single-use violations throw; this recording was exclusively transferred.
            // Still commit on a handled failure so no enqueued buffer strands later GPU work.
            let started = RecordingProfile.isEnabled ? mach_absolute_time() : 0
            try? commands.encode(into: satinBuffer)
            if RecordingProfile.isEnabled { RecordingProfile.addWorkerReplay(mach_absolute_time() - started) }
            satinBuffer.commit()
        }
    }

    /// Only for preparation failure, before schedule reserves the buffer's GPU queue position.
    static func cancel(satinBuffer: MTLCommandBuffer, admission: Admission) {
        precondition(satinBuffer.status == .notEnqueued, "An enqueued submission must be committed")
        admission.release()
    }
}
