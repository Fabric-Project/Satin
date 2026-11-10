//
//  GPUStrokeTessellation.swift
//  Satin
//

import Metal
import simd

#if SWIFT_PACKAGE
import SatinCore
#endif

/// Tessellates published points into stroke ribbons on the GPU, with no readback, as a best-effort
/// match for `StrokeGeometry`: joins, caps, dots, trim, dashes, layering, texture modes and bent normals.
///
/// Ten passes in one compute encoder:
/// 1. **Measure segments**, one thread per point: the length of the segment reaching it, and whether
///    a run of points at one place starts or ends there.
/// 2. **Measure blocks**, 256 points per threadgroup: running sums of those lengths, and the latest
///    run start and end, within each block.
/// 3. **Measure sums**, one thread: what the blocks before each block carry into it.
/// 4. **Measure carries**, one thread per point: its scans across every block before it.
/// 5. **Measure finish**, one thread per point: distance along its strip, and its previous and next
///    point at another place, so repeated points join the line instead of breaking it; each strip's
///    length.
/// 6. **Offset**, one thread: each strip's offset along all of them, and their total length.
/// 7. **Count**, one thread per point: exactly how many triangles the point draws.
/// 8. **Scan blocks**, 256 points per threadgroup: each point's offset within its block.
/// 9. **Scan sums**, one thread: each block's offset, and the draw's vertex count.
/// 10. **Emit**, one thread per point: its triangles at its offset, with nothing in between.
///
/// Points a GPU pass counted (`Points.drawArguments`) stroke only that many: every pass reads the
/// count and treats the points past it as in no strip.
///
/// Distances come from one running sum over every point, less the sum at the strip's start, so very
/// long lines lose float precision far along them.
///
/// A point draws the pieces of its segment to the next point that trim and dashes leave, each
/// capped where it was cut, and its join where the line runs through it unbroken. The result is
/// Points holding a triangle list (position, normal, texture coordinate, color) whose count the GPU
/// wrote (`Points.drawArguments`): draw it with `Geometry(context:points:primitiveType: .triangle)`
/// and any material. Its buffers are sized for the most the strokes could draw; a solid line pays
/// for caps per strip, not per point. The caller compiles `source` (`functionNames`) and passes the
/// pipelines to `encode`.
///
/// Differences from `StrokeGeometry`: every segment is drawn separately, overlapping on the inside
/// of a turn; a segment draws at most `dashesPerSegment` dashes; Whole Path stretching runs the
/// texture over the whole path untrimmed.
public enum GPUStrokeTessellation {
    /// The kernels `Pipelines(_:)` takes, in order.
    public static let functionNames = [
        "measureSegmentsKernel", "scanMeasureBlocksKernel", "scanMeasureSumsKernel", "measureCarriesKernel", "measureFinishKernel",
        "offsetStrokeKernel", "countStrokeKernel", "scanStrokeBlocksKernel", "scanStrokeSumsKernel", "emitStrokeKernel",
    ]

    /// Points per threadgroup in the block scans; the kernels' must match.
    static let scanBlockSize = 256

    public struct Pipelines {
        let measureSegments: MTLComputePipelineState
        let measureBlocks: MTLComputePipelineState
        let measureSums: MTLComputePipelineState
        let measureCarries: MTLComputePipelineState
        let measureFinish: MTLComputePipelineState
        let offset: MTLComputePipelineState
        let count: MTLComputePipelineState
        let scanBlocks: MTLComputePipelineState
        let scanSums: MTLComputePipelineState
        let emit: MTLComputePipelineState

        /// The pipelines of `functionNames`, in that order; nil for another number, or a device that
        /// can't run a block of either scan in one threadgroup.
        public init?(_ pipelines: [MTLComputePipelineState]) {
            guard pipelines.count == GPUStrokeTessellation.functionNames.count,
                  pipelines[1].maxTotalThreadsPerThreadgroup >= GPUStrokeTessellation.scanBlockSize,
                  pipelines[7].maxTotalThreadsPerThreadgroup >= GPUStrokeTessellation.scanBlockSize
            else { return nil }
            measureSegments = pipelines[0]
            measureBlocks = pipelines[1]
            measureSums = pipelines[2]
            measureCarries = pipelines[3]
            measureFinish = pipelines[4]
            offset = pipelines[5]
            count = pipelines[6]
            scanBlocks = pipelines[7]
            scanSums = pipelines[8]
            emit = pipelines[9]
        }
    }

    /// How texture u runs: over each piece trim and dashes leave, or held still on the line.
    public enum TextureMode: Equatable {
        case stretch
        case reveal
    }

    /// Whether texture u runs over each strip or once along all of them.
    public enum TextureSpan: Equatable {
        case eachPiece
        case wholePath
    }

    public struct Options: Equatable {
        /// Closes every strip whatever its own flag.
        public var closesAll: Bool
        /// 0 to 1: tilts normals toward each edge so a flat ribbon lights like a tube.
        public var bend: Float
        /// How far the lines rise along `up` from their first point to the last of the last strip.
        public var layerDepth: Float
        /// Fractions of each strip's length, or of all of them when `trimInOrder`.
        public var trimStart: Float
        public var trimEnd: Float
        public var trimInOrder: Bool
        /// A length or gap of 0 draws solid lines.
        public var dashLength: Float
        public var gapLength: Float
        public var dashOffset: Float
        /// The most dashes one segment draws.
        public var dashesPerSegment: Int
        public var textureMode: TextureMode
        public var textureSpan: TextureSpan

        public init(closesAll: Bool, bend: Float, layerDepth: Float, trimStart: Float, trimEnd: Float, trimInOrder: Bool,
                    dashLength: Float, gapLength: Float, dashOffset: Float, dashesPerSegment: Int,
                    textureMode: TextureMode, textureSpan: TextureSpan) {
            self.closesAll = closesAll
            self.bend = bend
            self.layerDepth = layerDepth
            self.trimStart = trimStart
            self.trimEnd = trimEnd
            self.trimInOrder = trimInOrder
            self.dashLength = dashLength
            self.gapLength = gapLength
            self.dashOffset = dashOffset
            self.dashesPerSegment = dashesPerSegment
            self.textureMode = textureMode
            self.textureSpan = textureSpan
        }

        /// Whole, solid, flat, unlayered strips with a stretched texture.
        public static let plain = Options(closesAll: false, bend: 0, layerDepth: 0, trimStart: 0, trimEnd: 1, trimInOrder: false,
                                          dashLength: 0, gapLength: 0, dashOffset: 0, dashesPerSegment: 4,
                                          textureMode: .stretch, textureSpan: .eachPiece)

