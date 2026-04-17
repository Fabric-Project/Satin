//
//  UInt32Parameter.swift
//  Satin
//
//  Created by Reza Ali on 4/22/20.
//

import Foundation

public final class UInt32Parameter: GenericParameterWithMinMax<UInt32> {
    override public var type: ParameterType { .uint32 }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description: String = "") {
        self.init(label, value, 0, 1, controlType, description)
    }

    override public func clone() -> any Parameter {
        UInt32Parameter(label, value, min, max, controlType, description)
    }
}
