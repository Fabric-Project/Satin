//
//  PointLight.swift
//  Satin
//
//  Created by Reza Ali on 11/6/22.
//

import Combine
import Foundation
import Metal
import simd

public final class PointLight: Light {
    override public var type: LightType { .point }

    override public var data: LightData {
        LightData(
            // (rgb, intensity)
            color: simd_make_float4(color, intensity),
            // (xyz, type)
            position: simd_make_float4(worldPosition, Float(type.rawValue)),
            // (xyz, inverse radius)
            direction: simd_make_float4(-worldForwardDirection, 1.0 / radius),
            // (spotScale, spotOffset, cosInner, cosOuter)
            spotInfo: .zero,
            // (shadowIndex, projectorIndex, projectorMode, unused)
            shadowInfo: simd_make_float4(Float(shadowIndex), Float(projectorIndex), 0.0, 0.0)
        )
    }
    
    override public var castShadow: Bool {
        didSet {
            setupShadow()
        }
    }
    
    public var radius: Float {
        didSet {
            shadow.update(light: self)
            publisher.send(self)
        }
    }

    private var transformSubscriber: AnyCancellable?

    private enum CodingKeys: String, CodingKey {
        case radius
    }

    public init(context: Context, label: String = "Point Light", color: simd_float3, intensity: Float = 1.0, radius: Float = 4.0) {
        self.radius = radius
        super.init(context: context, label: label)
        self.color = color
        self.intensity = intensity
        self.shadow = PointShadow(context: context, label: label)
    }

    public required init(from decoder: Decoder) throws {
        let context = try decoder.requireSatinContext(typeName: "PointLight")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        radius = try values.decode(Float.self, forKey: .radius)
        try super.init(from: decoder)
        shadow = PointShadow(context: context, label: label)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(radius, forKey: .radius)
    }

    override public func setup() {
        super.setup()
        transformSubscriber = transformPublisher.sink { [weak self] _ in
            guard let self = self else { return }
            self.shadow.update(light: self)
            self.publisher.send(self)
        }
        setupShadow()
    }

    private func setupShadow() {
        guard castShadow, let pointShadow = shadow as? PointShadow else { return }
        pointShadow.device = context.device
        pointShadow.update(light: self)
    }
}
