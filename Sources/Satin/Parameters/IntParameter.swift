//
//  IntParameter.swift
//  Satin
//
//  Created by Reza Ali on 10/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Foundation

public final class IntParameter: GenericParameterWithMinMax<Int> {
    override public var type: ParameterType { .int }

    override public var size: Int { return MemoryLayout<Int32>.size }
    override public var stride: Int { return MemoryLayout<Int32>.stride }
    override public var alignment: Int { return MemoryLayout<Int32>.alignment }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description:String = "") {
        self.init(label, value, 0, 1, controlType, description)
    }

    override public func writeData(pointer: UnsafeMutableRawPointer, offset: inout Int) -> UnsafeMutableRawPointer {
        var data = alignData(pointer: pointer, offset: &offset)
        data.storeBytes(of: Int32(value), as: Int32.self)
        data += size
        offset += size
        return data
    }

    override public func clone() -> any Parameter {
        IntParameter(label, value, min, max, controlType, description)
    }
}
