import Metal
import Satin
import simd
import XCTest

/// `PublishedAttribute` and `Points`: immutable attributes a geometry binds as they are, with
/// layouts that say when a vertex descriptor can describe them and when a shader must pull them.
final class PublishedAttributeTests: XCTestCase {
    func testLayoutsMetalCanDescribeHaveAVertexFormat() {
        XCTAssertEqual(AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: 16).vertexFormat, .float3)
        XCTAssertEqual(AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: 12).vertexFormat, .float3)
        XCTAssertEqual(AttributeLayout(scalar: .uint32, components: 1, byteOffset: 0, byteStride: 4).vertexFormat, .uint)
        XCTAssertEqual(AttributeLayout(scalar: .uint8Normalized, components: 4, byteOffset: 0, byteStride: 4).vertexFormat, .uchar4Normalized)
    }

    func testWideOrOddlyStridedLayoutsArePulled() {
        // Degree 3 spherical harmonics: 48 floats per point.
        XCTAssertNil(AttributeLayout(scalar: .float32, components: 48, byteOffset: 0, byteStride: 192).vertexFormat)
        // Metal's vertex layouts take strides in multiples of four.
        XCTAssertNil(AttributeLayout(scalar: .uint8, components: 3, byteOffset: 0, byteStride: 3).vertexFormat)
    }

    func testEveryPublishHasItsOwnVersion() throws {
        let allocator = try makeAllocator()
        let positions: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 2, 3]]
        let first = try Points(positions: positions, allocator: allocator)
        let second = try Points(positions: positions, allocator: allocator)
        XCTAssertNotEqual(first.version, second.version)
        XCTAssertNotEqual(first.position.version, second.position.version)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, first)
    }

    func testPublishingCopiesTheValues() throws {
        var positions: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 2, 3]]
        let points = try Points(positions: positions, allocator: try makeAllocator())
        positions[1] = [9, 9, 9]
        let published = points.position.buffer.contents().bindMemory(to: simd_float3.self, capacity: 2)
        XCTAssertEqual(published[1], simd_float3(1, 2, 3))
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.position.stride, MemoryLayout<simd_float3>.stride)
    }

    func testAGeometryBindsPublishedPositionsAndTheirBounds() throws {
        let context = try makeContext()
        let points = try Points(positions: [[-1, 0, 0], [1, 2, 3]], allocator: context.gpuAllocator)
        let geometry = Geometry(context: context, points: points, primitiveType: .point)
        geometry.update()

        XCTAssertEqual(geometry.vertexCount, 2)
        XCTAssertTrue(geometry.vertexBuffers[.Position] === points.position.buffer)
        XCTAssertEqual(geometry.vertexDescriptor.attributes[VertexAttributeIndex.Position.rawValue].format, .float3)
        XCTAssertTrue(geometry.boundsAreKnown)
        XCTAssertEqual(geometry.bounds.min, simd_float3(-1, 0, 0))
        XCTAssertEqual(geometry.bounds.max, simd_float3(1, 2, 3))
    }

    func testPublishedPositionsWithoutBoundsAreNeverCulled() throws {
        let context = try makeContext()
        let buffer = try XCTUnwrap(context.device.makeBuffer(length: 3 * 16, options: .storageModePrivate))
        let position = PublishedAttribute(adopting: buffer,
                                          layout: AttributeLayout(scalar: .float32, components: 3, byteOffset: 0, byteStride: 16),
                                          count: 3)
        let geometry = Geometry(context: context, points: Points(position: position, bounds: .unknown), primitiveType: .point)
        let mesh = Mesh(context: context, geometry: geometry, material: nil)

        XCTAssertFalse(geometry.boundsAreKnown)
        XCTAssertFalse(mesh.cullingBoundsAreKnown)

        geometry.setPoints(Points(position: position, bounds: .known(Bounds(min: .zero, max: .one))))
        XCTAssertTrue(mesh.cullingBoundsAreKnown)
    }

    func testAPulledAttributeIsBoundButNotDescribed() throws {
        let context = try makeContext()
        let points = try Points(positions: [[0, 0, 0]], allocator: context.gpuAllocator)
        let harmonicsBuffer = try XCTUnwrap(context.device.makeBuffer(length: 192, options: .storageModeShared))
        let harmonics = PublishedAttribute(adopting: harmonicsBuffer,
                                           layout: AttributeLayout(scalar: .float32, components: 48, byteOffset: 0, byteStride: 192),
                                           count: 1)
        let geometry = Geometry(context: context, points: points, primitiveType: .point)
        geometry.addAttribute(harmonics, for: .Custom0)
        geometry.update()

        XCTAssertTrue(harmonics.isPulled)
        XCTAssertTrue(geometry.vertexBuffers[.Custom0] === harmonicsBuffer)
        XCTAssertEqual(geometry.vertexDescriptor.attributes[VertexAttributeIndex.Custom0.rawValue].format, .invalid)
    }

    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func makeAllocator() throws -> GPUAllocator {
        try makeContext().gpuAllocator
    }
}
