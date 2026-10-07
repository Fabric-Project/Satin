//
//  InstanceMatrixUniformBuffer.swift
//  Satin
//
//  Created by Reza Ali on 10/19/22.
//

import Metal
import simd

public final class InstanceMatrixUniformBuffer {
    public private(set) var buffer: MTLBuffer!
    public private(set) var offset = 0
    public private(set) var index = 0
    public private(set) var count: Int
    public private(set) var maxBuffersInFlight: Int
    public private(set) var encodesPerFrame: Int
    public private(set) var totalSlotCount: Int
    private var latestUpdatedIndex: Int = 0
    /// Repeated encoding: the slot each iteration's matrices were uploaded into this frame.
    private var capturedSlots: [Int?] = []

    public init(
        device: MTLDevice,
        count: Int,
        maxBuffersInFlight: Int = Satin.maxBuffersInFlight,
        encodesPerFrame: Int = 1
    ) {
        self.count = count
        self.maxBuffersInFlight = max(1, maxBuffersInFlight)
        self.encodesPerFrame = max(1, encodesPerFrame)
        self.totalSlotCount = self.maxBuffersInFlight * self.encodesPerFrame
        let length = alignedSize * totalSlotCount
        guard let buffer = device.makeBuffer(length: length, options: [MTLResourceOptions.cpuCacheModeWriteCombined]) else { fatalError("Couldn't not create Instance Matrix Uniform Buffer") }
        self.buffer = buffer
        self.buffer.label = "Instance Matrix Uniforms"
    }

//    public func update(data: [InstanceMatrixUniforms]) {
//        index = (index + 1) % maxBuffersInFlight
//        offset = alignedSize * index
//
//        _ = data.withUnsafeBytes { dataPtr in
//            memcpy(buffer.contents().advanced(by: offset), dataPtr.baseAddress!, MemoryLayout<InstanceMatrixUniforms>.size * data.count)
//        }
//    }
    
    public func update(data: [InstanceMatrixUniforms]) {
        index = (index + 1) % totalSlotCount
        latestUpdatedIndex = index
        offset = alignedSize * index

        guard !data.isEmpty else { return }

        let n = min(data.count, self.count)
        let bytes = MemoryLayout<InstanceMatrixUniforms>.stride * n

        // Optional but HIGHLY recommended debug check:
        precondition(offset + bytes <= buffer.length, "InstanceMatrixUniformBuffer overflow")
        
        let _ = data.withUnsafeBytes { dataPtr in
            memcpy(buffer.contents().advanced(by: offset),
                   dataPtr.baseAddress!,
                   bytes)
        }
    }

    // TODO(render-packets): repeated-encoding stopgap; see Renderable.prepareForRepeatedEncoding.
    /// Records the latest upload as `iteration`'s, for `selectRecentSlot` to draw it.
    public func captureLatestSlot(iteration: Int, count: Int) {
        let sanitizedCount = max(1, count)
        if capturedSlots.count != sanitizedCount { capturedSlots = Array(repeating: nil, count: sanitizedCount) }
        guard capturedSlots.indices.contains(iteration) else { return }
        capturedSlots[iteration] = latestUpdatedIndex
    }

    /// The slot `iteration` was captured into, or the latest upload when it was not captured.
    public func selectRecentSlot(iteration: Int, count: Int) {
        if capturedSlots.indices.contains(iteration), let capturedSlot = capturedSlots[iteration] {
            index = capturedSlot
        } else {
            index = latestUpdatedIndex
        }
        offset = alignedSize * index
    }

    private var alignedSize: Int {
        align(size: MemoryLayout<InstanceMatrixUniforms>.size * count)
    }

    private func align(size: Int) -> Int {
        return ((size + 255) / 256) * 256
    }
}
