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
    public internal(set) var buffer: MTLBuffer!
    public internal(set) var offset = 0
}

public final class StructBuffer<T>: BindableBuffer {
    public private(set) var index = -1
    public private(set) var count: Int

    public init(device: MTLDevice, count: Int, label: String = "Struct Buffer") {
        self.count = count
        super.init()

        let length = alignedSize * Satin.maxBuffersInFlight
        guard let buffer = device.makeBuffer(length: length, options: [MTLResourceOptions.cpuCacheModeWriteCombined]) else {
            fatalError("Couldn't not create \(label)")
        }
        self.buffer = buffer
        self.buffer.label = label
    }

    public func update(data: [T]) {
        index = (index + 1) % maxBuffersInFlight
        offset = alignedSize * index
        _ = data.withUnsafeBytes { dataPtr in
            memcpy(buffer.contents().advanced(by: offset), dataPtr.baseAddress!, MemoryLayout<T>.size * data.count)
        }
    }

    public func update(data: ContiguousArray<T>) {
        index = (index + 1) % maxBuffersInFlight
        offset = alignedSize * index
        _ = data.withUnsafeBytes { dataPtr in
            memcpy(buffer.contents().advanced(by: offset), dataPtr.baseAddress!, MemoryLayout<T>.size * data.count)
        }
    }

    private var alignedSize: Int {
        align(size: MemoryLayout<T>.size * count)
    }

    private func align(size: Int) -> Int {
        ((size + 255) / 256) * 256
    }
}
