//
//  Float2x2Parameter.swift
//
//
//  Created by Reza Ali on 8/3/22.
//

import Foundation
import simd

public final class Float2x2Parameter: GenericParameter<simd_float2x2> {
    override public var type: ParameterType { .float2x2 }

    override public init(_ label: String, _ value: simd_float2x2, _ controlType: ControlType = .none) {
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
        Float2x2Parameter(label, value, controlType)
    }
}
