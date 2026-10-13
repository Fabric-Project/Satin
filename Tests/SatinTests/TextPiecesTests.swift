import Metal
@testable import Satin
import simd
import XCTest

/// Text geometry divided into pieces by `pieceGeneration`: none by default, or one piece per
/// sentence, word or Character, each with its vertices' joint index, center and size.
final class TextPiecesTests: XCTestCase {
    func testTextHasNoPiecesByDefault() throws {
        let geometry = makeText(try makeContext(), "Hi you")
        XCTAssertNil(geometry.pieces)
        XCTAssertFalse(geometry.hasAttribute(.JointIndices))
        XCTAssertFalse(geometry.hasAttribute(.JointWeights))
    }

    func testEachDrawnCharacterIsAPiece() throws {
        let geometry = makeText(try makeContext(), "Hi y!", .character)
        let pieces = try XCTUnwrap(geometry.pieces)
        XCTAssertEqual(pieces.count, 4, "The space draws nothing, so it is no piece")
        try assertJointsMatchPieces(geometry)
        XCTAssertEqual(pieces.sizeMeasure, .area)
        XCTAssertTrue(pieces.sizes.allSatisfy { $0 > 0 })
        XCTAssertEqual(pieces.centers.map(\.x), pieces.centers.map(\.x).sorted(), "Left to right")
    }

    func testACharacterOfSeveralGlyphsIsOnePiece() throws {
        // "कि" is one Character drawn as two glyphs.
        let geometry = makeText(try makeContext(), "कि", .character)
        try XCTSkipIf(geometry.vertexCount == 0, "No font draws Devanagari here")
        XCTAssertEqual(geometry.pieces?.count, 1)
    }

    func testWordsKeepTheirPunctuation() throws {
        let geometry = makeText(try makeContext(), "Hi, (you)!", .word)
        XCTAssertEqual(geometry.pieces?.count, 2, "\"Hi,\" and \"(you)!\"")
        try assertJointsMatchPieces(geometry)
    }

    func testWordsDivideTextWithoutSpaces() throws {
        let text = "今日は晴れです"
        let geometry = makeText(try makeContext(), text, .word)
        try XCTSkipIf(geometry.vertexCount == 0, "No font draws Japanese here")
        let pieceCount = try XCTUnwrap(geometry.pieces?.count)
        XCTAssertGreaterThan(pieceCount, 1)
        XCTAssertLessThan(pieceCount, text.count)
    }

    func testSentencesAreOnePieceEach() throws {
        let geometry = makeText(try makeContext(), "One cat. Two dogs!", .sentence)
        XCTAssertEqual(geometry.pieces?.count, 2)
        try assertJointsMatchPieces(geometry)
    }

    func testSwitchingUnitsRegroupsWithoutRebuildingVertices() throws {
        let geometry = makeText(try makeContext(), "Hi you", .word)
        XCTAssertEqual(geometry.pieces?.count, 2)
        let vertexData = geometry.geometryData.vertexData

        geometry.pieceGeneration = .character
        XCTAssertEqual(geometry.pieces?.count, 5)
        XCTAssertFalse(geometry._updateData, "Regrouped in place")
        XCTAssertEqual(geometry.geometryData.vertexData, vertexData)
        try assertJointsMatchPieces(geometry)

        geometry.pieceGeneration = .none
        XCTAssertNil(geometry.pieces)
        XCTAssertFalse(geometry.hasAttribute(.JointIndices))

        // Every glyph is recorded whatever the unit, so leaving none regroups in place too.
        geometry.pieceGeneration = .sentence
        XCTAssertFalse(geometry._updateData, "Regrouped in place")
        XCTAssertEqual(geometry.pieces?.count, 1)
        XCTAssertEqual(geometry.geometryData.vertexData, vertexData)
        try assertJointsMatchPieces(geometry)
    }

    func testTextBuiltWithoutPiecesGainsThemWithoutRebuilding() throws {
        let geometry = makeText(try makeContext(), "Hi you")
        XCTAssertNil(geometry.pieces)
        let vertexData = geometry.geometryData.vertexData

        geometry.pieceGeneration = .word
        XCTAssertFalse(geometry._updateData, "Regrouped in place")
        XCTAssertEqual(geometry.pieces?.count, 2)
        XCTAssertEqual(geometry.geometryData.vertexData, vertexData)
        try assertJointsMatchPieces(geometry)
    }

