import Metal
import Satin
import XCTest

/// A SourceShader opts into alpha OIT by defining `SATIN_ALPHA_OIT_ENABLED`, read from its
/// source when made and again when it reloads.
final class SourceShaderAlphaOitTests: XCTestCase {
    func testOptingInIsReadFromTheSourceAndFollowsAReload() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let directory = FileManager.default.temporaryDirectory.appending(path: "SatinAlphaOit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Shaders.metal")

        // Mentioning the name, as AlphaOIT.metal's comments do, is not opting in.
        try "// shaders opt in by defining `SATIN_ALPHA_OIT_ENABLED`\n".write(to: url, atomically: true, encoding: .utf8)
        let shader = SourceShader(context: context, label: "Probe", pipelineURL: url)
        XCTAssertFalse(shader.definesAlphaOrderIndependentTransparency)

        try "#define SATIN_ALPHA_OIT_ENABLED\n".write(to: url, atomically: true, encoding: .utf8)
        shader.reloadFromSource()
        XCTAssertTrue(shader.definesAlphaOrderIndependentTransparency, "A reload reads the new source")
    }
}
