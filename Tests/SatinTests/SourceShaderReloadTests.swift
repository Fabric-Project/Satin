import Metal
@testable import Satin
import XCTest

final class SourceShaderReloadTests: XCTestCase {
    private func shaderSource(textureCount: Int) -> String {
        let arguments = (0 ..< textureCount)
            .map { "\ttexture2d<half, access::sample> texture\($0) [[texture(FragmentTextureCustom\($0))]]," }
            .joined(separator: "\n")

        let samples = (0 ..< textureCount)
            .map { "\tcolor += texture\($0).sample(s, in.texcoord);" }
            .joined(separator: "\n")

        return """
        typedef struct {
            float amount; // slider, 0.0, 1.0, 1.0, Amount
        } ReloadProbeUniforms;

        fragment half4 reloadProbeFragment(VertexData in [[stage_in]],
        \(arguments)
        \tconstant ReloadProbeUniforms &uniforms [[buffer(FragmentBufferMaterialUniforms)]]) {
        \tconstexpr sampler s(address::clamp_to_edge, filter::linear);
        \thalf4 color = half4(0.0);
        \(samples)
        \treturn color * half(uniforms.amount);
        }
        """
    }

    func testReloadFromSourceRebuildsPipelineReflection() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceShaderReloadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pipelineURL = directory.appendingPathComponent("Shaders.metal")
        try shaderSource(textureCount: 1).write(to: pipelineURL, atomically: false, encoding: .utf8)

        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let shader = SourceShader(context: context, label: "ReloadProbe", pipelineURL: pipelineURL)
        shader.setup()

        XCTAssertNil(shader.pipelineError)
        XCTAssertEqual(shader.fragmentTextureBindingIsUsed, [.Custom0])
        let recorded = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        let recordedPipeline = try XCTUnwrap(recorded.resolve(lightCount: 1, shadowCount: 0,
                                                             shadowTextureCount: 0, projectorCount: 0))

        try shaderSource(textureCount: 2).write(to: pipelineURL, atomically: false, encoding: .utf8)
        shader.reloadFromSource()

        XCTAssertNil(shader.pipelineError)
        XCTAssertEqual(shader.fragmentTextureBindingIsUsed, [.Custom0, .Custom1])
        let reloaded = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        let reloadedPipeline = try XCTUnwrap(reloaded.resolve(lightCount: 1, shadowCount: 0,
                                                             shadowTextureCount: 0, projectorCount: 0))
        XCTAssertFalse(recordedPipeline === reloadedPipeline, "Reload invalidates lighting variants too")
        XCTAssertTrue(recordedPipeline === recorded.resolve(lightCount: 1, shadowCount: 0,
                                                            shadowTextureCount: 0, projectorCount: 0),
                      "Already captured work retains its resolved pipeline")
    }
}
