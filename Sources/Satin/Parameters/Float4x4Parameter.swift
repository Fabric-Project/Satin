//
//  Float4x4Parameter.swift
//
//
//  Created by Reza Ali on 4/19/22.
//

import Foundation
import simd

public final class Float4x4Parameter: GenericParameter<simd_float4x4> {
    override public var type: ParameterType { .float4x4 }

    override public init(_ label: String, _ value: simd_float4x4, _ controlType: ControlType = .none) {
        super.init(label, value, controlType)
    }

    private enum CodingKeys: String, CodingKey {
        case controlType
        case label
        case value
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    override public func clone() -> any Parameter {
        Float4x4Parameter(label, value, controlType)
    }
}
