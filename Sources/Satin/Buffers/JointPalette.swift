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
/// Slot-rotated like `InstanceMatrixUniformBuffer`, so updating it never touches memory a
/// frame in flight is reading.
public final class JointPalette {
    public let jointCount: Int
    public private(set) var buffer: MTLBuffer
    public private(set) var offset = 0
    public private(set) var index = 0
    public private(set) var joints: [SkinJoint]

    private let totalSlotCount: Int
    private var latestUpdatedIndex = 0

    public init(device: MTLDevice, jointCount: Int, maxBuffersInFlight: Int = Satin.maxBuffersInFlight, encodesPerFrame: Int = 1) {
        self.jointCount = max(jointCount, 1)
        totalSlotCount = max(1, maxBuffersInFlight) * max(1, encodesPerFrame)
        joints = Array(repeating: SkinJoint(current: matrix_identity_float4x4, previous: matrix_identity_float4x4), count: self.jointCount)
        let length = Self.alignedSize(jointCount: self.jointCount) * totalSlotCount
        guard let buffer = device.makeBuffer(length: length, options: [.cpuCacheModeWriteCombined]) else {
            fatalError("Couldn't create Joint Palette buffer")
        }
        self.buffer = buffer
        self.buffer.label = "Joint Palette"
        upload()
    }

    /// Sets a new pose. The outgoing pose becomes last frame's, for velocity.
    public func update(matrices: [simd_float4x4]) {
        for jointIndex in joints.indices {
            joints[jointIndex].previous = joints[jointIndex].current
            joints[jointIndex].current = jointIndex < matrices.count ? matrices[jointIndex] : matrix_identity_float4x4
        }
        upload()
    }

    /// Sets a pose with no motion: last frame's matrices equal this frame's.
    public func reset(matrices: [simd_float4x4]) {
        for jointIndex in joints.indices {
            let matrix = jointIndex < matrices.count ? matrices[jointIndex] : matrix_identity_float4x4
            joints[jointIndex] = SkinJoint(current: matrix, previous: matrix)
        }
        upload()
    }

    /// Same as `InstanceMatrixUniformBuffer.selectRecentSlot`, for repeated encoding.
    public func selectRecentSlot(iteration: Int, count: Int) {
        let sanitizedCount = max(1, count)
        let clampedIteration = min(max(0, iteration), sanitizedCount - 1)
        let distanceFromCurrent = sanitizedCount - 1 - clampedIteration
        index = (latestUpdatedIndex - distanceFromCurrent + totalSlotCount) % totalSlotCount
        offset = Self.alignedSize(jointCount: jointCount) * index
    }

    private func upload() {
        index = (index + 1) % totalSlotCount
        latestUpdatedIndex = index
        offset = Self.alignedSize(jointCount: jointCount) * index
        joints.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memcpy(buffer.contents().advanced(by: offset), baseAddress, MemoryLayout<SkinJoint>.stride * jointCount)
        }
    }

    private static func alignedSize(jointCount: Int) -> Int {
        ((MemoryLayout<SkinJoint>.stride * jointCount + 255) / 256) * 256
    }
}
