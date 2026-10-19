@testable import Satin
import Metal
import XCTest

/// `FrameArena` hands out aligned slices that stay valid, and untouched, until their command buffer
/// completes; growth never moves earlier slices; completed and never-committed regions return their
/// chunks; a steady workload stops creating chunks; owners are released on completion.
final class FrameArenaTests: XCTestCase {
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

    func testSlicesAreAligned() throws {
        let arena = FrameArena(device: device)
        let commandBuffer = try makeCommandBuffer()

        _ = arena.allocate(length: 3, commandBuffer: commandBuffer)
        let aligned = arena.allocate(length: 64, alignment: 256, commandBuffer: commandBuffer)
        let smallAlignment = arena.allocate(length: 8, alignment: 16, commandBuffer: commandBuffer)

        XCTAssertEqual(aligned.offset % 256, 0)
        XCTAssertEqual(smallAlignment.offset % 16, 0)
        XCTAssertGreaterThanOrEqual(smallAlignment.offset, aligned.offset + aligned.length)
    }

    func testGrowthNeverMovesEarlierSlices() throws {
        let arena = FrameArena(device: device, initialChunkLength: 1024, maximumChunkLength: 4096)
        let commandBuffer = try makeCommandBuffer()

        let first = arena.allocate(length: 512, commandBuffer: commandBuffer)
        first.contents.storeBytes(of: UInt32(0xC0FFEE), as: UInt32.self)
        let second = arena.allocate(length: 900, commandBuffer: commandBuffer)
        let oversized = arena.allocate(length: 10_000, commandBuffer: commandBuffer)

        XCTAssertFalse(first.buffer === second.buffer, "a full chunk is followed by a new one")
        XCTAssertGreaterThanOrEqual(oversized.buffer.length - oversized.offset, 10_000)
        XCTAssertEqual(first.contents.load(as: UInt32.self), 0xC0FFEE, "earlier contents are untouched")
    }

    func testAllocationsForOneCommandBufferShareARegion() throws {
        let arena = FrameArena(device: device)
        let commandBuffer = try makeCommandBuffer()

        let first = arena.allocate(length: 64, commandBuffer: commandBuffer)
        let second = arena.allocate(length: 64, commandBuffer: commandBuffer)

        XCTAssertTrue(first.buffer === second.buffer)
        XCTAssertEqual(arena.chunkCount, 1)
    }

    func testChunksAreReusedOnlyAfterCompletion() throws {
        let arena = FrameArena(device: device)
        let inFlight = try makeCommandBuffer()
        let inFlightSlice = arena.allocate(length: 64, commandBuffer: inFlight)

        let concurrent = try makeCommandBuffer()
        let concurrentSlice = arena.allocate(length: 64, commandBuffer: concurrent)
        XCTAssertFalse(inFlightSlice.buffer === concurrentSlice.buffer, "an incomplete region's chunk is not shared")

        complete(inFlight)
        complete(concurrent)

        let later = try makeCommandBuffer()
        let laterSlice = arena.allocate(length: 64, commandBuffer: later)
        XCTAssertTrue(laterSlice.buffer === inFlightSlice.buffer || laterSlice.buffer === concurrentSlice.buffer)
        XCTAssertEqual(arena.chunkCount, 2, "no new chunk once completed ones are free")
    }

    func testANeverCommittedCommandBufferIsReclaimed() throws {
        let arena = FrameArena(device: device)
        var abandonedBuffer: MTLBuffer?

        // An Objective-C command buffer may be autoreleased: drain so it is truly released.
        try autoreleasepool {
            let abandoned = try makeCommandBuffer()
            abandonedBuffer = arena.allocate(length: 64, commandBuffer: abandoned).buffer
        }

        let next = try makeCommandBuffer()
        let nextSlice = arena.allocate(length: 64, commandBuffer: next)
        XCTAssertTrue(nextSlice.buffer === abandonedBuffer)
        XCTAssertEqual(arena.chunkCount, 1)
    }

    func testASteadyWorkloadStopsCreatingChunks() throws {
        let arena = FrameArena(device: device, initialChunkLength: 4096, maximumChunkLength: 4096)

        for _ in 0 ..< 3 {
            let commandBuffer = try makeCommandBuffer()
            for _ in 0 ..< 20 { _ = arena.allocate(length: 512, commandBuffer: commandBuffer) }
            complete(commandBuffer)
        }
        let warmedUp = arena.chunkCount

        for _ in 0 ..< 10 {
            let commandBuffer = try makeCommandBuffer()
            for _ in 0 ..< 20 { _ = arena.allocate(length: 512, commandBuffer: commandBuffer) }
            complete(commandBuffer)
        }

        XCTAssertEqual(arena.chunkCount, warmedUp)
    }

    func testOwnersAreReleasedOnCompletionAndOnReclamation() throws {
        final class Owner {}
        let arena = FrameArena(device: device)
        weak var completedOwner: Owner?
        weak var abandonedOwner: Owner?

        let committed = try makeCommandBuffer()
        do {
            let owner = Owner()
            completedOwner = owner
            arena.retainUntilCompleted(owner, commandBuffer: committed)
        }
        XCTAssertNotNil(completedOwner, "kept alive while the command buffer is in flight")
        complete(committed)
        XCTAssertNil(completedOwner)

        try autoreleasepool {
            let abandoned = try makeCommandBuffer()
            let owner = Owner()
            abandonedOwner = owner
            arena.retainUntilCompleted(owner, commandBuffer: abandoned)
        }
        _ = arena.allocate(length: 16, commandBuffer: try makeCommandBuffer())
        XCTAssertNil(abandonedOwner)
    }

    func testTypedCopies() throws {
        let arena = FrameArena(device: device)
        let commandBuffer = try makeCommandBuffer()

        let single = arena.allocate(simd_float4(1, 2, 3, 4), commandBuffer: commandBuffer)
        let values: [Float] = [5, 6, 7]
        let many = values.withUnsafeBufferPointer { arena.allocate($0, commandBuffer: commandBuffer) }

        XCTAssertEqual(single.contents.load(as: simd_float4.self), simd_float4(1, 2, 3, 4))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: many.contents.assumingMemoryBound(to: Float.self), count: 3)), values)
    }
}
