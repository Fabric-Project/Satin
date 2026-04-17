//
//  FloatParameter.swift
//  Satin
//
//  Created by Reza Ali on 10/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Foundation

public final class FloatParameter: GenericParameterWithMinMax<Float> {
    override public var type: ParameterType { .float }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description:String = "") {
        self.init(label, value, 0.0, 1.0, controlType, description)
    }

    override public func clone() -> any Parameter {
        FloatParameter(label, value, min, max, controlType, description)
    }
}
