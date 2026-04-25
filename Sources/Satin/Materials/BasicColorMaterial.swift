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
    public var color: simd_float4 {
        set {
            set("Color", newValue)
        }
        get {
            get("Color", as: Float4Parameter.self)!.value
        }
    }

    public init(color: simd_float4 = simd_float4(repeating: 1.0), blending: Blending = .alpha) {
        super.init()
        set("Color", color)
        self.blending = blending
    }

    public required init() {
        super.init()
        set("Color", simd_float4.one)
        blending = .alpha
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
