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
    // Count of ring-buffer slots still needing a copy after the last dirty transition.
    // Counts down from maxBuffersInFlight to 0; copyMemory is skipped at 0.
    private var dirtySlots: Int = 0

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
        if parameters.isDirty {
            // New dirty transition: ensure all ring-buffer slots receive the updated data.
            dirtySlots = maxBuffersInFlight
            parameters.isDirty = false
        }
        guard dirtySlots > 0 else { return }
        (buffer.contents() + offset).copyMemory(from: parameters.data, byteCount: parameters.size)
        dirtySlots -= 1
    }

    public func reset() {
        index = -1
    }
}
