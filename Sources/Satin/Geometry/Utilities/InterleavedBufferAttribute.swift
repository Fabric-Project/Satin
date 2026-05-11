//
//  File.swift
//
//
//  Created by Reza Ali on 7/13/23.
//

import Foundation
import Metal
import simd

open class GenericInterleavedBufferAttribute<T: Codable>: InterleavedBufferAttribute {
    public typealias ValueType = T

    open override var type: AttributeType { .generic }
    open override var format: MTLVertexFormat { type.format }
    open override var count: Int { parent.count }

    open override var size: Int { MemoryLayout<ValueType>.size }
    open override var stride: Int { MemoryLayout<ValueType>.stride }
    open override var alignment: Int { MemoryLayout<ValueType>.alignment }
    open override var components: Int { 0 }

    public let attributeStepRate: Int
    public let attributeStepFunction: MTLVertexStepFunction

    public init(parent: InterleavedBuffer, offset: Int, stepRate: Int = 1, stepFunction: MTLVertexStepFunction = .perVertex) {
        self.attributeStepRate = stepRate
        self.attributeStepFunction = stepFunction
        super.init(parent: parent, offset: offset)
    }

    open override var stepRate: Int { attributeStepRate }
    open override var stepFunction: MTLVertexStepFunction { attributeStepFunction }
}

public final class FloatInterleavedBufferAttribute: GenericInterleavedBufferAttribute<Float> {
    override public var type: AttributeType { .float }
    override public var components: Int { 1 }
}

public final class Float2InterleavedBufferAttribute: GenericInterleavedBufferAttribute<simd_float2> {
    override public var type: AttributeType { .float2 }
    override public var components: Int { simd_float2.scalarCount }
}

public final class Float3InterleavedBufferAttribute: GenericInterleavedBufferAttribute<simd_float3> {
    override public var type: AttributeType { .float3 }
    override public var components: Int { simd_float3.scalarCount }
}

public final class Float4InterleavedBufferAttribute: GenericInterleavedBufferAttribute<simd_float4> {
    override public var type: AttributeType { .float4 }
    override public var components: Int { simd_float4.scalarCount }
}

// public final class PackedFloat3InterleavedBufferAttribute: GenericInterleavedBufferAttribute<simd_float3> {
//    override public var type: AttributeType { .packedfloat3 }
//    override public var components: Int { simd_float3.scalarCount }
//
//    override public var size: Int { return 12 }
//    override public var stride: Int { return 12 }
//    override public var alignment: Int { return 4 }
// }
