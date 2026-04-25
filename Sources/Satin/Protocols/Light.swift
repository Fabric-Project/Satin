//
//  Light.swift
//
//
//  Created by Reza Ali on 11/2/22.
//

import Combine
import Foundation
import simd

public class Light: Object {
    public var type: LightType { fatalError("Subclasses must overload") }
    
    public var data: LightData { fatalError("Subclasses must overload") }
    
    public var color: simd_float3 = .zero {
        didSet {
            publisher.send(self)
        }
    }

    public var intensity: Float = 1.0  {
        didSet {
            publisher.send(self)
        }
    }
    
    public var castShadow: Bool = false // { fatalError("Subclasses must overload") }
    public var shadow: Shadow
    
    public let publisher = PassthroughSubject<Light, Never>()
    
    override init(label: String = "Light", visible: Bool = true, _ children: [Object] = [])
    {
        shadow = Shadow(label: "Empty Shadow")
        
        super.init()
    }
    
    private enum CodingKeys: String, CodingKey {
        case color
        case intensity
    }
    
    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(intensity, forKey: .intensity)
    }
    
    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        color = try values.decode(simd_float3.self, forKey: .color)
        intensity = try values.decode(Float.self, forKey: .intensity)
        shadow = Shadow(label: "Empty Shadow")

        try super.init(from: decoder)
    }
}
