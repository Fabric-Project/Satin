//
//  PublishedAttribute.swift
//  Satin
//

import Metal

/// The scalar type of each component of an attribute.
public enum AttributeScalar: Equatable {
    case float32
    case float16
    case int32
    case uint32
    case int16
    case uint16
    case uint8
    /// Bytes read as 0 to 1.
    case uint8Normalized

    public var byteSize: Int {
        switch self {
            case .float32, .int32, .uint32: return 4
            case .float16, .int16, .uint16: return 2
            case .uint8, .uint8Normalized: return 1
        }
    }
}

/// Where each element of an attribute sits in its buffer: `components` scalars, starting
/// `byteOffset` bytes in, one element every `byteStride` bytes. A float3 packed into 12 bytes and
/// one padded to 16 are different layouts.
public struct AttributeLayout: Equatable {
    public let scalar: AttributeScalar
    public let components: Int
    public let byteOffset: Int
    public let byteStride: Int

    public init(scalar: AttributeScalar, components: Int, byteOffset: Int, byteStride: Int) {
        precondition(components > 0, "An attribute has at least one component")
        precondition(byteOffset >= 0, "An attribute's offset can't be negative")
        precondition(byteStride >= scalar.byteSize * components, "An element must fit within its stride")
        self.scalar = scalar
        self.components = components
        self.byteOffset = byteOffset
        self.byteStride = byteStride
    }

    /// The bytes one element's components take, without padding.
    public var elementSize: Int { scalar.byteSize * components }

    /// The vertex format describing one element, or nil when a vertex descriptor can't: more than
    /// four components, or a stride Metal's vertex layouts don't accept (not a multiple of four).
    /// An attribute without one is pulled: its shader reads its buffer directly.
    public var vertexFormat: MTLVertexFormat? {
        guard components <= 4, byteStride % 4 == 0 else { return nil }
        switch (scalar, components) {
            case (.float32, 1): return .float
            case (.float32, 2): return .float2
            case (.float32, 3): return .float3
            case (.float32, 4): return .float4
            case (.float16, 1): return .half
            case (.float16, 2): return .half2
            case (.float16, 3): return .half3
            case (.float16, 4): return .half4
            case (.int32, 1): return .int
            case (.int32, 2): return .int2
            case (.int32, 3): return .int3
            case (.int32, 4): return .int4
            case (.uint32, 1): return .uint
            case (.uint32, 2): return .uint2
            case (.uint32, 3): return .uint3
            case (.uint32, 4): return .uint4
            case (.int16, 1): return .short
            case (.int16, 2): return .short2
            case (.int16, 3): return .short3
            case (.int16, 4): return .short4
            case (.uint16, 1): return .ushort
            case (.uint16, 2): return .ushort2
            case (.uint16, 3): return .ushort3
            case (.uint16, 4): return .ushort4
            case (.uint8, 1): return .uchar
            case (.uint8, 2): return .uchar2
            case (.uint8, 3): return .uchar3
            case (.uint8, 4): return .uchar4
            case (.uint8Normalized, 1): return .ucharNormalized
            case (.uint8Normalized, 2): return .uchar2Normalized
            case (.uint8Normalized, 3): return .uchar3Normalized
            case (.uint8Normalized, 4): return .uchar4Normalized
            default: return nil
        }
    }
}

/// An attribute whose contents never change once published, so any number of geometries, ports,
/// held values and recorded draws can share it. To change it, publish a new one.
///
/// Publishing hands the buffer over: whoever wrote it makes no further writes to it through any
/// reference it keeps. Satin can't enforce that for a buffer the producer still holds, so it is
/// the producer's side of the contract. The buffer lives until its last owner, a CPU reference or
/// a command buffer using it, releases it.
///
/// Unlike `BufferAttribute`, which is the mutable builder, this has no data to edit and nothing to
/// re-upload: a geometry binds `buffer` as it is.
public final class PublishedAttribute: VertexAttribute {
    public let layout: AttributeLayout
    public let buffer: MTLBuffer
    /// Unique among everything published in this process; equal versions mean the same contents.
    public let version: UInt64
    private let elementCount: Int

    /// Publishes `count` elements already written to `buffer` in `layout`, such as a compute pass's
    /// output or a plugin's own buffer. The caller hands the buffer over (see the type's notes).
    public init(adopting buffer: MTLBuffer, layout: AttributeLayout, count: Int) {
        precondition(count >= 0, "An attribute can't have a negative count")
        precondition(count == 0 || layout.byteOffset + (count - 1) * layout.byteStride + layout.elementSize <= buffer.length,
                     "The buffer is too short for \(count) elements in this layout")
        self.layout = layout
        self.buffer = buffer
        self.elementCount = count
        self.version = PublishedVersion.next()
        super.init()
    }

    /// Publishes a copy of `values` in a new buffer from `allocator`, one element per value at the
    /// element type's stride (16 bytes for `simd_float3`). Each value's first `components` scalars
    /// are its components.
    public static func publishing<Element>(_ values: ContiguousArray<Element>,
                                           scalar: AttributeScalar,
                                           components: Int,
                                           allocator: GPUAllocator,
                                           label: String? = nil) throws -> PublishedAttribute
    {
        let elementStride = MemoryLayout<Element>.stride
        let layout = AttributeLayout(scalar: scalar, components: components, byteOffset: 0, byteStride: elementStride)
        precondition(layout.elementSize <= MemoryLayout<Element>.size, "Each value must hold \(components) components")
        // Metal has no empty buffers: an empty attribute still gets one element's worth.
        let buffer = try allocator.makeBuffer(length: max(elementStride * values.count, elementStride),
                                              memoryClass: .cpuWrites,
                                              label: label)
        values.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                buffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
            }
        }
        return PublishedAttribute(adopting: buffer, layout: layout, count: values.count)
    }

    /// Read by its shader from `buffer` instead of through the vertex descriptor.
    public var isPulled: Bool { layout.vertexFormat == nil }

    public override var format: MTLVertexFormat { layout.vertexFormat ?? .invalid }
    public override var count: Int { elementCount }
    public override var size: Int { layout.elementSize }
    public override var stride: Int { layout.byteStride }
    public override var alignment: Int { layout.scalar.byteSize }
    public override var components: Int { layout.components }
}

/// Hands out the versions of published values: one counter for the whole process, so versions
/// from unrelated producers never coincide. Compared only for equality; wrapping after 2^64
/// publishes is harmless.
enum PublishedVersion {
    private static let lock = UnfairLock()
    private nonisolated(unsafe) static var lastVersion: UInt64 = 0

    static func next() -> UInt64 {
        lock.sync {
            lastVersion &+= 1
            return lastVersion
        }
    }
}
