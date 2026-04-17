//
//  GenericParameter.swift
//
//
//  Created by Reza Ali on 4/7/22.
//

import Combine
import Foundation

public class GenericParameter<T: Codable & Equatable>: Parameter {
    public var id: UUID

    public typealias ValueType = T

    // Delegate
    public let valuePublisher = PassthroughSubject<ValueType, Never>()

    // Getable Properties
    public var type: ParameterType { .generic }
    public var string: String { type.string }

    // Computed Properties
    public var size: Int { return MemoryLayout<ValueType>.size }
    public var stride: Int { return MemoryLayout<ValueType>.stride }
    public var alignment: Int { return MemoryLayout<ValueType>.alignment }

    // Setable Properties
    public var controlType = ControlType.none
    public var label: String

    public var description: String = ""
    
    public var debugDescription: String {
        "Label: \(label) type: \(string) value: \(value) controlType: \(controlType)"
    }

    // Maybe a bit too verbose?
    public var valueDidChange:Bool = true
        
    public var value: ValueType
    {
        didSet
        {
            if oldValue != self.value
            {
                self.valueDidChange = true
                valuePublisher.send(self.value)
            }
        }
    }

    public var defaultValue: ValueType

    private enum CodingKeys: String, CodingKey {
        case id
        case controlType
        case label
        case value
        case defaultValue
        case description
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decode(UUID.self, forKey: .id)
        self.id = id
        
        self.controlType = try container.decode(ControlType.self, forKey: .controlType)

        self.label = try container.decode(String.self, forKey: .label)

        let value = try container.decode(ValueType.self, forKey: .value)

        self.value = value

        if let defaultValue = try container.decodeIfPresent(ValueType.self, forKey: .defaultValue) {
            self.defaultValue = defaultValue
        }
        else {
            defaultValue = value
        }
        
        if let description = try container.decodeIfPresent(String.self, forKey: .description)
        {
            self.description = description
        }
        else
        {
            self.description = ""
        }
        
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(controlType, forKey: .controlType)
        try container.encode(label, forKey: .label)
        try container.encode(description, forKey: .description)

        var saveDefaultValueInPlaceOfValue = false
        if controlType == .none, let ignoreControlTypeNone = encoder.userInfo[.ignoreControlTypeNone] as? Bool {
            saveDefaultValueInPlaceOfValue = ignoreControlTypeNone
        }

        try container.encode(saveDefaultValueInPlaceOfValue ? defaultValue : value, forKey: .value)
        try container.encode(defaultValue, forKey: .defaultValue)
    }

    public init(_ label: String, _ value: ValueType, _ controlType: ControlType = .none, _ description:String = "") {
        self.id = UUID()
        self.label = label
        self.value = value
        self.defaultValue = value
        self.controlType = controlType
        self.description = description
    }

    public func alignData(pointer: UnsafeMutableRawPointer, offset: inout Int) -> UnsafeMutableRawPointer {
        var data = pointer
        let rem = offset % alignment
        if rem > 0 {
            let remOffset = alignment - rem
            data += remOffset
            offset += remOffset
        }
        return data
    }

    public func writeData(pointer: UnsafeMutableRawPointer, offset: inout Int) -> UnsafeMutableRawPointer {
        var data = alignData(pointer: pointer, offset: &offset)
        data.storeBytes(of: value, as: ValueType.self)
        data += size
        offset += size
        return data
    }

    public func clone() -> any Parameter {
        GenericParameter<ValueType>(label, value, controlType, description)
    }
}

public class GenericParameterWithMinMax<T: Codable & Equatable>: GenericParameter<T> {
    public typealias ValueType = T

    public let minValuePublisher = PassthroughSubject<ValueType, Never>()

    public var min: ValueType {
        didSet {
            minValuePublisher.send(min)
            valuePublisher.send(value)
        }
    }

    public let maxValuePublisher = PassthroughSubject<ValueType, Never>()

    public var max: ValueType {
        didSet {
            maxValuePublisher.send(max)
            valuePublisher.send(value)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case min
        case max
    }

    public init(_ label: String, _ value: ValueType, _ min: ValueType, _ max: ValueType, _ controlType: ControlType = .none,  _ description:String = "") {
        self.min = min
        self.max = max
        super.init(label, value, controlType, description)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.min = try container.decode(ValueType.self, forKey: .min)
        self.max = try container.decode(ValueType.self, forKey: .max)
        try super.init(from: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(min, forKey: .min)
        try container.encode(max, forKey: .max)
    }

    override public func clone() -> any Parameter {
        GenericParameterWithMinMax<ValueType>(label, value, min, max, controlType, description)
    }
}
