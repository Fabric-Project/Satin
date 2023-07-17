//
//  RaycastResult.swift
//  Satin
//
//  Created by Reza Ali on 11/29/22.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import Foundation
import simd

public struct RaycastResult {
    public let barycentricCoordinates: simd_float3
    public let distance: Float
    public let normal: simd_float3
    public let position: simd_float3
    public let primitiveIndex: UInt32
    public let object: Object
    public let submesh: Submesh?
    public let instance: Int
    public let data: Any?

    public init(barycentricCoordinates: simd_float3, distance: Float, normal: simd_float3, position: simd_float3, primitiveIndex: UInt32, object: Object, submesh: Submesh? = nil, instance: Int = 0, data: Any? = nil) {
        self.barycentricCoordinates = barycentricCoordinates
        self.distance = distance
        self.normal = normal
        self.position = position
        self.primitiveIndex = primitiveIndex
        self.object = object
        self.submesh = submesh
        self.instance = instance
        self.data = data
    }
}
