//
//  BasicDiffuseMaterial.swift
//  Satin
//
//  Created by Reza Ali on 7/26/20.
//

import Metal
import simd

public final class BasicDiffuseMaterial: BasicColorMaterial {
    override public var lightingModel: LightingModel { .surface }
    override public var supportedOutputs: RendererOutputs { [.color, .albedo, .normals, .pbr, .velocity, .emissive] }

    public var ambient: Float {
        get {
            get("Ambient", as: FloatParameter.self)!.value
        }
        set {
            set("Ambient", newValue)
        }
    }

    public var hardness: Float {
        get {
            get("Hardness", as: FloatParameter.self)!.value
        }
        set {
            set("Hardness", newValue)
        }
    }

    public init(context: Context, color: simd_float4 = .one, blending: Blending = .alpha, hardness: Float = 0.75) {
        super.init(context: context, color: color, blending: blending)
        lighting = true
        ambient = 0.0
        self.hardness = hardness
    }

    public required init(context: Context) {
        super.init(context: context)
        lighting = true
        ambient = 0.0
        hardness = 0.75
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
