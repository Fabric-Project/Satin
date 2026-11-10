import Metal
import Satin
import simd
import XCTest

/// `GPUStrokeTessellation`: points stroked into triangles on the GPU, a fixed number per point.
final class GPUStrokeTessellationTests: XCTestCase {
    private var context: Context!
    private var pipelines: GPUStrokeTessellation.Pipelines!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let library = try device.makeLibrary(source: GPUStrokeTessellation.source, options: nil)
        let compiled = try GPUStrokeTessellation.functionNames.map { name in
            try device.makeComputePipelineState(function: try XCTUnwrap(library.makeFunction(name: name)))
        }
        pipelines = try XCTUnwrap(GPUStrokeTessellation.Pipelines(compiled))
    }

    private struct Ribbons {
        let positions: [simd_float4]
        let normals: [simd_float4]
        let texcoords: [simd_float2]
        let result: Points

        /// Triangles drawn that aren't collapsed: all of them, now the GPU counts exactly.
        var drawn: Int {
            stride(from: 0, to: positions.count, by: 3).filter { triangle in
                let a = simd_make_float3(positions[triangle]), b = simd_make_float3(positions[triangle + 1]), c = simd_make_float3(positions[triangle + 2])
                return simd_length(simd_cross(b - a, c - a)) > 1e-8
            }.count
        }

        /// The vertices of triangles that aren't collapsed.
        var drawnPositions: [simd_float3] {
            stride(from: 0, to: positions.count, by: 3).flatMap { triangle -> [simd_float3] in
                let a = simd_make_float3(positions[triangle]), b = simd_make_float3(positions[triangle + 1]), c = simd_make_float3(positions[triangle + 2])
                return simd_length(simd_cross(b - a, c - a)) > 1e-8 ? [a, b, c] : []
            }
        }
    }

    /// The ribbons `points` stroke into, read back.
    private func tessellate(_ points: Points, style: Stroke.Style, options: GPUStrokeTessellation.Options = .plain) throws -> Ribbons {
        let commandBuffer = try XCTUnwrap(context.device.makeCommandQueue()?.makeCommandBuffer())
        let result = try XCTUnwrap(try GPUStrokeTessellation.encode(points: points, style: style, options: options, pipelines: pipelines,
                                                                    commandBuffer: commandBuffer, allocator: context.gpuAllocator))
        func copy(_ attribute: PublishedAttribute, blit: MTLBlitCommandEncoder) throws -> MTLBuffer {
            let length = result.count * attribute.layout.byteStride
            let shared = try XCTUnwrap(context.device.makeBuffer(length: length, options: .storageModeShared))
            blit.copy(from: attribute.buffer, sourceOffset: 0, to: shared, destinationOffset: 0, size: length)
            return shared
        }
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        let positions = try copy(result.position, blit: blit)
        let normals = try copy(try XCTUnwrap(result.attribute(.normal)), blit: blit)
        let texcoords = try copy(try XCTUnwrap(result.attribute(.texcoord)), blit: blit)
        let drawArguments = try XCTUnwrap(result.drawArguments)
        let sharedArguments = try XCTUnwrap(context.device.makeBuffer(length: MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride,
                                                                      options: .storageModeShared))
        blit.copy(from: drawArguments.buffer, sourceOffset: drawArguments.offset, to: sharedArguments, destinationOffset: 0,
                  size: MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        // Only the vertices the GPU counted are drawn; the rest of the capacity is unwritten.
        let drawnCount = Int(sharedArguments.contents().load(as: MTLDrawPrimitivesIndirectArguments.self).vertexCount)
        XCTAssertLessThanOrEqual(drawnCount, result.count)
        func read<Element>(_ buffer: MTLBuffer, as _: Element.Type) -> [Element] {
            Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: Element.self, capacity: result.count), count: drawnCount))
        }
        return Ribbons(positions: read(positions, as: simd_float4.self), normals: read(normals, as: simd_float4.self),
                       texcoords: read(texcoords, as: simd_float2.self), result: result)
    }

    private func line(_ positions: ContiguousArray<simd_float3>) throws -> Points {
        try Points(positions: positions, allocator: context.gpuAllocator)
    }

    private func options(_ change: (inout GPUStrokeTessellation.Options) -> Void) -> GPUStrokeTessellation.Options {
        var options = GPUStrokeTessellation.Options.plain
        change(&options)
        return options
    }

    func testOnePointWithRoundCapsIsADot() throws {
        let style = Stroke.Style(width: 0.2, join: .round, cap: .round, roundResolution: 6)
        let dot = try tessellate(try line([[1, 2, 0]]), style: style)
        XCTAssertEqual(dot.drawn, GPUStrokeTessellation.dotTriangles(style: style))
        XCTAssertTrue(dot.drawnPositions.allSatisfy { simd_distance($0, [1, 2, 0]) <= 0.1 + 1e-4 })

        let twoAtOnePlace = try tessellate(try line([[1, 2, 0], [1, 2, 0]]), style: style)
        XCTAssertEqual(twoAtOnePlace.drawn, GPUStrokeTessellation.dotTriangles(style: style))

        XCTAssertEqual(try tessellate(try line([[1, 2, 0]]), style: Stroke.Style(width: 0.2, cap: .butt)).drawn, 0)
    }

    func testBendTiltsEdgeNormalsAcrossTheRibbon() throws {
        let straight = try line([[0, 0, 0], [1, 0, 0]])
        let style = Stroke.Style(width: 0.2, join: .bevel, cap: .butt)

        let flat = try tessellate(straight, style: style)
        XCTAssertTrue(flat.normals.prefix(6).allSatisfy { simd_distance(simd_make_float3($0), [0, 0, 1]) < 1e-5 })

        // Fully bent, the edges face sideways: +y on the left (y > 0), -y on the right.
        let bent = try tessellate(straight, style: style, options: options { $0.bend = 1 })
        for index in 0 ..< 6 {
            let position = simd_make_float3(bent.positions[index])
            let normal = simd_make_float3(bent.normals[index])
            XCTAssertEqual(normal.z, 0, accuracy: 1e-5)
            XCTAssertEqual(normal.y, position.y > 0 ? 1 : -1, accuracy: 1e-5)
        }
    }

    func testAnLDrawsItsSegmentsJoinAndCapsWithinItsWidth() throws {
        let style = Stroke.Style(width: 0.2, join: .round, cap: .round, roundResolution: 4)
        let corner = try tessellate(try line([[0, 0, 0], [1, 0, 0], [1, 1, 0]]), style: style)

        XCTAssertEqual(corner.result.count, GPUStrokeTessellation.maximumTriangles(pointCount: 3, stripCount: 1, style: style, options: .plain) * 3)
        // Two segments of two triangles, one round join, two round caps.
        XCTAssertEqual(corner.drawn, 2 * 2 + 4 + 2 * 4)
        for point in corner.drawnPositions {
            let nearest = min(simd_distance(point, [0, 0, 0]), simd_distance(point, [1, 0, 0]), simd_distance(point, [1, 1, 0]),
                              abs(point.y) + max(0, -point.x) + max(0, point.x - 1), abs(point.x - 1) + max(0, -point.y) + max(0, point.y - 1))
            XCTAssertLessThanOrEqual(nearest, 0.1 + 1e-4, "\(point) lies within half the width of the line")
            XCTAssertEqual(point.z, 0, accuracy: 1e-6)
        }
        XCTAssertEqual(corner.result.slots.map { $0.index }, [.Position, .Normal, .Texcoord, .Color])
    }

    func testRepeatedPointsJoinTheLineInsteadOfBreakingIt() throws {
        let repeated = try tessellate(try line([[0, 0, 0], [1, 0, 0], [1, 0, 0], [1, 0, 0], [2, 0, 0]]),
                                      style: Stroke.Style(width: 0.2, join: .bevel, cap: .square))
        // Two segments and a cap at each end only: no caps where the points repeat.
        XCTAssertEqual(repeated.drawn, 2 * 2 + 2 * 2)
        let xs = repeated.drawnPositions.map(\.x)
        XCTAssertEqual(try XCTUnwrap(xs.min()), -0.1, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(xs.max()), 2.1, accuracy: 1e-4)
    }

    func testALongLineMeasuresAcrossScanBlocks() throws {
        // 1,000 points, four scan blocks, with a repeated point where the first block meets the
        // second: distances carry across blocks, and the repeat joins the line instead of capping it.
        let positions = ContiguousArray((0 ..< 1_000).map { index in simd_float3(Float(index <= 255 ? index : index - 1) * 0.01, 0, 0) })
        let style = Stroke.Style(width: 0.1, join: .bevel, cap: .square)
        let trimmed = try tessellate(try line(positions), style: style, options: options { $0.trimStart = 0.25; $0.trimEnd = 0.75 })
        // The line is 9.98 long, so the trim keeps 2.495 to 7.485: 500 segments, cut by a square cap at each end.
        XCTAssertEqual(trimmed.drawn, 500 * 2 + 2 * 2)
        let xs = trimmed.drawnPositions.map(\.x)
        XCTAssertEqual(try XCTUnwrap(xs.min()), 2.495 - 0.05, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(xs.max()), 7.485 + 0.05, accuracy: 1e-3)
    }

    func testALongClosedLoopWrapsAcrossScanBlocks() throws {
        // A circle of 600 points, closed: every point joins, the first looking back past the last.
        let positions = ContiguousArray((0 ..< 600).map { index -> simd_float3 in
            let angle = Float(index) / 600 * 2 * .pi
            return simd_float3(cos(angle), sin(angle), 0)
        })
        let loop = try tessellate(try line(positions), style: Stroke.Style(width: 0.05, join: .bevel, cap: .butt),
                                  options: options { $0.closesAll = true })
        // A segment and a bevel per point, and no caps.
        XCTAssertEqual(loop.drawn, 600 * (2 + 1))
    }

    func testASolidLinePaysForCapsPerStripNotPerPoint() {
        let style = Stroke.Style(width: 0.1, join: .round, cap: .round, roundResolution: 8)
        let solid = GPUStrokeTessellation.maximumTriangles(pointCount: 1_000, stripCount: 1, style: style, options: .plain)
        // A segment and a join per point, two caps and a dot's worth per strip.
        XCTAssertEqual(solid, 1_000 * (2 + 8) + (2 * 8 + 16))
        var dashed = GPUStrokeTessellation.Options.plain
        dashed.dashLength = 0.2
        dashed.gapLength = 0.2
        XCTAssertGreaterThan(GPUStrokeTessellation.maximumTriangles(pointCount: 1_000, stripCount: 1, style: style, options: dashed), solid)
    }

    func testButtCapsAndBevelsDrawLess() throws {
        let corner = try tessellate(try line([[0, 0, 0], [1, 0, 0], [1, 1, 0]]), style: Stroke.Style(width: 0.2, join: .bevel, cap: .butt, roundResolution: 4))
        XCTAssertEqual(corner.drawn, 2 * 2 + 1)
    }

    func testStripsAreStrokedSeparately() throws {
        let position = try PublishedAttribute.publishing(ContiguousArray<simd_float3>([[0, 0, 0], [1, 0, 0], [5, 0, 0], [6, 0, 0]]),
                                                         scalar: .float32, components: 3, allocator: context.gpuAllocator)
        let points = try Points(attributes: [(.position, position)],
                                topology: .strips([PointStrip(range: 0 ..< 2, closed: false), PointStrip(range: 2 ..< 4, closed: false)]),
                                bounds: .unknown)
        let ribbons = try tessellate(points, style: Stroke.Style(width: 0.2, join: .bevel, cap: .butt))
        // One segment per strip; nothing bridges x = 1 to x = 5.
        XCTAssertEqual(ribbons.drawn, 2 * 2)
        XCTAssertFalse(ribbons.drawnPositions.contains { $0.x > 1.1 && $0.x < 4.9 })
    }

    func testPointsAGPUPassCountedStrokeOnlyThatMany() throws {
        // Four positions in the buffer, two of them counted: only the first segment draws.
        let position = try PublishedAttribute.publishing(ContiguousArray<simd_float3>([[0, 0, 0], [1, 0, 0], [5, 0, 0], [6, 0, 0]]),
                                                         scalar: .float32, components: 3, allocator: context.gpuAllocator)
        let arguments = try XCTUnwrap(context.device.makeBuffer(length: PointsDrawArguments.recordLength, options: .storageModeShared))
        func counted(_ count: UInt32) throws -> Points {
            arguments.contents().storeBytes(of: MTLDrawPrimitivesIndirectArguments(vertexCount: count, instanceCount: 1, vertexStart: 0, baseInstance: 0),
                                            as: MTLDrawPrimitivesIndirectArguments.self)
            return try Points(attributes: [(.position, position)], topology: .implicit, bounds: .unknown,
                              drawArguments: try PointsDrawArguments(buffer: arguments, offset: 0))
        }
        let style = Stroke.Style(width: 0.2, join: .bevel, cap: .butt)
        let two = try tessellate(try counted(2), style: style)
        XCTAssertEqual(two.positions.count, 6)
        XCTAssertFalse(two.drawnPositions.contains { $0.x > 1.1 })
        XCTAssertEqual(try tessellate(try counted(0), style: style).positions.count, 0)
    }

    func testTrimKeepsTheMiddleWithCapsAtTheCuts() throws {
        let style = Stroke.Style(width: 0.2, join: .bevel, cap: .square)
        let trimmed = try tessellate(try line([[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0], [4, 0, 0]]), style: style,
                                     options: options { $0.trimStart = 0.25; $0.trimEnd = 0.75 })
        let xs = trimmed.drawnPositions.map(\.x)
        // From x = 1 to 3, with square caps reaching half the width past each cut.
        XCTAssertEqual(try XCTUnwrap(xs.min()), 0.9, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(xs.max()), 3.1, accuracy: 1e-4)
    }

    func testDashesLeaveGaps() throws {
        let style = Stroke.Style(width: 0.1, join: .bevel, cap: .butt)
        let dashed = try tessellate(try line([[0, 0, 0], [4, 0, 0]]), style: style,
                                    options: options { $0.dashLength = 0.5; $0.gapLength = 0.5 })
        // Four dashes, each a quad, from x = 0–0.5, 1–1.5, 2–2.5 and 3–3.5.
        XCTAssertEqual(dashed.drawn, 4 * 2)
        XCTAssertFalse(dashed.drawnPositions.contains { $0.x > 0.5 + 1e-4 && $0.x < 1 - 1e-4 })
        XCTAssertFalse(dashed.drawnPositions.contains { $0.x > 3.5 + 1e-4 })
    }

    func testEverySegmentDrawsAllItsDashes() throws {
        // Segments that start partway through the pattern: each dash end lands where rounding can
        // leave the cursor just short of the gap, which once ended a segment after its first dash.
        let style = Stroke.Style(width: 0.02, join: .bevel, cap: .butt)
        let positions = ContiguousArray((0 ..< 10).map { simd_float3(Float($0) * 0.37, 0, 0) })
        let dashed = try tessellate(try line(positions), style: style,
                                    options: options { $0.dashLength = 0.15; $0.gapLength = 0.1; $0.dashesPerSegment = 8 })
        let xs = dashed.drawnPositions.map(\.x)
        let lineLength: Float = 9 * 0.37
        for dash in 0 ..< Int(lineLength / 0.25)
        {
            let start = Float(dash) * 0.25
            XCTAssertTrue(xs.contains { $0 >= start - 1e-4 && $0 <= start + 0.15 + 1e-4 }, "dash \(dash) at \(start) is drawn")
        }
        XCTAssertFalse(xs.contains { $0.truncatingRemainder(dividingBy: 0.25) > 0.15 + 1e-3 && $0.truncatingRemainder(dividingBy: 0.25) < 0.25 - 1e-3 },
                       "nothing is drawn inside a gap")
    }

    func testLayerDepthRaisesLaterPoints() throws {
        let layered = try tessellate(try line([[0, 0, 0], [1, 0, 0], [2, 0, 0]]), style: Stroke.Style(width: 0.2, join: .bevel, cap: .butt),
                                     options: options { $0.layerDepth = 0.5 })
        for point in layered.drawnPositions {
            XCTAssertEqual(point.z, point.x / 2 * 0.5, accuracy: 1e-4)
        }
    }

    func testRevealHoldsTheTextureOnTheLineWhileStretchFitsTheTrim() throws {
        let points = try line([[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0], [4, 0, 0]])
        let style = Stroke.Style(width: 0.2, join: .bevel, cap: .butt)
        func uRange(_ mode: GPUStrokeTessellation.TextureMode) throws -> ClosedRange<Float> {
            let ribbons = try tessellate(points, style: style, options: options { $0.trimStart = 0.25; $0.trimEnd = 0.75; $0.textureMode = mode })
            let us = stride(from: 0, to: ribbons.positions.count, by: 3).flatMap { triangle -> [Float] in
                let a = simd_make_float3(ribbons.positions[triangle]), b = simd_make_float3(ribbons.positions[triangle + 1]), c = simd_make_float3(ribbons.positions[triangle + 2])
                return simd_length(simd_cross(b - a, c - a)) > 1e-8 ? (0 ..< 3).map { ribbons.texcoords[triangle + $0].x } : []
            }
            return try XCTUnwrap(us.min()) ... XCTUnwrap(us.max())
        }
        let stretched = try uRange(.stretch)
        XCTAssertEqual(stretched.lowerBound, 0, accuracy: 1e-4)
        XCTAssertEqual(stretched.upperBound, 1, accuracy: 1e-4)
        let revealed = try uRange(.reveal)
        XCTAssertEqual(revealed.lowerBound, 0.25, accuracy: 1e-4)
        XCTAssertEqual(revealed.upperBound, 0.75, accuracy: 1e-4)
    }

    func testARoundJoinThatDoublesBackTurnsAHalfCircle() throws {
        let style = Stroke.Style(width: 0.2, join: .round, cap: .butt, roundResolution: 8)
        let reversal = try tessellate(try line([[0, 0, 0], [1, 0, 0], [0, 0, 0]]), style: style)
        // Two segments, and a round join of 8 that bulges forward past x = 1.
        XCTAssertEqual(reversal.drawn, 2 * 2 + 8)
        XCTAssertEqual(try XCTUnwrap(reversal.drawnPositions.map(\.x).max()), 1.1, accuracy: 1e-4)
    }

    func testDashesTooShortToSeeDrawASolidLine() throws {
        let style = Stroke.Style(width: 0.1, join: .bevel, cap: .butt)
        let tiny = try tessellate(try line([[0, 0, 0], [4, 0, 0]]), style: style,
                                  options: options { $0.dashLength = 1e-7; $0.gapLength = 1e-7; $0.dashesPerSegment = 64 })
        XCTAssertEqual(tiny.drawn, 2)
        let xs = tiny.drawnPositions.map(\.x)
        XCTAssertEqual(try XCTUnwrap(xs.min()), 0, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(xs.max()), 4, accuracy: 1e-4)
    }

    func testDashesFarAlongALongLineStillFinish() throws {
        // Far from the origin a float can't step by a dash this short: the kernel must still end.
        let style = Stroke.Style(width: 0.1, join: .bevel, cap: .butt)
        let far = try tessellate(try line([[0, 0, 0], [100_000, 0, 0], [100_001, 0, 0]]), style: style,
                                 options: options { $0.dashLength = 0.001; $0.gapLength = 0.001 })
        XCTAssertGreaterThan(far.drawn, 0)
    }

    func testValuesThatArentFiniteAreSanitized() throws {
        let points = try line([[0, 0, 0], [1, 0, 0]])
        let commandBuffer = try XCTUnwrap(context.device.makeCommandQueue()?.makeCommandBuffer())
        XCTAssertNil(try GPUStrokeTessellation.encode(points: points, style: Stroke.Style(width: .nan), options: .plain, pipelines: pipelines,
                                                      commandBuffer: commandBuffer, allocator: context.gpuAllocator))
        let wild = try tessellate(points, style: Stroke.Style(width: 0.2, join: .bevel, cap: .butt, miterLimit: .infinity, up: [0, 0, 0]),
                                  options: options { $0.bend = .nan; $0.trimStart = -.infinity; $0.trimEnd = .nan; $0.dashOffset = .infinity })
        XCTAssertEqual(wild.drawn, 2)
    }

    func testTooManyVerticesIsAnError() throws {
        // Past the 32-bit vertex count on any device, so it throws whatever the device's memory.
        let points = try line(ContiguousArray((0 ..< 200_000).map { simd_float3(Float($0), 0, 0) }))
        let commandBuffer = try XCTUnwrap(context.device.makeCommandQueue()?.makeCommandBuffer())
        let style = Stroke.Style(width: 0.1, cap: .round, roundResolution: 64)
        let dashed = options { $0.dashLength = 0.1; $0.gapLength = 0.1; $0.dashesPerSegment = 64 }
        XCTAssertGreaterThan(GPUStrokeTessellation.maximumTriangles(pointCount: points.count, stripCount: 1, style: style, options: dashed) * 3,
                             GPUStrokeTessellation.maximumVertexCount(device: context.device))
        XCTAssertThrowsError(try GPUStrokeTessellation.encode(points: points, style: style,
                                                              options: dashed,
                                                              pipelines: pipelines, commandBuffer: commandBuffer, allocator: context.gpuAllocator)) {
            guard case .tooManyVertices = $0 as? GPUStrokeTessellation.TessellationError else {
                return XCTFail("\($0) is too many vertices")
            }
        }
    }

    func testPointsThatArentFloatsAreRejected() throws {
        let position = PublishedAttribute(adopting: try XCTUnwrap(context.device.makeBuffer(length: 64, options: .storageModeShared)),
                                          layout: AttributeLayout(scalar: .float16, components: 4, byteOffset: 0, byteStride: 8), count: 2)
        let commandBuffer = try XCTUnwrap(context.device.makeCommandQueue()?.makeCommandBuffer())
        XCTAssertThrowsError(try GPUStrokeTessellation.encode(points: Points(position: position, bounds: .unknown), style: Stroke.Style(),
                                                              options: .plain, pipelines: pipelines, commandBuffer: commandBuffer,
                                                              allocator: context.gpuAllocator)) {
            XCTAssertEqual($0 as? GPUStrokeTessellation.TessellationError, .unsupportedLayout(.position))
        }
    }
}
