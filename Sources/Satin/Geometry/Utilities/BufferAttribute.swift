//
//  BufferAttribute.swift
//
//
//  Created by Reza Ali on 7/13/23.
//

import Combine
import Foundation
import Metal
import simd

open class BufferAttribute: VertexAttribute, Codable {
    public weak var delegate: BufferAttributeDelegate?
    public var needsUpdate: Bool = true
    public var buffer: MTLBuffer?

    open var length: Int { count * stride }

    public override init() {
        super.init()
    }

    public required init(from decoder: Decoder) throws {
        super.init()
    }

    open func encode(to encoder: Encoder) throws {}
    open func getBuffer(device: MTLDevice) -> MTLBuffer? { nil }
    open func getData() -> Data { Data() }
    open func duplicate() -> BufferAttribute { fatalError("Subclasses must override duplicate()") }
    open func duplicate(at index: Int) { fatalError("Subclasses must override duplicate(at:)") }
    open func remove(at index: Int) { fatalError("Subclasses must override remove(at:)") }
    open func removeLast() { fatalError("Subclasses must override removeLast()") }
    open func removeLast(_ k: Int) { fatalError("Subclasses must override removeLast(_:)") }
    open func reserveCapacity(_ minimumCapacity: Int) { fatalError("Subclasses must override reserveCapacity(_:)") }
    open func resize(_ capacity: Int) { fatalError("Subclasses must override resize(_:)") }
    open func expand(_ size: Int) { fatalError("Subclasses must override expand(_:)") }
    open func interpolate(start: Int, end: Int, at time: Float) { fatalError("Subclasses must override interpolate(start:end:at:)") }
    open func set(at: Int, from: Int, source: BufferAttribute) { fatalError("Subclasses must override set(at:from:source:)") }
}

public protocol BufferAttributeDelegate: AnyObject {
    func updated(attribute: BufferAttribute)
}

open class GenericBufferAttribute<T: Codable>: BufferAttribute {
    public typealias ValueType = T

    open override var type: AttributeType { .generic }
    open override var format: MTLVertexFormat { type.format }

    open override var size: Int { MemoryLayout<T>.size }
    open override var stride: Int { MemoryLayout<T>.stride }
    open override var alignment: Int { MemoryLayout<T>.alignment }

    open override var components: Int { 0 }
    open override var count: Int { data.count }
    open override var length: Int { count * stride }

    public subscript<ValueType>(index: Int) -> ValueType {
        get {
            data[index] as! ValueType
        }
        set {
            data[index] = newValue as! T
        }
    }

    public var defaultValue: ValueType

    public var data: [ValueType] {
        didSet {
            needsUpdate = true
            delegate?.updated(attribute: self)
        }
    }

    public let attributeStepRate: Int
    public let attributeStepFunction: MTLVertexStepFunction

    public required init(defaultValue: ValueType, data: [ValueType], stepRate: Int = 1, stepFunction: MTLVertexStepFunction = .perVertex) {
        self.defaultValue = defaultValue
        self.data = data
        self.attributeStepRate = stepRate
        self.attributeStepFunction = stepFunction
        super.init()
    }

    public required init(defaultValue: ValueType, count: Int = 0, stepRate: Int = 1, stepFunction: MTLVertexStepFunction = .perVertex) {
        self.defaultValue = defaultValue
        self.data = Array(repeating: defaultValue, count: count)
        self.attributeStepRate = stepRate
        self.attributeStepFunction = stepFunction
        super.init()
    }

    open override var stepRate: Int { attributeStepRate }
    open override var stepFunction: MTLVertexStepFunction { attributeStepFunction }

    private enum CodingKeys: String, CodingKey {
        case defaultValue
        case data
        case count
        case stepRate
        case stepFunction
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let count = try container.decode(Int.self, forKey: .count)
        self.defaultValue = try container.decode(ValueType.self, forKey: .defaultValue)
        let bytes = try container.decode(Data.self, forKey: .data)
        var data: [ValueType] = []
        bytes.withUnsafeBytes { ptr in
            let typedPtr = ptr.baseAddress?.assumingMemoryBound(to: ValueType.self)
            data = Array(UnsafeBufferPointer(start: typedPtr, count: count))
        }
        self.data = data

