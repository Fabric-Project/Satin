import Metal
import Satin
import simd
import XCTest

/// `Points`: named attributes resolved to slots once, topologies turned into indices once, and a
/// geometry that binds whichever points it is given, unbinding what the previous ones had.
final class PointsTests: XCTestCase {
    func testStandardAttributesTakeTheirSlotsAndCustomOnesTakeCustomSlotsInOrder() throws {
        let context = try makeContext()
        let position = try floats3(count: 2, context)
        let points = try Points(attributes: [
            (.custom("heat"), try floats1(count: 2, context)),
            (.position, position),
            (.color, try floats4(count: 2, context)),
            (.custom("age"), try floats1(count: 2, context)),
            (.size, try floats1(count: 2, context)),
        ], topology: .implicit, bounds: .unknown)

        XCTAssertEqual(points.attributes.map { $0.key }, [.position, .custom("heat"), .color, .custom("age"), .size])
        XCTAssertEqual(points.slots.map { $0.index }, [.Position, .Custom0, .Color, .Custom1, .PointSize])
        XCTAssertTrue(points.attribute(.position) === position)
        XCTAssertNil(points.attribute(.normal))
    }

    func testInvalidAttributeSetsAreRejected() throws {
        let context = try makeContext()
        let position = try floats3(count: 3, context)

        XCTAssertThrowsError(try Points(attributes: [(.color, try floats4(count: 3, context))], topology: .implicit, bounds: .unknown)) {
            XCTAssertEqual($0 as? PointsError, .missingPosition)
        }
        XCTAssertThrowsError(try Points(attributes: [(.position, position), (.position, position)], topology: .implicit, bounds: .unknown)) {
            XCTAssertEqual($0 as? PointsError, .duplicateAttribute(.position))
        }
        XCTAssertThrowsError(try Points(attributes: [(.position, position), (.color, try floats4(count: 2, context))], topology: .implicit, bounds: .unknown)) {
            XCTAssertEqual($0 as? PointsError, .attributeTooShort(.color))
        }
        let tooMany = try (0 ... PointAttribute.customIndices.count).map { (PointAttribute.custom("c\($0)"), try floats1(count: 3, context)) }
        XCTAssertThrowsError(try Points(attributes: [(.position, position)] + tooMany, topology: .implicit, bounds: .unknown)) {
            XCTAssertEqual($0 as? PointsError, .tooManyCustomAttributes(limit: PointAttribute.customIndices.count))
        }
        XCTAssertThrowsError(try Points(attributes: [(.position, position)], topology: .indexed([0, 3]), bounds: .unknown)) {
            XCTAssertEqual($0 as? PointsError, .topologyOutOfRange)
        }
    }

    func testStripsMustBeInOrderAndApart() throws {
        let context = try makeContext()
        let position = try floats3(count: 4, context)
        XCTAssertThrowsError(try Points(attributes: [(.position, position)],
                                        topology: .strips([PointStrip(range: 2 ..< 4, closed: false), PointStrip(range: 0 ..< 2, closed: false)]),
                                        bounds: .unknown)) {
            XCTAssertEqual($0 as? PointsError, .stripsOutOfOrder)
        }
        XCTAssertThrowsError(try Points(attributes: [(.position, position)],
                                        topology: .strips([PointStrip(range: 0 ..< 3, closed: false), PointStrip(range: 2 ..< 4, closed: false)]),
                                        bounds: .unknown)) {
            XCTAssertEqual($0 as? PointsError, .stripsOutOfOrder)
        }
    }

