@testable import Satin
import Metal
import XCTest

private final class CountingRecordedShader: Shader {
    nonisolated(unsafe) static var initializations = 0
    nonisolated(unsafe) static var resolutions = 0
    nonisolated(unsafe) static var testPipeline: MTLRenderPipelineState?

    required init(configuration: ShaderConfiguration) {
        Self.initializations += 1
        super.init(configuration: configuration)
    }

    override func getPipeline(renderContext: Context, shadow: Bool, layout: DrawLayout?) -> MTLRenderPipelineState? {
        Self.resolutions += 1
        return Self.testPipeline
    }
}

final class RecordedLightingReuseTests: XCTestCase {
    private func makeShader() throws -> (CountingRecordedShader, Context) {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        vertex float4 vertexMain(uint index [[vertex_id]]) { return float4(0, 0, 0, 1); }
        fragment float4 fragmentMain() { return float4(1); }
        """, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        CountingRecordedShader.testPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        CountingRecordedShader.initializations = 0
        CountingRecordedShader.resolutions = 0
        var configuration = ShaderConfiguration()
        configuration.context = context
        return (CountingRecordedShader(configuration: configuration), context)
    }

    func testUnchangedRecordingsReuseShaderAndResolvedPipeline() throws {
        let (shader, context) = try makeShader()
        for _ in 0..<20 {
            let recipe = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
            XCTAssertNotNil(recipe.resolve(lightCount: 2, shadowCount: 1, shadowTextureCount: 1, projectorCount: 0))
        }
        XCTAssertEqual(CountingRecordedShader.initializations, 2, "One source shader and one reusable lighting variant")
        XCTAssertEqual(CountingRecordedShader.resolutions, 1, "Steady-state recording must not reenter pipeline resolution")
    }

    func testLightingCountsSelectReusableVariants() throws {
        let (shader, context) = try makeShader()
        let recipe = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        for count in [1, 2, 1, 2] {
            XCTAssertNotNil(recipe.resolve(lightCount: count, shadowCount: 0, shadowTextureCount: 0, projectorCount: 0))
        }
        XCTAssertEqual(CountingRecordedShader.resolutions, 2)
    }

    func testEveryLightingCountParticipatesInVariantSelection() throws {
        let (shader, context) = try makeShader()
        let recipe = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        for _ in 0..<2 {
            for counts in [(1, 0, 0, 0), (1, 1, 0, 0), (1, 1, 2, 0), (1, 1, 2, 1)] {
                XCTAssertNotNil(recipe.resolve(lightCount: counts.0, shadowCount: counts.1,
                                               shadowTextureCount: counts.2, projectorCount: counts.3))
            }
        }
        XCTAssertEqual(CountingRecordedShader.resolutions, 4)
    }

    func testChangedCapturedConfigurationDoesNotReuseOldPipelineResolution() throws {
        let (shader, context) = try makeShader()
        let old = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        XCTAssertNotNil(old.resolve(lightCount: 1, shadowCount: 0, shadowTextureCount: 0, projectorCount: 0))
        shader.configuration.rendering.vertexDescriptor.layouts[0].stride += 16
        let changed = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        XCTAssertNotNil(changed.resolve(lightCount: 1, shadowCount: 0, shadowTextureCount: 0, projectorCount: 0))
        XCTAssertEqual(CountingRecordedShader.resolutions, 2)
        XCTAssertNotEqual(old.configuration.rendering.vertexDescriptor.layouts[0].stride,
                          changed.configuration.rendering.vertexDescriptor.layouts[0].stride)
    }

    func testInvalidationDoesNotChangeAnAlreadyCapturedRecipe() throws {
        let (shader, context) = try makeShader()
        let captured = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        XCTAssertNotNil(captured.resolve(lightCount: 1, shadowCount: 0, shadowTextureCount: 0, projectorCount: 0))
        shader.configurationNeedsUpdate = true
        let next = RecordedLightingPipeline(shader: shader, renderContext: context, layout: nil)
        XCTAssertNotNil(next.resolve(lightCount: 1, shadowCount: 0, shadowTextureCount: 0, projectorCount: 0))
        XCTAssertNotNil(captured.resolve(lightCount: 1, shadowCount: 0, shadowTextureCount: 0, projectorCount: 0))
        XCTAssertEqual(CountingRecordedShader.resolutions, 2)
    }
}
