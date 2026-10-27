@testable import Satin
import Metal
import XCTest

/// `FrameArena` hands out aligned slices that stay valid, and untouched, until their command buffer
/// completes; growth never moves earlier slices; completed and never-committed segments return their
/// chunks; a steady workload stops creating chunks.
final class FrameArenaTests: XCTestCase {
    func testLeaseCanRecordBeforeACommandBufferExists() throws {
        let arena = FrameArena(device: device)
        var lease: FrameArena.Lease? = arena.lease(frame: .zero)
        let slice = try XCTUnwrap(lease).allocate(length: 32)
        slice.contents.storeBytes(of: UInt32(42), as: UInt32.self)
        let commandBuffer = try makeCommandBuffer()
        try XCTUnwrap(lease).retain(untilCompleted: commandBuffer)
        lease = nil
        let other = arena.lease(frame: .zero)
        XCTAssertFalse(try other.allocate(length: 32).buffer === slice.buffer)
        XCTAssertEqual(slice.contents.load(as: UInt32.self), 42)
        complete(commandBuffer)
        let later = arena.lease(frame: .zero)
        XCTAssertTrue(try later.allocate(length: 32).buffer === slice.buffer)
    }

    func testAbandonedLeaseImmediatelyReleasesItsStorage() throws {
        let arena = FrameArena(device: device)
        var buffer: MTLBuffer?
        do {
            let lease = arena.lease(frame: .zero)
            buffer = try lease.allocate(length: 32).buffer
        }
        XCTAssertTrue(try arena.lease(frame: .zero).allocate(length: 32).buffer === buffer)
    }

