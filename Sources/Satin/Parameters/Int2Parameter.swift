//
//  Int2Parameter.swift
//  Satin
//
//  Created by Reza Ali on 2/5/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Foundation
import simd

public final class Int2Parameter: GenericParameterWithMinMax<simd_int2> {
    override public var type: ParameterType { .int2 }
    override public var string: String { "int2" }
    override public var count: Int { 2 }

    override public var value: GenericParameter<simd_int2>.ValueType {
        didSet {
            if value != oldValue {
                delegate?.updated(parameter: self)
            }
        }
    }

    override public func dataType<Int32>() -> Int32.Type {
        return Int32.self
    }

    override public subscript<T>(index: Int) -> T {
        get {
            return value[index] as! T
        }
        set {
            value[index] = newValue as! Int32
        }
    }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none) {
        self.init(label, value, .zero, .one, controlType)
    }
}