        self.attributeStepRate = try container.decodeIfPresent(Int.self, forKey: .stepRate) ?? 1
        self.attributeStepFunction = try container.decodeIfPresent(MTLVertexStepFunction.self, forKey: .stepFunction) ?? .perVertex
        try super.init(from: decoder)
    }

    open override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(count, forKey: .count)
        try container.encode(defaultValue, forKey: .defaultValue)
        try container.encode(getData(), forKey: .data)
    }

    open override func getBuffer(device: MTLDevice) -> MTLBuffer? {
        guard length > 0 else { return nil }

        if needsUpdate {
            data.withUnsafeBytes { dataPtr in
                buffer = device.makeBuffer(bytes: dataPtr.baseAddress!, length: length)
            }
            needsUpdate = false
        }

        return buffer
    }

    open override func getData() -> Data {
        var result = Data()
        data.withUnsafeBytes { dataPtr in
            result = Data(bytes: dataPtr.baseAddress!, count: length)
        }
        return result
    }

    public func append(_ value: ValueType) {
        data.append(value)
    }

    open override func resize(_ capacity: Int) {
        if data.count < capacity {
            expand(capacity - data.count)
        } else if data.count > capacity {
            removeLast(data.count - capacity)
        }
    }

    open override func expand(_ size: Int = 1) {
        data.reserveCapacity(data.count + size)
        data.append(contentsOf: Array(repeating: defaultValue, count: size))
    }

    public func append(contentsOf array: [ValueType]) {
        data.append(contentsOf: array)
    }

    open override func reserveCapacity(_ minimumCapacity: Int) {
        data.reserveCapacity(minimumCapacity)
    }

    open override func duplicate() -> BufferAttribute {
        GenericBufferAttribute<ValueType>(defaultValue: defaultValue, data: data)
    }

    open override func duplicate(at index: Int) {
        data.append(data[index])
    }

    open override func remove(at index: Int) {
        data.remove(at: index)
    }

    open override func removeLast() {
        data.removeLast()
    }

    open override func removeLast(_ k: Int) {
        data.removeLast(k)
    }

    open override func interpolate(start: Int, end: Int, at time: Float) {
        fatalError("")
    }

    open override func set(at: Int, from: Int, source: BufferAttribute) {
        if let sourceBuffer = source as? GenericBufferAttribute<T> {
            data[at] = sourceBuffer[from]
        }
    }
}

public final class BoolBufferAttribute: GenericBufferAttribute<Bool> {
    override public var type: AttributeType { .bool }
    override public var components: Int { 1 }

    override public func duplicate() -> BufferAttribute {
        BoolBufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(time > 0.5 ? data[end] : data[start])
    }
}

public final class UInt16BufferAttribute: GenericBufferAttribute<UInt16> {
    override public var type: AttributeType { .uint16 }
    override public var components: Int { 1 }

    override public func duplicate() -> BufferAttribute {
        UInt16BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(UInt16(simd_mix(Float(data[start]), Float(data[end]), time)))
    }
}

public final class UInt32BufferAttribute: GenericBufferAttribute<UInt32> {
    override public var type: AttributeType { .uint32 }
    override public var components: Int { 1 }

    override public func duplicate() -> BufferAttribute {
        UInt32BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(UInt32(simd_mix(Float(data[start]), Float(data[end]), time)))
    }
}

public final class IntBufferAttribute: GenericBufferAttribute<simd_int1> {
    override public var type: AttributeType { .int }
    override public var components: Int { 1 }

    override public func duplicate() -> BufferAttribute {
        IntBufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(Int32(simd_mix(Float(data[start]), Float(data[end]), time)))
    }
}

