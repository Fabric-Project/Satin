//
//  PackedFloat3Parameter.swift
//  Satin
//
//  Created by Reza Ali on 4/22/20.
//

import Foundation
import Metal
import simd

public final class PackedFloat3Parameter: GenericParameterWithMinMax<MTLPackedFloat3> {
    override public var type: ParameterType { .packedfloat3 }

    public convenience init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description:String = "") {
        self.init(label, value, MTLPackedFloat3Make(0.0, 0.0, 0.0), MTLPackedFloat3Make(1.0, 1.0, 1.0), controlType, description)
    }

    override public func clone() -> any Parameter {
        PackedFloat3Parameter(label, value, min, max, controlType, description)
    }
}
