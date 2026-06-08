//
//  ValueCache.swift
//
//
//  Created by Taylor Holliday on 3/29/22.
//

import simd

struct ValueCache<T> {
    var value: T?

    // Pre-specialize for the matrix types used in Object to avoid generic metadata
    // instantiation overhead in the hot per-frame path (worldMatrix, normalMatrix, etc.).
    @_specialize(exported: true, where T == matrix_float4x4)
    @_specialize(exported: true, where T == matrix_float3x3)
    @_specialize(exported: true, where T == simd_float3)
    @_specialize(exported: true, where T == simd_quatf)
    mutating func get(_ compute: () -> T) -> T {
        if let v = value { return v }
        let v = compute()
        value = v
        return v
    }

    mutating func clear() {
        value = nil
    }
}
