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
    public init(context: Context, _ absolute: Bool = false) {
        super.init(context: context)
        set("Absolute", absolute)
    }

    public required init(context: Context) {
        super.init(context: context)
        set("Absolute", false)
    }

    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
}
