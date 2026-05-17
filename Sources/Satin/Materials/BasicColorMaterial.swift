//
//  BasicColorMaterial.swift
//  Satin
//
//  Created by Reza Ali on 9/25/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal
import simd

open class BasicColorMaterial: Material {
    override open var lightingModel: LightingModel { .unlit }
    override var supportsAlphaOrderIndependentTransparency: Bool { true }
    public var color: simd_float4 {
        set {
            set("Color", newValue)
        }
        get {
            get("Color", as: Float4Parameter.self)!.value
        }
    }

    public var pointSize: Float {
        get { get("Point Size", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Point Size", newValue) }
    }

    public init(context: Context, color: simd_float4 = simd_float4(repeating: 1.0), blending: Blending = .disabled) {
        super.init(context: context)
        set("Color", color)
        set("Point Size", Float(1.0))
        self.blending = blending
    }

    public required init(context: Context) {
        super.init(context: context)
        set("Color", simd_float4.one)
        set("Point Size", Float(1.0))
        blending = .disabled
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
