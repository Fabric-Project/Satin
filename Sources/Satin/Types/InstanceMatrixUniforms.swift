//
//  InstanceMatrixUniforms.swift
//  Satin
//
//  Created by Reza Ali on 10/19/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import simd

public struct InstanceMatrixUniforms {
    public var modelMatrix: float4x4
    public var normalMatrix: float3x3
    /// Last frame's `modelMatrix`, so instance motion reaches the velocity output. Maintained
    /// by `InstancedMesh`; equal to `modelMatrix` when the instance has not moved.
    public var previousModelMatrix: float4x4

    public init(modelMatrix: float4x4 = matrix_identity_float4x4, normalMatrix: float3x3 = matrix_identity_float3x3) {
        self.modelMatrix = modelMatrix
        self.normalMatrix = normalMatrix
        previousModelMatrix = modelMatrix
    }
}
