//
//  Float3Parameter.swift
//  Satin
//
//  Created by Reza Ali on 2/4/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Foundation
import simd

public final class Float3Parameter: GenericParameterWithMinMax<simd_float3> {
    override public var type: ParameterType { .float3 }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description:String = "") {
        self.init(label, value, .zero, .one, controlType, description)
    }

    override public func clone() -> any Parameter {
        Float3Parameter(label, value, min, max, controlType, description)
    }
}
