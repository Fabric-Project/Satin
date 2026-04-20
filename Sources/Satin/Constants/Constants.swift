//
//  Defines.swift
//  Satin
//
//  Created by Reza Ali on 7/23/19.
//  Copyright © 2022 Reza Ali. All rights reserved.
//

import ModelIO
import simd

public let maxBuffersInFlight = 3

// Max sub-passes per frame (shadow face passes + main pass).
// 32 supports up to 5 point lights (30 faces) + 1 main = 31 passes.
public let maxSubPassesPerFrame = 32

public let worldForwardDirection = simd_make_float3(0, 0, 1)
public let worldUpDirection = simd_make_float3(0, 1, 0)
public let worldRightDirection = simd_make_float3(1, 0, 0)
