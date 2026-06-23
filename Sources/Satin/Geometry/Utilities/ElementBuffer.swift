//
//  ElementBuffer.swift
//
//
//  Created by Reza Ali on 7/17/23.
//

import Foundation
import Metal

public protocol ElementBufferDelegate: AnyObject {
    func updated(buffer: ElementBuffer)
}

public class ElementBuffer: Equatable {
    public let id: String = UUID().uuidString

    public private(set) var type: MTLIndexType
    public private(set) var data: UnsafeMutableRawPointer?
    public var size: Int {
        type == .uint32 ? MemoryLayout<UInt32>.stride : MemoryLayout<UInt16>.stride
    }

    public private(set) var count: Int // represents the total number of indices
    public var length: Int { size * count }

    var source: Any?

    public private(set) var needsUpdate: Bool = true
    public private(set) var buffer: MTLBuffer?

    public weak var delegate: ElementBufferDelegate?

    public init(type: MTLIndexType, data: UnsafeMutableRawPointer?, count: Int, source: Any?) {
        self.type = type
        self.data = data
        self.count = count
        self.source = source
    }

    public func updateData(data: UnsafeMutableRawPointer?, count: Int, source: Any?) {
        self.data = data
        self.count = count
        self.source = source
        needsUpdate = true
        delegate?.updated(buffer: self)
    }

    func markClean() {
        needsUpdate = false
    }

    func getBuffer(device: MTLDevice) -> MTLBuffer? {
        guard count > 0, let data else { return nil }

        if needsUpdate {
            buffer = device.makeBuffer(bytes: data, length: length)
            buffer?.label = "Indices"
            needsUpdate = false
        }

        return buffer
    }

    deinit {
        source = nil
    }

    public static func == (lhs: ElementBuffer, rhs: ElementBuffer) -> Bool {
        lhs === rhs
    }
}
