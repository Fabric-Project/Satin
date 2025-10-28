//
//  SpotLight.swift
//  Satin
//
//  Created by Reza Ali on 11/6/22.
//

import Combine
import Foundation
import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

public final class SpotLight: Light {
    override public var type: LightType { .spot }

    override public var data: LightData {
        let cosOuter = cos(degToRad(angleOuter))
        let cosInner = cos(degToRad(angleInner))
        let spotScale = 1.0 / max(cosInner - cosOuter, 1e-4)
        let spotOffset = -cosOuter * spotScale

        return LightData(
            // (rgb, intensity)
            color: simd_make_float4(color.x, color.y, color.z, intensity),
            // (xyz, type)
            position: simd_make_float4(worldPosition.x, worldPosition.y, worldPosition.z, Float(type.rawValue)),
            // (xyz, inverse radius)
            direction: simd_make_float4(-worldForwardDirection, 0.0),
            // (spotScale, spotOffset, cosInner, cosOuter)
            spotInfo: simd_make_float4(spotScale, spotOffset, cosInner, cosOuter)
        )
    }

    override public var castShadow: Bool
    {
        get { false }
        set { }
    }
    /* FIX ME */

    public var radius: Float {
        didSet {
            publisher.send(self)
        }
    }

    public var angleInner: Float {
        didSet {
            publisher.send(self)
        }
    }

    public var angleOuter: Float {
        didSet {
            publisher.send(self)
        }
    }

    private var transformSubscriber: AnyCancellable?

    private enum CodingKeys: String, CodingKey {
        case radius
        case angleInner
        case angleOuter
    }

    public init(label: String = "Spot Light", color: simd_float3, intensity: Float = 1.0, radius: Float = 4.0, angleInner: Float = 60.0, angleOuter: Float = 90.0) {
        self.radius = radius
        self.angleInner = angleInner
        self.angleOuter = angleOuter

        super.init(label: label)
        self.color = color
        self.intensity = intensity
        
        self.shadow = DirectionalLightShadow(label: label)
    }

    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        radius = try values.decode(Float.self, forKey: .radius)
        angleInner = try values.decode(Float.self, forKey: .angleInner)
        angleOuter = try values.decode(Float.self, forKey: .angleOuter)
        try super.init(from: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(angleInner, forKey: .angleInner)
        try container.encode(angleOuter, forKey: .angleOuter)
        try container.encode(radius, forKey: .radius)
    }

    override public func setup() {
        super.setup()
        transformSubscriber = transformPublisher.sink { [weak self] _ in
            guard let self = self else { return }
            self.publisher.send(self)
        }
    }
}
