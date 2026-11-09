//
//  GPUStrokeTessellation.swift
//  Satin
//

import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// Tessellates published points into stroke ribbons on the GPU, with no readback: one thread per
/// point writes a fixed number of triangles (its segment to the next point, then its join or cap),
/// so no point waits on another. Triangles a point doesn't need collapse to nothing.
///
/// The result is Points holding a triangle list (position, normal, texture coordinate, color) for
/// `Geometry(context:points:primitiveType: .triangle)` and any material. Texture u runs from 0 to 1
/// by point index along each strip, not by length; v is 1 on the left, 0 on the right.
///
/// The caller compiles `source` (function `functionName`) and passes the pipeline to `encode`.
public enum GPUStrokeTessellation {
    public static let functionName = "tessellateStrokeKernel"

    /// Triangles each point writes: two for its segment, and room for a round join or cap.
    public static func trianglesPerPoint(style: Stroke.Style) -> Int {
        2 + max(roundResolution(style), 2)
    }

    static func roundResolution(_ style: Stroke.Style) -> Int {
        min(max(style.roundResolution, 1), 64)
    }

    public enum TessellationError: Error, Equatable {
        /// Positions must be float32 with three or more components; colors float32 with four;
        /// sizes float32 with one; each at 4-byte-aligned offsets and strides.
        case unsupportedLayout(PointAttribute)
    }

    private struct Uniforms {
        var pointCount: UInt32
        var stripCount: UInt32
        var trianglesPerPoint: UInt32
        var roundResolution: UInt32
        var join: UInt32
        var cap: UInt32
        var hasColors: UInt32
        var hasSizes: UInt32
        var positionStride: UInt32
        var positionOffset: UInt32
        var colorStride: UInt32
        var colorOffset: UInt32
        var sizeStride: UInt32
        var sizeOffset: UInt32
        var width: Float
        var miterLimit: Float
        var up: simd_float4
    }

    private struct Strip {
        var start: UInt32
        var count: UInt32
        var closed: UInt32
        var reserved: UInt32 = 0
    }

