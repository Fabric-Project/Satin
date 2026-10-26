@testable import Satin
import Metal
import XCTest

final class GPUAllocationFailureTests: XCTestCase {
    private func makeBuilder(context: Context, arena: FrameArena, pool: PacketStoragePool) -> SubmissionBuilder {
        let renderer = RenderEncoder(context: context)
        let template = renderer.makeSubmissionBuilder(frame: .zero,
            cameras: [PerspectiveCamera(context: context, position: [0, 0, 5], near: 0.1, far: 100, fov: 45)],
            viewports: [MTLViewport(originX: 0, originY: 0, width: 32, height: 32, znear: 0, zfar: 1)])
        let lease = arena.lease(frame: .zero)
        return SubmissionBuilder(encoder: renderer, recorder: PacketRecorder(storage: pool.lease(), lease: lease),
            lease: lease, frame: template.frame, destination: template.destination,
            configuration: template.configuration, cameras: template.cameras, viewports: template.viewports, pool: pool)
    }

    func testFailedRecordingReturnsStorageAndCannotBeSealed() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let arena = FrameArena(device: device, initialChunkLength: device.maxBufferLength + 1)
        let pool = PacketStoragePool()
        var builder: SubmissionBuilder? = makeBuilder(context: context, arena: arena, pool: pool)
        let mesh = Mesh(context: context, geometry: BoxGeometry(context: context), material: BasicColorMaterial(context: context))
        mesh.update()
        let scene = Object(context: context, label: "Allocation Failure", [mesh])

        XCTAssertThrowsError(try XCTUnwrap(builder).record(scene: scene)) { error in
            XCTAssertEqual(error as? GPUError, .allocationFailed)
        }
        XCTAssertEqual(pool.availableCount, 1)
        XCTAssertThrowsError(try XCTUnwrap(builder).seal()) { error in
            XCTAssertEqual(error as? SubmissionError, .alreadyDrawn)
        }
        builder = nil
        XCTAssertEqual(pool.availableCount, 1, "Failed builder deinit must not return storage twice")
    }

    func testPreparationMemorySurvivesAnAllocationFailureAndAbandonment() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let context = Context(device: device, sampleCount: 1, colorPixelFormat: .bgra8Unorm)
        let arena = FrameArena(device: device, initialChunkLength: 256)
        let pool = PacketStoragePool()
        var builder: SubmissionBuilder? = makeBuilder(context: context, arena: arena, pool: pool)
        let commandBuffer = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let preparation = try XCTUnwrap(builder).encodingContext(commandBuffer: commandBuffer)
        let input = try preparation.allocate(length: 4)
        input.buffer.contents().advanced(by: input.offset).storeBytes(of: UInt32(1234), as: UInt32.self)
        let output = try XCTUnwrap(device.makeBuffer(length: 4, options: .storageModeShared))
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blit.copy(from: input.buffer, sourceOffset: input.offset, to: output, destinationOffset: 0, size: 4)
        blit.endEncoding()

        XCTAssertThrowsError(try preparation.allocate(length: device.maxBufferLength + 1)) { error in
            XCTAssertEqual(error as? GPUError, .allocationFailed)
        }
        builder = nil
        XCTAssertEqual(pool.availableCount, 1)
        let concurrentLease = arena.lease(frame: .zero)
        let concurrentSlice = try concurrentLease.allocate(length: 4)
        XCTAssertFalse(concurrentSlice.buffer === input.buffer, "Pending preparation still owns its arena chunk")

        let completed = expectation(description: "preparation and arena retirement completed")
        commandBuffer.addCompletedHandler { _ in completed.fulfill() }
        commandBuffer.commit()
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(commandBuffer.status, .completed, String(describing: commandBuffer.error))
        XCTAssertEqual(output.contents().load(as: UInt32.self), 1234)
        let retired = try arena.lease(frame: .zero).allocate(length: 4)
        XCTAssertTrue(retired.buffer === input.buffer)
        withExtendedLifetime(concurrentLease) {}
    }
}
