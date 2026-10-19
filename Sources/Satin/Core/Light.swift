//
//  Light.swift
//
//
//  Created by Reza Ali on 11/2/22.
//

import Foundation
import simd

public class Light: Object {
    public var type: LightType { fatalError("Subclasses must overload") }
    
    public var data: LightData { fatalError("Subclasses must overload") }

    var shadowIndex: Int = -1
    var projectorIndex: Int = -1
    
    public var color: simd_float3 = .zero {
        didSet {
            if color != oldValue { lightPropertiesDidChange() }
        }
    }

    public var intensity: Float = 1.0  {
        didSet {
            if intensity != oldValue { lightPropertiesDidChange() }
        }
    }
    
    public var castShadow: Bool = false // { fatalError("Subclasses must overload") }
    public var shadow: Shadow
    
    /// Advances when a property feeding the light's data or views changes: colour, intensity,
    /// and a subclass's own (radius, angles, projection). Its transform has `worldRevision`.
    public private(set) var lightRevision: UInt64 = 0

    func lightPropertiesDidChange() {
        lightRevision &+= 1
    }

    /// What the shadow (and projector) cameras were last aimed for.
    private var viewKey: (world: UInt64, light: UInt64)?

    /// Re-aims the shadow (and projector) cameras when the light moved (its world revision, which
    /// validates against its ancestors) or changed since they were aimed.
    func updateViewIfNeeded() {
        let key = (world: worldRevision, light: lightRevision)
        if let viewKey, viewKey == key { return }
        viewKey = key
        updateView()
    }

    /// Aims the shadow's cameras at the light as it is now.
    func updateView() {
        shadow.update(light: self)
    }
    
    override public init(context: Context, label: String = "Light", visible: Bool = true, _ children: [Object] = []) {
        shadow = Shadow(context: context, label: "Empty Shadow")
        super.init(context: context, label: label, visible: visible, children)
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
        let ctx = try decoder.requireSatinContext(typeName: "Light")
        shadow = Shadow(context: ctx, label: "Empty Shadow")
        try super.init(from: decoder)
    }
}
