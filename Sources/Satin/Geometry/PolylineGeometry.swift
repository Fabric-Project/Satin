//
//  PolylineGeometry.swift
//  Satin
//
//  Created by Anton Marini on 10/3/25.
//

#if SWIFT_PACKAGE
import SatinCore
#endif

import simd

/// Mirrors `generatePolylineGeometryData`'s `joinStyle` integer convention.
public enum PolylineJoinStyle: Int32 {
    case miter = 0
    case bevel = 1
    case round = 2
}

/// Mirrors `generatePolylineGeometryData`'s `capStyle` integer convention
/// (ignored when the polyline is closed).
public enum PolylineCapStyle: Int32 {
    case butt = 0
    case square = 1
    case round = 2
}

/// How a polyline is drawn as a ribbon: its width, the shape of its joins and caps, and
/// the plane it lies in (perpendicular to `up`).
public struct PolylineStyle: Equatable {
    public var width: Float
    public var join: PolylineJoinStyle
    /// Ignored when the polyline is closed.
    public var cap: PolylineCapStyle
    /// How far a miter may reach, in half-widths, before the join falls back to a bevel.
    public var miterLimit: Float
    /// Segments in each round join's fan and each round cap's half circle.
    public var roundResolution: Int
    public var up: simd_float3

    public init(width: Float = 0.1, join: PolylineJoinStyle = .miter, cap: PolylineCapStyle = .butt,
                miterLimit: Float = 4, roundResolution: Int = 8, up: simd_float3 = [0, 0, 1]) {
        self.width = width
        self.join = join
        self.cap = cap
        self.miterLimit = miterLimit
        self.roundResolution = roundResolution
        self.up = up
    }
}

/// A triangulated ribbon mesh tessellated from an ordered polyline, with joins
/// (miter/bevel/round), caps (butt/square/round), and optional per-point width scales
/// and colors. Beyond the usual Position/Normal/Texcoord/Color, each vertex carries
/// `.Custom0` (side, width scale relative to `style.width`, corner type, reserved),
/// `.Custom1` (core point) and `.Custom2` (neighbor point), so a shader can rebuild a
/// camera-facing offset instead of trusting Position outright.
///
/// Tessellation runs in SatinCore (`generatePolylineGeometryData`) for performance, straight
/// into C-allocated memory this geometry owns and reuses, growing it only when a polyline needs
/// more. The vertex and index buffers, and their attributes, are made once. As dynamic data, its
/// uploads reuse a ring of Metal buffers, one slot per frame in flight, instead of new ones.
public final class PolylineGeometry: Geometry {
    private var geometryData: PolylineGeometryData = createPolylineGeometryData()
    private let ribbonVertexBuffer = InterleavedBuffer(index: .Vertices, data: nil, stride: MemoryLayout<PolylineVertex>.stride, count: 0, source: nil)
    private let ribbonIndexBuffer = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)

    public init(context: Context) {
        super.init(context: context, primitiveType: .triangle, windingOrder: .counterClockwise)
        mutability = .dynamicData
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.position)!), for: .Position)
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.normal)!), for: .Normal)
        addAttribute(Float2InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.uv)!), for: .Texcoord)
        addAttribute(Float4InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.custom0)!), for: .Custom0)
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.custom1)!), for: .Custom1)
        addAttribute(Float3InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.custom2)!), for: .Custom2)
        addAttribute(Float4InterleavedBufferAttribute(parent: ribbonVertexBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.color)!), for: .Color)
        setElements(ribbonIndexBuffer)
    }

    deinit {
        freePolylineGeometryData(&geometryData)
    }

    /// Rebuilds the ribbon through `points`. `widthScales` multiplies `style.width` per point
    /// and `colors` colors each point; either may be shorter than `points` (its last value
    /// repeats) or nil (1 and opaque white).
    public func update(
        points: ContiguousArray<simd_float3>,
        closed: Bool,
        style: PolylineStyle,
        widthScales: ContiguousArray<Float>? = nil,
        colors: ContiguousArray<simd_float4>? = nil
    ) {
        let widthScales = widthScales ?? []
        let colors = colors ?? []
        points.withUnsafeBufferPointer { pointsBuffer in
            widthScales.withUnsafeBufferPointer { widthScalesBuffer in
                colors.withUnsafeBufferPointer { colorsBuffer in
                    generatePolylineGeometryData(
                        &geometryData,
                        pointsBuffer.baseAddress,
                        Int32(pointsBuffer.count),
                        closed,
                        style.width,
                        style.join.rawValue,
                        style.cap.rawValue,
                        style.miterLimit,
                        style.up,
                        Int32(style.roundResolution),
                        widthScalesBuffer.baseAddress,
                        Int32(widthScalesBuffer.count),
                        colorsBuffer.baseAddress,
                        Int32(colorsBuffer.count)
                    )
                }
            }
        }

        // The storage moves only when it grows; the buffers copy from it at upload either way.
        ribbonVertexBuffer.updateData(data: UnsafeMutableRawPointer(geometryData.vertexData), stride: MemoryLayout<PolylineVertex>.stride,
                                      count: Int(geometryData.vertexCount), source: nil)
        ribbonIndexBuffer.updateData(data: UnsafeMutableRawPointer(geometryData.indexData), count: Int(geometryData.indexCount) * 3, source: nil)
    }
}
