//
//  Points.swift
//  Satin
//

import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// What a point attribute means. Standard ones always take the same slot; custom ones take
/// `Custom0` to `Custom8` in the order a `Points` declares them.
public enum PointAttribute: Hashable {
    case position
    case normal
    case color
    case texcoord
    /// Size in pixels, multiplying a material's point size.
    case size
    case custom(String)

    /// The slot this attribute always takes, or nil for a custom one.
    public var standardIndex: VertexAttributeIndex? {
        switch self {
            case .position: return .Position
            case .normal: return .Normal
            case .color: return .Color
            case .texcoord: return .Texcoord
            case .size: return .PointSize
            case .custom: return nil
        }
    }

    /// The slots custom attributes take, in declaration order. `Custom9` and `Custom10` are
    /// reserved for `PointSize` and `PreviousPosition`.
    public static let customIndices: [VertexAttributeIndex] = [
        .Custom0, .Custom1, .Custom2, .Custom3, .Custom4, .Custom5, .Custom6, .Custom7, .Custom8
    ]
}

/// One run of connected points: `range` of a `Points`' indices, back to its first when `closed`.
public struct PointStrip: Equatable {
    public let range: Range<Int>
    public let closed: Bool

    public init(range: Range<Int>, closed: Bool) {
        self.range = range
        self.closed = closed
    }
}

/// How a set of points connects.
public enum PointTopology {
    /// Every point in order: points, or one line or triangle list through them all.
    case implicit
    /// Separate runs, drawn as line or triangle strips with a break between each.
    case strips(ContiguousArray<PointStrip>)
    /// An index list, for any primitive.
    case indexed(ContiguousArray<UInt32>)
}

/// Whether the box around a set of points is known. Unknown bounds, as for points a GPU pass wrote,
/// are never culled.
public enum PointsBounds {
    case known(Bounds)
    case unknown

    /// The box around `positions`; unknown when there are none.
    public static func of(_ positions: ContiguousArray<simd_float3>) -> PointsBounds {
        guard !positions.isEmpty else { return .unknown }
        var bounds = createBounds()
        for position in positions {
            bounds = expandBounds(bounds, position)
        }
        return .known(bounds)
    }
}

public enum PointsError: Error, Equatable {
    case missingPosition
    case duplicateAttribute(PointAttribute)
    /// More custom attributes than `PointAttribute.customIndices` has slots for.
    case tooManyCustomAttributes(limit: Int)
    /// An attribute with fewer elements than there are positions.
    case attributeTooShort(PointAttribute)
    /// A strip or index that reaches past the last point.
    case topologyOutOfRange
    /// Strips that overlap or aren't in the order of their first points.
    case stripsOutOfOrder
    /// A GPU-written count with strips or indices, which would index past what was drawn.
    case drawArgumentsNeedImplicitTopology
    /// Draw arguments whose record isn't wholly inside their buffer, or at an offset that isn't a
    /// multiple of 4.
    case drawArgumentsOutOfRange
}

/// A count of points to draw that a GPU pass wrote: a whole `MTLDrawPrimitivesIndirectArguments`
/// (count, instance count 1, vertex start 0, base instance 0) in `buffer` at `offset`, read by GPU
/// passes and indirect draws. Immutable once published, like the points' attributes.
public struct PointsDrawArguments {
    public let buffer: MTLBuffer
    public let offset: Int

    /// Bytes in one record.
    public static let recordLength = MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride

    /// Throws `drawArgumentsOutOfRange` unless the record at `offset` is 4-byte aligned and lies
    /// wholly inside `buffer`.
    public init(buffer: MTLBuffer, offset: Int) throws {
        guard offset >= 0, offset % 4 == 0,
              offset <= buffer.length - Self.recordLength
        else { throw PointsError.drawArgumentsOutOfRange }
        self.buffer = buffer
        self.offset = offset
    }

    /// The same record: the same buffer at the same offset.
    public func isSameRecord(as other: PointsDrawArguments) -> Bool {
        buffer === other.buffer && offset == other.offset
    }
}

/// A published set of points: immutable, so it can be held, queued and drawn by any number of
/// consumers while its producer publishes the next. Draw it with `Geometry(context:points:primitiveType:)`.
///
/// Attributes are resolved to their slots once, when the points are made: standard ones to their
/// fixed slots, custom ones to `Custom0` onward in the order given.
public struct Points: Equatable {
    /// The attributes as declared, position first.
    public let attributes: ContiguousArray<(key: PointAttribute, attribute: PublishedAttribute)>
    /// Each attribute with the slot it binds to.
    public let slots: ContiguousArray<(index: VertexAttributeIndex, attribute: PublishedAttribute)>
    public let position: PublishedAttribute
    public let topology: PointTopology
    /// The topology's indices, made once: strips with a restart between each, or the index list.
    public let elements: ElementBuffer?
    public let bounds: PointsBounds
    /// Where a GPU pass wrote how many of these points to draw, as `MTLDrawPrimitivesIndirectArguments`,
    /// for points whose count only the GPU knows; `count` is then their capacity. Nil draws `count`.
    public let drawArguments: PointsDrawArguments?
    /// Unique among everything published in this process; a new publish always has a new one.
    public let version: UInt64

