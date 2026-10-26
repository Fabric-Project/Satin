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
        override func update(_ commands: MTLCommandBuffer, iterations: Int = 1) throws {
            updateCount += 1
            try super.update(commands, iterations: iterations)
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

    private final class Tessellated: TessellationProcessor<MTLTriangleTessellationFactorsHalf> {}
    private final class TessellatedMaterial: SourceMaterial {}

    func testExampleShadersRenderAndRespondToLaterFactors() throws {
        let pipelines = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Example/Assets/TessellationRenderer/Pipelines")
        let geometry = TessellationGeometry(baseGeometry: IcoSphereGeometry(context: context, radius: 1, resolution: 1))
        let tessellator = Tessellated(device: context.device,
            pipelineURL: pipelines.appending(path: "Tessellated/Compute.metal"), live: false, geometry: geometry)
        let material = TessellatedMaterial(context: context, pipelinesURL: pipelines)
        let mesh = TessellationMesh(context: context, label: "Example tessellation", geometry: geometry,
            material: material, tessellator: tessellator)
        let scene = Object(context: context, [mesh])
        let renderer = RenderEncoder(context: context, clearColor: [0, 0, 0, 1])
        renderer.resize((32, 32))
        let camera = PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 30)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 32, height: 32, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let output = try XCTUnwrap(context.device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output

        func render(factor: Float, frame: FrameTime) throws -> Int {
            tessellator.set("Edge Tessellation Factor", factor)
            tessellator.set("Inside Tessellation Factor", factor)
            material.set("Color", SIMD4<Float>(repeating: 1))
            let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
            try renderer.draw(frame: frame, renderPassDescriptor: pass, commandBuffer: commands, scene: scene, camera: camera)
            commands.commit()
            commands.waitUntilCompleted()
            XCTAssertEqual(commands.status, .completed, String(describing: commands.error))
            var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
            output.getBytes(&pixels, bytesPerRow: 32 * 4, from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
            return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 0 || pixels[$0 + 1] > 0 || pixels[$0 + 2] > 0 }.count
        }

        XCTAssertEqual(try render(factor: 0, frame: .zero), 0, "Zero edge factors discard patches")
        XCTAssertGreaterThan(try render(factor: 4, frame: .zero.next(time: 1)), 100,
                             "A later nonzero factor must produce visible pixels with the real example shaders")

        mesh.tessellate = false
        XCTAssertEqual(try render(factor: 0, frame: .zero.next(time: 2)), 0)
        XCTAssertEqual(try render(factor: 4, frame: .zero.next(time: 3)), 0,
                       "Freezing zero factors keeps the surface invisible despite later parameter changes")
        mesh.tessellate = true
        XCTAssertGreaterThan(try render(factor: 4, frame: .zero.next(time: 4)), 100,
                             "Re-enabling tessellation must regenerate visible patches")
    }

    func testMissingPipelineDoesNotPublishFactorsAndRetriesAFreeze() throws {
        for tessellate in [true, false] {
            let renderer = RenderEncoder(context: context)
            let submission = builder(renderer)
            let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
            let (mesh, tessellator) = fixture(tessellate: tessellate)
            for attempt in 1...3 {
                try mesh.encode(in: submission.encodingContext(commandBuffer: commands))
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
        try mesh.encode(in: encoding)
        XCTAssertNil(mesh.encodedFactors)
        try installPipeline(on: tessellator)
        try mesh.encode(in: encoding)
        let frozen = try XCTUnwrap(mesh.encodedFactors)
        try mesh.encode(in: encoding)
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
        try mesh.encode(in: submission.encodingContext(commandBuffer: commands))
        XCTAssertNotNil(mesh.encodedFactors)
        tessellator.shader?.updatePipeline = nil
        try mesh.encode(in: submission.encodingContext(commandBuffer: commands))
        XCTAssertNil(mesh.encodedFactors, "An earlier slice is not a fallback for a failed preparation")
        commands.commit()
        commands.waitUntilCompleted()
    }

    func testResetOnlyPipelineReportsSuccessOnlyWhenItDispatches() throws {
        let (_, tessellator) = fixture(tessellate: true)
        try installPipeline(on: tessellator, resetOnly: true)
        let commands = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let destination = try XCTUnwrap(context.device.makeBuffer(length: tessellator.factorsLength, options: .storageModePrivate))
        XCTAssertTrue(try tessellator.encodeFactors(commands, into: (destination, 0)))
        XCTAssertFalse(try tessellator.encodeFactors(commands, into: (destination, 0)), "Reset has already run and there is no update pipeline")
        commands.commit()
        commands.waitUntilCompleted()
    }
}
