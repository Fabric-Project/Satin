import Metal
import Satin
import simd
import XCTest

/// `PolylineGeometry`: SatinCore tessellates a ribbon straight into memory the geometry owns,
/// and each update hands that memory to buffers made once.
final class PolylineGeometryTests: XCTestCase {
    /// A zigzag with sharp turns, so joins take every path: straight, miter, miter falling back
    /// to bevel, bevel, and round fans.
    private let zigzag: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [2, 1, 0], [2.1, -1, 0], [3, 0, 0], [4, 0, 0]]

    func testEveryJoinAndCapIndexesOnlyItsOwnVertices() throws {
        let geometry = try makeGeometry()
        for joinStyle in [PolylineJoinStyle.miter, .bevel, .round] {
            for capStyle in [PolylineCapStyle.butt, .square, .round] {
                for closed in [false, true] {
                    geometry.update(points: zigzag, closed: closed,
                                    style: PolylineStyle(width: 0.2, join: joinStyle, cap: capStyle, miterLimit: 2, roundResolution: 8))
                    let label = "\(joinStyle) \(capStyle) closed: \(closed)"
                    XCTAssertGreaterThan(geometry.vertexCount, 0, label)
                    XCTAssertGreaterThan(geometry.indexCount, 0, label)
                    let indices = try XCTUnwrap(geometry.elementBuffer?.data).bindMemory(to: UInt32.self, capacity: geometry.indexCount)
                    for index in 0 ..< geometry.indexCount {
                        XCTAssertLessThan(Int(indices[index]), geometry.vertexCount, label)
                    }
                    let bounds = geometry.bounds
                    XCTAssertTrue(bounds.min.x.isFinite && bounds.max.x.isFinite, label)
                    XCTAssertLessThanOrEqual(bounds.min.x, 0, label)
                    XCTAssertGreaterThanOrEqual(bounds.max.x, 4, label)
                }
            }
        }
    }

    func testFewerThanTwoPointsDrawNothing() throws {
        let geometry = try makeGeometry()
        let style = PolylineStyle(width: 0.2, join: .round, cap: .round)
        geometry.update(points: zigzag, closed: false, style: style)
        for points: ContiguousArray<simd_float3> in [[], [[1, 1, 1]], [[1, 1, 1], [1, 1, 1]]] {
            geometry.update(points: points, closed: false, style: style)
            XCTAssertEqual(geometry.vertexCount, 0)
            XCTAssertEqual(geometry.indexCount, 0)
        }
    }

    func testWidthScalesWidenTheRibbonPerPoint() throws {
        // A straight ribbon along x, 0.2 wide, with butt caps: its height is its width.
        let geometry = try makeGeometry()
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [2, 0, 0]]
        let style = PolylineStyle(width: 0.2)
        geometry.update(points: points, closed: false, style: style)
        XCTAssertEqual(geometry.bounds.max.y, 0.1, accuracy: 1e-5)

        geometry.update(points: points, closed: false, style: style, widthScales: [1, 3])
        XCTAssertEqual(geometry.bounds.max.y, 0.3, accuracy: 1e-5, "The last scale repeats for the third point")
        XCTAssertEqual(geometry.bounds.min.y, -0.3, accuracy: 1e-5)
    }

    func testAReversalHasNoInvalidVertices() throws {
        let geometry = try makeGeometry()
        let style = PolylineStyle(width: 0.2, join: .round, cap: .round)
        for (points, closed) in [(ContiguousArray<simd_float3>([[0, 0, 0], [1, 0, 0], [0, 0, 0]]), false),
                                 (ContiguousArray<simd_float3>([[0, 0, 0], [1, 0, 0]]), true)] {
            geometry.update(points: points, closed: closed, style: style)
            for vertex in try vertices(of: geometry) {
                XCTAssertTrue(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite,
                              "closed: \(closed)")
            }
        }
    }

    func testUpdatesReuseTheirMemory() throws {
        let geometry = try makeGeometry()
        let style = PolylineStyle(width: 0.2, join: .round, cap: .round)
        geometry.update(points: zigzag, closed: false, style: style)
        geometry.update()
        let tessellated = try XCTUnwrap((geometry.getAttribute(.Position) as? InterleavedBufferAttribute)?.parent.data)
        for frame in 0 ..< 5 {
            geometry.update(points: zigzag, closed: false, style: style)
            geometry.update()
            XCTAssertEqual((geometry.getAttribute(.Position) as? InterleavedBufferAttribute)?.parent.data, tessellated, "frame \(frame)")
        }
    }

    func testAnUpdateAfterUnchangedFramesLeavesTheBuffersOnScreenAlone() throws {
        // Frames still in flight read the buffers on screen; whatever the gap, a new upload goes elsewhere.
        let geometry = try makeGeometry()
        let style = PolylineStyle(width: 0.2)
        for unchangedFrames in 0 ..< 6 {
            geometry.update(points: zigzag, closed: false, style: style)
            geometry.update()
            let vertexBufferOnScreen = try XCTUnwrap(geometry.vertexBuffers[.Vertices])
            let indexBufferOnScreen = try XCTUnwrap(geometry.indexBuffer)
            for _ in 0 ..< unchangedFrames { geometry.update() }
            XCTAssertTrue(geometry.vertexBuffers[.Vertices] === vertexBufferOnScreen, "unchanged after \(unchangedFrames) frames")
            geometry.update(points: zigzag, closed: false, style: style)
            geometry.update()
            XCTAssertFalse(geometry.vertexBuffers[.Vertices] === vertexBufferOnScreen, "after \(unchangedFrames) unchanged frames")
            XCTAssertFalse(geometry.indexBuffer === indexBufferOnScreen, "after \(unchangedFrames) unchanged frames")
        }
    }

    func testAPathDrawsLikeItsPointsAndClosesWithIt() throws {
        var path = BezierPath(start: [0, 0, 0], isClosed: true)
        path.addCubic(control1: [1, 2, 0], control2: [3, 2, 0], to: [4, 0, 0])
        path.addLine(to: [2, -1, 0])
        let style = PolylineStyle(width: 0.2, join: .round, cap: .round)
        for isClosed in [true, false] {
            path.isClosed = isClosed
            let fromPath = try makeGeometry()
            fromPath.update(path: path, style: style, simplifyTolerance: 0.01)
            let fromPoints = try makeGeometry()
            fromPoints.update(points: simplifyPolyline(path.sampledPoints(), tolerance: 0.01, closed: isClosed), closed: isClosed, style: style)
            XCTAssertEqual(fromPath.vertexCount, fromPoints.vertexCount, "closed: \(isClosed)")
            XCTAssertEqual(try vertices(of: fromPath).map(\.position), try vertices(of: fromPoints).map(\.position), "closed: \(isClosed)")
        }
    }

    func testAReversalCoversBeyondItsTipOnceAndFacesForward() throws {
        // Out to (1, 0) and straight back, 0.2 wide: the round join is a semicircle past x = 1.
        let geometry = try makeGeometry()
        geometry.update(points: [[0, 0, 0], [1, 0, 0], [0, 0, 0]], closed: false, style: PolylineStyle(width: 0.2, join: .round))
        let positions = try vertices(of: geometry).map { simd_make_float2($0.position) }
        for probe: simd_float2 in [[1.05, 0.013], [1.03, -0.06]] {
            let covering = try triangles(of: geometry).filter { triangle in
                contains(probe, positions[Int(triangle.0)], positions[Int(triangle.1)], positions[Int(triangle.2)])
            }
            XCTAssertEqual(covering.count, 1, "\(probe)")
            for triangle in covering {
                let first = positions[Int(triangle.0)], second = positions[Int(triangle.1)], third = positions[Int(triangle.2)]
                let doubleSignedArea = (second.x - first.x) * (third.y - first.y) - (second.y - first.y) * (third.x - first.x)
                XCTAssertGreaterThan(doubleSignedArea, 0, "Counter-clockwise, as the geometry's winding order says front-facing is")
            }
        }
    }

    func testAJoinCoversItsCornerOnce() throws {
        // A 90° left turn at the origin, 0.2 wide: the inner corner is near (-0.1, 0.1).
        let geometry = try makeGeometry()
        let points: ContiguousArray<simd_float3> = [[-1, 0, 0], [0, 0, 0], [0, 1, 0]]
        // Off every shared edge: the miter's diagonal x + y = 0 and the bevel's two inner-corner edges.
        let probes: [simd_float2] = [[-0.03, 0.04], [0.02, -0.03], [-0.06, 0.07]]
        for join in [PolylineJoinStyle.miter, .bevel, .round] {
            geometry.update(points: points, closed: false, style: PolylineStyle(width: 0.2, join: join))
            let positions = try vertices(of: geometry).map { simd_make_float2($0.position) }
            for probe in probes {
                let covering = try triangles(of: geometry).filter { triangle in
                    contains(probe, positions[Int(triangle.0)], positions[Int(triangle.1)], positions[Int(triangle.2)])
                }
                XCTAssertEqual(covering.count, 1, "\(join) join at \(probe)")
            }
        }
    }

    func testAClosedLoopsTextureCoordinateNeverRunsBackwards() throws {
        let geometry = try makeGeometry()
        let square: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]
        geometry.update(points: square, closed: true, style: PolylineStyle(width: 0.1, join: .bevel))
        let textureU = try vertices(of: geometry).map(\.texcoord.x)
        XCTAssertEqual(textureU.max() ?? 0, 1, accuracy: 1e-5, "The closing segment ends at u = 1")
        for triangle in try triangles(of: geometry) {
            let triangleU = [textureU[Int(triangle.0)], textureU[Int(triangle.1)], textureU[Int(triangle.2)]]
            XCTAssertLessThanOrEqual((triangleU.max() ?? 0) - (triangleU.min() ?? 0), 0.26, "No triangle spans more than one side")
        }
    }

    private func vertices(of geometry: Geometry) throws -> [(position: simd_float3, texcoord: simd_float2)] {
        let position = try XCTUnwrap(geometry.getAttribute(.Position) as? InterleavedBufferAttribute)
        let texcoord = try XCTUnwrap(geometry.getAttribute(.Texcoord) as? InterleavedBufferAttribute)
        let buffer = position.parent
        guard buffer.count > 0 else { return [] }
        let data = try XCTUnwrap(buffer.data)
        return (0 ..< buffer.count).map { vertexIndex in
            let vertex = data.advanced(by: vertexIndex * buffer.stride)
            return (vertex.load(fromByteOffset: position.offset, as: simd_float3.self),
                    vertex.load(fromByteOffset: texcoord.offset, as: simd_float2.self))
        }
    }

    private func triangles(of geometry: Geometry) throws -> [(UInt32, UInt32, UInt32)] {
        let indices = try XCTUnwrap(geometry.elementBuffer?.data).bindMemory(to: UInt32.self, capacity: geometry.indexCount)
        return stride(from: 0, to: geometry.indexCount, by: 3).map { (indices[$0], indices[$0 + 1], indices[$0 + 2]) }
    }

    /// Strictly inside, in the xy plane, whichever way the triangle winds.
    private func contains(_ point: simd_float2, _ first: simd_float2, _ second: simd_float2, _ third: simd_float2) -> Bool {
        func side(_ start: simd_float2, _ end: simd_float2) -> Float {
            (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
        }
        let sides = [side(first, second), side(second, third), side(third, first)]
        return sides.allSatisfy { $0 > 1e-6 } || sides.allSatisfy { $0 < -1e-6 }
    }

    private func makeGeometry() throws -> PolylineGeometry {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return PolylineGeometry(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
    }
}
