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
    public private(set) var encodesPerFrame: Int
    public private(set) var totalSlotCount: Int
    private var latestUpdatedIndex: Int = -1

    public init(
        device: MTLDevice,
        parameters: ParameterGroup,
        options: MTLResourceOptions = [.cpuCacheModeWriteCombined],
        maxBuffersInFlight: Int = Satin.maxBuffersInFlight,
        encodesPerFrame: Int = 1
    ) {
        self.parameters = parameters
        self.maxBuffersInFlight = max(1, maxBuffersInFlight)
        self.encodesPerFrame = max(1, encodesPerFrame)
        self.totalSlotCount = self.maxBuffersInFlight * self.encodesPerFrame
        self.alignedSize = align256(size: parameters.size)
        let length = alignedSize * totalSlotCount

        let buffer = device.makeBuffer(length: length, options: options)!
        buffer.label = parameters.label
        self.buffer = buffer
        update()
    }

    public func update() {
        index = (index + 1) % totalSlotCount
        latestUpdatedIndex = index
        offset = alignedSize * index
        (buffer.contents() + offset).copyMemory(from: parameters.data, byteCount: parameters.size)
    }

    public func selectRecentSlot(iteration: Int, count: Int) {
        guard latestUpdatedIndex >= 0 else { return }
        let sanitizedCount = max(1, count)
        let clampedIteration = min(max(0, iteration), sanitizedCount - 1)
        let distanceFromCurrent = sanitizedCount - 1 - clampedIteration
        index = (latestUpdatedIndex - distanceFromCurrent + totalSlotCount) % totalSlotCount
        offset = alignedSize * index
    }

    public func reset() {
        index = -1
    }
}
