@testable import Satin
import Metal
import XCTest

/// Recorded shadowed lights get a new map per occurrence every frame. Those versions come from the
/// context's allocator, so a steady stream of frames reuses heap memory instead of growing it.
final class RecordedShadowAllocationTests: XCTestCase {
    private var device: MTLDevice!
    private var context: Context!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm, depthPixelFormat: .depth32Float)
    }

    private func makeTarget() throws -> MTLRenderPassDescriptor {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = .renderTarget
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        return pass
    }

    /// Records `lights` moving shadowed point lights per frame, over a lit receiver and a caster.
    private func renderFrame(_ renderer: RenderEncoder, frame: Int, lights: [PointLight], root: Object) throws {
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 45)
        let submission = renderer.makeSubmissionBuilder(frame: .zero, cameras: [camera],
                                                        viewports: [.init(originX: 0, originY: 0, width: 64, height: 64, znear: 0, zfar: 1)])
        for (index, light) in lights.enumerated() {
            // Moving every light every frame forces a new shadow version per occurrence.
            light.position = [Float(index) * 0.1, Float(frame) * 0.01, 1]
            try submission.record(scene: Object(context: context, label: "Recorded Light \(index)", [light]))
        }
        let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        try submission.record(scene: root, renderPassDescriptor: try makeTarget(), preparationCommandBuffer: commands)
        try submission.seal().encode(into: commands)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, String(describing: commands.error))
    }

    func testRecordedShadowVersionsReuseHeapMemoryAcrossFrames() throws {
        let renderer = RenderEncoder(context: context)
        renderer.resize((width: 64, height: 64))
        let lights = (0 ..< 8).map { _ in
            let light = PointLight(context: context, color: .one, radius: 4)
            light.castShadow = true
            light.shadow.resolution = (64, 64)
            return light
        }
        let receiver = Mesh(context: context, geometry: PlaneGeometry(context: context), material: BasicDiffuseMaterial(context: context))
        receiver.receiveShadow = true
        let caster = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicDiffuseMaterial(context: context))
        caster.scale = .init(repeating: 0.25)
        caster.castShadow = true
        let root = Object(context: context, label: "Root", [receiver, caster])

        for frame in 0 ..< 3 { try renderFrame(renderer, frame: frame, lights: lights, root: root) }
        let warm = context.gpuAllocator.statistics(for: .gpuOnly)
        XCTAssertGreaterThan(warm.heapCount, 0, "recorded shadow versions come from the allocator")

        for frame in 3 ..< 20 { try renderFrame(renderer, frame: frame, lights: lights, root: root) }
        let later = context.gpuAllocator.statistics(for: .gpuOnly)
        XCTAssertEqual(later.heapCount, warm.heapCount, "steady frames reuse heap memory")
        XCTAssertEqual(later.fallbackCount, 0)
    }

    func testFrameArenaChunksComeFromTheContextsAllocator() throws {
        let arena = FrameArena(allocator: context.gpuAllocator)
        let lease = arena.lease(frame: .zero)
        let slice = try lease.allocate(length: 1024)
        XCTAssertNotNil(slice.buffer.heap)
        XCTAssertEqual(slice.buffer.heap?.cpuCacheMode, .writeCombined)
        XCTAssertEqual(context.gpuAllocator.statistics(for: .cpuWrites).heapCount, 1)
    }
}
