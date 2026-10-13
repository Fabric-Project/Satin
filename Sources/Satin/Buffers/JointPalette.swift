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
///
/// Repeated encoding (the same mesh drawn several times a frame): after each
/// iteration's update, `captureRepeatedEncoding(iteration:count:)` uploads that iteration's
/// pose into its own slot, with the pose the same iteration had last frame as `previous`, and
/// `selectRecentSlot(iteration:count:)` selects exactly that slot when drawing it.
public final class JointPalette {
    public let jointCount: Int
    public private(set) var buffer: MTLBuffer
    public private(set) var offset = 0
    public private(set) var index = 0
    public private(set) var joints: [SkinJoint]

    private let device: MTLDevice
    private let maxBuffersInFlight: Int
    private var totalSlotCount: Int
    private var latestUpdatedIndex = 0

    /// Repeated encoding: the slot each iteration's pose was captured into this frame, and
    /// each iteration's current matrices, which become its previous ones next frame: flat,
    /// iteration × jointCount, filled in place so capturing allocates nothing.
    private var repeatedCount = 0
    private var capturedSlots: [Int?] = []
    private var iterationHistory: [simd_float4x4] = []
    private var iterationHasHistory: [Bool] = []
    /// Changes whenever the pose does: for posed bounds and raycasts to know when to rebuild,
    /// and for a second capture of an unchanged iteration to be recognised.
    public private(set) var poseVersion = 0
    /// Iterations captured since the palette was last drawn, with the pose version each
    /// was captured at. Several meshes drawing one palette each capture it every iteration;
    /// only the first capture of a pose in a frame may move its history on.
    private var capturedSinceDraw: [Int: Int] = [:]
    /// The latest update may have moved the pose, and whether that pose has been drawn: once it
    /// has, and nothing updates it again, previous catches up with current (`settleMotion`).
    private var motionNeedsSettling = false
    private var motionDrawn = false

    public init(device: MTLDevice, jointCount: Int, maxBuffersInFlight: Int = Satin.maxBuffersInFlight, encodesPerFrame: Int = 1) {
        self.device = device
        self.jointCount = max(jointCount, 1)
        self.maxBuffersInFlight = max(1, maxBuffersInFlight)
        totalSlotCount = Self.slotCount(maxBuffersInFlight: self.maxBuffersInFlight, encodesPerFrame: max(1, encodesPerFrame))
        joints = Array(repeating: SkinJoint(current: matrix_identity_float4x4, previous: matrix_identity_float4x4), count: self.jointCount)
        buffer = Self.makeBuffer(device: device, jointCount: self.jointCount, slotCount: totalSlotCount)
        upload()
    }

    /// Sets a new pose. The outgoing pose becomes last frame's, for velocity.
    public func update(matrices: [simd_float4x4]) {
        for jointIndex in joints.indices {
            joints[jointIndex].previous = joints[jointIndex].current
            joints[jointIndex].current = jointIndex < matrices.count ? matrices[jointIndex] : matrix_identity_float4x4
        }
        motionNeedsSettling = true
        motionDrawn = false
        upload()
    }

    /// Sets a pose with no motion: last frame's matrices equal this frame's.
    public func reset(matrices: [simd_float4x4]) {
        for jointIndex in joints.indices {
            let matrix = jointIndex < matrices.count ? matrices[jointIndex] : matrix_identity_float4x4
            joints[jointIndex] = SkinJoint(current: matrix, previous: matrix)
        }
        motionNeedsSettling = false
        upload()
    }

    /// Records that the latest pose was bound for drawing.
    func markDrawn() {
        motionDrawn = true
    }

    /// Before a frame's drawing: when a moving pose has been drawn and nothing updated it
    /// since, last frame's matrices catch up with this frame's, so a held pose draws no
    /// velocity. The pose itself is unchanged, so `poseVersion` stays.
    func settleMotion() {
        guard motionNeedsSettling, motionDrawn else { return }
        for jointIndex in joints.indices {
            joints[jointIndex].previous = joints[jointIndex].current
        }
        advanceSlot()
        write(joints)
        motionNeedsSettling = false
    }