    public var count: Int { position.count }

    /// An index list or strips with nothing in them: these points connect to nothing, so draw nothing.
    public var drawsNothing: Bool {
        switch topology {
            case .implicit: return false
            case .indexed, .strips: return elements == nil
        }
    }

    /// Points with `attributes`, which must include `.position` and may each appear once. Every
    /// attribute has at least as many elements as there are positions. `drawArguments` gives a count a
    /// GPU pass wrote, for implicit topology only.
    public init(attributes: [(PointAttribute, PublishedAttribute)], topology: PointTopology, bounds: PointsBounds,
                drawArguments: PointsDrawArguments? = nil) throws {
        guard let position = attributes.first(where: { $0.0 == .position })?.1 else { throw PointsError.missingPosition }
        guard attributes.filter({ $0.0 == .position }).count == 1 else { throw PointsError.duplicateAttribute(.position) }

        var seen = Set<PointAttribute>()
        var declared = ContiguousArray<(key: PointAttribute, attribute: PublishedAttribute)>()
        var slots = ContiguousArray<(index: VertexAttributeIndex, attribute: PublishedAttribute)>()
        var nextCustom = 0
        // Position first, then the rest in the order given.
        for (key, attribute) in [(PointAttribute.position, position)] + attributes.filter({ $0.0 != .position }) {
            guard seen.insert(key).inserted else { throw PointsError.duplicateAttribute(key) }
            guard attribute.count >= position.count else { throw PointsError.attributeTooShort(key) }
            let index: VertexAttributeIndex
            if let standardIndex = key.standardIndex {
                index = standardIndex
            } else {
                guard nextCustom < PointAttribute.customIndices.count else {
                    throw PointsError.tooManyCustomAttributes(limit: PointAttribute.customIndices.count)
                }
                index = PointAttribute.customIndices[nextCustom]
                nextCustom += 1
            }
            declared.append((key, attribute))
            slots.append((index, attribute))
        }

        self.attributes = declared
        self.slots = slots
        self.position = position
        self.topology = topology
        self.elements = try Self.makeElements(for: topology, pointCount: position.count)
        self.bounds = bounds
        if drawArguments != nil {
            guard case .implicit = topology else { throw PointsError.drawArgumentsNeedImplicitTopology }
        }
        self.drawArguments = drawArguments
        self.version = PublishedVersion.next()
    }

    /// Positions alone, every point in order.
    public init(position: PublishedAttribute, bounds: PointsBounds) {
        self.attributes = [(.position, position)]
        self.slots = [(.Position, position)]
        self.position = position
        self.topology = .implicit
        self.elements = nil
        self.bounds = bounds
        self.drawArguments = nil
        self.version = PublishedVersion.next()
    }

    /// Publishes a copy of `positions`, with their bounds.
    public init(positions: ContiguousArray<simd_float3>, allocator: GPUAllocator) throws {
        let position = try PublishedAttribute.publishing(positions, scalar: .float32, components: 3,
                                                         allocator: allocator, label: "Points Position")
        self.init(position: position, bounds: .of(positions))
    }

    /// The attribute declared for `key`, if any.
    public func attribute(_ key: PointAttribute) -> PublishedAttribute? {
        attributes.first(where: { $0.key == key })?.attribute
    }

    public static func == (lhs: Points, rhs: Points) -> Bool {
        lhs.version == rhs.version
    }

    /// Restarts a strip primitive: Metal begins a new strip after this index.
    static let stripRestartIndex = UInt32.max

    private static func makeElements(for topology: PointTopology, pointCount: Int) throws -> ElementBuffer? {
        var indices = ContiguousArray<UInt32>()
        switch topology {
            case .implicit:
                return nil
            case let .indexed(given):
                guard given.allSatisfy({ Int($0) < pointCount }) else { throw PointsError.topologyOutOfRange }
                indices = given
            case let .strips(strips):
                var previousEnd = 0
                for strip in strips {
                    guard strip.range.lowerBound >= 0, strip.range.upperBound <= pointCount else { throw PointsError.topologyOutOfRange }
                    guard !strip.range.isEmpty else { continue }
                    // In order and apart, so each point belongs to one strip, as tessellation needs.
                    guard strip.range.lowerBound >= previousEnd else { throw PointsError.stripsOutOfOrder }
                    previousEnd = strip.range.upperBound
                    if !indices.isEmpty { indices.append(stripRestartIndex) }
                    indices.append(contentsOf: strip.range.map { UInt32($0) })
                    if strip.closed, strip.range.count > 2 { indices.append(UInt32(strip.range.lowerBound)) }
                }
        }
        guard !indices.isEmpty else { return nil }
        let storage = PointIndexStorage(indices)
        return ElementBuffer(type: .uint32, data: UnsafeMutableRawPointer(storage.indices.baseAddress), count: indices.count, source: storage)
    }
}

/// Owns the memory an element buffer reads its indices from, for as long as the buffer keeps it.
private final class PointIndexStorage {
    let indices: UnsafeMutableBufferPointer<UInt32>

    init(_ values: ContiguousArray<UInt32>) {
        indices = .allocate(capacity: values.count)
        _ = indices.initialize(from: values)
    }

    deinit {
        indices.deallocate()
    }
}
