//
//  UniformBuffer.swift
//  Satin
//
//  Created by Reza Ali on 11/3/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Foundation
import Metal
import simd

func align256(size: Int) -> Int {
    return ((size + 255) / 256) * 256
}

public final class UniformBuffer {
    public private(set) var parameters: ParameterGroup
    public private(set) var buffer: MTLBuffer
    public private(set) var index: Int = -1
    public private(set) var offset = 0
    public private(set) var alignedSize: Int
    public private(set) var maxBuffersInFlight: Int

    public init(device: MTLDevice, parameters: ParameterGroup, options: MTLResourceOptions = [.cpuCacheModeWriteCombined], maxBuffersInFlight: Int = Satin.maxBuffersInFlight) {
        self.parameters = parameters
        self.maxBuffersInFlight = maxBuffersInFlight
        self.alignedSize = align256(size: parameters.size)
        let length = alignedSize * maxBuffersInFlight

        let buffer = device.makeBuffer(length: length, options: options)!
        buffer.label = parameters.label
        self.buffer = buffer
        update()
    }

    public func update() {
        index = (index + 1) % maxBuffersInFlight
        offset = alignedSize * index
        let dest = buffer.contents() + offset
        parameters.withData { ptr, byteCount in
            dest.copyMemory(from: ptr, byteCount: byteCount)
        }
    }

    public func reset() {
        index = -1
    }
}
