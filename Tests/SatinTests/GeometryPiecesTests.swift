import Metal
import Satin
import simd
import XCTest

/// `GeometryPieces`: a flat hierarchy of rigid pieces whose initializer enforces the contract.
final class GeometryPiecesTests: XCTestCase {
    /// Two words: the first holds two glyphs, the second one glyph.
    private let parentIndices = [-1, 0, 0, -1, 3]
    private let centers: [simd_float3] = [SIMD3(1, 0, 0), SIMD3(0.5, 0, 0), SIMD3(1.5, 0, 0), SIMD3(4, 0, 0), SIMD3(4, 0, 0)]
    private let sizes: [Float] = [3, 1, 2, 5, 5]
    private let vertexRanges: [Range<Int>] = [0 ..< 12, 0 ..< 6, 6 ..< 12, 12 ..< 18, 12 ..< 18]

    func testAWellFormedHierarchyIsReadablePartByPart() throws {
        let pieces = try GeometryPieces(parentIndices: parentIndices, centers: centers, sizes: sizes, sizeMeasure: .area, vertexRanges: vertexRanges)
        XCTAssertEqual(pieces.count, 5)
        let glyph = pieces[2]
        XCTAssertEqual(glyph.center, SIMD3(1.5, 0, 0))
        XCTAssertEqual(glyph.size, 2)
        XCTAssertEqual(glyph.parentIndex, 0)
        XCTAssertEqual(glyph.vertexRange, 6 ..< 12)
        XCTAssertEqual(pieces.sizeMeasure, .area)
        XCTAssertEqual(pieces.lowestLevelIndices, [1, 2, 4], "The two words hold the three glyphs vertices belong to")
    }

    func testEveryInvariantIsEnforced() {
        XCTAssertThrowsError(try make(centers: Array(centers.dropLast()))) { XCTAssertEqual($0 as? GeometryPieces.ValidationError, .mismatchedCounts) }
        XCTAssertThrowsError(try make(parentIndices: [-1, 2, 0, -1, 3])) { XCTAssertEqual($0 as? GeometryPieces.ValidationError, .parentNotBeforeChild(piece: 1)) }
        XCTAssertThrowsError(try make(vertexRanges: [0 ..< 12, 0 ..< 6, 6 ..< 14, 12 ..< 18, 12 ..< 18])) {
            XCTAssertEqual($0 as? GeometryPieces.ValidationError, .rangeOutsideParent(piece: 2))
        }
        XCTAssertThrowsError(try make(vertexRanges: [0 ..< 12, 0 ..< 7, 6 ..< 12, 12 ..< 18, 12 ..< 18])) {
            XCTAssertEqual($0 as? GeometryPieces.ValidationError, .siblingsOverlap(piece: 2))
        }
        XCTAssertThrowsError(try make(sizes: [3, 1, -2, 5, 5])) { XCTAssertEqual($0 as? GeometryPieces.ValidationError, .invalidSize(piece: 2)) }
        XCTAssertThrowsError(try make(sizes: [4, 1, 2, 5, 5])) { XCTAssertEqual($0 as? GeometryPieces.ValidationError, .parentSizeMismatch(piece: 0)) }
        let tooMany = Int(UInt16.max) + 2
        XCTAssertThrowsError(try GeometryPieces(parentIndices: Array(repeating: -1, count: tooMany), centers: Array(repeating: .zero, count: tooMany),
                                                sizes: Array(repeating: 0, count: tooMany), sizeMeasure: .area,
                                                vertexRanges: Array(repeating: 0 ..< 0, count: tooMany))) {
            XCTAssertEqual($0 as? GeometryPieces.ValidationError, .tooManyPieces)
        }
    }

    func testSettingPiecesGivesEachVertexItsLowestLevelPiece() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let geometry = makeGeometry(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
        try geometry.setPieces(make())
        let jointIndices = try XCTUnwrap(geometry.getAttribute(.JointIndices) as? UShort4BufferAttribute).data.map(\.x)
        XCTAssertEqual(jointIndices, Array(repeating: 1, count: 6) + Array(repeating: 2, count: 6) + Array(repeating: 4, count: 6))
        XCTAssertEqual(try XCTUnwrap(geometry.getAttribute(.JointWeights) as? Float4BufferAttribute).data, Array(repeating: simd_float4(1, 0, 0, 0), count: 18))

        geometry.setPieces(nil)
        XCTAssertNil(geometry.pieces)
        XCTAssertFalse(geometry.hasAttribute(.JointIndices))
        XCTAssertFalse(geometry.hasAttribute(.JointWeights))
    }

    func testRegroupingKeepsTheWeightsItWrote() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let geometry = makeGeometry(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
        try geometry.setPieces(make())
        let weights = try XCTUnwrap(geometry.getAttribute(.JointWeights))
        // Regrouped flat: three top-level pieces over the same 18 vertices.
        try geometry.setPieces(make(parentIndices: [-1, -1, -1], centers: [.zero, .zero, .zero], sizes: [1, 2, 5],
                                    vertexRanges: [0 ..< 6, 6 ..< 12, 12 ..< 18]))
        XCTAssertTrue(geometry.getAttribute(.JointWeights) === weights, "Same vertices: the uniform weights stay")
    }

    func testAPaletteWithFewerJointsThanPiecesDoesNotSkin() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let geometry = makeGeometry(context: Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm))
        try geometry.setPieces(make())
        geometry.jointPalette = JointPalette(jointCount: 4)
        XCTAssertFalse(geometry.isSkinned, "Piece 4's vertices would read past a four-joint palette")
        geometry.jointPalette = JointPalette(jointCount: 5)
        XCTAssertTrue(geometry.isSkinned)
    }

    func testPosedViewReportsItsSourcesParts() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let source = makeGeometry(context: context)
        try source.setPieces(make())
        let view = PosedGeometry(source: source)
        XCTAssertEqual(view.pieces, source.pieces)
        XCTAssertNil(Geometry(context: context).pieces, "Ordinary geometry has no pieces")
    }

    /// The 18 vertices `vertexRanges` covers.
    private func makeGeometry(context: Context) -> Geometry {
        let geometry = Geometry(context: context)
        geometry.addAttribute(Float3BufferAttribute(defaultValue: .zero, data: Array(repeating: .zero, count: 18)), for: .Position)
        return geometry
    }

    private func make(parentIndices: [Int]? = nil, centers: [simd_float3]? = nil, sizes: [Float]? = nil,
                      vertexRanges: [Range<Int>]? = nil) throws -> GeometryPieces {
        try GeometryPieces(parentIndices: parentIndices ?? self.parentIndices, centers: centers ?? self.centers, sizes: sizes ?? self.sizes,
                          sizeMeasure: .area, vertexRanges: vertexRanges ?? self.vertexRanges)
    }
}
