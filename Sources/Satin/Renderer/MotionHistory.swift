//
//  MotionHistory.swift
//  Satin
//

/// Producer-owned history storage. Owners decide when an occurrence begins: once per frame for
/// cameras, once per render event for objects, or once per recorded palette/instance snapshot.
/// Samples are flat groups so recording matrices needs neither hashing nor temporary arrays.
struct MotionHistory<Sample> {
    private(set) var frameNumber: Int?
    private var previousSamples = ContiguousArray<Sample>()
    private var currentSamples = ContiguousArray<Sample>()
    private var previousGroupSize = 0
    private var currentGroupSize = 0
    private var occurrenceEnd = 0
    private var hasPrevious = false

    mutating func beginOccurrence(frameNumber: Int, sampleCount: Int = 1) {
        precondition(sampleCount >= 0)
        if self.frameNumber != frameNumber {
            if let previousFrame = self.frameNumber, previousFrame == frameNumber - 1 {
                swap(&previousSamples, &currentSamples)
                previousGroupSize = currentGroupSize
            } else {
                previousSamples.removeAll(keepingCapacity: true)
                previousGroupSize = 0
            }
            currentSamples.removeAll(keepingCapacity: true)
            self.frameNumber = frameNumber
        }
        if currentGroupSize != sampleCount {
            currentSamples.removeAll(keepingCapacity: true)
        }
        currentGroupSize = sampleCount
        occurrenceEnd = currentSamples.count + sampleCount
        hasPrevious = previousGroupSize == sampleCount && occurrenceEnd <= previousSamples.count
    }

    /// Appends one current sample, returning its previous counterpart, or itself when unpaired.
    mutating func record(_ current: Sample) -> Sample {
        precondition(currentSamples.count < occurrenceEnd, "Begin an occurrence before recording its samples")
        let previous = hasPrevious ? previousSamples[currentSamples.count] : current
        currentSamples.append(current)
        return previous
    }

    mutating func reset() {
        previousSamples.removeAll(keepingCapacity: true)
        currentSamples.removeAll(keepingCapacity: true)
        frameNumber = nil
        previousGroupSize = 0
        currentGroupSize = 0
        occurrenceEnd = 0
        hasPrevious = false
    }
}
