//
//  DirectionalLight.swift
//  Satin
//
//  Created by Reza Ali on 11/3/22.
//

import Combine
import Foundation
import Metal
import simd

public final class DirectionalLight: Light {
    override public var type: LightType { .directional }

    override public var data: LightData {
        LightData(
            // (rgb, intensity)
            color: simd_make_float4(color, intensity),
            // (xyz, type)
            position: simd_make_float4(worldPosition, Float(type.rawValue)),
            // (xyz, inverse radius)
            direction: simd_make_float4(-worldForwardDirection, 0.0),
            // (spotScale, spotOffset, cosInner, cosOuter)
            spotInfo: .zero
        )
    }

    override public var castShadow:Bool  {
        didSet {
            setupShadow()
        }
    }

    private var transformSubscriber: AnyCancellable?

    private enum CodingKeys: String, CodingKey {
        case color
        case intensity
    }

    public init(label: String = "Directional Light", color: simd_float3, intensity: Float = 1.0) {

        super.init(label: label)

        self.color = color
        self.intensity = intensity
        self.shadow = DirectionalLightShadow(label: label)
    }
        
    public required init(from decoder: Decoder) throws {
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        color = try values.decode(simd_float3.self, forKey: .color)
//        intensity = try values.decode(Float.self, forKey: .intensity)
        try super.init(from: decoder)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(color, forKey: .color)
//        try container.encode(intensity, forKey: .intensity)
    }

    override public func setup() {
        super.setup()
        setupTransformSubscriber()
        setupShadow()
    }

    func setupTransformSubscriber() {
        transformSubscriber = transformPublisher.sink { [weak self] _ in
            guard let self = self else { return }
            self.shadow.update(light: self)
            self.publisher.send(self)
        }
    }

    func setupShadow() {
        guard castShadow, let directionalShadow = shadow as? DirectionalLightShadow, let context else { return }
        directionalShadow.device = context.device
        directionalShadow.update(light: self)
    }
}
