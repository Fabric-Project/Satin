//
//  Int3Parameter.swift
//  Satin
//
//  Created by Reza Ali on 2/10/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Foundation
import simd

public final class Int3Parameter: GenericParameterWithMinMax<simd_int3> {
    override public var type: ParameterType { .int3 }
    override public var string: String { "int3" }
    override public var count: Int { 3 }

    override public var value: GenericParameter<simd_int3>.ValueType {
        didSet {
            if value != oldValue {
                delegate?.updated(parameter: self)
            }
        }
    }

    override public func dataType<Int32>() -> Int32.Type {
        return Int32.self
    }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none) {
        self.init(label, value, .zero, .one, controlType)
    }
}
