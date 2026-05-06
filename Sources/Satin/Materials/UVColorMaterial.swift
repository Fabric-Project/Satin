//
//  UVMaterial.swift
//  Satin
//
//  Created by Reza Ali on 4/18/20.
//

import Metal

public final class UVColorMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public var pointSize: Float {
        get { get("Point Size", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Point Size", newValue) }
    }

    public required init(context: Context) {
        super.init(context: context)
        set("Point Size", Float(1.0))
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