    // MARK: - Repeated Encoding

    // TODO(render-packets): repeated-encoding stopgap; see Renderable.prepareForRepeatedEncoding.
    /// Makes room for `count` iterations a frame: each may upload once when its pose changes
    /// and once when it is captured, for every frame in flight. Only grows.
    public func prepareForRepeatedEncoding(count: Int) {
        let sanitizedCount = max(1, count)
        if sanitizedCount != repeatedCount {
            repeatedCount = sanitizedCount
            capturedSlots = Array(repeating: nil, count: sanitizedCount)
            iterationHistory = Array(repeating: matrix_identity_float4x4, count: sanitizedCount * jointCount)
            iterationHasHistory = Array(repeating: false, count: sanitizedCount)
        }
        let wantedSlotCount = Self.slotCount(maxBuffersInFlight: maxBuffersInFlight, encodesPerFrame: 2 * sanitizedCount + 1)
        guard wantedSlotCount > totalSlotCount else { return }
        totalSlotCount = wantedSlotCount
        buffer = Self.makeBuffer(device: device, jointCount: jointCount, slotCount: totalSlotCount)
        index = 0
        upload()
    }

    /// Uploads the current pose as `iteration`'s, with the pose that iteration had last frame
    /// as `previous`, so velocity is per iteration rather than between iterations.
    public func captureRepeatedEncoding(iteration: Int, count: Int) {
        if repeatedCount != max(1, count) { prepareForRepeatedEncoding(count: count) }
        guard capturedSlots.indices.contains(iteration) else { return }
        // Already captured this frame with this pose (by another mesh drawing this palette).
        if capturedSinceDraw[iteration] == poseVersion, capturedSlots[iteration] != nil { return }
        capturedSinceDraw[iteration] = poseVersion
        advanceSlot()
        let slot = buffer.contents().advanced(by: offset).bindMemory(to: SkinJoint.self, capacity: jointCount)
        let historyStart = iteration * jointCount
        let hasHistory = iterationHasHistory[iteration]
        for jointIndex in 0 ..< jointCount {
            let current = joints[jointIndex].current
            slot[jointIndex] = SkinJoint(current: current, previous: hasHistory ? iterationHistory[historyStart + jointIndex] : current)
            iterationHistory[historyStart + jointIndex] = current
        }
        iterationHasHistory[iteration] = true
        capturedSlots[iteration] = index
    }

    /// The slot `iteration`'s pose was captured into, or the latest upload when it was not
    /// captured (drawing without repeated encoding, or before the first capture).
    public func selectRecentSlot(iteration: Int, count: Int) {
        // Drawing ends this frame's captures.
        capturedSinceDraw.removeAll()
        if capturedSlots.indices.contains(iteration), let capturedSlot = capturedSlots[iteration] {
            index = capturedSlot
        } else {
            index = latestUpdatedIndex
        }
        offset = Self.alignedSize(jointCount: jointCount) * index
    }

    // MARK: - Private

    private func upload() {
        poseVersion &+= 1
        advanceSlot()
        write(joints)
    }

    private func advanceSlot() {
        index = (index + 1) % totalSlotCount
        latestUpdatedIndex = index
        offset = Self.alignedSize(jointCount: jointCount) * index
    }

    private func write(_ values: [SkinJoint]) {
        values.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            memcpy(buffer.contents().advanced(by: offset), baseAddress, MemoryLayout<SkinJoint>.stride * min(values.count, jointCount))
        }
    }

    private static func slotCount(maxBuffersInFlight: Int, encodesPerFrame: Int) -> Int {
        maxBuffersInFlight * encodesPerFrame
    }

    private static func makeBuffer(device: MTLDevice, jointCount: Int, slotCount: Int) -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: alignedSize(jointCount: jointCount) * slotCount, options: [.cpuCacheModeWriteCombined]) else {
            fatalError("Couldn't create Joint Palette buffer")
        }
        buffer.label = "Joint Palette"
        return buffer
    }

    private static func alignedSize(jointCount: Int) -> Int {
        ((MemoryLayout<SkinJoint>.stride * jointCount + 255) / 256) * 256
    }
}