        var isDashing: Bool { dashLength > 0 && gapLength > 0 }
    }

    public enum TessellationError: Error, Equatable {
        /// Positions must be float32 with three or more components; colors float32 with four;
        /// sizes float32 with one; each at 4-byte-aligned offsets and strides.
        case unsupportedLayout(PointAttribute)
        /// The ribbons could need more than `maximumVertexCount(device:)` vertices: fewer points, round
        /// segments or dashes per segment draw them.
        case tooManyVertices(Int)
    }

    /// The bytes each vertex reserves: position, normal and color float4s and a float2 texcoord.
    private static let bytesPerVertex = 3 * MemoryLayout<simd_float4>.stride + MemoryLayout<simd_float2>.stride

    /// The most vertices one encode may reserve on `device`: each buffer within the device's largest,
    /// all of them within a quarter of its recommended working set (leaving room for frames in flight
    /// and everything else), and the count within the 32-bit counts the kernels keep.
    public static func maximumVertexCount(device: MTLDevice) -> Int {
        let byLargestBuffer = device.maxBufferLength / MemoryLayout<simd_float4>.stride
        let byWorkingSet = Int(clamping: device.recommendedMaxWorkingSetSize / 4) / bytesPerVertex
        return min(byLargestBuffer, byWorkingSet, Int(UInt32.max))
    }

    /// `style` with finite, usable values: a width that isn't positive draws nothing, a miter limit
    /// below 1 is 1, and an up vector of no length is +z.
    static func sanitized(_ style: Stroke.Style) -> Stroke.Style {
        var result = style
        result.width = style.width.isFinite ? style.width : 0
        result.miterLimit = style.miterLimit.isFinite ? max(style.miterLimit, 1) : 4
        let up = style.up
        result.up = up.x.isFinite && up.y.isFinite && up.z.isFinite && simd_length(up) > 1e-6 ? up : [0, 0, 1]
        return result
    }

    /// `options` with finite values in range. Dashes or gaps shorter than a hundredth of the width
    /// can't be seen and would only make work, so they draw a solid line.
    static func sanitized(_ options: Options, width: Float) -> Options {
        func finite(_ value: Float, _ fallback: Float) -> Float { value.isFinite ? value : fallback }
        var result = options
        result.bend = min(max(finite(options.bend, 0), 0), 1)
        result.layerDepth = max(finite(options.layerDepth, 0), 0)
        result.trimStart = min(max(finite(options.trimStart, 0), 0), 1)
        result.trimEnd = min(max(finite(options.trimEnd, 1), 0), 1)
        result.dashOffset = finite(options.dashOffset, 0)
        result.dashesPerSegment = min(max(options.dashesPerSegment, 1), 64)
        let shortest = max(width * 0.01, 1e-5)
        let dash = finite(options.dashLength, 0)
        let gap = finite(options.gapLength, 0)
        if dash >= shortest, gap >= shortest {
            result.dashLength = dash
            result.gapLength = gap
        } else {
            result.dashLength = 0
            result.gapLength = 0
        }
        return result
    }

    static func roundResolution(_ style: Stroke.Style) -> Int {
        min(max(style.roundResolution, 1), 64)
    }

    static func capTriangles(_ style: Stroke.Style) -> Int {
        switch style.cap {
            case .round: return roundResolution(style)
            case .square: return 2
            case .butt: return 0
        }
    }

    static func joinTriangles(_ style: Stroke.Style) -> Int {
        switch style.join {
            case .round: return roundResolution(style)
            case .miter: return 2
            case .bevel: return 1
        }
    }

    /// Triangles in a dot, a strip of points all at one place drawn with round caps.
    public static func dotTriangles(style: Stroke.Style) -> Int {
        max(2 * roundResolution(style), 8)
    }

    static func piecesPerSegment(_ options: Options) -> Int {
        options.isDashing ? min(max(options.dashesPerSegment, 1), 64) : 1
    }

    /// The most triangles `pointCount` points in `stripCount` strips could draw. A solid line has a cap
    /// at each end of each strip's visible part, so its caps cost per strip; a dashed one could cap
    /// every dash, so it pays per point.
    public static func maximumTriangles(pointCount: Int, stripCount: Int, style: Stroke.Style, options: Options) -> Int {
        let style = sanitized(style)
        let options = sanitized(options, width: style.width)
        let caps = capTriangles(style)
        let perPoint = options.isDashing ? piecesPerSegment(options) * (2 + 2 * caps) + joinTriangles(style) : 2 + joinTriangles(style)
        let perStrip = (options.isDashing ? 0 : 2 * caps) + dotTriangles(style: style)
        return pointCount * perPoint + stripCount * perStrip
    }

    private struct Uniforms {
        var pointCount: UInt32
        var stripCount: UInt32
        var capacityTriangles: UInt32
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
        var piecesPerSegment: UInt32
        var textureReveal: UInt32
        var textureWholePath: UInt32
        var trimInOrder: UInt32
        var dashing: UInt32
        var blockCount: UInt32
        var width: Float
        var miterLimit: Float
        var bendCosine: Float
        var bendSine: Float
        var layerDepth: Float
        var trimStart: Float
        var trimEnd: Float
        var dashLength: Float
        var gapLength: Float
        var dashOffset: Float
        var dotTriangles: UInt32
        var hasGPUCount: UInt32
        var up: simd_float4
    }

    private struct Strip {
        var start: UInt32
        var count: UInt32
        var closed: UInt32
        var reserved: UInt32 = 0
    }

