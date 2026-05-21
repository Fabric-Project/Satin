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

    var shadowIndex: Int = -1
    var projectorIndex: Int = -1
    
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
    internal var shadowStateDirty = true
    internal var lightStateDirty = true
    private var previousRenderWorldPosition: simd_float3?
    private var previousRenderWorldForwardDirection: simd_float3?

    /// Per-frame render snapshot fields for light scalars, written by `prepareForRender()` on the render owner. Never mutated from authoring code during encoding. Read by `data` to produce `LightData` for the current frame.
    internal var renderSnapshotColor: simd_float3 = .zero
    internal var renderSnapshotIntensity: Float = 1.0

    public let publisher = PassthroughSubject<Light, Never>()
    
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

    override open func prepareForRender() {
        super.prepareForRender()

        renderSnapshotColor = color
        renderSnapshotIntensity = intensity
        shadow.prepareForRender()

        if let previousRenderWorldPosition,
           !simd_equal(previousRenderWorldPosition, renderSnapshotWorldPosition)
        {
            shadowStateDirty = true
            lightStateDirty = true
        }

        if let previousRenderWorldForwardDirection,
           !simd_equal(previousRenderWorldForwardDirection, renderSnapshotWorldForwardDirection)
        {
            shadowStateDirty = true
            lightStateDirty = true
        }

        if shadowStateDirty {
            updateShadowForRender()
            shadowStateDirty = false
        }
        lightStateDirty = false

        previousRenderWorldPosition = renderSnapshotWorldPosition
        previousRenderWorldForwardDirection = renderSnapshotWorldForwardDirection
    }

    open func updateShadowForRender() {}
}
