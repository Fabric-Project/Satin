//
//  StringParameter.swift
//  Satin
//
//  Created by Reza Ali on 10/30/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Combine
import Foundation

public final class StringParameter: GenericParameter<String> {
    override public var type: ParameterType { .string }

    public let optionsPublisher = PassthroughSubject<[ValueType], Never>()

    @Published public var options: [String] = [] {
        didSet {
            if oldValue != options {
                optionsPublisher.send(options)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case controlType
        case label
        case value
        case options
    }
    
    public override init(_ label: String, _ value: ValueType = "" , _ controlType: ControlType = .dropdown) {
        self.options = []
        super.init(label, value, controlType)
    }
    
    public convenience init(_ label: String, _ value: ValueType = "", _ options: [String], _ controlType: ControlType = .dropdown) {
        self.init(label, value, controlType)
        self.options = options
    }

    override public func clone() -> any Parameter {
        StringParameter(label, value, options, controlType)
    }
    
    override public func encode(to encoder: any Encoder) throws {
        try super.encode(to: encoder)
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(options, forKey: .options)
    }
    
    required public init(from decoder: Decoder) throws {
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.options = try container.decodeIfPresent([String].self, forKey:.options) ?? []
        
        try super.init(from: decoder)
    }
}
