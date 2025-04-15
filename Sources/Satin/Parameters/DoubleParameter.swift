//
//  DoubleParameter.swift
//  Satin
//
//  Created by Reza Ali on 10/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Foundation

public final class DoubleParameter: GenericParameterWithMinMax<Double> {
    override public var type: ParameterType { .double }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none) {
        self.init(label, value, 0.0, 1.0, controlType)
    }

    override public func clone() -> any Parameter {
        DoubleParameter(label, value, min, max, controlType)
    }
}
