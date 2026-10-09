import CoreText
import Foundation
import Metal
@testable import Satin
import XCTest

// Writes timings as TSV to <file> and <file>.outline, for comparing two builds. Run in release:
// TEXT_GEOMETRY_BENCHMARK_OUTPUT=<file> swift test -c release -Xswiftc -enable-testing --filter TextGeometryBenchmark
// TEXT_GEOMETRY_BENCHMARK_CASE=<name> limits the run to one case, so a build that crashes on one loses only that case.
final class TextGeometryBenchmark: XCTestCase {
    private static let commonFonts = ["Helvetica", "SF Pro", "Hoefler Text"]

    // name: (text, font native to the script, or nil when a common font already covers it)
    private static let cases: [String: (String, String?)] = [
        "ascii": ("The quick brown fox jumps over the lazy dog 0123456789", nil),
        "latin-accented": ("Ça été drôle: Øresund, ñandú, Straße, œuvre, Ångström, Łódź, Dvořák", nil),
        "cyrillic": ("Съешь же ещё этих мягких французских булок", nil),
        "greek": ("Ξεσκεπάζω την ψυχοφθόρα βδελυγμία", nil),
        "math-punctuation": ("∑∫√∞≈≠≤≥±×÷→←↑↓★☆♠♥«»„“”‘’…•", nil),
        "chinese": ("永和九年歲在癸丑暮春之初會于會稽山陰之蘭亭修禊事也", "PingFang SC"),
        "japanese": ("いろはにほへとちりぬるをわかよたれそつねならむカタカナ漢字", "Hiragino Sans"),
        "hangul": ("다람쥐 헌 쳇바퀴에 타고파 키스의 고유조건은", "Apple SD Gothic Neo"),
        "devanagari": ("ऋषियों को सताने वाले दुष्ट राक्षसों के राजा रावण का सर्वनाश", "Kohinoor Devanagari"),
        "arabic": ("نص حكيم له سر قاطع وذو شأن عظيم مكتوب على ثوب أخضر", "Geeza Pro"),
        "sf-symbols": (sfSymbols(), nil),
        "emoji": ("😀🎉👍🚀🍕❤️🐶🌈👨‍👩‍👧🇺🇸", nil),
        "mixed": ("Hello 世界 नमस्ते مرحبا Привет 😀 " + String(sfSymbols().prefix(3)), nil),
    ]