    /// Encodes the ribbons for `points` into `commandBuffer` and returns them, or nil when there is
    /// nothing to draw. Points' strips are kept; points without strips are one strip. `closesAll`
    /// closes every strip whatever its own flag. Each point's `.size`, when present, multiplies the width.
    public static func encode(points: Points, style: Stroke.Style, closesAll: Bool,
                              pipeline: MTLComputePipelineState, commandBuffer: MTLCommandBuffer,
                              allocator: GPUAllocator) throws -> Points?
    {
        let pointCount = points.count
        guard pointCount >= 2, style.width > 0 else { return nil }

        let position = points.position
        try check(position.layout, minimumComponents: 3, key: .position)
        let color = points.attribute(.color)
        if let color { try check(color.layout, minimumComponents: 4, key: .color) }
        let size = points.attribute(.size)
        if let size { try check(size.layout, minimumComponents: 1, key: .size) }

        var strips: [Strip]
        switch points.topology {
            case let .strips(given):
                strips = given.filter { !$0.range.isEmpty }.map {
                    Strip(start: UInt32($0.range.lowerBound), count: UInt32($0.range.count), closed: closesAll || $0.closed ? 1 : 0)
                }
            case .implicit, .indexed:
                strips = [Strip(start: 0, count: UInt32(pointCount), closed: closesAll ? 1 : 0)]
        }
        guard !strips.isEmpty else { return nil }

        let resolution = roundResolution(style)
        let trianglesPerPoint = trianglesPerPoint(style: style)
        let vertexCount = pointCount * trianglesPerPoint * 3
        let float4Stride = MemoryLayout<simd_float4>.stride
        let float2Stride = MemoryLayout<simd_float2>.stride
        let positions = try allocator.makeBuffer(length: vertexCount * float4Stride, memoryClass: .gpuOnly, label: "Stroke Positions")
        let normals = try allocator.makeBuffer(length: vertexCount * float4Stride, memoryClass: .gpuOnly, label: "Stroke Normals")
        let texcoords = try allocator.makeBuffer(length: vertexCount * float2Stride, memoryClass: .gpuOnly, label: "Stroke Texcoords")
        let colors = try allocator.makeBuffer(length: vertexCount * float4Stride, memoryClass: .gpuOnly, label: "Stroke Colors")

        var uniforms = Uniforms(pointCount: UInt32(pointCount),
                                stripCount: UInt32(strips.count),
                                trianglesPerPoint: UInt32(trianglesPerPoint),
                                roundResolution: UInt32(resolution),
                                join: UInt32(style.join.rawValue),
                                cap: UInt32(style.cap.rawValue),
                                hasColors: color == nil ? 0 : 1,
                                hasSizes: size == nil ? 0 : 1,
                                positionStride: UInt32(position.layout.byteStride),
                                positionOffset: UInt32(position.layout.byteOffset),
                                colorStride: UInt32(color?.layout.byteStride ?? 0),
                                colorOffset: UInt32(color?.layout.byteOffset ?? 0),
                                sizeStride: UInt32(size?.layout.byteStride ?? 0),
                                sizeOffset: UInt32(size?.layout.byteOffset ?? 0),
                                width: style.width,
                                miterLimit: style.miterLimit,
                                up: simd_make_float4(style.up, 0))

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        encoder.label = "Tessellate Strokes"
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(position.buffer, offset: 0, index: 0)
        // Unused inputs are bound to the positions, which the kernel never reads as them.
        encoder.setBuffer(color?.buffer ?? position.buffer, offset: 0, index: 1)
        encoder.setBuffer(size?.buffer ?? position.buffer, offset: 0, index: 2)
        let stripLength = strips.count * MemoryLayout<Strip>.stride
        if stripLength <= 4096 {
            encoder.setBytes(&strips, length: stripLength, index: 3)
        } else {
            let stripBuffer = try allocator.makeBuffer(length: stripLength, memoryClass: .cpuWrites, label: "Stroke Strips")
            strips.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress { stripBuffer.contents().copyMemory(from: baseAddress, byteCount: stripLength) }
            }
            encoder.setBuffer(stripBuffer, offset: 0, index: 3)
        }
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 4)
        encoder.setBuffer(positions, offset: 0, index: 5)
        encoder.setBuffer(normals, offset: 0, index: 6)
        encoder.setBuffer(texcoords, offset: 0, index: 7)
        encoder.setBuffer(colors, offset: 0, index: 8)
        encoder.dispatchThreads(MTLSize(width: pointCount, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 64), height: 1, depth: 1))
        encoder.endEncoding()

        let float3Layout = AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: float4Stride)
        let bounds: PointsBounds
        switch points.bounds {
            case let .known(known) where size == nil:
                // A ribbon reaches half its width past its points, or a miter's length at most.
                let reach = 0.5 * style.width * max(style.miterLimit, 1)
                bounds = .known(Bounds(min: known.min - reach, max: known.max + reach))
            default:
                bounds = .unknown
        }
        return try Points(attributes: [
            (.position, PublishedAttribute(adopting: positions, layout: float3Layout, count: vertexCount)),
            (.normal, PublishedAttribute(adopting: normals, layout: float3Layout, count: vertexCount)),
            (.texcoord, PublishedAttribute(adopting: texcoords,
                                           layout: AttributeLayout(scalar: .float32, components: 2, byteOffset: 0, byteStride: float2Stride),
                                           count: vertexCount)),
            (.color, PublishedAttribute(adopting: colors,
                                        layout: AttributeLayout(scalar: .float32, components: 4, byteOffset: 0, byteStride: float4Stride),
                                        count: vertexCount)),
        ], topology: .implicit, bounds: bounds)
    }

    private static func check(_ layout: AttributeLayout, minimumComponents: Int, key: PointAttribute) throws {
        guard layout.scalar == .float32, layout.components >= minimumComponents,
              layout.byteStride % 4 == 0, layout.byteOffset % 4 == 0
        else { throw TessellationError.unsupportedLayout(key) }
    }

    /// Joins: 0 miter, 1 bevel, 2 round (`Stroke.Join`). Caps: 0 butt, 1 square, 2 round (`Stroke.Cap`).
    public static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct StrokeUniforms {
        uint pointCount;
        uint stripCount;
        uint trianglesPerPoint;
        uint roundResolution;
        uint join;
        uint cap;
        uint hasColors;
        uint hasSizes;
        uint positionStride;
        uint positionOffset;
        uint colorStride;
        uint colorOffset;
        uint sizeStride;
        uint sizeOffset;
        float width;
        float miterLimit;
        float4 up;
    };

    struct StrokeStrip {
        uint start;
        uint count;
        uint closed;
        uint reserved;
    };

    struct StrokeOutput {
        device float4 *positions;
        device float4 *normals;
        device float2 *texcoords;
        device float4 *colors;
        float3 up;
    };

    static float3 readPosition(device const uchar *data, constant StrokeUniforms &u, uint index) {
        device const float *value = (device const float *)(data + u.positionOffset + index * u.positionStride);
        return float3(value[0], value[1], value[2]);
    }

    static float4 readColor(device const uchar *data, constant StrokeUniforms &u, uint index) {
        if (u.hasColors == 0) { return float4(1.0); }
        device const float *value = (device const float *)(data + u.colorOffset + index * u.colorStride);
        return float4(value[0], value[1], value[2], value[3]);
    }

    static float readHalfWidth(device const uchar *data, constant StrokeUniforms &u, uint index) {
        float scale = 1.0;
        if (u.hasSizes != 0) { scale = *(device const float *)(data + u.sizeOffset + index * u.sizeStride); }
        return 0.5 * u.width * scale;
    }

    // Writes triangle `index`, wound counterclockwise seen from `up`.
    static void emitTriangle(thread const StrokeOutput &out, uint index,
                             float3 a, float3 b, float3 c,
                             float2 ta, float2 tb, float2 tc,
                             float4 ca, float4 cb, float4 cc) {
        if (dot(cross(b - a, c - a), out.up) < 0.0) {
            const float3 p = b; b = c; c = p;
            const float2 t = tb; tb = tc; tc = t;
            const float4 k = cb; cb = cc; cc = k;
        }
        const uint v = index * 3;
        out.positions[v] = float4(a, 1.0);
        out.positions[v + 1] = float4(b, 1.0);
        out.positions[v + 2] = float4(c, 1.0);
        out.normals[v] = float4(out.up, 0.0);
        out.normals[v + 1] = float4(out.up, 0.0);
        out.normals[v + 2] = float4(out.up, 0.0);
        out.texcoords[v] = ta;
        out.texcoords[v + 1] = tb;
        out.texcoords[v + 2] = tc;
        out.colors[v] = ca;
        out.colors[v + 1] = cb;
        out.colors[v + 2] = cc;
    }

    // `offset` turned toward `target` (both a half width long) by `fraction` of the angle between them.
    static float3 turnToward(float3 offset, float3 target, float fraction, float halfWidth) {
        const float3 mixed = mix(offset, target, fraction);
        const float len = length(mixed);
        return len > 1e-6 ? mixed / len * halfWidth : offset;
    }

    kernel void tessellateStrokeKernel(device const uchar *positionData [[buffer(0)]],
                                       device const uchar *colorData [[buffer(1)]],
                                       device const uchar *sizeData [[buffer(2)]],
                                       constant StrokeStrip *strips [[buffer(3)]],
                                       constant StrokeUniforms &u [[buffer(4)]],
                                       device float4 *outPositions [[buffer(5)]],
                                       device float4 *outNormals [[buffer(6)]],
                                       device float2 *outTexcoords [[buffer(7)]],
                                       device float4 *outColors [[buffer(8)]],
                                       uint id [[thread_position_in_grid]]) {
        if (id >= u.pointCount) { return; }
        StrokeOutput out = { outPositions, outNormals, outTexcoords, outColors, normalize(u.up.xyz) };
        const uint first = id * u.trianglesPerPoint;
        uint written = 0;
        const float3 p = readPosition(positionData, u, id);

        // The last strip starting at or before this point.
        uint low = 0;
        uint high = u.stripCount;
        while (low + 1 < high) {
            const uint middle = (low + high) / 2;
            if (strips[middle].start <= id) { low = middle; } else { high = middle; }
        }
        const StrokeStrip strip = strips[low];

        if (id >= strip.start && id < strip.start + strip.count && strip.count >= 2) {
            const uint local = id - strip.start;
            const bool closed = strip.closed != 0 && strip.count > 2;
            const bool hasPrevious = closed || local > 0;
            const bool hasNext = closed || local + 1 < strip.count;
            const uint previousIndex = strip.start + (local + strip.count - 1) % strip.count;
            const uint nextIndex = strip.start + (local + 1) % strip.count;
            const float3 previous = readPosition(positionData, u, previousIndex);
            const float3 next = readPosition(positionData, u, nextIndex);
            const float halfWidth = readHalfWidth(sizeData, u, id);
            const float4 color = readColor(colorData, u, id);
            const float span = closed ? float(strip.count) : float(strip.count - 1);
            const float uHere = float(local) / span;
            const float2 center = float2(uHere, 0.5);
            const float3 up = out.up;

            const float3 toNext = next - p;
            const float3 fromPrevious = p - previous;
            const bool nextIsApart = length(toNext) > 1e-6;
            const bool previousIsApart = length(fromPrevious) > 1e-6;
            const float3 directionOut = nextIsApart ? normalize(toNext) : float3(0.0);
            const float3 directionIn = previousIsApart ? normalize(fromPrevious) : float3(0.0);
            const float3 leftOut = nextIsApart ? normalize(cross(up, directionOut)) : float3(0.0);
            const float3 leftIn = previousIsApart ? normalize(cross(up, directionIn)) : float3(0.0);

            // The segment to the next point.
            if (hasNext && nextIsApart) {
                const float nextHalfWidth = readHalfWidth(sizeData, u, nextIndex);
                const float4 nextColor = readColor(colorData, u, nextIndex);
                const float uNext = float(local + 1) / span;
                const float3 hereLeft = p + leftOut * halfWidth;
                const float3 hereRight = p - leftOut * halfWidth;
                const float3 nextLeft = next + leftOut * nextHalfWidth;
                const float3 nextRight = next - leftOut * nextHalfWidth;
                emitTriangle(out, first + written, hereLeft, hereRight, nextRight,
                             float2(uHere, 1.0), float2(uHere, 0.0), float2(uNext, 0.0), color, color, nextColor);
                written += 1;
                emitTriangle(out, first + written, hereLeft, nextRight, nextLeft,
                             float2(uHere, 1.0), float2(uNext, 0.0), float2(uNext, 1.0), color, nextColor, nextColor);
                written += 1;
            }

            if (hasPrevious && hasNext && nextIsApart && previousIsApart) {
                // The join fills the outer side of the turn.
                const float turn = dot(cross(directionIn, directionOut), up);
                if (abs(turn) > 1e-5 || dot(directionIn, directionOut) < 0.0) {
                    const float side = turn > 0.0 ? -1.0 : 1.0;
                    const float3 offsetIn = leftIn * side * halfWidth;
                    const float3 offsetOut = leftOut * side * halfWidth;
                    const float outerV = side > 0.0 ? 1.0 : 0.0;
                    const float2 outer = float2(uHere, outerV);
                    bool bevel = u.join == 1;
                    if (u.join == 0) {
                        const float3 bisector = offsetIn + offsetOut;
                        const float cosine = length(bisector) > 1e-6 ? dot(normalize(bisector), normalize(offsetIn)) : 0.0;
                        const float miterLength = cosine > 1e-4 ? halfWidth / cosine : INFINITY;
                        if (miterLength <= halfWidth * u.miterLimit) {
                            const float3 tip = p + normalize(bisector) * miterLength;
                            emitTriangle(out, first + written, p, p + offsetIn, tip, center, outer, outer, color, color, color);
                            written += 1;
                            emitTriangle(out, first + written, p, tip, p + offsetOut, center, outer, outer, color, color, color);
                            written += 1;
                        } else {
                            bevel = true;
                        }
                    }
                    if (bevel) {
                        emitTriangle(out, first + written, p, p + offsetIn, p + offsetOut, center, outer, outer, color, color, color);
                        written += 1;
                    } else if (u.join == 2) {
                        for (uint step = 0; step < u.roundResolution; step++) {
                            const float3 a = turnToward(offsetIn, offsetOut, float(step) / float(u.roundResolution), halfWidth);
                            const float3 b = turnToward(offsetIn, offsetOut, float(step + 1) / float(u.roundResolution), halfWidth);
                            emitTriangle(out, first + written, p, p + a, p + b, center, outer, outer, color, color, color);
                            written += 1;
                        }
                    }
                }
            } else if (!hasPrevious || !hasNext) {
                // A cap at the strip's open end, reaching back from its first point or on from its last.
                const bool isStart = !hasPrevious;
                const float3 left = isStart ? leftOut : leftIn;
                const float3 outward = isStart ? -directionOut : directionIn;
                if ((isStart ? nextIsApart : previousIsApart) && u.cap == 1) {
                    const float3 reach = outward * halfWidth;
                    const float3 a = p + left * halfWidth;
                    const float3 b = p - left * halfWidth;
                    emitTriangle(out, first + written, a, b, b + reach, float2(uHere, 1.0), float2(uHere, 0.0), float2(uHere, 0.0), color, color, color);
                    written += 1;
                    emitTriangle(out, first + written, a, b + reach, a + reach, float2(uHere, 1.0), float2(uHere, 0.0), float2(uHere, 1.0), color, color, color);
                    written += 1;
                } else if ((isStart ? nextIsApart : previousIsApart) && u.cap == 2) {
                    for (uint step = 0; step < u.roundResolution; step++) {
                        const float a0 = M_PI_F * float(step) / float(u.roundResolution);
                        const float a1 = M_PI_F * float(step + 1) / float(u.roundResolution);
                        const float3 a = (left * cos(a0) + outward * sin(a0)) * halfWidth;
                        const float3 b = (left * cos(a1) + outward * sin(a1)) * halfWidth;
                        emitTriangle(out, first + written, p, p + a, p + b, center,
                                     float2(uHere, 0.5 + 0.5 * cos(a0)), float2(uHere, 0.5 + 0.5 * cos(a1)), color, color, color);
                        written += 1;
                    }
                }
            }
        }

        // Unused triangles collapse onto the point.
        for (; written < u.trianglesPerPoint; written++) {
            emitTriangle(out, first + written, p, p, p, float2(0.0), float2(0.0), float2(0.0), float4(0.0), float4(0.0), float4(0.0));
        }
    }
    """
}
