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
    private let slotsInFlight: Int
    private var latestUpdatedIndex: Int = 0

    /// - Parameter slotsInFlight: Total ring-buffer slots. Default is `maxBuffersInFlight` (3).
    ///   Pass `maxBuffersInFlight * iterationCount` when this buffer is updated multiple times per frame.
    public init(device: MTLDevice, count: Int, slotsInFlight: Int = Satin.maxBuffersInFlight) {
        self.count = count
        self.slotsInFlight = slotsInFlight
        let length = alignedSize * slotsInFlight
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
        index = (index + 1) % slotsInFlight
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

    public func selectRecentSlot(iteration: Int, count: Int) {
        let sanitizedCount = max(1, count)
        let clampedIteration = min(max(0, iteration), sanitizedCount - 1)
        let distanceFromCurrent = sanitizedCount - 1 - clampedIteration
        index = (latestUpdatedIndex - distanceFromCurrent + slotsInFlight) % slotsInFlight
        offset = alignedSize * index
    }

    private var alignedSize: Int {
        align(size: MemoryLayout<InstanceMatrixUniforms>.size * count)
    }

    private func align(size: Int) -> Int {
        return ((size + 255) / 256) * 256
    }
}
