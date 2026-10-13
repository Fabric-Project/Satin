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

/// A triangulated ribbon mesh tessellated from an ordered polyline, with
/// joins (miter/bevel/round) and caps (butt/square/round), and an optional
/// per-point width taper driven by local point spacing (`speedWidthAmount`
/// in `update(...)`) — widely-spaced ("fast") stretches scale toward
/// `speedWidthMinMultiplier`, tightly-spaced ("slow") stretches toward
/// `speedWidthMaxMultiplier`. Beyond the usual Position/Normal/Texcoord, each
/// vertex carries `.Custom0` (side, width scale *relative to the base half-width
/// passed to `update`, already folding in any speed taper*, corner type,
/// reserved), `.Custom1` (core point), `.Custom2` (neighbor point) — a
/// companion shader can use these to recompute a camera-facing/
/// resolution-independent offset (honoring the taper) instead of trusting
/// Position outright.
///
/// Tessellation runs in SatinCore (`generatePolylineGeometryData`) for
/// performance, straight into C-allocated memory this geometry owns. The vertex
/// and index buffers, and their attributes, are made once; each update hands
/// them the new memory and frees the old, without a Swift array copy.
public final class PolylineGeometry: Geometry {
    private var geometryData: PolylineGeometryData = createPolylineGeometryData()
    private let ribbonVertexBuffer = InterleavedBuffer(index: .Vertices, data: nil, stride: MemoryLayout<PolylineVertex>.stride, count: 0, source: nil)
    private let ribbonIndexBuffer = ElementBuffer(type: .uint32, data: nil, count: 0, source: nil)

    public init(context: Context) {
        super.init(context: context, primitiveType: .triangle, windingOrder: .counterClockwise)
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

    public func update(
        points: ContiguousArray<simd_float3>,
        closed: Bool,
        width: Float,
        joinStyle: PolylineJoinStyle,
        capStyle: PolylineCapStyle,
        miterLimit: Float,
        up: simd_float3,
        roundResolution: Int,
        speedWidthAmount: Float = 0,
        speedWidthMinMultiplier: Float = 0.25,
        speedWidthMaxMultiplier: Float = 1.0,
        pointColors: ContiguousArray<simd_float4>? = nil
    ) {
        let colors = pointColors ?? []
        let newGeometryData = points.withUnsafeBufferPointer { pointsBuffer in
            colors.withUnsafeBufferPointer { colorsBuffer in
                generatePolylineGeometryData(
                    pointsBuffer.baseAddress,
                    Int32(pointsBuffer.count),
                    closed,
                    width,
                    joinStyle.rawValue,
                    capStyle.rawValue,
                    miterLimit,
                    up,
                    Int32(roundResolution),
                    speedWidthAmount,
                    speedWidthMinMultiplier,
                    speedWidthMaxMultiplier,
                    colorsBuffer.baseAddress,
                    Int32(colorsBuffer.count)
                )
            }
        }

        // The buffers point at the new memory before the old is freed.
        ribbonVertexBuffer.updateData(data: UnsafeMutableRawPointer(newGeometryData.vertexData), stride: MemoryLayout<PolylineVertex>.stride,
                                count: Int(newGeometryData.vertexCount), source: nil)
        ribbonIndexBuffer.updateData(data: UnsafeMutableRawPointer(newGeometryData.indexData), count: Int(newGeometryData.indexCount) * 3, source: nil)
        freePolylineGeometryData(&geometryData)
        geometryData = newGeometryData
    }
}
