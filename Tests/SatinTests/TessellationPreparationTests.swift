@testable import Satin
import Foundation
import Metal
import XCTest

final class TessellationPreparationTests: XCTestCase {
    private var context: Context!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm,
                          depthPixelFormat: .depth32Float, stencilPixelFormat: .invalid)
    }

    /// Avoid file discovery, but use the real pipeline selection, binding and dispatch paths.
    private final class CountingTessellator: TessellationProcessor<MTLTriangleTessellationFactorsHalf> {
        var updateCount = 0
        override func setup() {}
        override func update() {}
        override func update(_ commands: MTLCommandBuffer, iterations: Int = 1) {
            updateCount += 1
            super.update(commands, iterations: iterations)
        }
    }

    private func fixture(tessellate: Bool) -> (TessellationMesh, CountingTessellator) {
        let geometry = TessellationGeometry(baseGeometry: QuadGeometry(context: context, size: 1))
        let tessellator = CountingTessellator(device: context.device,
            pipelineURL: URL(fileURLWithPath: "/unused/TessellationPreparation.metal"), live: false, geometry: geometry)
        tessellator.shader = ComputeShader(label: "Tessellation preparation")
        let mesh = TessellationMesh(context: context, label: "Tessellated", geometry: geometry,
            material: nil, tessellator: tessellator, tessellate: tessellate)
        return (mesh, tessellator)
    }

    private func builder(_ renderer: RenderEncoder) -> SubmissionBuilder {
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 45)
        return renderer.makeSubmissionBuilder(frame: .zero, cameras: [camera],
            viewports: [.init(originX: 0, originY: 0, width: 16, height: 16, znear: 0, zfar: 1)])
    }

    private func installPipeline(on tessellator: CountingTessellator, resetOnly: Bool = false) throws {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void writeFactors(uint patch [[thread_position_in_grid]],
            device ushort *factors [[buffer(\(ComputeBufferIndex.TessellationFactors.rawValue))]]) {
            if (patch >= \(tessellator.geometry.patchCount)) { return; }
            for (uint index = 0; index < 4; ++index) {
                factors[patch * 4 + index] = 0x3c00; // half(1), without a host Float16 conversion
            }
        }
        """
        let library = try context.device.makeLibrary(source: source, options: nil)
        let function = try XCTUnwrap(library.makeFunction(name: "writeFactors"))
        let pipeline = try context.device.makeComputePipelineState(function: function)
        let shader = try XCTUnwrap(tessellator.shader)
        if resetOnly { shader.resetPipeline = pipeline }
        else { shader.updatePipeline = pipeline }
    }

    func testMissingPipelineDoesNotPublishFactorsAndRetriesAFreeze() throws {
        for tessellate in [true, false] {
            let renderer = RenderEncoder(context: context)
            let submission = builder(renderer)
            let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
            let (mesh, tessellator) = fixture(tessellate: tessellate)
            for attempt in 1...3 {
                mesh.encode(in: submission.encodingContext(commandBuffer: commands))
                XCTAssertNil(mesh.encodedFactors, "No pipeline wrote the requested factors")
                XCTAssertEqual(tessellator.updateCount, attempt, "Failed preparation must be retried")
                XCTAssertNil(tessellator.factorsDestination, "A frame-arena destination must not escape preparation")
            }
            commands.commit()
            commands.waitUntilCompleted()
        }
    }

    func testFreezeRecoversWhenPipelineAppearsAndKeepsItsWrittenFactors() throws {
        let renderer = RenderEncoder(context: context)
        let submission = builder(renderer)
        let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let (mesh, tessellator) = fixture(tessellate: false)
        let encoding = submission.encodingContext(commandBuffer: commands)
        mesh.encode(in: encoding)
        XCTAssertNil(mesh.encodedFactors)
        try installPipeline(on: tessellator)
        mesh.encode(in: encoding)
        let frozen = try XCTUnwrap(mesh.encodedFactors)
        mesh.encode(in: encoding)
        XCTAssertEqual(tessellator.updateCount, 2, "A successful freeze must not dispatch again")
        XCTAssertTrue(mesh.encodedFactors?.buffer === frozen.buffer)

        let staging = try XCTUnwrap(context.device.makeBuffer(length: tessellator.factorsLength, options: .storageModeShared))
        let blit = try XCTUnwrap(commands.makeBlitCommandEncoder())
        blit.copy(from: frozen.buffer, sourceOffset: frozen.offset, to: staging, destinationOffset: 0, size: tessellator.factorsLength)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertEqual(commands.status, .completed, String(describing: commands.error))
        let bits = staging.contents().assumingMemoryBound(to: UInt16.self)
        for index in 0..<(tessellator.factorsLength / MemoryLayout<UInt16>.stride) {
            XCTAssertEqual(bits[index], 0x3c00)
        }
    }

    func testFailedDynamicPreparationDoesNotReuseAnEarlierArenaSlice() throws {
        let renderer = RenderEncoder(context: context)
        let submission = builder(renderer)
        let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let (mesh, tessellator) = fixture(tessellate: true)
        try installPipeline(on: tessellator)
        mesh.encode(in: submission.encodingContext(commandBuffer: commands))
        XCTAssertNotNil(mesh.encodedFactors)
        tessellator.shader?.updatePipeline = nil
        mesh.encode(in: submission.encodingContext(commandBuffer: commands))
        XCTAssertNil(mesh.encodedFactors, "An earlier slice is not a fallback for a failed preparation")
        commands.commit()
        commands.waitUntilCompleted()
    }

    func testResetOnlyPipelineReportsSuccessOnlyWhenItDispatches() throws {
        let (_, tessellator) = fixture(tessellate: true)
        try installPipeline(on: tessellator, resetOnly: true)
        let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let destination = try XCTUnwrap(context.device.makeBuffer(length: tessellator.factorsLength, options: .storageModePrivate))
        XCTAssertTrue(tessellator.encodeFactors(commands, into: (destination, 0)))
        XCTAssertFalse(tessellator.encodeFactors(commands, into: (destination, 0)), "Reset has already run and there is no update pipeline")
        commands.commit()
        commands.waitUntilCompleted()
    }
}
