import Metal
import Satin
import simd
import XCTest

/// `StrokeGeometry`: SatinCore tessellates a ribbon straight into memory the geometry owns,
/// and each update hands that memory to buffers made once.
final class StrokeGeometryTests: XCTestCase {
    /// A zigzag with sharp turns, so joins take every path: straight, miter, miter falling back
    /// to bevel, bevel, and round fans.
    private let zigzag: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [2, 1, 0], [2.1, -1, 0], [3, 0, 0], [4, 0, 0]]

    func testEveryJoinAndCapIndexesOnlyItsOwnVertices() throws {
        let geometry = try makeGeometry()
        for joinStyle in [Stroke.Join.miter, .bevel, .round] {
            for capStyle in [Stroke.Cap.butt, .square, .round] {
                for closed in [false, true] {
                    geometry.update(points: zigzag, closed: closed,
                                    style: Stroke.Style(width: 0.2, join: joinStyle, cap: capStyle, miterLimit: 2, roundResolution: 8))
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

    func testFewerThanTwoPointsDrawNothingWithoutARoundCap() throws {
        let geometry = try makeGeometry()
        for cap in [Stroke.Cap.butt, .square] {
            let style = Stroke.Style(width: 0.2, join: .round, cap: cap)
            geometry.update(points: zigzag, closed: false, style: style)
            for points: ContiguousArray<simd_float3> in [[], [[1, 1, 1]], [[1, 1, 1], [1, 1, 1]]] {
                geometry.update(points: points, closed: false, style: style)
                XCTAssertEqual(geometry.vertexCount, 0)
                XCTAssertEqual(geometry.indexCount, 0)
            }
        }
    }

    func testOnePointWithARoundCapDrawsADisc() throws {
        // 0.2 wide, doubled by its width scale: a radius of 0.2.
        let geometry = try makeGeometry()
        let style = Stroke.Style(width: 0.2, cap: .round, roundResolution: 8)
        for points: ContiguousArray<simd_float3> in [[[1, 2, 0]], [[1, 2, 0], [1, 2, 0]]] {
            geometry.update(points: points, closed: false, style: style, widthScales: [2])
            XCTAssertEqual(geometry.vertexCount, 17, "A hub and two half circles of 8")
            XCTAssertEqual(geometry.indexCount, 48)
            XCTAssertEqual(geometry.bounds.max.x, 1.2, accuracy: 1e-5)
            XCTAssertEqual(geometry.bounds.min.x, 0.8, accuracy: 1e-5)
            XCTAssertEqual(geometry.bounds.max.y, 2.2, accuracy: 1e-5)
            XCTAssertEqual(geometry.bounds.min.y, 1.8, accuracy: 1e-5)
        }
        XCTAssertTrue(try everyTriangleFacesUp(geometry))
    }

    func testADotBetweenTwoLinesEqualsEachStrokeAlone() throws {
        let style = Stroke.Style(width: 0.2, cap: .round)
        let strokes = [Stroke(points: [[0, 0, 0], [1, 0, 0]], style: style), Stroke(points: [[3, 3, 0]], style: style), Stroke(points: [[0, 5, 0], [1, 5, 0]], style: style)]
        let together = try makeGeometry()
        together.update(strokes: strokes)
        var expectedPositions: [simd_float3] = []
        for stroke in strokes {
            let alone = try makeGeometry()
            alone.update(strokes: [stroke])
            expectedPositions += try vertices(of: alone).map(\.position)
        }
        XCTAssertEqual(try vertices(of: together).map(\.position), expectedPositions)
    }

    func testEveryJoinAndCapFacesUp() throws {
        // A Mesh culls back faces by default, so a ribbon facing the camera must draw whole.
        let geometry = try makeGeometry()
        for join in [Stroke.Join.miter, .bevel, .round] {
            for cap in [Stroke.Cap.butt, .square, .round] {
                for closed in [false, true] {
                    geometry.update(points: zigzag, closed: closed, style: Stroke.Style(width: 0.2, join: join, cap: cap, miterLimit: 2))
                    XCTAssertTrue(try everyTriangleFacesUp(geometry), "\(join) \(cap) closed: \(closed)")
                }
            }
        }
    }

    private func everyTriangleFacesUp(_ geometry: Geometry) throws -> Bool {
        let positions = try vertices(of: geometry).map { simd_make_float2($0.position) }
        return try triangles(of: geometry).allSatisfy { triangle in
            let first = positions[Int(triangle.0)], second = positions[Int(triangle.1)], third = positions[Int(triangle.2)]
            let doubleSignedArea = (second.x - first.x) * (third.y - first.y) - (second.y - first.y) * (third.x - first.x)
            return doubleSignedArea > -1e-5
        }
    }

    func testWidthScalesWidenTheRibbonPerPoint() throws {
        // A straight ribbon along x, 0.2 wide, with butt caps: its height is its width.
        let geometry = try makeGeometry()
        let points: ContiguousArray<simd_float3> = [[0, 0, 0], [1, 0, 0], [2, 0, 0]]
        let style = Stroke.Style(width: 0.2)
        geometry.update(points: points, closed: false, style: style)
        XCTAssertEqual(geometry.bounds.max.y, 0.1, accuracy: 1e-5)

        geometry.update(points: points, closed: false, style: style, widthScales: [1, 3])
        XCTAssertEqual(geometry.bounds.max.y, 0.3, accuracy: 1e-5, "The last scale repeats for the third point")
        XCTAssertEqual(geometry.bounds.min.y, -0.3, accuracy: 1e-5)
    }

    func testAReversalHasNoInvalidVertices() throws {
        let geometry = try makeGeometry()
        let style = Stroke.Style(width: 0.2, join: .round, cap: .round)
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
        let style = Stroke.Style(width: 0.2, join: .round, cap: .round)
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
        let style = Stroke.Style(width: 0.2)
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

    func testAPathStrokeDrawsLikeItsPointsAndClosesWithIt() throws {
        var path = BezierPath(start: [0, 0, 0], isClosed: true)
        path.addCubic(control1: [1, 2, 0], control2: [3, 2, 0], to: [4, 0, 0])
        path.addLine(to: [2, -1, 0])
        let style = Stroke.Style(width: 0.2, join: .round, cap: .round)
        for isClosed in [true, false] {
            path.isClosed = isClosed
            let fromPath = try makeGeometry()
            fromPath.update(strokes: [Stroke(path: path, style: style, simplifyTolerance: 0.01)])
            let fromPoints = try makeGeometry()
            fromPoints.update(points: simplifyPolyline(path.sampledPoints(), tolerance: 0.01, closed: isClosed), closed: isClosed, style: style)
            XCTAssertEqual(fromPath.vertexCount, fromPoints.vertexCount, "closed: \(isClosed)")
            XCTAssertEqual(try vertices(of: fromPath).map(\.position), try vertices(of: fromPoints).map(\.position), "closed: \(isClosed)")
        }
    }

    func testAReversalCoversBeyondItsTipOnceAndFacesForward() throws {
        // Out to (1, 0) and straight back, 0.2 wide: the round join is a semicircle past x = 1.
        let geometry = try makeGeometry()
        geometry.update(points: [[0, 0, 0], [1, 0, 0], [0, 0, 0]], closed: false, style: Stroke.Style(width: 0.2, join: .round))
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
        for join in [Stroke.Join.miter, .bevel, .round] {
            geometry.update(points: points, closed: false, style: Stroke.Style(width: 0.2, join: join))
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
        geometry.update(points: square, closed: true, style: Stroke.Style(width: 0.1, join: .bevel))
        let textureU = try vertices(of: geometry).map(\.texcoord.x)
        XCTAssertEqual(textureU.max() ?? 0, 1, accuracy: 1e-5, "The closing segment ends at u = 1")
        for triangle in try triangles(of: geometry) {
            let triangleU = [textureU[Int(triangle.0)], textureU[Int(triangle.1)], textureU[Int(triangle.2)]]
            XCTAssertLessThanOrEqual((triangleU.max() ?? 0) - (triangleU.min() ?? 0), 0.26, "No triangle spans more than one side")
        }
    }

    func testSeparateStrokesEqualEachStrokeAloneWithNoTriangleBetweenThem() throws {
        let strokes = [
            Stroke(points: zigzag, style: Stroke.Style(width: 0.2, join: .round, cap: .round)),
            Stroke(points: [[0, 5, 0], [1, 5, 0], [1, 6, 0]], closed: true, style: Stroke.Style(width: 0.05, join: .bevel)),
            Stroke(points: [[8, 0, 0], [9, 1, 0]], style: Stroke.Style(width: 0.3, cap: .square)),
        ]
        let together = try makeGeometry()
        together.update(strokes: strokes)

        var expectedPositions: [simd_float3] = []
        var expectedTriangles: [[UInt32]] = []
        for stroke in strokes {
            let alone = try makeGeometry()
            alone.update(strokes: [stroke])
            let offset = UInt32(expectedPositions.count)
            expectedTriangles += try triangles(of: alone).map { [$0.0 + offset, $0.1 + offset, $0.2 + offset] }
            expectedPositions += try vertices(of: alone).map(\.position)
        }
        XCTAssertEqual(try vertices(of: together).map(\.position), expectedPositions)
        XCTAssertEqual(try triangles(of: together).map { [$0.0, $0.1, $0.2] }, expectedTriangles)
    }

    func testADegenerateStrokeIsSkippedAndTheOthersDraw() throws {
        let style = Stroke.Style(width: 0.2)
        let first = Stroke(points: [[0, 0, 0], [1, 0, 0]], style: style)
        let last = Stroke(points: [[0, 2, 0], [1, 2, 0]], style: style)
        let withDegenerate = try makeGeometry()
        withDegenerate.update(strokes: [first, Stroke(points: [[5, 5, 5]], style: style), Stroke(points: [], style: style), last])
        let without = try makeGeometry()
        without.update(strokes: [first, last])
        XCTAssertEqual(try vertices(of: withDegenerate).map(\.position), try vertices(of: without).map(\.position))
    }

    func testNoStrokesClearTheGeometry() throws {
        let geometry = try makeGeometry()
        geometry.update(points: zigzag)
        geometry.update(strokes: [])
        XCTAssertEqual(geometry.vertexCount, 0)
        XCTAssertEqual(geometry.indexCount, 0)
    }

    func testTextureCoordinateRunsToOneOnEachStroke() throws {
        let first = Stroke(points: [[0, 0, 0], [1, 0, 0]])
        let second = Stroke(points: [[0, 1, 0], [9, 1, 0]])
        let alone = try makeGeometry()
        alone.update(strokes: [first])
        let firstVertexCount = alone.vertexCount
        let geometry = try makeGeometry()
        geometry.update(strokes: [first, second])
        let textureU = try vertices(of: geometry).map(\.texcoord.x)
        XCTAssertEqual(textureU[..<firstVertexCount].max() ?? 0, 1, accuracy: 1e-5)
        XCTAssertEqual(textureU[firstVertexCount...].min() ?? 1, 0, accuracy: 1e-5)
        XCTAssertEqual(textureU[firstVertexCount...].max() ?? 0, 1, accuracy: 1e-5)
    }

    func testOneColorColorsEveryPointAndPerPointColorsFollowThePoints() throws {
        let geometry = try makeGeometry()
        let red: simd_float4 = [1, 0, 0, 1]
        let blue: simd_float4 = [0, 0, 1, 1]
        geometry.update(points: [[0, 0, 0], [1, 0, 0], [2, 0, 0]], color: red)
        XCTAssertTrue(try colors(of: geometry).allSatisfy { $0 == red })
        geometry.update(points: [[0, 0, 0], [1, 0, 0], [2, 0, 0]], colors: [red, blue])
        let colored = try colors(of: geometry)
        XCTAssertEqual(colored.first, red)
        XCTAssertEqual(colored.last, blue, "The last color repeats")
    }

    private func colors(of geometry: Geometry) throws -> [simd_float4] {
        let color = try XCTUnwrap(geometry.getAttribute(.Color) as? InterleavedBufferAttribute)
        let data = try XCTUnwrap(color.parent.data)
        return (0 ..< color.parent.count).map { vertexIndex in
            data.advanced(by: vertexIndex * color.parent.stride).load(fromByteOffset: color.offset, as: simd_float4.self)
        }
    }

    func testDashesFollowTheirLengthAndGapAcrossCorners() {
        let line = Stroke(points: [[0, 0, 0], [3, 0, 0], [3, 3, 0]])
        let dashes = line.dashed(length: 1, gap: 0.5)
        // Dashes start every 1.5 along a line 6 long.
        XCTAssertEqual(dashes.count, 4)
        XCTAssertEqual(dashes[0].points, [[0, 0, 0], [1, 0, 0]])
        XCTAssertEqual(dashes[1].points, [[1.5, 0, 0], [2.5, 0, 0]])
        XCTAssertEqual(dashes[2].points, [[3, 0, 0], [3, 1, 0]], "A dash starting at the corner runs up from it")
        let turning = line.dashed(length: 2, gap: 1, offset: -1.5)
        XCTAssertTrue(turning.contains { $0.points.contains([3, 0, 0]) && $0.points.count == 3 }, "A dash across a corner keeps the corner")
    }

    func testDashOffsetSlidesThePattern() {
        let line = Stroke(points: [[0, 0, 0], [10, 0, 0]])
        let dashes = line.dashed(length: 1, gap: 1, offset: -0.5)
        XCTAssertEqual(dashes[0].points, [[0, 0, 0], [0.5, 0, 0]], "The line starts part way through a dash")
        XCTAssertEqual(dashes[1].points, [[1.5, 0, 0], [2.5, 0, 0]])
        let starting = line.dashed(length: 1, gap: 1, offset: 0.5)
        XCTAssertEqual(starting[0].points[0], [0.5, 0, 0], "The line starts in a gap")
    }

    func testDashesInterpolateWidthsAndColors() {
        let red: simd_float4 = [1, 0, 0, 1]
        let blue: simd_float4 = [0, 0, 1, 1]
        let line = Stroke(points: [[0, 0, 0], [10, 0, 0]], colors: [red, blue], widthScales: [1, 3])
        let dashes = line.dashed(length: 5, gap: 1)
        XCTAssertEqual(dashes[0].widthScales.last ?? 0, 2, accuracy: 1e-5)
        XCTAssertEqual(dashes[0].colors.last?.x ?? 0, 0.5, accuracy: 1e-5)
        XCTAssertEqual(dashes[0].colors.count, dashes[0].points.count)
        let oneColor = Stroke(points: [[0, 0, 0], [10, 0, 0]], color: red).dashed(length: 5, gap: 1)
        XCTAssertEqual(oneColor[0].colors.last, red)
    }

    func testClosedStrokesDashAroundTheirLoopAndBecomeOpen() {
        let square = Stroke(points: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], closed: true)
        let dashes = square.dashed(length: 0.5, gap: 0.5)
        XCTAssertEqual(dashes.count, 4)
        XCTAssertTrue(dashes.allSatisfy { !$0.closed })
        XCTAssertTrue(dashes.contains { $0.points.contains([0, 0.5, 0]) }, "The closing side is dashed too")
    }

    func testTrimKeepsTheRangeAcrossCorners() {
        let line = Stroke(points: [[0, 0, 0], [1, 0, 0], [1, 1, 0]])
        XCTAssertEqual(Array(line.trimmed(start: 0, end: 0.75).points), [[0, 0, 0], [1, 0, 0], [1, 0.5, 0]])
        XCTAssertEqual(Array(line.trimmed(start: 0.25, end: 1).points), [[0.5, 0, 0], [1, 0, 0], [1, 1, 0]])
        XCTAssertEqual(Array(line.trimmed(start: 0.75, end: 0.25).points), Array(line.trimmed(start: 0.25, end: 0.75).points), "Either order is the same range")
    }

    func testTrimInterpolatesWidthsAndColors() {
        let red = simd_float4(1, 0, 0, 1)
        let blue = simd_float4(0, 0, 1, 1)
        let line = Stroke(points: [[0, 0, 0], [10, 0, 0]], colors: [red, blue], widthScales: [1, 3])
        let trimmed = line.trimmed(start: 0, end: 0.5)
        XCTAssertEqual(Array(trimmed.widthScales), [1, 2])
        XCTAssertEqual(trimmed.colors.last, simd_float4(0.5, 0, 0.5, 1))
    }

    func testTrimmingAClosedStrokeOpensIt() {
        let square = Stroke(points: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], closed: true)
        XCTAssertEqual(square.totalLength, 4)
        let half = square.trimmed(start: 0.5, end: 1)
        XCTAssertFalse(half.closed)
        XCTAssertEqual(Array(half.points), [[1, 1, 0], [0, 1, 0], [0, 0, 0]])
    }

    func testFullAndEmptyTrims() {
        let square = Stroke(points: [[0, 0, 0], [1, 0, 0], [1, 1, 0]], closed: true)
        XCTAssertEqual(square.trimmed(start: 0, end: 1), square)
        XCTAssertEqual(square.trimmed(start: -1, end: 2), square)
        XCTAssertTrue(square.trimmed(start: 0, end: 0).points.isEmpty)
        XCTAssertTrue(square.trimmed(start: 1, end: 1).points.isEmpty)
    }

    func testRevealingTrimKeepsTheTextureOnTheLine() {
        let line = Stroke(points: [[0, 0, 0], [10, 0, 0]])
        XCTAssertEqual(line.trimmed(start: 0.25, end: 0.75).textureRange, [0, 1], "Fits by default")
        XCTAssertEqual(line.trimmed(start: 0.25, end: 0.75, revealingTexture: true).textureRange, [0.25, 0.75])
        XCTAssertEqual(line.trimmed(start: 0, end: 1, revealingTexture: true).textureRange, [0, 1])
    }

    func testRevealingTrimCountsCapReach() {
        // Half width 1, so u spans 12 from tip to tip, and the piece's own caps reach 1 past each cut.
        let style = Stroke.Style(width: 2, cap: .round)
        let range = Stroke(points: [[0, 0, 0], [10, 0, 0]], style: style).trimmed(start: 0.25, end: 0.75, revealingTexture: true).textureRange
        XCTAssertEqual(range.x, 2.5 / 12, accuracy: 1e-5)
        XCTAssertEqual(range.y, 9.5 / 12, accuracy: 1e-5)
    }

    func testRevealingDashesComposeWithTrim() throws {
        let line = Stroke(points: [[0, 0, 0], [10, 0, 0]])
        let half = line.trimmed(start: 0.5, end: 1, revealingTexture: true)
        let dash = try XCTUnwrap(half.dashed(length: 1, gap: 1, revealingTexture: true).first)
        XCTAssertEqual(dash.textureRange.x, 0.5, accuracy: 1e-5)
        XCTAssertEqual(dash.textureRange.y, 0.6, accuracy: 1e-5)
    }

    func testGeometryAppliesTheTextureRange() throws {
        let geometry = try makeGeometry()
        geometry.update(strokes: [Stroke(points: [[0, 0, 0], [10, 0, 0]]).trimmed(start: 0.25, end: 0.75, revealingTexture: true)])
        let textureU = try vertices(of: geometry).map(\.texcoord.x)
        XCTAssertEqual(try XCTUnwrap(textureU.min()), 0.25, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(textureU.max()), 0.75, accuracy: 1e-5)
    }

    func testAClosedStrokeWithoutPointsHasNoLength() {
        let empty = Stroke(points: [], closed: true)
        XCTAssertEqual(empty.totalLength, 0)
        XCTAssertEqual(empty.trimmed(start: 0, end: 0.5), empty)
    }

    func testTrimLeavesADotWholeUntilTheRangeIsEmpty() {
        let dot = Stroke(points: [[1, 1, 0]])
        XCTAssertEqual(dot.trimmed(start: 0, end: 0.5), dot)
        XCTAssertTrue(dot.trimmed(start: 0, end: 0).points.isEmpty)
    }

    func testStrokesThatCannotDashStayWhole() {
        let line = Stroke(points: [[0, 0, 0], [1, 0, 0]])
        XCTAssertEqual(line.dashed(length: 0, gap: 1), [line])
        XCTAssertEqual(line.dashed(length: 1, gap: 0), [line])
        XCTAssertEqual(line.dashed(length: 1e-9, gap: 1e-9), [line])
        let dot = Stroke(points: [[0, 0, 0]])
        XCTAssertEqual(dot.dashed(length: 1, gap: 1), [dot])
    }

    func testEachStrokeBecomesAPieceWithItsOwnVertices() throws {
        let geometry = try makeGeometry()
        let strokes = [Stroke(points: [[0, 0, 0], [2, 0, 0]], style: Stroke.Style(width: 0.5)),
                       Stroke(points: [[5, 5, 0]], style: Stroke.Style(width: 0.2)),
                       Stroke(points: [[0, 3, 0], [1, 3, 0], [1, 4, 0]])]
        geometry.update(strokes: strokes, pieces: .strokes)
        let pieces = try XCTUnwrap(geometry.pieces)
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces.parentIndices, [-1, -1, -1])
        XCTAssertEqual(pieces.vertexRanges[0].lowerBound, 0)
        XCTAssertEqual(pieces.vertexRanges[1].upperBound, pieces.vertexRanges[2].lowerBound)
        XCTAssertEqual(pieces.vertexRanges[2].upperBound, geometry.vertexCount)
        XCTAssertTrue(pieces.vertexRanges[1].isEmpty, "A butt-capped dot draws nothing and keeps its index")
        XCTAssertEqual(pieces.centers[0], [1, 0, 0])
        XCTAssertEqual(pieces.sizes[0], 1, accuracy: 1e-5)
        XCTAssertTrue(geometry.hasAttribute(.JointIndices))
    }

    func testGroupsMakeAParentBeforeItsChildren() throws {
        let geometry = try makeGeometry()
        let strokes = [Stroke(points: [[0, 0, 0], [1, 0, 0]]), Stroke(points: [[2, 0, 0], [3, 0, 0]]), Stroke(points: [[0, 5, 0], [1, 5, 0]])]
        geometry.update(strokes: strokes, pieces: .groups([0, 0, 1]))
        let pieces = try XCTUnwrap(geometry.pieces)
        XCTAssertEqual(pieces.parentIndices, [-1, 0, 0, -1, 3])
        XCTAssertEqual(pieces.lowestLevelIndices, [1, 2, 4])
        XCTAssertEqual(pieces.vertexRanges[0].upperBound, pieces.vertexRanges[2].upperBound)
        XCTAssertEqual(pieces.centers[0], [1.5, 0, 0])
    }

    func testMergedGroupsMakeOnePiecePerRun() throws {
        let geometry = try makeGeometry()
        let strokes = [Stroke(points: [[0, 0, 0], [1, 0, 0]]), Stroke(points: [[2, 0, 0], [3, 0, 0]]), Stroke(points: [[0, 5, 0], [1, 5, 0]])]
        geometry.update(strokes: strokes, pieces: .mergedGroups([0, 0, 1]))
        let pieces = try XCTUnwrap(geometry.pieces)
        XCTAssertEqual(pieces.parentIndices, [-1, -1])
        XCTAssertEqual(pieces.vertexRanges[1].upperBound, geometry.vertexCount)
        XCTAssertEqual(pieces.vertexRanges[0].upperBound, pieces.vertexRanges[1].lowerBound)
    }

    func testPiecesComeAndGoWithTheUpdate() throws {
        let geometry = try makeGeometry()
        let line = [Stroke(points: [[0, 0, 0], [1, 0, 0]])]
        geometry.update(strokes: line)
        XCTAssertNil(geometry.pieces)
        XCTAssertFalse(geometry.hasAttribute(.JointIndices))
        geometry.update(strokes: line, pieces: .strokes)
        XCTAssertNotNil(geometry.pieces)
        geometry.update(strokes: line + line, pieces: .strokes)
        XCTAssertEqual(geometry.pieces?.count, 2)
        geometry.update(strokes: [], pieces: .strokes)
        XCTAssertNil(geometry.pieces)
        geometry.update(strokes: line, pieces: .strokes)
        geometry.update(strokes: line)
        XCTAssertNil(geometry.pieces)
        XCTAssertFalse(geometry.hasAttribute(.JointIndices))
        geometry.update(strokes: line, pieces: .groups([0, 1, 2]))
        XCTAssertNil(geometry.pieces, "Groups must have one value per stroke")
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

    private func makeGeometry() throws -> StrokeGeometry {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return StrokeGeometry(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
    }
}