    // 30 SF Symbols spread across the private use range SF Pro maps them to
    private static func sfSymbols() -> String {
        let font = CTFontCreateWithName("SF Pro" as CFString, 1, nil)
        var symbols = ""
        var scalarValue: UInt32 = 0x100000
        while symbols.unicodeScalars.count < 30, scalarValue < 0x101000 {
            if let scalar = Unicode.Scalar(scalarValue) {
                var characters = Array(String(scalar).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: characters.count)
                if CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) {
                    symbols.unicodeScalars.append(scalar)
                }
            }
            scalarValue += 131
        }
        return symbols
    }

    private static func decimal(_ fractionLength: Int) -> FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(fractionLength)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
    }

    private func outputPath() throws -> String {
        guard let path = ProcessInfo.processInfo.environment["TEXT_GEOMETRY_BENCHMARK_OUTPUT"] else {
            throw XCTSkip("Set TEXT_GEOMETRY_BENCHMARK_OUTPUT to run.")
        }
        return path
    }

    private func makeContext() throws -> Context {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
    }

    private func selectedCases() -> [(name: String, text: String, fonts: [String])] {
        let selection = ProcessInfo.processInfo.environment["TEXT_GEOMETRY_BENCHMARK_CASE"]
        return Self.cases.sorted { $0.key < $1.key }
            .filter { selection == nil || $0.key == selection }
            .map { (name: $0.key, text: $0.value.0, fonts: Self.commonFonts + [$0.value.1].compactMap { $0 }) }
    }

    private func runs(_ text: String, _ fontName: String) -> [CTRun] {
        let font = CTFontCreateWithName(fontName as CFString, 1, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.init(kCTFontAttributeName as String): font]))
        return CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    }

    // Milliseconds: "cold" builds every glyph outline, "relayout" lays out new text from cached glyphs.
    func testTextGeometryTimings() throws {
        let outputPath = try outputPath()
        let context = try makeContext()
        let repetitions = 11
        var lines = [["case", "font", "kind", "characters", "glyphs", "triangles", "cold", "relayout"].joined(separator: "\t")]

        func median(_ body: () -> Void) -> Double {
            var samples: [Double] = []
            for _ in 0 ..< repetitions {
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            }
            return samples.sorted()[repetitions / 2]
        }

        for (name, text, fonts) in selectedCases() {
            for font in fonts {
                for (kind, geometry) in [("tesselated", TesselatedTextGeometry(context: context, text: text, fontName: font, fontSize: 1)),
                                         ("extruded", ExtrudedTextGeometry(context: context, text: text, fontName: font, fontSize: 1, distance: 0.2))]
                {
                    var triangles = 0
                    let cold = median {
                        geometry.clearCache()
                        geometry.text = text
                        var data = geometry.generateGeometryData()
                        triangles = Int(data.indexCount)
                        freeGeometryData(&data)
                    }
                    var appendSpace = false
                    let relayout = median {
                        appendSpace.toggle()
                        geometry.text = appendSpace ? text + " " : text
                        var data = geometry.generateGeometryData()
                        freeGeometryData(&data)
                    }
                    let glyphs = runs(text, font).reduce(0) { $0 + CTRunGetGlyphCount($1) }
                    lines.append([name, font, kind, "\(text.count)", "\(glyphs)", "\(triangles)",
                                  cold.formatted(Self.decimal(3)), relayout.formatted(Self.decimal(4))].joined(separator: "\t"))
                }
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    // Microseconds per outlined glyph: triangulating the original outline alone, merging its contours alone, and
    // makeGlyphOutline, which does both and triangulates the merged outline where the original falls short.
    func testGlyphOutlineCost() throws {
        let outputPath = try outputPath() + ".outline"
        let context = try makeContext()
        let geometry = TesselatedTextGeometry(context: context, text: "", fontName: "Helvetica", fontSize: 1)
        let distanceLimit = geometry.fontSize / 10.0
        var lines = [["case", "font", "glyphs", "outlined", "original failed", "merged chosen", "original", "merge", "makeGlyphOutline"].joined(separator: "\t")]

        func fastest(_ body: () -> Void) -> Double {
            var best = Double.infinity
            for _ in 0 ..< 5 {
                let start = DispatchTime.now().uptimeNanoseconds
                body()
                best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e3)
            }
            return best
        }

        for (name, text, fonts) in selectedCases() {
            for fontName in fonts {
                var originalTotal = 0.0, mergeTotal = 0.0, outlineTotal = 0.0
                var glyphCount = 0, outlined = 0, originalFailed = 0, mergedChosen = 0
                for run in runs(text, fontName) {
                    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName].map { $0 as! CTFont } ?? CTFontCreateWithName(fontName as CFString, 1, nil)
                    var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
                    CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
                    for glyph in glyphs {
                        glyphCount += 1
                        guard let path = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                        outlined += 1
                        var failed = false
                        originalTotal += fastest {
                            let outline = geometry.triangulateOutline(path, geometry.getPolylines(path, geometry.angleLimit, distanceLimit))
                            failed = outline.triangles == nil
                            geometry.freeGlyphOutline(outline)
                        }
                        mergeTotal += fastest { _ = path.normalized(using: .winding) }
                        var merged = false
                        outlineTotal += fastest {
                            guard let outline = geometry.makeGlyphOutline(runFont, glyph) else { return }
                            merged = outline.path != path
                            geometry.freeGlyphOutline(outline)
                        }
                        if failed { originalFailed += 1 }
                        if merged { mergedChosen += 1 }
                    }
                }
                let perGlyph = { (total: Double) in (total / Double(max(outlined, 1))).formatted(Self.decimal(1)) }
                lines.append([name, fontName, "\(glyphCount)", "\(outlined)", "\(originalFailed)", "\(mergedChosen)",
                              perGlyph(originalTotal), perGlyph(mergeTotal), perGlyph(outlineTotal)].joined(separator: "\t"))
            }
        }
        try (lines.joined(separator: "\n") + "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}