    func testFlatTextMeasuresAreaAroundItsFace() throws {
        // Helvetica's "I" is a rectangle: its area and centroid are its bounds'.
        let geometry = makeText(try makeContext(), "I", .character)
        let piece = try XCTUnwrap(geometry.pieces?[0])
        let bounds = geometry.bounds
        XCTAssertEqual(piece.size, bounds.size.x * bounds.size.y, accuracy: 1e-4)
        XCTAssertEqual(piece.center.x, bounds.center.x, accuracy: 1e-4)
        XCTAssertEqual(piece.center.y, bounds.center.y, accuracy: 1e-4)
        XCTAssertEqual(piece.center.z, 0, accuracy: 1e-6)
    }

    func testExtrudedTextMeasuresVolumeAroundItsMiddle() throws {
        let context = try makeContext()
        let geometry = ExtrudedTextGeometry(context: context, text: "I", fontSize: 1, distance: 2, pieceGeneration: .character)
        geometry.update()
        let pieces = try XCTUnwrap(geometry.pieces)
        let bounds = geometry.bounds
        XCTAssertEqual(pieces.sizeMeasure, .volume)
        XCTAssertEqual(pieces.sizes[0], bounds.size.x * bounds.size.y * 2, accuracy: 1e-4, "Face area times depth, front cap only")
        XCTAssertEqual(pieces.centers[0].z, 0, accuracy: 1e-5)
        try assertJointsMatchPieces(geometry)
    }

    func testPosingAPieceMovesOnlyThatPiece() throws {
        let context = try makeContext()
        let geometry = makeText(context, "AB", .character)
        let pieces = try XCTUnwrap(geometry.pieces)
        let palette = JointPalette(device: context.device, jointCount: pieces.count)
        palette.reset(matrices: [matrix_identity_float4x4, translation(0, 10, 0)])
        let posed = PosedGeometry(source: geometry, jointPalette: palette)

        XCTAssertEqual(posed.bounds.max.y, geometry.bounds.max.y + 10, accuracy: 1e-4, "B rises")
        XCTAssertEqual(posed.bounds.min.y, geometry.bounds.min.y, accuracy: 1e-4, "A stays")
    }

    func testPiecesWithoutAPaletteDrawExactlyAsBefore() throws {
        let plain = try renderText(.none)
        let withPieces = try renderText(.character)
        XCTAssertEqual(plain.pixels, withPieces.pixels)
        XCTAssertGreaterThan(Set(plain.pixels).count, 2, "The text is in frame")
    }

    // MARK: - Helpers

    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func makeText(_ context: Context, _ text: String, _ pieceGeneration: TesselatedTextGeometry.PieceGeneration = .none) -> TesselatedTextGeometry {
        let geometry = TesselatedTextGeometry(context: context, text: text, fontSize: 1, pieceGeneration: pieceGeneration)
        geometry.update()
        return geometry
    }

    /// Every vertex carries the index of the one piece whose range holds it, at full weight.
    private func assertJointsMatchPieces(_ geometry: TesselatedTextGeometry, file: StaticString = #filePath, line: UInt = #line) throws {
        let pieces = try XCTUnwrap(geometry.pieces, file: file, line: line)
        let jointIndices = try XCTUnwrap(geometry.getAttribute(.JointIndices) as? UShort4BufferAttribute, file: file, line: line)
        let jointWeights = try XCTUnwrap(geometry.getAttribute(.JointWeights) as? Float4BufferAttribute, file: file, line: line)
        XCTAssertEqual(jointIndices.count, geometry.vertexCount, file: file, line: line)
        XCTAssertEqual(pieces.vertexRanges.first?.lowerBound, 0, file: file, line: line)
        XCTAssertEqual(pieces.vertexRanges.last?.upperBound, geometry.vertexCount, "Every vertex is in a piece", file: file, line: line)
        for (pieceIndex, range) in pieces.vertexRanges.enumerated() {
            for vertex in range {
                XCTAssertEqual(jointIndices.data[vertex], simd_ushort4(UInt16(pieceIndex), 0, 0, 0), file: file, line: line)
                XCTAssertEqual(jointWeights.data[vertex], simd_float4(1, 0, 0, 0), file: file, line: line)
            }
        }
    }

    private func renderText(_ pieceGeneration: TesselatedTextGeometry.PieceGeneration) throws -> RGBAImage {
        try VisualTestHarness.render(size: [160, 160]) { renderer, camera in
            let context = renderer.context
            let geometry = TesselatedTextGeometry(context: context, text: "Hi", fontSize: 1, pieceGeneration: pieceGeneration)
            let mesh = Mesh(context: context, label: "Text", geometry: geometry, material: NormalColorMaterial(context: context))
            mesh.cullMode = .none
            return (scene: Object(context: context, label: "Scene", [mesh]), camera: camera)
        }
    }

    private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        matrix_float4x4(columns: (simd_float4(1, 0, 0, 0), simd_float4(0, 1, 0, 0), simd_float4(0, 0, 1, 0), simd_float4(x, y, z, 1)))
    }
}
