@testable import Satin
import Metal
import XCTest

/// A context gets its own allocator unless handed one, so every context Satin derives from another
/// must pass the parent's. A derived context that forgot would silently get its own heaps.
final class ContextAllocatorTests: XCTestCase {
    private var device: MTLDevice!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
    }

    private func makeContext(id: UUID = UUID(), gpuAllocator: GPUAllocator? = nil) -> Context {
        Context(id: id, device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                depthPixelFormat: .depth32Float, gpuAllocator: gpuAllocator)
    }

    func testEveryDerivedContextSharesItsParentsAllocator() throws {
        let context = makeContext()
        var derived: [(name: String, context: Context)] = []

        // RenderEncoder derives its render contexts while recording; draw once to create them.
        let encoder = RenderEncoder(context: context)
        encoder.resize((16, 16))
        let mesh = Mesh(context: context, geometry: QuadGeometry(context: context), material: BasicColorMaterial(context: context))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100)
        let commandBuffer = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        try encoder.draw(frame: .zero, renderPassDescriptor: MTLRenderPassDescriptor(), commandBuffer: commandBuffer,
                         scene: mesh, camera: camera)
        let renderContexts = encoder.renderContexts.compactMap { $0 }
        XCTAssertFalse(renderContexts.isEmpty, "drawing a mesh creates a render context")
        derived += renderContexts.map { ("RenderEncoder render context", $0) }
        derived.append(("PostProcessRenderEncoder forward context",
                        PostProcessRenderEncoder(context: context, colorPixelFormat: .bgra8Unorm).forwardRenderContext))

        let ssao = SsaoPostProcessEncoder(context: context)
        derived.append(("SSAO depth", ssao.prefilterMaterial.context))
        derived.append(("SSAO occlusion", ssao.ssaoMaterial.context))
        derived.append(("SSAO composite", ssao.compositeMaterial.context))

        let ssgi = SsgiPostProcessEncoder(context: context)
        derived.append(("SSGI", ssgi.ssgiMaterial.context))
        derived.append(("SSGI composite", ssgi.compositeMaterial.context))

        let motionBlur = MotionBlurPostProcessEncoder(context: context)
        derived.append(("Motion blur", motionBlur.motionBlurMaterial.context))
        derived.append(("Motion blur tile max", motionBlur.tileMaxMaterial.context))
        derived.append(("Motion blur pointers", motionBlur.neighborMaxMaterial.context))

        derived.append(("Bokeh composite", BokehDepthOfFieldPostProcessEncoder(context: context).compositeMaterial.context))

        for (name, derivedContext) in derived {
            XCTAssertTrue(derivedContext.gpuAllocator === context.gpuAllocator, "\(name) must share its parent's allocator")
        }
    }

    func testContextsShareMemoryOnlyWhenHandedTheSameAllocator() {
        XCTAssertFalse(makeContext().gpuAllocator === makeContext().gpuAllocator)

        let shared = GPUAllocator(device: device)
        XCTAssertTrue(makeContext(gpuAllocator: shared).gpuAllocator === shared)
        XCTAssertTrue(makeContext(gpuAllocator: shared).gpuAllocator === makeContext(gpuAllocator: shared).gpuAllocator)
    }

    func testTheAllocatorIsNotPartOfContextIdentity() {
        let id = UUID()
        let first = makeContext(id: id, gpuAllocator: GPUAllocator(device: device))
        let second = makeContext(id: id, gpuAllocator: GPUAllocator(device: device))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertEqual(first.index, second.index)
    }
}
