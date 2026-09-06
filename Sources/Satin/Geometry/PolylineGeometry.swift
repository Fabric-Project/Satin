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
/// performance; the vertex/index buffers read directly from that
/// C-allocated memory via `InterleavedBuffer`/`ElementBuffer` (same
/// `source:`-keeps-it-alive pattern as `SatinGeometry.setFrom`), without an
/// intermediate Swift array copy.
public final class PolylineGeometry: Geometry {
    private var geometryData: PolylineGeometryData = createPolylineGeometryData()

    public init(context: Context) {
        super.init(context: context, primitiveType: .triangle, windingOrder: .counterClockwise)
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
        freePolylineGeometryData(&geometryData)

        let colors = pointColors ?? []
        geometryData = points.withUnsafeBufferPointer { pointsBuffer in
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

        setFrom(geometryData: geometryData)
    }

    // MARK: - Read-back

    /// Direct read-back of the C-generated vertex/index buffers, exposed via
    /// plain Swift-native types so callers don't need `import SatinCore` to
    /// inspect them — used by Fabric's differential test against the (now
    /// legacy) pure-Swift tessellator this ports. `vertexCount` itself is
    /// already inherited from `Geometry`.
    public var triangleCount: Int { Int(geometryData.indexCount) }

    public func position(at index: Int) -> simd_float3 { geometryData.vertexData![index].position }
    public func normal(at index: Int) -> simd_float3 { geometryData.vertexData![index].normal }
    public func texcoord(at index: Int) -> simd_float2 { geometryData.vertexData![index].uv }
    public func custom0(at index: Int) -> simd_float4 { geometryData.vertexData![index].custom0 }
    public func custom1(at index: Int) -> simd_float3 { geometryData.vertexData![index].custom1 }
    public func custom2(at index: Int) -> simd_float3 { geometryData.vertexData![index].custom2 }
    public func color(at index: Int) -> simd_float4 { geometryData.vertexData![index].color }

    public func triangleIndices(at index: Int) -> (UInt32, UInt32, UInt32) {
        let triangle = geometryData.indexData![index]
        return (triangle.i0, triangle.i1, triangle.i2)
    }

    private func setFrom(geometryData: PolylineGeometryData) {
        let vertexCount = Int(geometryData.vertexCount)
        let interleavedBuffer = InterleavedBuffer(
            index: .Vertices,
            data: geometryData.vertexData,
            stride: MemoryLayout<PolylineVertex>.stride,
            count: vertexCount,
            source: geometryData
        )

        if geometryData.indexCount > 0, let indexData = geometryData.indexData {
            setElements(
                ElementBuffer(
                    type: .uint32,
                    data: indexData,
                    count: Int(geometryData.indexCount) * 3,
                    source: geometryData
                )
            )
        } else {
            setElements(nil)
        }

        addAttribute(Float3InterleavedBufferAttribute(parent: interleavedBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.position)!), for: .Position)
        addAttribute(Float3InterleavedBufferAttribute(parent: interleavedBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.normal)!), for: .Normal)
        addAttribute(Float2InterleavedBufferAttribute(parent: interleavedBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.uv)!), for: .Texcoord)
        addAttribute(Float4InterleavedBufferAttribute(parent: interleavedBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.custom0)!), for: .Custom0)
        addAttribute(Float3InterleavedBufferAttribute(parent: interleavedBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.custom1)!), for: .Custom1)
        addAttribute(Float3InterleavedBufferAttribute(parent: interleavedBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.custom2)!), for: .Custom2)
        addAttribute(Float4InterleavedBufferAttribute(parent: interleavedBuffer, offset: MemoryLayout<PolylineVertex>.offset(of: \.color)!), for: .Color)
    }
}
