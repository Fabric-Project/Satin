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

    public var projectionTexture: MTLTexture? {
        didSet {
            updateProjectorCamera()
            publisher.send(self)
        }
    }

    public var projectionMode: SpotLightProjectionMode = .mask {
        didSet {
            publisher.send(self)
        }
    }

    public var projectionAspect: Float? {
        didSet {
            updateProjectorCamera()
            publisher.send(self)
        }
    }

    public var projectionTransform = matrix_identity_float3x3 {
        didSet {
            publisher.send(self)
        }
    }

    public var projectorMatrix: simd_float4x4 {
        projectorCamera.viewProjectionMatrix
    }

    private let projectorCamera: PerspectiveCamera

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
            direction: simd_make_float4(-worldForwardDirection, 1.0 / max(radius, 1e-4)),
            // (spotScale, spotOffset, cosInner, cosOuter)
            spotInfo: simd_make_float4(spotScale, spotOffset, cosInner, cosOuter),
            // (shadowIndex, projectorIndex, projectorMode, unused)
            shadowInfo: simd_make_float4(Float(shadowIndex), Float(projectorIndex), Float(projectionMode.rawValue), 0.0)
        )
    }

    override public var castShadow: Bool {
        didSet {
            setupShadow()
        }
    }

    public var radius: Float {
        didSet {
            updateProjectorCamera()
            shadow.update(light: self)
            publisher.send(self)
        }
    }

    public var angleInner: Float {
        didSet {
            updateProjectorCamera()
            publisher.send(self)
        }
    }

    public var angleOuter: Float {
        didSet {
            updateProjectorCamera()
            shadow.update(light: self)
            publisher.send(self)
        }
    }

    private var transformSubscriber: AnyCancellable?

    private enum CodingKeys: String, CodingKey {
        case radius
        case angleInner
        case angleOuter
    }

    public init(context: Context, label: String = "Spot Light", color: simd_float3, intensity: Float = 1.0, radius: Float = 4.0, angleInner: Float = 60.0, angleOuter: Float = 90.0) {
        self.radius = radius
        self.angleInner = angleInner
        self.angleOuter = angleOuter
        projectorCamera = PerspectiveCamera(context: context, label: "\(label) Projector", position: .zero, near: 0.01, far: radius, fov: angleOuter * 2.0)
        super.init(context: context, label: label)
        self.color = color
        self.intensity = intensity
        self.shadow = SpotShadow(context: context, label: label)
        updateProjectorCamera()
    }

    public required init(from decoder: Decoder) throws {
        let context = try decoder.requireSatinContext(typeName: "SpotLight")
        let values = try decoder.container(keyedBy: CodingKeys.self)
        radius = try values.decode(Float.self, forKey: .radius)
        angleInner = try values.decode(Float.self, forKey: .angleInner)
        angleOuter = try values.decode(Float.self, forKey: .angleOuter)
        projectorCamera = PerspectiveCamera(context: context, label: "Spot Projector", position: .zero, near: 0.01, far: radius, fov: angleOuter * 2.0)
        try super.init(from: decoder)
        shadow = SpotShadow(context: context, label: label)
        updateProjectorCamera()
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
            self.shadow.update(light: self)
            self.updateProjectorCamera()
            self.publisher.send(self)
        }
        setupShadow()
    }

    private func setupShadow() {
        guard castShadow, let spotShadow = shadow as? SpotShadow else { return }
        spotShadow.device = context.device
        spotShadow.update(light: self)
    }

    private func updateProjectorCamera() {
        projectorCamera.position = worldPosition
        projectorCamera.lookAt(target: worldPosition + worldForwardDirection, up: Satin.worldUpDirection)
        projectorCamera.fov = angleOuter * 2.0
        projectorCamera.aspect = resolvedProjectionAspect
        projectorCamera.near = 0.01
        projectorCamera.far = max(radius, projectorCamera.near + 0.01)
    }

    private var resolvedProjectionAspect: Float {
        if let projectionAspect {
            return projectionAspect
        }

        if let projectionTexture, projectionTexture.height > 0 {
            return Float(projectionTexture.width) / Float(projectionTexture.height)
        }

        return 1.0
    }
}
