//
//  BasicColorMaterial.swift
//  Satin
//
//  Created by Reza Ali on 9/25/19.
//  Copyright © 2019 Reza Ali. All rights reserved.
//

import Metal

public final class NormalColorMaterial: Material {
    override public var lightingModel: LightingModel { .unlit }

    public var pointSize: Float {
        get { get("Point Size", as: FloatParameter.self)?.value ?? 1.0 }
        set { set("Point Size", newValue) }
    }

    public init(context: Context, _ absolute: Bool = false) {
        super.init(context: context)
        set("Absolute", absolute)
        set("Point Size", Float(1.0))
    }

    public required init(context: Context) {
        super.init(context: context)
        set("Absolute", false)
        set("Point Size", Float(1.0))
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
