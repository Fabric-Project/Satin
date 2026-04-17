//
//  Float4Parameter.swift
//  Satin
//
//  Created by Reza Ali on 2/4/20.
//  Copyright © 2020 Reza Ali. All rights reserved.
//

import Foundation
import simd

public final class Float4Parameter: GenericParameterWithMinMax<simd_float4> {
    override public var type: ParameterType { .float4 }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description:String = "") {
        self.init(label, value, .zero, .one, controlType, description)
    }

    override public func clone() -> any Parameter {
        Float4Parameter(label, value, min, max, controlType, description)
    }
}
