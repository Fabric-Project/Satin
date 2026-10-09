import CoreText
import Metal
@testable import Satin
import XCTest

final class TesselatedTextGeometryTests: XCTestCase {
    private func makeContext() throws -> Context {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this machine.")
        }
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func makeGeometry(_ context: Context, _ text: String, _ fontName: String) -> TesselatedTextGeometry {
        let geometry = TesselatedTextGeometry(context: context, text: text, fontName: fontName, fontSize: 1)
        geometry.update()
        return geometry
    }

    private func glyph(for character: Character, in font: CTFont) throws -> CGGlyph {
        var characters = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        try XCTSkipUnless(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count), "\(CTFontCopyFamilyName(font)) has no glyph for \(character)")
        return glyphs[0]
    }

    // CoreText resolves a missing font name to Helvetica, so a test of another font would pass without exercising it.
    private func requireInstalledFont(_ fontName: String) throws -> CTFont {
        let font = CTFontCreateWithName(fontName as CFString, 1, nil)
        try XCTSkipUnless(CTFontCopyFamilyName(font) as String == fontName, "\(fontName) is not installed")
        return font
    }

    // The runs CoreText lays the text out in, each with the font it draws from
    private func runs(_ text: String, _ fontName: String) -> [(font: CTFont, glyphs: [CGGlyph])] {
        let font = CTFontCreateWithName(fontName as CFString, 1, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        return runs.map { run in
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName].map { $0 as! CTFont } ?? font
            return (runFont, glyphs)
        }
    }

    // These SF Pro outlines have overlapping contours that fail to triangulate as drawn.
    func testOverlappingContoursTriangulate() throws {
        let context = try makeContext()
        _ = try requireInstalledFont("SF Pro")
        for character in "&2<>MNX^aeyÑéå®" {
            XCTAssertGreaterThan(makeGeometry(context, String(character), "SF Pro").indexCount, 0, "\(character)")
        }
    }

    // These outlines triangulate correctly as drawn and fail once their contours are merged.
    func testWellFormedOutlinesAreKept() throws {
        let context = try makeContext()
        let geometry = TesselatedTextGeometry(context: context, text: "", fontName: "Helvetica", fontSize: 1)
        for (fontName, characters) in [("American Typewriter", "T"), ("Bodoni 72", "irZ"), ("Marker Felt", "Y")] {
            let font = try requireInstalledFont(fontName)
            for character in characters {
                let glyph = try glyph(for: character, in: font)
                let outline = try XCTUnwrap(geometry.makeGlyphOutline(font, glyph))
                XCTAssertNotNil(outline.triangles, "\(fontName) \(character)")
                XCTAssertEqual(outline.path, CTFontCreatePathForGlyph(font, glyph, nil), "\(fontName) \(character)")
                geometry.freeGlyphOutline(outline)
            }
        }
    }

    // Helvetica has no SF Symbols, so CoreText draws them from a fallback font whose glyph IDs differ.
    func testFallbackFontGlyphsMatchTheirOwnFont() throws {
        let context = try makeContext()
        let symbol: Character = "\u{100000}"
        let fallback = try XCTUnwrap(runs(String(symbol), "Helvetica").first)
        XCTAssertNotEqual(CTFontCopyFamilyName(fallback.font) as String, "Helvetica")
        let fallbackGlyph = try XCTUnwrap(fallback.glyphs.first)

        let geometry = makeGeometry(context, String(symbol), "Helvetica")
        let outline = try XCTUnwrap(geometry.makeGlyphOutline(fallback.font, fallbackGlyph))
        defer { geometry.freeGlyphOutline(outline) }
        let triangles = try XCTUnwrap(outline.triangles)
        XCTAssertGreaterThan(geometry.indexCount, 0)
        XCTAssertEqual(geometry.indexCount, Int(triangles.count) * 3)
    }

    // "कि" is one Character, two UTF-16 units and two glyphs, so all three positions diverge after it.
    func testClustersWithMoreGlyphsThanCharacters() throws {
        let context = try makeContext()
        let width = { (bounds: Bounds) in bounds.max.x - bounds.min.x }
        let cluster = makeGeometry(context, "कि", "Helvetica")
        let clusterThenLetter = makeGeometry(context, "किA", "Helvetica")
        let letter = makeGeometry(context, "A", "Helvetica")
        XCTAssertGreaterThan(clusterThenLetter.indexCount, cluster.indexCount)
        XCTAssertGreaterThan(width(clusterThenLetter.bounds), width(cluster.bounds) + width(letter.bounds) * 0.9)
        XCTAssertEqual(clusterThenLetter.characterOffsets.count, 2)
    }

    // Each glyph of "कि" maps to its one Character, which keeps every glyph's contours rather than the last glyph's.
    func testClusterCharacterPathsHoldEveryGlyph() throws {
        let context = try makeContext()
        let cluster: Character = "कि"
        let geometry = makeGeometry(context, String(cluster), "Helvetica")
        var glyphCount = 0
        var contourCount = 0
        for run in runs(String(cluster), "Helvetica") {
            for glyph in run.glyphs {
                glyphCount += 1
                guard let outline = geometry.makeGlyphOutline(run.font, glyph) else { continue }
                contourCount += outline.polylines.count
                geometry.freeGlyphOutline(outline)
            }
        }
        XCTAssertGreaterThan(glyphCount, 1)
        XCTAssertEqual(geometry.characterPaths[cluster]?.count, contourCount)
    }

    // CoreText ranges count UTF-16 units, two per emoji, so a range of Characters stops short of the last ones.
    func testTextAfterSupplementaryPlaneCharactersIsStyled() throws {
        let context = try makeContext()
        let plain = makeGeometry(context, "AB", "Helvetica").bounds
        let afterEmoji = makeGeometry(context, "\u{1F600}\u{1F600}AB", "Helvetica").bounds
        XCTAssertEqual(afterEmoji.max.y - afterEmoji.min.y, plain.max.y - plain.min.y, accuracy: 1e-4)
    }

    // Kern widens the advance after every Character, including those after supplementary-plane characters.
    func testKernAppliesAfterSupplementaryPlaneCharacters() throws {
        let context = try makeContext()
        let text = "\u{1F600}\u{100000}AB"
        let lastCharacter = try XCTUnwrap(text.indices.last)
        // Measured from the first Character, since the pivot centers the wider kerned line
        func lastCharacterDistance(kern: Float) throws -> Float {
            let geometry = TesselatedTextGeometry(context: context, text: text, fontName: "Helvetica", fontSize: 1, kern: kern)
            geometry.update()
            return try XCTUnwrap(geometry.characterOffsets[lastCharacter]).x - XCTUnwrap(geometry.characterOffsets[text.startIndex]).x
        }
        XCTAssertEqual(try lastCharacterDistance(kern: 0.5) - lastCharacterDistance(kern: 0), 1.5, accuracy: 1e-3)
    }
}
