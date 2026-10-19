@testable import Satin
import Metal
import XCTest

/// Render contexts are interned by everything a pipeline depends on, so equal configurations share
/// an index and with it their compiled pipelines, and a draw finds those pipelines and a
/// material's bindings by index rather than by hashing.
final class RenderContextRegistryTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func makeContext(sampleCount: Int = 1, alphaOitEnabled: Bool = false, activeOutputs: RendererOutputs = [.color]) -> Context {
        Context(
            device: device,
            sampleCount: sampleCount,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            activeOutputs: activeOutputs,
            alphaOitEnabled: alphaOitEnabled
        )
    }

    func testEqualConfigurationsShareAnIndexAndDifferentOnesDont() {
        let first = makeContext()
        let second = makeContext()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.index, second.index, "equal configurations share an index")

        XCTAssertNotEqual(first.index, makeContext(sampleCount: 4).index)
        XCTAssertNotEqual(first.index, makeContext(alphaOitEnabled: true).index)
        XCTAssertNotEqual(first.index, makeContext(activeOutputs: [.color, .velocity]).index)
    }

    func testTheRegistryGrowsWithConfigurationsNotWithContexts() {
        _ = makeContext()
        let count = RenderContextRegistry.count
        for _ in 0 ..< 100 {
            _ = makeContext()
        }
        XCTAssertEqual(RenderContextRegistry.count, count)
    }

    func testEqualContextsShareCompiledPipelines() throws {
        let material = BasicColorMaterial(context: makeContext())
        material.setup()
        let first = makeContext()
        let second = makeContext()

        let compiled = try XCTUnwrap(material.getPipeline(renderContext: first, shadow: false))
        let shader = try XCTUnwrap(material.shader)

        XCTAssertTrue(shader.pipeline(for: second, shadow: false) === compiled, "a context equal to one already compiled for finds its pipeline")
    }

    func testAMaterialBindingSetToNilIsNoLongerRecorded() throws {
        let context = makeContext()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        // Binds its G-buffer inputs through the material's own slots (`set(_:index:)`).
        let material = DeferredLightingMaterial(context: context)
        material.albedoTexture = texture
        material.update()
        // Compiling reflects which slots the shader reads.
        XCTAssertNotNil(material.getPipeline(renderContext: context, shadow: false))

        let vertexUniformsBuffer = try XCTUnwrap(device.makeBuffer(length: 4096))
        func recordsAlbedo() -> Bool {
            let storage = PacketStorage()
            storage.beginRecording(cullMode: .back, windingOrder: .counterClockwise, triangleFillMode: .fill, renderOrder: 0, debugLabel: "Test")
            let drawContext = RenderableDrawContext(
                renderContext: context,
                pass: .color,
                materialPass: .all,
                vertexUniforms: VertexUniformsBinding(buffer: vertexUniformsBuffer, offset: 0),
                storage: storage
            )
            material.draw(in: drawContext.materialContext(layout: nil))
            return storage.commands.contains { if case .fragmentTexture(_, .Custom0) = $0 { return true } else { return false } }
        }

        XCTAssertTrue(recordsAlbedo())
        material.albedoTexture = nil
        XCTAssertFalse(recordsAlbedo())
    }
}
