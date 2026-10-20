//
//  StructBuffer.swift
//  Satin
//
//  Created by Reza Ali on 11/2/22.
//

import Foundation
import Metal
import simd

open class BindableBuffer {
    public let buffer: MTLBuffer
    public internal(set) var offset = 0
    /// The bytes the last update wrote at `offset`: what a draw recorded now copies, so a ring
    /// that wraps before that draw encodes can't change it. 0 before any update.
    public internal(set) var contentLength = 0

    public init(buffer: MTLBuffer) {
        self.buffer = buffer
    }
}

public final class StructBuffer<T>: BindableBuffer {
    public private(set) var index = -1
    public private(set) var count: Int

    public init(device: MTLDevice, count: Int, label: String = "Struct Buffer") {
        self.count = count
        guard let buffer = device.makeBuffer(length: Self.alignedSize(count: count) * Satin.maxBuffersInFlight, options: [MTLResourceOptions.cpuCacheModeWriteCombined]) else {
            fatalError("Couldn't not create \(label)")
        }
        buffer.label = label
        super.init(buffer: buffer)
    }

    public func update(data: [T]) {
        index = (index + 1) % maxBuffersInFlight
        offset = alignedSize * index
        contentLength = MemoryLayout<T>.size * data.count
        _ = data.withUnsafeBytes { dataPtr in
            memcpy(buffer.contents().advanced(by: offset), dataPtr.baseAddress!, MemoryLayout<T>.size * data.count)
        }
    }

    public func update(data: ContiguousArray<T>) {
        index = (index + 1) % maxBuffersInFlight
        offset = alignedSize * index
        contentLength = MemoryLayout<T>.size * data.count
        _ = data.withUnsafeBytes { dataPtr in
            memcpy(buffer.contents().advanced(by: offset), dataPtr.baseAddress!, MemoryLayout<T>.size * data.count)
        }
    }

    private var alignedSize: Int {
        Self.alignedSize(count: count)
    }

    /// One frame's slice of `count` values, on a 256-byte boundary.
    private static func alignedSize(count: Int) -> Int {
        ((MemoryLayout<T>.size * count + 255) / 256) * 256
    }
}
