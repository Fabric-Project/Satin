//
//  InterleavedBuffer.swift
//
//
//  Created by Reza Ali on 7/13/23.
//

import Foundation
import Metal

open class InterleavedBufferAttribute: VertexAttribute {
    public let parent: InterleavedBuffer
    public let offset: Int

    public init(parent: InterleavedBuffer, offset: Int) {
        self.parent = parent
        self.offset = offset
        super.init()
    }

    open var interleavedStride: Int { parent.stride }
}

public protocol InterleavedBufferDelegate: AnyObject {
    func updated(buffer: InterleavedBuffer)
}

public class InterleavedBuffer: Equatable {
    public let id: String = UUID().uuidString

    public let index: VertexBufferIndex
    public private(set) var data: UnsafeMutableRawPointer?
    public private(set) var stride: Int // represents the distance to another vertex (in bytes) i.e. MemoryLayout<Float>.size * 4
    public private(set) var count: Int // represents the total number of vertices

    var stepRate: Int
    var stepFunction: MTLVertexStepFunction

    var length: Int { stride * count }

    var source: Any?

    public var needsUpdate: Bool = true
    public var buffer: MTLBuffer?

    public weak var delegate: InterleavedBufferDelegate?

    public init(index: VertexBufferIndex, data: UnsafeMutableRawPointer?, stride: Int, count: Int, source: Any?, stepRate: Int = 1, stepFunction: MTLVertexStepFunction = .perVertex) {
        self.index = index
        self.data = data
        self.stride = stride
        self.count = count
        self.source = source
        self.stepRate = stepRate
        self.stepFunction = stepFunction
    }

    public func updateData(data: UnsafeMutableRawPointer, stride: Int, count: Int, source: Any?) {
        self.stride = stride
        self.count = count
        self.source = source
        self.data = data
        needsUpdate = true
        delegate?.updated(buffer: self)
    }

    public func getBuffer(device: MTLDevice) -> MTLBuffer? {
        guard length > 0, let data else { return nil }

        if needsUpdate {
            buffer = device.makeBuffer(bytes: data, length: length)
            needsUpdate = false
        }

        return buffer
    }

    public static func == (lhs: InterleavedBuffer, rhs: InterleavedBuffer) -> Bool {
        lhs === rhs
    }

    deinit {
        source = nil
    }
}
