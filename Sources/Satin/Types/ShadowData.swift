//
//  ShadowData.swift
//  Satin
//
//  Created by Reza Ali on 3/9/23.
//  Copyright © 2023 Reza Ali. All rights reserved.
//

import Foundation
import simd

public struct ShadowData {
    var parameters: simd_float4
    var indices: simd_uint4

    init(
        strength: Float,
        bias: Float,
        normalBias: Float,
        radius: Float,
        textureIndex: UInt32 = 0,
        matrixIndex: UInt32 = 0,
        viewCount: UInt32 = 1
    ) {
        parameters = simd_make_float4(strength, bias, normalBias, radius)
        indices = simd_make_uint4(textureIndex, matrixIndex, viewCount, 0)
    }
}
