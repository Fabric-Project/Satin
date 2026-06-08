//
//  Environment.swift
//
//
//  Created by Reza Ali on 4/25/23.
//

import Foundation
import Metal
import simd

open class IBLEnvironment: Object {
    open var environmentIntensity: Float = 1.0

    open var environment: MTLTexture?
    open var cubemapTexture: MTLTexture?

    open var irradianceTexture: MTLTexture?
    open var irradianceTexcoordTransform: simd_float3x3 = matrix_identity_float3x3

    open var reflectionTexture: MTLTexture?
    open var reflectionTexcoordTransform: simd_float3x3  = matrix_identity_float3x3
    open var brdfTexture: MTLTexture?
}