    func testDrawArgumentsMustLieInsideTheirBuffer() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let buffer = try XCTUnwrap(device.makeBuffer(length: 32, options: .storageModeShared))
        XCTAssertNoThrow(try PointsDrawArguments(buffer: buffer, offset: 0))
        XCTAssertNoThrow(try PointsDrawArguments(buffer: buffer, offset: 16))
        XCTAssertThrowsError(try PointsDrawArguments(buffer: buffer, offset: 20)) { XCTAssertEqual($0 as? PointsError, .drawArgumentsOutOfRange) }
        XCTAssertThrowsError(try PointsDrawArguments(buffer: buffer, offset: 2)) { XCTAssertEqual($0 as? PointsError, .drawArgumentsOutOfRange) }
        XCTAssertThrowsError(try PointsDrawArguments(buffer: buffer, offset: -4)) { XCTAssertEqual($0 as? PointsError, .drawArgumentsOutOfRange) }
    }

    func testEmptyTopologyDrawsNothing() throws {
        let context = try makeContext()
        let position = try floats3(count: 3, context)
        let unconnected = try Points(attributes: [(.position, position)], topology: .indexed([]), bounds: .unknown)
        XCTAssertTrue(unconnected.drawsNothing)
        XCTAssertTrue(try Points(attributes: [(.position, position)], topology: .strips([]), bounds: .unknown).drawsNothing)
        XCTAssertFalse(try Points(attributes: [(.position, position)], topology: .implicit, bounds: .unknown).drawsNothing)
        XCTAssertNil(Geometry(context: context, points: unconnected, primitiveType: .triangle).elementBuffer)
    }

    func testStripsBecomeIndicesWithARestartBetweenEach() throws {
        let context = try makeContext()
        let points = try Points(attributes: [(.position, try floats3(count: 7, context))],
                                topology: .strips([PointStrip(range: 0 ..< 4, closed: true), PointStrip(range: 4 ..< 7, closed: false)]),
                                bounds: .unknown)
        let elements = try XCTUnwrap(points.elements)
        let indices = Array(UnsafeBufferPointer(start: try XCTUnwrap(elements.data).bindMemory(to: UInt32.self, capacity: elements.count),
                                                count: elements.count))
        XCTAssertEqual(indices, [0, 1, 2, 3, 0, UInt32.max, 4, 5, 6])
    }

    func testAGeometryBindsEveryAttributeAndUnbindsWhatTheNextPointsLack() throws {
        let context = try makeContext()
        let colored = try Points(attributes: [(.position, try floats3(count: 2, context)),
                                              (.color, try floats4(count: 2, context)),
                                              (.size, try floats1(count: 2, context))],
                                 topology: .implicit, bounds: .unknown)
        let geometry = Geometry(context: context, points: colored, primitiveType: .point)
        geometry.update()
        XCTAssertTrue(geometry.hasAttribute(.Color))
        XCTAssertTrue(geometry.hasAttribute(.PointSize))
        XCTAssertEqual(geometry.vertexDescriptor.attributes[VertexAttributeIndex.PointSize.rawValue].format, .float)

        geometry.setPoints(try Points(positions: [[0, 0, 0], [1, 1, 1]], allocator: context.gpuAllocator))
        geometry.update()
        XCTAssertFalse(geometry.hasAttribute(.Color))
        XCTAssertFalse(geometry.hasAttribute(.PointSize))
        XCTAssertNil(geometry.vertexBuffers[VertexAttributeIndex.Color.bufferIndex])
        XCTAssertEqual(geometry.vertexDescriptor.attributes[VertexAttributeIndex.Color.rawValue].format, .invalid)
    }

    func testStripsIndexOnlyStripPrimitives() throws {
        let context = try makeContext()
        let points = try Points(attributes: [(.position, try floats3(count: 4, context))],
                                topology: .strips([PointStrip(range: 0 ..< 2, closed: false), PointStrip(range: 2 ..< 4, closed: false)]),
                                bounds: .unknown)
        XCTAssertNotNil(Geometry(context: context, points: points, primitiveType: .lineStrip).elementBuffer)
        XCTAssertNil(Geometry(context: context, points: points, primitiveType: .point).elementBuffer)
    }

    func testRepublishingTheSameLayoutKeepsTheVertexDescriptor() throws {
        let context = try makeContext()
        let geometry = Geometry(context: context, points: try Points(positions: [[0, 0, 0]], allocator: context.gpuAllocator), primitiveType: .point)
        let descriptor = geometry.vertexDescriptor
        geometry.setPoints(try Points(positions: [[1, 1, 1]], allocator: context.gpuAllocator))
        XCTAssertTrue(geometry.vertexDescriptor === descriptor)

        geometry.setPoints(try Points(attributes: [(.position, try floats3(count: 1, context)), (.color, try floats4(count: 1, context))],
                                      topology: .implicit, bounds: .unknown))
        XCTAssertFalse(geometry.vertexDescriptor === descriptor)
    }

    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func floats1(count: Int, _ context: Context) throws -> PublishedAttribute {
        try PublishedAttribute.publishing(ContiguousArray(repeating: Float(1), count: count), scalar: .float32, components: 1, allocator: context.gpuAllocator)
    }

    private func floats3(count: Int, _ context: Context) throws -> PublishedAttribute {
        try PublishedAttribute.publishing(ContiguousArray(repeating: simd_float3.zero, count: count), scalar: .float32, components: 3, allocator: context.gpuAllocator)
    }

    private func floats4(count: Int, _ context: Context) throws -> PublishedAttribute {
        try PublishedAttribute.publishing(ContiguousArray(repeating: simd_float4.one, count: count), scalar: .float32, components: 4, allocator: context.gpuAllocator)
    }
}
