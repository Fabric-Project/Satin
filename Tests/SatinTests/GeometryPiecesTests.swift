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
    }

    func testPosedViewReportsItsSourcesParts() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let source = Geometry(context: context)
        source.pieces = try make()
        let view = PosedGeometry(source: source)
        XCTAssertEqual(view.pieces, source.pieces)
        XCTAssertNil(Geometry(context: context).pieces, "Ordinary geometry has no pieces")
    }

    private func make(parentIndices: [Int]? = nil, centers: [simd_float3]? = nil, sizes: [Float]? = nil,
                      vertexRanges: [Range<Int>]? = nil) throws -> GeometryPieces {
        try GeometryPieces(parentIndices: parentIndices ?? self.parentIndices, centers: centers ?? self.centers, sizes: sizes ?? self.sizes,
                          sizeMeasure: .area, vertexRanges: vertexRanges ?? self.vertexRanges)
    }
}
