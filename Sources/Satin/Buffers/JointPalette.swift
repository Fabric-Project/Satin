//
//  JointPalette.swift
//  Satin
//

import Metal
import simd

/// One joint's matrices as the GPU reads them (`SkinJoint` in Skinning.metal): this frame's
/// and last frame's, so skinned motion reaches the velocity output.
public struct SkinJoint {
    public var current: simd_float4x4
    public var previous: simd_float4x4

    public init(current: simd_float4x4, previous: simd_float4x4) {
        self.current = current
        self.previous = previous
    }
}

/// The pose of a skinned geometry: one matrix per joint, which skinned vertices look up by
/// their joint indices. Each matrix takes a vertex from the geometry's rest pose to its
/// posed position, in object space.
///
/// Drawing snapshots the pose into the draw's frame arena, once per record: every mesh sharing
/// the palette in one record binds the same snapshot. Each snapshot carries the pose of the
/// matching record in the frame before (by palette draw ordinal), so skinned motion reaches the
/// velocity output, and an unchanged pose reports none.
public final class JointPalette {
    public let jointCount: Int
    /// The current pose, one matrix per joint.
    public private(set) var matrices: [simd_float4x4]
    /// Changes whenever the pose does: for posed bounds and raycasts to know when to rebuild.
    public private(set) var poseVersion = 0

    // Motion: poses by palette draw ordinal, the kth snapshot of a frame pairing with the kth of
    // the frame before; flat, ordinal × jointCount.
    private var previousFramePoses: [simd_float4x4] = []
    private var currentFramePoses: [simd_float4x4] = []
    private var motionFrameNumber: Int?

    // The snapshot of the current record, reused by every mesh drawing this palette in it.
    private var snapshotRecordToken: RecordToken?
    private var snapshotBinding: (buffer: MTLBuffer, offset: Int)?

    public init(jointCount: Int) {
        self.jointCount = max(jointCount, 1)
        matrices = Array(repeating: matrix_identity_float4x4, count: self.jointCount)
    }

    /// Sets a new pose.
    public func update(matrices newMatrices: [simd_float4x4]) {
        for jointIndex in matrices.indices {
            matrices[jointIndex] = jointIndex < newMatrices.count ? newMatrices[jointIndex] : matrix_identity_float4x4
        }
        poseVersion &+= 1
    }

    /// Sets a pose with no motion: its next snapshots report none.
    public func reset(matrices newMatrices: [simd_float4x4]) {
        update(matrices: newMatrices)
        resetMotion()
    }

    /// Forgets this palette's motion: its next snapshots draw with none.
    public func resetMotion() {
        previousFramePoses.removeAll(keepingCapacity: true)
        currentFramePoses.removeAll(keepingCapacity: true)
    }

    /// The pose as it is now, with each joint's previous matrix, in `recorder`'s arena: taken once per
    /// record, so meshes sharing this palette in one record bind one snapshot and advance its motion
    /// once.
    func snapshot(recorder: PacketRecorder) -> (buffer: MTLBuffer, offset: Int) {
        if let snapshotBinding, snapshotRecordToken == recorder.recordToken {
            return snapshotBinding
        }

        let frameNumber = recorder.frame.frameNumber
        if motionFrameNumber != frameNumber {
            if let motionFrameNumber, motionFrameNumber == frameNumber - 1 {
                swap(&previousFramePoses, &currentFramePoses)
            } else {
                previousFramePoses.removeAll(keepingCapacity: true)
            }
            currentFramePoses.removeAll(keepingCapacity: true)
            motionFrameNumber = frameNumber
        }

        let ordinalStart = currentFramePoses.count
        let hasPrevious = ordinalStart + jointCount <= previousFramePoses.count
        let slice = recorder.allocate(length: MemoryLayout<SkinJoint>.stride * jointCount)
        let joints = slice.contents.bindMemory(to: SkinJoint.self, capacity: jointCount)
        for jointIndex in 0 ..< jointCount {
            let current = matrices[jointIndex]
            joints[jointIndex] = SkinJoint(current: current, previous: hasPrevious ? previousFramePoses[ordinalStart + jointIndex] : current)
            currentFramePoses.append(current)
        }

        let binding = (buffer: slice.buffer, offset: slice.offset)
        snapshotBinding = binding
        snapshotRecordToken = recorder.recordToken
        return binding
    }
}
