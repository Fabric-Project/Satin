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
            color: simd_make_float4(renderSnapshotColor, renderSnapshotIntensity),
            // (xyz, type)
            position: simd_make_float4(renderSnapshotWorldPosition, Float(type.rawValue)),
            // (xyz, inverse radius)
            direction: simd_make_float4(-renderSnapshotWorldForwardDirection, 0.0),
            // (spotScale, spotOffset, cosInner, cosOuter)
            spotInfo: .zero,
            // (shadowIndex, projectorIndex, projectorMode, unused)
            shadowInfo: simd_make_float4(Float(shadowIndex), Float(projectorIndex), 0.0, 0.0)
        )
    }

    override public var castShadow:Bool  {
        didSet {
            shadowStateDirty = true
            lightStateDirty = true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case color
        case intensity
    }

    public init(context: Context, label: String = "Directional Light", color: simd_float3, intensity: Float = 1.0) {
        super.init(context: context, label: label)
        self.color = color
        self.intensity = intensity
        self.shadow = DirectionalShadow(context: context, label: label)
    }
        
    public required init(from decoder: Decoder) throws {
        let context = try decoder.requireSatinContext(typeName: "DirectionalLight")
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        color = try values.decode(simd_float3.self, forKey: .color)
//        intensity = try values.decode(Float.self, forKey: .intensity)
        try super.init(from: decoder)
        shadow = DirectionalShadow(context: context, label: label)
    }

    override public func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(color, forKey: .color)
//        try container.encode(intensity, forKey: .intensity)
    }

    override public func setup() {
        super.setup()
        shadowStateDirty = true
    }

    override public func updateShadowForRender() {
        guard castShadow, let directionalShadow = shadow as? DirectionalShadow else { return }
        directionalShadow.device = context.device
        directionalShadow.update(light: self)
    }
}
