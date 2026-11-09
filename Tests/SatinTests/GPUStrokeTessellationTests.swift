import Metal
import Satin
import simd
import XCTest

/// `GPUStrokeTessellation`: points stroked into triangles on the GPU, a fixed number per point.
final class GPUStrokeTessellationTests: XCTestCase {
    private var context: Context!
    private var pipeline: MTLComputePipelineState!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let library = try device.makeLibrary(source: GPUStrokeTessellation.source, options: nil)
        pipeline = try device.makeComputePipelineState(function: try XCTUnwrap(library.makeFunction(name: GPUStrokeTessellation.functionName)))
    }

    /// The triangles `points` stroke into, read back, and how many are not collapsed.
    private func tessellate(_ points: Points, style: Stroke.Style) throws -> (vertices: [simd_float4], drawn: Int, result: Points) {
        let commandBuffer = try XCTUnwrap(context.device.makeCommandQueue()?.makeCommandBuffer())
        let result = try XCTUnwrap(try GPUStrokeTessellation.encode(points: points, style: style, closesAll: false, pipeline: pipeline,
                                                                    commandBuffer: commandBuffer, allocator: context.gpuAllocator))
        let length = result.count * MemoryLayout<simd_float4>.stride
        let shared = try XCTUnwrap(context.device.makeBuffer(length: length, options: .storageModeShared))
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: result.position.buffer, sourceOffset: 0, to: shared, destinationOffset: 0, size: length)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let vertices = Array(UnsafeBufferPointer(start: shared.contents().bindMemory(to: simd_float4.self, capacity: result.count), count: result.count))
        var drawn = 0
        for triangle in stride(from: 0, to: vertices.count, by: 3) {
            let a = simd_make_float3(vertices[triangle]), b = simd_make_float3(vertices[triangle + 1]), c = simd_make_float3(vertices[triangle + 2])
            if simd_length(simd_cross(b - a, c - a)) > 1e-8 { drawn += 1 }
        }
        return (vertices, drawn, result)
    }

    func testAnLDrawsItsSegmentsJoinAndCapsWithinItsWidth() throws {
        let corner = try Points(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0]], allocator: context.gpuAllocator)
        let style = Stroke.Style(width: 0.2, join: .round, cap: .round, roundResolution: 4)
        let (vertices, drawn, result) = try tessellate(corner, style: style)

        XCTAssertEqual(result.count, 3 * GPUStrokeTessellation.trianglesPerPoint(style: style) * 3)
        // Two segments of two triangles, one round join, two round caps.
        XCTAssertEqual(drawn, 2 * 2 + 4 + 2 * 4)
        for vertex in vertices {
            let point = simd_make_float3(vertex)
            let nearest = min(simd_distance(point, [0, 0, 0]) , simd_distance(point, [1, 0, 0]), simd_distance(point, [1, 1, 0]),
                              abs(point.y) + max(0, -point.x) + max(0, point.x - 1), abs(point.x - 1) + max(0, -point.y) + max(0, point.y - 1))
            XCTAssertLessThanOrEqual(nearest, 0.1 + 1e-4, "\(point) lies within half the width of the line")
            XCTAssertEqual(point.z, 0, accuracy: 1e-6)
        }
        XCTAssertEqual(result.slots.map { $0.index }, [.Position, .Normal, .Texcoord, .Color])
    }

    func testButtCapsAndBevelsDrawLess() throws {
        let corner = try Points(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0]], allocator: context.gpuAllocator)
        let (_, drawn, _) = try tessellate(corner, style: Stroke.Style(width: 0.2, join: .bevel, cap: .butt, roundResolution: 4))
        XCTAssertEqual(drawn, 2 * 2 + 1)
    }

    func testStripsAreStrokedSeparately() throws {
        let position = try PublishedAttribute.publishing(ContiguousArray<simd_float3>([[0, 0, 0], [1, 0, 0], [5, 0, 0], [6, 0, 0]]),
                                                         scalar: .float32, components: 3, allocator: context.gpuAllocator)
        let points = try Points(attributes: [(.position, position)],
                                topology: .strips([PointStrip(range: 0 ..< 2, closed: false), PointStrip(range: 2 ..< 4, closed: false)]),
                                bounds: .unknown)
        let (vertices, drawn, _) = try tessellate(points, style: Stroke.Style(width: 0.2, join: .bevel, cap: .butt))
        // One segment per strip; nothing bridges x = 1 to x = 5.
        XCTAssertEqual(drawn, 2 * 2)
        XCTAssertFalse(vertices.contains { $0.x > 1.1 && $0.x < 4.9 })
    }

    func testPointsThatArentFloatsAreRejected() throws {
        let position = PublishedAttribute(adopting: try XCTUnwrap(context.device.makeBuffer(length: 64, options: .storageModeShared)),
                                          layout: AttributeLayout(scalar: .float16, components: 4, byteOffset: 0, byteStride: 8), count: 2)
        let commandBuffer = try XCTUnwrap(context.device.makeCommandQueue()?.makeCommandBuffer())
        XCTAssertThrowsError(try GPUStrokeTessellation.encode(points: Points(position: position, bounds: .unknown), style: Stroke.Style(),
                                                              closesAll: false, pipeline: pipeline, commandBuffer: commandBuffer,
                                                              allocator: context.gpuAllocator)) {
            XCTAssertEqual($0 as? GPUStrokeTessellation.TessellationError, .unsupportedLayout(.position))
        }
    }
}