    func testACompletedSegmentDoesNotReleaseTheFramesProducerLease() throws {
        let arena = FrameArena(device: device)
        var lease: FrameArena.Lease? = arena.lease(frame: .zero)
        let first = try XCTUnwrap(lease).allocate(length: 32)
        first.contents.storeBytes(of: UInt32(99), as: UInt32.self)
        let prefix = try makeCommandBuffer()
        lease?.retain(untilCompleted: prefix)
        complete(prefix)
        let unrelated = arena.lease(frame: .zero)
        XCTAssertFalse(try unrelated.allocate(length: 32).buffer === first.buffer, "the producer still holds the lease's chunks")
        let second = try XCTUnwrap(lease).allocate(length: 32)
        XCTAssertTrue(second.buffer === first.buffer)
        XCTAssertNotEqual(second.offset, first.offset)
        XCTAssertEqual(first.contents.load(as: UInt32.self), 99)
        let final = try makeCommandBuffer()
        lease?.retain(untilCompleted: final)
        lease = nil
        // Kept alive, so its own chunk isn't free for the next lease to take instead.
        let probe = arena.lease(frame: .zero)
        XCTAssertFalse(try probe.allocate(length: 32).buffer === first.buffer, "the final segment still holds them")
        complete(final)
        XCTAssertTrue(try arena.lease(frame: .zero).allocate(length: 32).buffer === first.buffer, "and gives them back on completion")
        withExtendedLifetime((unrelated, probe)) {}
    }

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
    }

    private func makeCommandBuffer() throws -> MTLCommandBuffer {
        try XCTUnwrap(commandQueue.makeCommandBuffer())
    }

    /// Commits `commandBuffer` and waits until its completed handlers, the arena's included, have run.
    private func complete(_ commandBuffer: MTLCommandBuffer) {
        let handlersRan = expectation(description: "completed handlers ran")
        // Completed handlers run in the order they were added: this one runs after the arena's.
        commandBuffer.addCompletedHandler { _ in handlersRan.fulfill() }
        commandBuffer.commit()
        wait(for: [handlersRan], timeout: 5)
    }

    /// Hands `lease` to `commandBuffer` as a submitted segment would.
    private func submit(_ lease: FrameArena.Lease, to commandBuffer: MTLCommandBuffer) {
        lease.retain(untilCompleted: commandBuffer)
        lease.finishRecording()
    }

    func testAllocationFailureThrowsAndLeavesLeaseUsable() throws {
        let arena = FrameArena(device: device)
        let lease = arena.lease(frame: .zero)
        let first = try lease.allocate(length: 32)
        first.contents.storeBytes(of: UInt32(123), as: UInt32.self)

        XCTAssertThrowsError(try lease.allocate(length: device.maxBufferLength + 1)) { error in
            XCTAssertEqual(error as? GPUError, .allocationFailed)
        }
        XCTAssertEqual(arena.chunkCount, 1)
        XCTAssertEqual(first.contents.load(as: UInt32.self), 123)
        let next = try lease.allocate(length: 32)
        XCTAssertTrue(next.buffer === first.buffer)
        XCTAssertGreaterThan(next.offset, first.offset)
    }

    func testSlicesAreAligned() throws {
        let lease = FrameArena(device: device).lease(frame: .zero)

        _ = try lease.allocate(length: 3)
        let aligned = try lease.allocate(length: 64, alignment: 256)
        let smallAlignment = try lease.allocate(length: 8, alignment: 16)

        XCTAssertEqual(aligned.offset % 256, 0)
        XCTAssertEqual(smallAlignment.offset % 16, 0)
        XCTAssertGreaterThanOrEqual(smallAlignment.offset, aligned.offset + aligned.length)
    }

    func testGrowthNeverMovesEarlierSlices() throws {
        let lease = FrameArena(device: device, initialChunkLength: 1024, maximumChunkLength: 4096).lease(frame: .zero)

        let first = try lease.allocate(length: 512)
        first.contents.storeBytes(of: UInt32(0xC0FFEE), as: UInt32.self)
        let second = try lease.allocate(length: 900)
        let oversized = try lease.allocate(length: 10_000)

        XCTAssertFalse(first.buffer === second.buffer, "a full chunk is followed by a new one")
        XCTAssertGreaterThanOrEqual(oversized.buffer.length - oversized.offset, 10_000)
        XCTAssertEqual(first.contents.load(as: UInt32.self), 0xC0FFEE, "earlier contents are untouched")
    }

    func testOneLeasesAllocationsShareAChunk() throws {
        let arena = FrameArena(device: device)
        let lease = arena.lease(frame: .zero)

        let first = try lease.allocate(length: 64)
        let second = try lease.allocate(length: 64)

        XCTAssertTrue(first.buffer === second.buffer)
        XCTAssertEqual(arena.chunkCount, 1)
    }

    func testChunksAreReusedOnlyAfterCompletion() throws {
        let arena = FrameArena(device: device)
        let inFlight = try makeCommandBuffer()
        let inFlightLease = arena.lease(frame: .zero)
        let inFlightSlice = try inFlightLease.allocate(length: 64)
        submit(inFlightLease, to: inFlight)

        let concurrent = try makeCommandBuffer()
        let concurrentLease = arena.lease(frame: .zero)
        let concurrentSlice = try concurrentLease.allocate(length: 64)
        submit(concurrentLease, to: concurrent)
        XCTAssertFalse(inFlightSlice.buffer === concurrentSlice.buffer, "an incomplete segment's chunk is not shared")

        complete(inFlight)
        complete(concurrent)

        let laterSlice = try arena.lease(frame: .zero).allocate(length: 64)
        XCTAssertTrue(laterSlice.buffer === inFlightSlice.buffer || laterSlice.buffer === concurrentSlice.buffer)
        XCTAssertEqual(arena.chunkCount, 2, "no new chunk once completed ones are free")
    }

    func testANeverCommittedCommandBufferGivesItsChunksBack() throws {
        let arena = FrameArena(device: device)
        var abandonedBuffer: MTLBuffer?

        // An Objective-C command buffer may be autoreleased: drain so it is truly released.
        try autoreleasepool {
            let abandoned = try makeCommandBuffer()
            let lease = arena.lease(frame: .zero)
            abandonedBuffer = try lease.allocate(length: 64).buffer
            submit(lease, to: abandoned)
        }

        XCTAssertTrue(try arena.lease(frame: .zero).allocate(length: 64).buffer === abandonedBuffer)
        XCTAssertEqual(arena.chunkCount, 1)
    }

    func testASteadyWorkloadStopsCreatingChunks() throws {
        let arena = FrameArena(device: device, initialChunkLength: 4096, maximumChunkLength: 4096)
        func frame() throws {
            let commandBuffer = try makeCommandBuffer()
            let lease = arena.lease(frame: .zero)
            for _ in 0 ..< 20 { _ = try lease.allocate(length: 512) }
            submit(lease, to: commandBuffer)
            complete(commandBuffer)
        }

        for _ in 0 ..< 3 { try frame() }
        let warmedUp = arena.chunkCount
        for _ in 0 ..< 10 { try frame() }

        XCTAssertEqual(arena.chunkCount, warmedUp)
    }
}