    /// Encodes the ribbons for `points` into `commandBuffer` and returns them, or nil when there is
    /// nothing to draw. Points' strips are kept; points without strips are one strip. Each point's
    /// `.size`, when present, multiplies the width, and its `.color` colors it.
    public static func encode(points: Points, style requestedStyle: Stroke.Style, options requestedOptions: Options, pipelines: Pipelines,
                              commandBuffer: MTLCommandBuffer, allocator: GPUAllocator) throws -> Points?
    {
        let style = sanitized(requestedStyle)
        let options = sanitized(requestedOptions, width: style.width)
        let pointCount = points.count
        guard pointCount >= 1, style.width > 0 else { return nil }

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
                    Strip(start: UInt32($0.range.lowerBound), count: UInt32($0.range.count), closed: options.closesAll || $0.closed ? 1 : 0)
                }
            case .implicit, .indexed:
                strips = [Strip(start: 0, count: UInt32(pointCount), closed: options.closesAll ? 1 : 0)]
        }
        guard !strips.isEmpty else { return nil }

        let capacityTriangles = maximumTriangles(pointCount: pointCount, stripCount: strips.count, style: style, options: options)
        let vertexCapacity = capacityTriangles * 3
        guard vertexCapacity <= maximumVertexCount(device: allocator.device) else { throw TessellationError.tooManyVertices(vertexCapacity) }
        let blockCount = (pointCount + scanBlockSize - 1) / scanBlockSize

        let float4Stride = MemoryLayout<simd_float4>.stride
        let float2Stride = MemoryLayout<simd_float2>.stride
        let uintStride = MemoryLayout<UInt32>.stride
        let positions = try allocator.makeBuffer(length: vertexCapacity * float4Stride, memoryClass: .gpuOnly, label: "Stroke Positions")
        let normals = try allocator.makeBuffer(length: vertexCapacity * float4Stride, memoryClass: .gpuOnly, label: "Stroke Normals")
        let texcoords = try allocator.makeBuffer(length: vertexCapacity * float2Stride, memoryClass: .gpuOnly, label: "Stroke Texcoords")
        let colors = try allocator.makeBuffer(length: vertexCapacity * float4Stride, memoryClass: .gpuOnly, label: "Stroke Colors")
        let drawArguments = try allocator.makeBuffer(length: MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride, memoryClass: .gpuOnly,
                                                     label: "Stroke Draw Arguments")
        // This frame's working storage: distances and distinct neighbors per point, strip measures,
        // and the triangle counts and their offsets.
        let distances = try allocator.makeBuffer(length: pointCount * MemoryLayout<Float>.stride, memoryClass: .gpuOnly, label: "Stroke Distances")
        let stripMeasures = try allocator.makeBuffer(length: strips.count * float2Stride, memoryClass: .gpuOnly, label: "Stroke Strip Measures")
        let total = try allocator.makeBuffer(length: MemoryLayout<Float>.stride, memoryClass: .gpuOnly, label: "Stroke Total Length")
        let counts = try allocator.makeBuffer(length: pointCount * uintStride, memoryClass: .gpuOnly, label: "Stroke Triangle Counts")
        let offsets = try allocator.makeBuffer(length: pointCount * uintStride, memoryClass: .gpuOnly, label: "Stroke Triangle Offsets")
        let blockSums = try allocator.makeBuffer(length: blockCount * uintStride, memoryClass: .gpuOnly, label: "Stroke Block Sums")
        let previousDistinct = try allocator.makeBuffer(length: pointCount * uintStride, memoryClass: .gpuOnly, label: "Stroke Previous Points")
        let nextDistinct = try allocator.makeBuffer(length: pointCount * uintStride, memoryClass: .gpuOnly, label: "Stroke Next Points")
        // The measure scans' running sums and run flags, and each block's carry.
        let prefix = try allocator.makeBuffer(length: pointCount * MemoryLayout<Float>.stride, memoryClass: .gpuOnly, label: "Stroke Running Lengths")
        let runStarts = try allocator.makeBuffer(length: pointCount * uintStride, memoryClass: .gpuOnly, label: "Stroke Run Starts")
        let runEnds = try allocator.makeBuffer(length: pointCount * uintStride, memoryClass: .gpuOnly, label: "Stroke Run Ends")
        let measureBlocks = try allocator.makeBuffer(length: blockCount * 4 * uintStride, memoryClass: .gpuOnly, label: "Stroke Measure Blocks")

        let bendAngle = options.bend * .pi / 2
        var uniforms = Uniforms(pointCount: UInt32(pointCount),
                                stripCount: UInt32(strips.count),
                                capacityTriangles: UInt32(capacityTriangles),
                                roundResolution: UInt32(roundResolution(style)),
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
                                piecesPerSegment: UInt32(piecesPerSegment(options)),
                                textureReveal: options.textureMode == .reveal ? 1 : 0,
                                textureWholePath: options.textureSpan == .wholePath ? 1 : 0,
                                trimInOrder: options.trimInOrder ? 1 : 0,
                                dashing: options.isDashing ? 1 : 0,
                                blockCount: UInt32(blockCount),
                                width: style.width,
                                miterLimit: style.miterLimit,
                                bendCosine: cos(bendAngle),
                                bendSine: sin(bendAngle),
                                layerDepth: options.layerDepth,
                                trimStart: min(options.trimStart, options.trimEnd),
                                trimEnd: max(options.trimStart, options.trimEnd),
                                dashLength: options.dashLength,
                                gapLength: options.gapLength,
                                dashOffset: options.dashOffset,
                                dotTriangles: UInt32(dotTriangles(style: style)),
                                hasGPUCount: points.drawArguments == nil ? 0 : 1,
                                up: simd_make_float4(style.up, 0))

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        encoder.label = "Tessellate Strokes"
        encoder.setBuffer(position.buffer, offset: 0, index: 0)
        // Unused inputs are bound to the positions, which the kernels never read as them.
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
        encoder.setBuffer(distances, offset: 0, index: 9)
        encoder.setBuffer(stripMeasures, offset: 0, index: 10)
        encoder.setBuffer(total, offset: 0, index: 11)
        encoder.setBuffer(counts, offset: 0, index: 12)
        encoder.setBuffer(offsets, offset: 0, index: 13)
        encoder.setBuffer(blockSums, offset: 0, index: 14)
        encoder.setBuffer(drawArguments, offset: 0, index: 15)
        encoder.setBuffer(previousDistinct, offset: 0, index: 16)
        encoder.setBuffer(nextDistinct, offset: 0, index: 17)
        encoder.setBuffer(prefix, offset: 0, index: 18)
        encoder.setBuffer(runStarts, offset: 0, index: 19)
        encoder.setBuffer(runEnds, offset: 0, index: 20)
        encoder.setBuffer(measureBlocks, offset: 0, index: 21)
        // Points a GPU pass counted stroke only that many; the rest of their buffers may be unwritten.
        if let inputArguments = points.drawArguments {
            encoder.setBuffer(inputArguments.buffer, offset: inputArguments.offset, index: 22)
        } else {
            encoder.setBuffer(position.buffer, offset: 0, index: 22)
        }

        // A serial encoder runs the passes in order, each seeing the last one's writes.
        func dispatch(_ pipeline: MTLComputePipelineState, threads: Int) {
            encoder.setComputePipelineState(pipeline)
            encoder.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 64), height: 1, depth: 1))
        }
        func dispatchBlocks(_ pipeline: MTLComputePipelineState) {
            encoder.setComputePipelineState(pipeline)
            encoder.dispatchThreadgroups(MTLSize(width: blockCount, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: scanBlockSize, height: 1, depth: 1))
        }
        dispatch(pipelines.measureSegments, threads: pointCount)
        dispatchBlocks(pipelines.measureBlocks)
        dispatch(pipelines.measureSums, threads: 1)
        dispatch(pipelines.measureCarries, threads: pointCount)
        dispatch(pipelines.measureFinish, threads: pointCount)
        dispatch(pipelines.offset, threads: 1)
        dispatch(pipelines.count, threads: pointCount)
        dispatchBlocks(pipelines.scanBlocks)
        dispatch(pipelines.scanSums, threads: 1)
        dispatch(pipelines.emit, threads: pointCount)
        encoder.endEncoding()

        let float3Layout = AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: float4Stride)
        let bounds: PointsBounds
        switch points.bounds {
            case let .known(known) where size == nil:
                // A ribbon reaches half its width past its points, or a miter's length at most, and
                // layering lifts it by up to the depth.
                let reach = 0.5 * style.width * max(style.miterLimit, 1) + options.layerDepth
                bounds = .known(Bounds(min: known.min - reach, max: known.max + reach))
            default:
                bounds = .unknown
        }
        return try Points(attributes: [
            (.position, PublishedAttribute(adopting: positions, layout: float3Layout, count: vertexCapacity)),
            (.normal, PublishedAttribute(adopting: normals, layout: float3Layout, count: vertexCapacity)),
            (.texcoord, PublishedAttribute(adopting: texcoords,
                                           layout: AttributeLayout(scalar: .float32, components: 2, byteOffset: 0, byteStride: float2Stride),
                                           count: vertexCapacity)),
            (.color, PublishedAttribute(adopting: colors,
                                        layout: AttributeLayout(scalar: .float32, components: 4, byteOffset: 0, byteStride: float4Stride),
                                        count: vertexCapacity)),
        ], topology: .implicit, bounds: bounds, drawArguments: try PointsDrawArguments(buffer: drawArguments, offset: 0))
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

    #define STROKE_NONE 0xFFFFFFFFu
    #define STROKE_SCAN_BLOCK 256u

    struct StrokeUniforms {
        uint pointCount;
        uint stripCount;
        uint capacityTriangles;
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
        uint piecesPerSegment;
        uint textureReveal;
        uint textureWholePath;
        uint trimInOrder;
        uint dashing;
        uint blockCount;
        float width;
        float miterLimit;
        float bendCosine;
        float bendSine;
        float layerDepth;
        float trimStart;
        float trimEnd;
        float dashLength;
        float gapLength;
        float dashOffset;
        uint dotTriangles;
        uint hasGPUCount;
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
        // Counting writes nothing; emitting writes below the capacity only.
        bool counting;
        uint capacity;
        float3 up;
        // The point the triangles being written are around, and the line through it (zero for
        // joins, caps and dots), for bent normals.
        float3 center;
        float3 axis;
        float bendCosine;
        float bendSine;
    };

    // One strip as the thread sees it: its measures and its trim, in distance along it.
    struct StrokeStripInfo {
        uint start;
        uint count;
        bool closed;
        float length;
        float offset;
        float total;
        float trimFrom;
        float trimTo;
    };

    static float3 rawPosition(device const uchar *data, constant StrokeUniforms &u, uint index) {
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

    static bool samePlace(float3 a, float3 b) {
        return distance(a, b) <= 1e-6;
    }

    // How many points are valid: all of them, or the count a GPU pass wrote, at most all of them.
    static uint activePointCount(constant StrokeUniforms &u, device const uint *gpuCount) {
        return u.hasGPUCount != 0 ? min(gpuCount[0], u.pointCount) : u.pointCount;
    }

    // The strip holding point `id`, cut short at the last valid point, in `strip`; returns its index,
    // or u.stripCount when none holds it.
    static uint stripOf(uint id, constant StrokeStrip *strips, constant StrokeUniforms &u, uint active, thread StrokeStrip &strip) {
        uint low = 0;
        uint high = u.stripCount;
        while (low + 1 < high) {
            const uint middle = (low + high) / 2;
            if (strips[middle].start <= id) { low = middle; } else { high = middle; }
        }
        strip = strips[low];
        const uint end = min(strip.start + strip.count, active);
        strip.count = end > strip.start ? end - strip.start : 0;
        return id >= strip.start && id < strip.start + strip.count ? low : u.stripCount;
    }

    // One block of the measure scans: its segment lengths summed, and the latest run start and run
    // end flagged in it.
    struct StrokeMeasureBlock {
        float length;
        uint runStart;
        uint runEnd;
        uint reserved;
    };

    // Measuring runs as three scans over every point at once. Per point: the length of the segment
    // that reaches it (0 at a strip's start), its index where a run of points at one place starts,
    // and, indexed back to front, its reversed index where such a run ends. A strip's first point
    // always starts a run and its last always ends one, so the max scans never cross a strip.
    kernel void measureSegmentsKernel(device const uchar *positionData [[buffer(0)]],
                                      constant StrokeStrip *strips [[buffer(3)]],
                                      constant StrokeUniforms &u [[buffer(4)]],
                                      device float *prefix [[buffer(18)]],
                                      device uint *runStarts [[buffer(19)]],
                                      device uint *runEnds [[buffer(20)]],
                                      device const uint *gpuCount [[buffer(22)]],
                                      uint id [[thread_position_in_grid]]) {
        if (id >= u.pointCount) { return; }
        const uint reversed = u.pointCount - 1 - id;
        StrokeStrip strip;
        const uint stripIndex = stripOf(id, strips, u, activePointCount(u, gpuCount), strip);
        if (stripIndex >= u.stripCount) {
            prefix[id] = 0.0;
            runStarts[id] = id;
            runEnds[reversed] = reversed;
            return;
        }
        const uint last = strip.start + strip.count - 1;
        const float3 here = rawPosition(positionData, u, id);
        if (id == strip.start) {
            prefix[id] = 0.0;
            runStarts[id] = id;
        } else {
            const float3 before = rawPosition(positionData, u, id - 1);
            prefix[id] = distance(before, here);
            runStarts[id] = samePlace(before, here) ? 0 : id;
        }
        runEnds[reversed] = id == last || !samePlace(here, rawPosition(positionData, u, id + 1)) ? reversed : 0;
    }

    // Within each block of STROKE_SCAN_BLOCK: running sums of the lengths and running maxima of the
    // run flags, in place, and each block's totals.
    kernel void scanMeasureBlocksKernel(constant StrokeUniforms &u [[buffer(4)]],
                                        device float *prefix [[buffer(18)]],
                                        device uint *runStarts [[buffer(19)]],
                                        device uint *runEnds [[buffer(20)]],
                                        device StrokeMeasureBlock *blocks [[buffer(21)]],
                                        uint id [[thread_position_in_grid]],
                                        uint local [[thread_position_in_threadgroup]],
                                        uint block [[threadgroup_position_in_grid]]) {
        threadgroup float lengths[STROKE_SCAN_BLOCK];
        threadgroup uint starts[STROKE_SCAN_BLOCK];
        threadgroup uint ends[STROKE_SCAN_BLOCK];
        const bool inside = id < u.pointCount;
        lengths[local] = inside ? prefix[id] : 0.0;
        starts[local] = inside ? runStarts[id] : 0;
        ends[local] = inside ? runEnds[id] : 0;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint stride = 1; stride < STROKE_SCAN_BLOCK; stride *= 2) {
            const bool reaches = local >= stride;
            const float length = reaches ? lengths[local - stride] : 0.0;
            const uint start = reaches ? starts[local - stride] : 0;
            const uint end = reaches ? ends[local - stride] : 0;
            threadgroup_barrier(mem_flags::mem_threadgroup);
            lengths[local] += length;
            starts[local] = max(starts[local], start);
            ends[local] = max(ends[local], end);
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (inside) {
            prefix[id] = lengths[local];
            runStarts[id] = starts[local];
            runEnds[id] = ends[local];
        }
        if (local == STROKE_SCAN_BLOCK - 1) { blocks[block] = StrokeMeasureBlock { lengths[local], starts[local], ends[local], 0 }; }
    }

    // What the blocks before each block carry into it; one thread.
    kernel void scanMeasureSumsKernel(constant StrokeUniforms &u [[buffer(4)]],
                                      device StrokeMeasureBlock *blocks [[buffer(21)]],
                                      uint id [[thread_position_in_grid]]) {
        if (id != 0) { return; }
        StrokeMeasureBlock carried = { 0.0, 0, 0, 0 };
        for (uint block = 0; block < u.blockCount; block++) {
            const StrokeMeasureBlock totals = blocks[block];
            blocks[block] = carried;
            carried.length += totals.length;
            carried.runStart = max(carried.runStart, totals.runStart);
            carried.runEnd = max(carried.runEnd, totals.runEnd);
        }
    }

    // Each point's scans across all the blocks before it.
    kernel void measureCarriesKernel(constant StrokeUniforms &u [[buffer(4)]],
                                     device float *prefix [[buffer(18)]],
                                     device uint *runStarts [[buffer(19)]],
                                     device uint *runEnds [[buffer(20)]],
                                     device const StrokeMeasureBlock *blocks [[buffer(21)]],
                                     uint id [[thread_position_in_grid]]) {
        if (id >= u.pointCount) { return; }
        const StrokeMeasureBlock carried = blocks[id / STROKE_SCAN_BLOCK];
        prefix[id] += carried.length;
        runStarts[id] = max(runStarts[id], carried.runStart);
        runEnds[id] = max(runEnds[id], carried.runEnd);
    }

    // Per point: distance along its strip (a closed strip's length includes its closing side), and
    // its nearest previous and next point at another place, wrapping around a closed strip. The last
    // point of each strip writes the strip's length.
    kernel void measureFinishKernel(device const uchar *positionData [[buffer(0)]],
                                    constant StrokeStrip *strips [[buffer(3)]],
                                    constant StrokeUniforms &u [[buffer(4)]],
                                    device float *distances [[buffer(9)]],
                                    device float2 *stripMeasures [[buffer(10)]],
                                    device uint *previousDistinct [[buffer(16)]],
                                    device uint *nextDistinct [[buffer(17)]],
                                    device const float *prefix [[buffer(18)]],
                                    device const uint *runStarts [[buffer(19)]],
                                    device const uint *runEnds [[buffer(20)]],
                                    device const uint *gpuCount [[buffer(22)]],
                                    uint id [[thread_position_in_grid]]) {
        if (id >= u.pointCount) { return; }
        StrokeStrip strip;
        const uint stripIndex = stripOf(id, strips, u, activePointCount(u, gpuCount), strip);
        if (stripIndex >= u.stripCount) {
            distances[id] = 0.0;
            previousDistinct[id] = STROKE_NONE;
            nextDistinct[id] = STROKE_NONE;
            return;
        }
        const uint start = strip.start;
        const uint last = start + strip.count - 1;
        const bool closed = strip.closed != 0 && strip.count > 2;
        const uint lastReversed = u.pointCount - 1;

        distances[id] = prefix[id] - prefix[start];
        const uint runStart = runStarts[id];
        uint previous = runStart > start ? runStart - 1 : STROKE_NONE;
        const uint runEnd = lastReversed - runEnds[lastReversed - id];
        uint next = runEnd < last ? runEnd + 1 : STROKE_NONE;

        const float3 first = rawPosition(positionData, u, start);
        const float3 lastPoint = rawPosition(positionData, u, last);
        if (closed) {
            // Points with nothing before them look back past the end; points with nothing after
            // them look on past the start.
            if (previous == STROKE_NONE) {
                const uint lastRunStart = runStarts[last];
                previous = !samePlace(lastPoint, first) ? last : (lastRunStart > start ? lastRunStart - 1 : STROKE_NONE);
            }
            if (next == STROKE_NONE) {
                const uint firstRunEnd = lastReversed - runEnds[lastReversed - start];
                next = !samePlace(first, lastPoint) ? start : (firstRunEnd < last ? firstRunEnd + 1 : STROKE_NONE);
            }
        }
        previousDistinct[id] = previous;
        nextDistinct[id] = next;

        if (id == last) {
            const float length = prefix[last] - prefix[start] + (closed ? distance(lastPoint, first) : 0.0);
            stripMeasures[stripIndex] = float2(length, 0.0);
        }
    }

    // Each strip's offset along all of them, and their total length; one thread.
    kernel void offsetStrokeKernel(constant StrokeUniforms &u [[buffer(4)]],
                                   device float2 *stripMeasures [[buffer(10)]],
                                   device float *total [[buffer(11)]],
                                   uint id [[thread_position_in_grid]]) {
        if (id != 0) { return; }
        float walked = 0.0;
        for (uint stripIndex = 0; stripIndex < u.stripCount; stripIndex++) {
            stripMeasures[stripIndex].y = walked;
            walked += stripMeasures[stripIndex].x;
        }
        total[0] = walked;
    }

    // Facing `up` at the line, tilting toward the edge by the bend there, so a flat ribbon lights like a tube.
    static float3 strokeNormal(thread const StrokeOutput &out, float3 point) {
        if (out.bendSine == 0.0) { return out.up; }
        float3 radial = point - out.center;
        radial -= dot(radial, out.axis) * out.axis;
        radial -= dot(radial, out.up) * out.up;
        const float len = length(radial);
        return len > 1e-6 ? normalize(out.up * out.bendCosine + radial / len * out.bendSine) : out.up;
    }

    // Writes triangle `index`, wound counterclockwise seen from `up`.
    static void emitTriangle(thread const StrokeOutput &out, uint index,
                             float3 a, float3 b, float3 c,
                             float2 ta, float2 tb, float2 tc,
                             float4 ca, float4 cb, float4 cc) {
        if (out.counting || index >= out.capacity) { return; }
        if (dot(cross(b - a, c - a), out.up) < 0.0) {
            const float3 p = b; b = c; c = p;
            const float2 t = tb; tb = tc; tc = t;
            const float4 k = cb; cb = cc; cc = k;
        }
        const uint v = index * 3;
        out.positions[v] = float4(a, 1.0);
        out.positions[v + 1] = float4(b, 1.0);
        out.positions[v + 2] = float4(c, 1.0);
        out.normals[v] = float4(strokeNormal(out, a), 0.0);
        out.normals[v + 1] = float4(strokeNormal(out, b), 0.0);
        out.normals[v + 2] = float4(strokeNormal(out, c), 0.0);
        out.texcoords[v] = ta;
        out.texcoords[v + 1] = tb;
        out.texcoords[v + 2] = tc;
        out.colors[v] = ca;
        out.colors[v + 1] = cb;
        out.colors[v + 2] = cc;
    }

    // `v` turned by `angle` around the unit `axis`.
    static float3 rotateAround(float3 v, float3 axis, float angle) {
        const float c = cos(angle);
        const float s = sin(angle);
        return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
    }

    // Where `x` (distance along the strip) falls in the dash pattern, anchored at the strip's start.
    static float dashPosition(constant StrokeUniforms &u, float x) {
        const float period = u.dashLength + u.gapLength;
        const float position = fmod(x - u.dashOffset, period);
        return position < 0.0 ? position + period : position;
    }

    static bool isVisible(constant StrokeUniforms &u, thread const StrokeStripInfo &info, float x) {
        if (x < info.trimFrom || x > info.trimTo) { return false; }
        return u.dashing == 0 || dashPosition(u, x) < u.dashLength;
    }

    // The piece of line around `x` that texture stretches over: its dash, or the trimmed strip.
    static float2 pieceAround(constant StrokeUniforms &u, thread const StrokeStripInfo &info, float x) {
        float2 piece = float2(max(info.trimFrom, 0.0), min(info.trimTo, info.length));
        if (u.dashing != 0) {
            const float dashStart = x - dashPosition(u, x);
            piece = float2(max(piece.x, dashStart), min(piece.y, dashStart + u.dashLength));
        }
        return piece;
    }

    static float textureU(constant StrokeUniforms &u, thread const StrokeStripInfo &info, float x, float2 piece) {
        if (u.textureWholePath != 0) { return info.total > 0.0 ? (info.offset + x) / info.total : 0.0; }
        if (u.textureReveal != 0) { return info.length > 0.0 ? x / info.length : 0.0; }
        return piece.y > piece.x ? (x - piece.x) / (piece.y - piece.x) : 0.0;
    }

    // The point at `index`, raised along `up` by how far along every strip it is, so a later part
    // draws over an earlier one; a closed strip stays level, at the height it starts.
    static float3 layeredPosition(device const uchar *positionData, constant StrokeUniforms &u, device const float *distances,
                                  thread const StrokeStripInfo &info, float3 up, uint index) {
        float3 position = rawPosition(positionData, u, index);
        if (u.layerDepth > 0.0 && info.total > 0.0) {
            const float along = info.closed ? info.offset : info.offset + distances[index];
            position += up * u.layerDepth * along / info.total;
        }
        return position;
    }

    // A cap at `center`, reaching along `outward`.
    static void emitCap(thread const StrokeOutput &out, constant StrokeUniforms &u, uint first, thread uint &written,
                        float3 center, float3 left, float3 outward, float halfWidth, float4 color, float capU) {
        if (u.cap == 1) {
            const float3 reach = outward * halfWidth;
            const float3 a = center + left * halfWidth;
            const float3 b = center - left * halfWidth;
            emitTriangle(out, first + written, a, b, b + reach, float2(capU, 1.0), float2(capU, 0.0), float2(capU, 0.0), color, color, color);
            written += 1;
            emitTriangle(out, first + written, a, b + reach, a + reach, float2(capU, 1.0), float2(capU, 0.0), float2(capU, 1.0), color, color, color);
            written += 1;
        } else if (u.cap == 2) {
            for (uint step = 0; step < u.roundResolution; step++) {
                const float a0 = M_PI_F * float(step) / float(u.roundResolution);
                const float a1 = M_PI_F * float(step + 1) / float(u.roundResolution);
                const float3 a = (left * cos(a0) + outward * sin(a0)) * halfWidth;
                const float3 b = (left * cos(a1) + outward * sin(a1)) * halfWidth;
                emitTriangle(out, first + written, center, center + a, center + b, float2(capU, 0.5),
                             float2(capU, 0.5 + 0.5 * cos(a0)), float2(capU, 0.5 + 0.5 * cos(a1)), color, color, color);
                written += 1;
            }
        }
    }

    // Everything point `id` draws, written from triangle `first` on; returns how many triangles.
    // Counting and emitting run this same function, so their numbers always agree.
    static uint strokePoint(uint id, uint first, thread StrokeOutput &out, constant StrokeUniforms &u,
                            device const uchar *positionData, device const uchar *colorData, device const uchar *sizeData,
                            constant StrokeStrip *strips, device const float *distances, device const float2 *stripMeasures,
                            device const float *total, device const uint *previousDistinct, device const uint *nextDistinct,
                            uint active) {
        uint written = 0;
        const float3 up = out.up;

        StrokeStrip strip;
        const uint stripIndex = stripOf(id, strips, u, active, strip);
        if (stripIndex >= u.stripCount) { return 0; }

        StrokeStripInfo info;
        info.start = strip.start;
        info.count = strip.count;
        info.closed = strip.closed != 0 && strip.count > 2;
        info.length = stripMeasures[stripIndex].x;
        info.offset = stripMeasures[stripIndex].y;
        info.total = total[0];
        if (u.trimInOrder != 0) {
            info.trimFrom = u.trimStart * info.total - info.offset;
            info.trimTo = u.trimEnd * info.total - info.offset;
        } else {
            info.trimFrom = u.trimStart * info.length;
            info.trimTo = u.trimEnd * info.length;
        }
        // A trimmed or dashed loop is open where it was cut.
        const bool seamOpens = info.trimFrom > 0.0 || info.trimTo < info.length || u.dashing != 0;

        const uint previousIndex = previousDistinct[id];
        const uint nextIndex = nextDistinct[id];
        const float3 p = layeredPosition(positionData, u, distances, info, up, id);
        out.center = p;
        out.axis = float3(0.0);
        const float halfWidth = readHalfWidth(sizeData, u, id);
        const float4 color = readColor(colorData, u, id);

        // A strip whose points are all at one place is a dot when caps are round, drawn by its first point.
        if (previousIndex == STROKE_NONE && nextIndex == STROKE_NONE) {
            if (id == strip.start && u.cap == 2 && isVisible(u, info, 0.0)) {
                const float3 seed = abs(up.z) < 0.9 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
                const float3 across = normalize(cross(up, seed));
                const float3 along = cross(up, across);
                for (uint slice = 0; slice < u.dotTriangles; slice++) {
                    const float a0 = 2.0 * M_PI_F * float(slice) / float(u.dotTriangles);
                    const float a1 = 2.0 * M_PI_F * float(slice + 1) / float(u.dotTriangles);
                    const float2 r0 = float2(cos(a0), sin(a0));
                    const float2 r1 = float2(cos(a1), sin(a1));
                    emitTriangle(out, first + written, p,
                                 p + (across * r0.x + along * r0.y) * halfWidth,
                                 p + (across * r1.x + along * r1.y) * halfWidth,
                                 float2(0.5), 0.5 + 0.5 * r0, 0.5 + 0.5 * r1, color, color, color);
                    written += 1;
                }
            }
            return written;
        }

        // Of points at one place, the last draws the segment on and the join; the rest draw nothing.
        const uint last = strip.start + strip.count - 1;
        const bool wraps = info.closed && id == last && nextIndex == strip.start;
        if (nextIndex == STROKE_NONE || (nextIndex != id + 1 && !wraps)) { return written; }

        const bool hasPrevious = previousIndex != STROKE_NONE;
        const float3 next = layeredPosition(positionData, u, distances, info, up, nextIndex);
        const float3 previous = hasPrevious ? layeredPosition(positionData, u, distances, info, up, previousIndex) : p;
        const float3 directionOut = normalize(next - p);
        const float3 directionIn = hasPrevious ? normalize(p - previous) : directionOut;
        const float3 leftOut = normalize(cross(up, directionOut));
        const float3 leftIn = normalize(cross(up, directionIn));

        const float epsilon = 1e-5 * max(info.length, 1.0);
        const float segmentStart = distances[id];
        const float segmentEnd = wraps ? info.length : distances[nextIndex];
        const float segmentLength = max(segmentEnd - segmentStart, 1e-12);
        const float nextHalfWidth = readHalfWidth(sizeData, u, nextIndex);
        const float4 nextColor = readColor(colorData, u, nextIndex);

        // Whether the line runs on past each end of the segment, so the joins there cover it. At a
        // closed strip's start and end, it does unless a trim or dashes cut the loop open.
        const bool seamAtStart = info.closed && segmentStart <= epsilon;
        const bool seamAtEnd = info.closed && segmentEnd >= info.length - epsilon;
        const bool runsOnBefore = hasPrevious && (seamAtStart ? !seamOpens : isVisible(u, info, segmentStart - epsilon));
        const bool runsOnAfter = nextDistinct[nextIndex] != STROKE_NONE
            && (seamAtEnd ? !seamOpens : isVisible(u, info, segmentEnd + epsilon));

        // The visible pieces of the segment, each capped where it was cut. Each piece follows at most
        // one gap, so the step bound always suffices; with the progress check, a cursor too large for
        // float precision can't loop forever.
        float cursor = max(segmentStart, info.trimFrom);
        const float limit = min(segmentEnd, info.trimTo);
        uint pieces = 0;
        const uint stepLimit = 2 * u.piecesPerSegment + 2;
        // At a dash's end the cursor can round to a hair short of its gap; that's the gap, not a
        // dash of no length, which would end the segment's dashes early.
        const float dashEndTolerance = min(epsilon, 0.5 * u.dashLength);
        for (uint step = 0; step < stepLimit && cursor < limit && pieces < u.piecesPerSegment; step++) {
            float pieceEnd = limit;
            if (u.dashing != 0) {
                const float position = dashPosition(u, cursor);
                if (position >= u.dashLength - dashEndTolerance) {
                    const float dashStart = cursor + (u.dashLength + u.gapLength - position);
                    if (!(dashStart > cursor)) { break; }
                    cursor = dashStart;
                    continue;
                }
                pieceEnd = min(limit, cursor + u.dashLength - position);
            }
            if (!(pieceEnd > cursor)) { break; }

            const float f0 = (cursor - segmentStart) / segmentLength;
            const float f1 = (pieceEnd - segmentStart) / segmentLength;
            const float3 c0 = mix(p, next, f0);
            const float3 c1 = mix(p, next, f1);
            const float h0 = mix(halfWidth, nextHalfWidth, f0);
            const float h1 = mix(halfWidth, nextHalfWidth, f1);
            const float4 k0 = mix(color, nextColor, f0);
            const float4 k1 = mix(color, nextColor, f1);
            const float2 piece = pieceAround(u, info, cursor);
            const float u0 = textureU(u, info, cursor, piece);
            const float u1 = textureU(u, info, pieceEnd, piece);

            out.center = c0;
            out.axis = directionOut;
            emitTriangle(out, first + written, c0 + leftOut * h0, c0 - leftOut * h0, c1 - leftOut * h1,
                         float2(u0, 1.0), float2(u0, 0.0), float2(u1, 0.0), k0, k0, k1);
            written += 1;
            emitTriangle(out, first + written, c0 + leftOut * h0, c1 - leftOut * h1, c1 + leftOut * h1,
                         float2(u0, 1.0), float2(u1, 0.0), float2(u1, 1.0), k0, k1, k1);
            written += 1;

            out.axis = float3(0.0);
            if (cursor > segmentStart + epsilon || !runsOnBefore) {
                out.center = c0;
                emitCap(out, u, first, written, c0, leftOut, -directionOut, h0, k0, u0);
            }
            if (pieceEnd < segmentEnd - epsilon || !runsOnAfter) {
                out.center = c1;
                emitCap(out, u, first, written, c1, leftOut, directionOut, h1, k1, u1);
            }
            pieces += 1;
            cursor = pieceEnd;
        }

        // The join fills the outer side of the turn where the line runs through this point.
        out.center = p;
        out.axis = float3(0.0);
        const bool runsThrough = seamAtStart ? !seamOpens : (isVisible(u, info, segmentStart - epsilon) && isVisible(u, info, segmentStart + epsilon));
        if (hasPrevious && runsThrough) {
            const float turn = dot(cross(directionIn, directionOut), up);
            if (abs(turn) > 1e-5 || dot(directionIn, directionOut) < 0.0) {
                const float side = turn > 0.0 ? -1.0 : 1.0;
                const float3 offsetIn = leftIn * side * halfWidth;
                const float3 offsetOut = leftOut * side * halfWidth;
                const float uHere = textureU(u, info, segmentStart, pieceAround(u, info, segmentStart));
                const float2 center = float2(uHere, 0.5);
                const float2 outer = float2(uHere, side > 0.0 ? 1.0 : 0.0);
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
                    // Turn around `up` from the incoming offset to the outgoing one. An exact reversal
                    // has no shorter way round, so it bulges forward, the way the line was going.
                    const float3 from = normalize(offsetIn);
                    const float3 to = normalize(offsetOut);
                    const float angle = acos(clamp(dot(from, to), -1.0, 1.0));
                    float turning = dot(cross(from, to), up);
                    if (abs(turning) < 1e-5) { turning = dot(cross(from, directionIn), up); }
                    const float signedAngle = turning >= 0.0 ? angle : -angle;
                    for (uint slice = 0; slice < u.roundResolution; slice++) {
                        const float3 a = rotateAround(offsetIn, up, signedAngle * float(slice) / float(u.roundResolution));
                        const float3 b = rotateAround(offsetIn, up, signedAngle * float(slice + 1) / float(u.roundResolution));
                        emitTriangle(out, first + written, p, p + a, p + b, center, outer, outer, color, color, color);
                        written += 1;
                    }
                }
            }
        }
        return written;
    }

    kernel void countStrokeKernel(device const uchar *positionData [[buffer(0)]],
                                  device const uchar *colorData [[buffer(1)]],
                                  device const uchar *sizeData [[buffer(2)]],
                                  constant StrokeStrip *strips [[buffer(3)]],
                                  constant StrokeUniforms &u [[buffer(4)]],
                                  device const float *distances [[buffer(9)]],
                                  device const float2 *stripMeasures [[buffer(10)]],
                                  device const float *total [[buffer(11)]],
                                  device uint *counts [[buffer(12)]],
                                  device const uint *previousDistinct [[buffer(16)]],
                                  device const uint *nextDistinct [[buffer(17)]],
                                  device const uint *gpuCount [[buffer(22)]],
                                  uint id [[thread_position_in_grid]]) {
        if (id >= u.pointCount) { return; }
        StrokeOutput out = { nullptr, nullptr, nullptr, nullptr, true, 0, normalize(u.up.xyz),
                             float3(0.0), float3(0.0), u.bendCosine, u.bendSine };
        counts[id] = strokePoint(id, 0, out, u, positionData, colorData, sizeData, strips, distances, stripMeasures, total,
                                 previousDistinct, nextDistinct, activePointCount(u, gpuCount));
    }

    // Each point's offset within its block of STROKE_SCAN_BLOCK, and each block's sum.
    kernel void scanStrokeBlocksKernel(constant StrokeUniforms &u [[buffer(4)]],
                                       device const uint *counts [[buffer(12)]],
                                       device uint *offsets [[buffer(13)]],
                                       device uint *blockSums [[buffer(14)]],
                                       uint id [[thread_position_in_grid]],
                                       uint local [[thread_position_in_threadgroup]],
                                       uint block [[threadgroup_position_in_grid]]) {
        threadgroup uint sums[STROKE_SCAN_BLOCK];
        const uint value = id < u.pointCount ? counts[id] : 0;
        sums[local] = value;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint stride = 1; stride < STROKE_SCAN_BLOCK; stride *= 2) {
            const uint add = local >= stride ? sums[local - stride] : 0;
            threadgroup_barrier(mem_flags::mem_threadgroup);
            sums[local] += add;
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (id < u.pointCount) { offsets[id] = sums[local] - value; }
        if (local == STROKE_SCAN_BLOCK - 1) { blockSums[block] = sums[local]; }
    }

    // Each block's offset, and the draw's vertex count, kept within the capacity; one thread.
    kernel void scanStrokeSumsKernel(constant StrokeUniforms &u [[buffer(4)]],
                                     device uint *blockSums [[buffer(14)]],
                                     device uint4 *drawArguments [[buffer(15)]],
                                     uint id [[thread_position_in_grid]]) {
        if (id != 0) { return; }
        uint running = 0;
        for (uint block = 0; block < u.blockCount; block++) {
            const uint sum = blockSums[block];
            blockSums[block] = running;
            running += sum;
        }
        // Vertex count, instance count, first vertex, first instance.
        drawArguments[0] = uint4(min(running, u.capacityTriangles) * 3, 1, 0, 0);
    }

    kernel void emitStrokeKernel(device const uchar *positionData [[buffer(0)]],
                                 device const uchar *colorData [[buffer(1)]],
                                 device const uchar *sizeData [[buffer(2)]],
                                 constant StrokeStrip *strips [[buffer(3)]],
                                 constant StrokeUniforms &u [[buffer(4)]],
                                 device float4 *outPositions [[buffer(5)]],
                                 device float4 *outNormals [[buffer(6)]],
                                 device float2 *outTexcoords [[buffer(7)]],
                                 device float4 *outColors [[buffer(8)]],
                                 device const float *distances [[buffer(9)]],
                                 device const float2 *stripMeasures [[buffer(10)]],
                                 device const float *total [[buffer(11)]],
                                 device const uint *offsets [[buffer(13)]],
                                 device const uint *blockSums [[buffer(14)]],
                                 device const uint *previousDistinct [[buffer(16)]],
                                 device const uint *nextDistinct [[buffer(17)]],
                                 device const uint *gpuCount [[buffer(22)]],
                                 uint id [[thread_position_in_grid]]) {
        if (id >= u.pointCount) { return; }
        StrokeOutput out = { outPositions, outNormals, outTexcoords, outColors, false, u.capacityTriangles, normalize(u.up.xyz),
                             float3(0.0), float3(0.0), u.bendCosine, u.bendSine };
        const uint first = blockSums[id / STROKE_SCAN_BLOCK] + offsets[id];
        strokePoint(id, first, out, u, positionData, colorData, sizeData, strips, distances, stripMeasures, total,
                    previousDistinct, nextDistinct, activePointCount(u, gpuCount));
    }
    """
}