public final class Int2BufferAttribute: GenericBufferAttribute<simd_int2> {
    override public var type: AttributeType { .int2 }
    override public var components: Int { 2 }

    override public func duplicate() -> BufferAttribute {
        Int2BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        let startValue = data[start]
        let endValue = data[end]
        append(
            simd_make_int2(
                Int32(simd_mix(Float(startValue.x), Float(endValue.x), time)),
                Int32(simd_mix(Float(startValue.y), Float(endValue.y), time))
            )
        )
    }
}

public final class Int3BufferAttribute: GenericBufferAttribute<simd_int3> {
    override public var type: AttributeType { .int3 }
    override public var components: Int { 3 }

    override public func duplicate() -> BufferAttribute {
        Int3BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        let startValue = data[start]
        let endValue = data[end]
        append(
            simd_make_int3(
                Int32(simd_mix(Float(startValue.x), Float(endValue.x), time)),
                Int32(simd_mix(Float(startValue.y), Float(endValue.y), time)),
                Int32(simd_mix(Float(startValue.z), Float(endValue.z), time))
            )
        )
    }
}

public final class Int4BufferAttribute: GenericBufferAttribute<simd_int4> {
    override public var type: AttributeType { .int4 }
    override public var components: Int { 4 }

    override public func duplicate() -> BufferAttribute {
        Int4BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        let startValue = data[start]
        let endValue = data[end]
        append(
            simd_make_int4(
                Int32(simd_mix(Float(startValue.x), Float(endValue.x), time)),
                Int32(simd_mix(Float(startValue.y), Float(endValue.y), time)),
                Int32(simd_mix(Float(startValue.z), Float(endValue.z), time)),
                Int32(simd_mix(Float(startValue.z), Float(endValue.z), time))
            )
        )
    }
}

public final class LongBufferAttribute: GenericBufferAttribute<Int> {
    override public var type: AttributeType { .long }
    override public var components: Int { 1 }

    override public func duplicate() -> BufferAttribute {
        LongBufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(Int(simd_mix(Float(data[start]), Float(data[end]), time)))
    }
}

public final class FloatBufferAttribute: GenericBufferAttribute<simd_float1> {
    override public var type: AttributeType { .float }
    override public var components: Int { 1 }

    override public func duplicate() -> BufferAttribute {
        FloatBufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(simd_mix(data[start], data[end], time))
    }
}

public final class Float2BufferAttribute: GenericBufferAttribute<simd_float2> {
    override public var type: AttributeType { .float2 }
    override public var components: Int { 2 }

    override public func duplicate() -> BufferAttribute {
        Float2BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(simd_mix(data[start], data[end], simd_float2(repeating: time)))
    }
}

public final class Float3BufferAttribute: GenericBufferAttribute<simd_float3> {
    override public var type: AttributeType { .float3 }
    override public var components: Int { 3 }

    override public func duplicate() -> BufferAttribute {
        Float3BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(simd_mix(data[start], data[end], simd_float3(repeating: time)))
    }
}

public final class Float4BufferAttribute: GenericBufferAttribute<simd_float4> {
    override public var type: AttributeType { .float4 }
    override public var components: Int { 4 }

    override public func duplicate() -> BufferAttribute {
        Float4BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        append(simd_mix(data[start], data[end], simd_float4(repeating: time)))
    }
}

public final class PackedFloat3BufferAttribute: GenericBufferAttribute<MTLPackedFloat3> {
    override public var type: AttributeType { .float3 }
    override public var components: Int { 3 }

    override public func duplicate() -> BufferAttribute {
        PackedFloat3BufferAttribute(defaultValue: defaultValue, data: data)
    }

    override public func interpolate(start: Int, end: Int, at time: Float) {
        let startValue = data[start]
        let endValue = data[end]
        append(
            MTLPackedFloat3Make(
                simd_mix(startValue.x, endValue.x, time),
                simd_mix(startValue.y, endValue.y, time),
                simd_mix(startValue.z, endValue.z, time)
            )
        )
    }
}
