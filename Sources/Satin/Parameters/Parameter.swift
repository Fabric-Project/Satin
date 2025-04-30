//
//  AnyParameter.swift
//  Satin
//
//  Created by Reza Ali on 10/22/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Foundation

public protocol Parameter: AnyObject, Codable, CustomStringConvertible {
    associatedtype ValueType: Codable & Equatable

    var id: String { get }
    var value: ValueType { get set }
    var defaultValue: ValueType { get set }

    var type: ParameterType { get }
    var string: String { get }

    var size: Int { get }
    var stride: Int { get }
    var alignment: Int { get }

    var controlType: ControlType { get set }
    var label: String { get }
    var description: String { get }

    var valuePublisher: PassthroughSubject<ValueType, Never> { get }

    func alignData(pointer: UnsafeMutableRawPointer, offset: inout Int) -> UnsafeMutableRawPointer
    func writeData(pointer: UnsafeMutableRawPointer, offset: inout Int) -> UnsafeMutableRawPointer

    func clone() -> any Parameter
}

public protocol ParameterWithMinMax: Parameter {
    var min: ValueType { get set }
    var max: ValueType { get set }
}

public enum ControlType: String, Codable {
    case none
    case slider
    case multislider
    case rangeslider
    case xypad
    case toggle
    case button
    case inputfield
    case stepper
    case colorpicker
    case colorpalette
    case dropdown
    case label
    case filepicker
}

public enum ParameterType: String, Codable {
    case bool, uint32, int, int2, int3, int4, float, float2, float3, float4, double, string, packedfloat3, float2x2, float3x3, float4x4, generic

    var metatype: any Parameter.Type {
        switch self {
        case .bool:
            return BoolParameter.self
        case .uint32:
            return UInt32Parameter.self
        case .int:
            return IntParameter.self
        case .int2:
            return Int2Parameter.self
        case .int3:
            return Int3Parameter.self
        case .int4:
            return Int4Parameter.self
        case .float:
            return FloatParameter.self
        case .float2:
            return Float2Parameter.self
        case .float3:
            return Float3Parameter.self
        case .float4:
            return Float4Parameter.self
        case .double:
            return DoubleParameter.self
        case .string:
            return StringParameter.self
        case .packedfloat3:
            return PackedFloat3Parameter.self
        case .float2x2:
            return Float2x2Parameter.self
        case .float3x3:
            return Float3x3Parameter.self
        case .float4x4:
            return Float4x4Parameter.self
        default:
            fatalError("Unknown Parameter Type")
        }
    }

    var string: String {
        switch self {
        case .uint32:
            return "uint32_t"
        case .packedfloat3:
            return "packed_float3"
        default:
            return self.rawValue
        }
    }
}
