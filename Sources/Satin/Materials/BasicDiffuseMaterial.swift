//
//  BasicDiffuseMaterial.swift
//  Satin
//
//  Created by Reza Ali on 7/26/20.
//

import Metal
import simd

public final class BasicDiffuseMaterial: BasicColorMaterial {
    public var hardness: Float {
        get {
            get("Hardness", as: FloatParameter.self)!.value
        }
        set {
            set("Hardness", newValue)
        }
    }

    public init(color: simd_float4 = .one, blending: Blending = .alpha, hardness: Float = 0.75) {
        super.init(color: color, blending: blending)
        self.hardness = hardness
    }

    public required init() {
        super.init()
        hardness = 0.75
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
